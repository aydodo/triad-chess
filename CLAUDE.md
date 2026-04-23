# Triad Chess — Conductor Instructions

## Project overview

**Triad Chess** is a tactical 3v3 chess/MOBA hybrid built in **Love2D 11.4 (Lua)**.
Phase 1 = 2D local prototype. Phase 2 = 3D via Menori (`libs/menori/`).

> USP: First team chess game where individual decisions affect teammates via a **shared invocation system**.

---

## Tech stack

| Layer | Tool |
|---|---|
| Language | Lua 5.1 (Love2D runtime) |
| Framework | Love2D 11.4 |
| 3D (Phase 2) | [Menori](https://github.com/rozenmad/Menori) — cloned as git submodule at `libs/menori/` |
| Entry point | `main.lua` + `conf.lua` |

**Run the game:**
```bash
love .
# or
love /path/to/triad_chess
```

**Clone with submodule (Menori included):**
```bash
git clone --recurse-submodules https://github.com/aydodo/triad-chess
```

---

## Architecture

```
main.lua            ← love.load / love.update / love.draw / input callbacks
conf.lua            ← window config (1400×760, resizable)
libs/
  menori/           ← Menori git submodule (3D scene graph for Phase 2)
src/
  constants.lua     ← ALL magic numbers & enums (edit here first)
  utils.lua         ← pure helpers (col↔letter, clamp, opponent…)
  piece.lua         ← Piece class; all 8 types; per-piece flags
  board.lua         ← Board (5×7 grid + totem system)
  game_state.lua    ← Global state: 3 boards, reserves, momentum, turns
  game_engine.lua   ← Action execution (move/shoot/invoke/ultimate…)
  logic/
    movement.lua    ← move_targets(), shoot_targets(), threat_cells()
    validation.lua  ← validate every action type; returns (ok, err)
  ui/
    board_view.lua  ← (Phase 1) renders one board in 2D; cell ↔ screen coords
    hud.lua         ← timer, momentum bars, reserves, kings, game-over
    game_view.lua   ← orchestrates 3 BoardViews + HUD + mouse input
    scene_3d.lua    ← (Phase 2) Menori 3D scene; replaces board_view.lua
```

**Data flow (Phase 1 — 2D):**
```
love.mousepressed → GameView → GameEngine:execute_*() → GameState mutation
love.update       → GameEngine:update(dt)              → turn timer / auto-end
love.draw         → GameView:draw() → BoardView:draw() + HUD:draw()
```

**Data flow (Phase 2 — 3D, target):**
```
love.mousepressed → GameView → ray-cast → GameEngine:execute_*() → GameState mutation
love.update       → GameEngine:update(dt) + Scene3D:update(dt)
love.draw         → Scene3D:draw() [Menori canvas] → HUD:draw() [2D overlay]
```

---

## Menori integration (Phase 2)

### How to load Menori
```lua
-- Always require from the project root path
local menori = require("libs.menori.menori")
```

### Key Menori classes

| Class | Purpose |
|---|---|
| `menori.PerspectiveCamera` | 3D perspective camera with `m_view` / `m_projection` matrices |
| `menori.Environment` | Scene-level uniforms: camera matrices, lights, fog |
| `menori.Scene` | Renders/updates a node tree via `render_nodes()` / `update_nodes()` |
| `menori.Node` | Scene-graph node; has `children`, `position`, `rotation`, `scale` |
| `menori.ModelNode` | Renderable node (mesh + material) |
| `menori.glTFLoader` | Loads `.gltf` / `.glb` files into a node tree |
| `menori.Box` | Procedural box mesh |
| `menori.Plane` | Procedural plane mesh |
| `menori.Sphere` | Procedural sphere mesh |
| `menori.ml` | Math library: `ml.vec3`, `ml.mat4`, `ml.quat` |

### Minimal 3D scene pattern
```lua
local menori = require("libs.menori.menori")

-- Camera: positioned above-behind, looking at board centre
local camera = menori.PerspectiveCamera(60, sw/sh, 0.1, 1000)
camera:set_position(0, 12, 10)
camera:look_at(menori.ml.vec3(0, 0, 0))

-- Environment (handles uniforms sent to shaders per frame)
local env = menori.Environment(camera)

-- Scene (renders node tree)
local scene = menori.Scene()

-- Root node
local root = menori.Node()

-- Board tile: a Plane mesh at world position
local tile = menori.ModelNode(menori.Plane(1, 1))
tile:set_position(x, 0, z)
root:attach(tile)

-- Render loop
function love.draw()
    love.graphics.setCanvas({canvas, depth = true})
    scene:render_nodes(root, env)
    love.graphics.setCanvas()
    -- blit canvas to screen …
end
```

### Phase 2 board → 3D mapping

| Game concept | 3D representation |
|---|---|
| Board cell (col, row) | `Plane(1,1)` at `vec3((col-3)*1.1, 0, (row-4)*1.1)` |
| Piece | `Box(0.7, 1.0, 0.7)` placeholder → swap for `.glb` model later |
| Selection highlight | Emissive colour uniform on the tile's material |
| 3 boards | Offset each board along the X axis: `board_idx * 8` units |
| Camera per player | 3 `PerspectiveCamera` instances; swap on focus change |
| Mouse picking | Ray–AABB intersection against piece bounding boxes (`menori.ml`) |

### GLTF piece loading (when models are ready)
```lua
-- Assets go in assets/models/<piece_type>.glb
local loader = menori.glTFLoader.load("assets/models/king.glb")
local node_tree = menori.NodeTreeBuilder.create(loader, scene, env)
root:attach(node_tree)
```

### Render target (Phase 2 main.lua pattern)
```lua
local canvas = love.graphics.newCanvas(sw, sh, {format="rgba8", depth=true})

function love.draw()
    love.graphics.setCanvas({canvas, depth=true})
    love.graphics.clear(0.08, 0.08, 0.10)
    scene_3d:draw()                  -- Menori scene
    love.graphics.setCanvas()
    love.graphics.draw(canvas, 0, 0) -- blit
    hud:draw(engine.state)           -- 2D HUD overlay
end
```

> **Rule:** `src/ui/scene_3d.lua` reads `GameState` and builds/updates the Menori node tree.
> It must **never** call `GameEngine` methods — UI is read-only.

---

## Game rules (authoritative reference)

### Boards
- **3 boards**, each **5 columns (a–e) × 7 rows (1–7)**
- Boards are connected in a triangle; an Invoker can invoke on any of the 3 boards
- Row zones (same for every board):

| Row | Zone |
|---|---|
| 1 | Team A base — invocation zone |
| 2–3 | Team A zone — invocation zone |
| 4 | **Neutral line** — Invoker must stand here to invoke |
| 5–6 | Team B zone — invocation zone |
| 7 | Team B base — invocation zone |

### Teams & players
- **Team A** vs **Team B**, 3 players each
- Player N of each team opposes each other on Board N
- Initial layout (Team A, row 1): `Invoker @ a1 · Slot1 @ b1 · King @ c1 · Slot2 @ d1 · Slot3 @ e1`
- Team B mirrors on row 7 (columns reversed)

### Piece classes

| Piece | Move | Capture | Special | Invocable |
|---|---|---|---|---|
| **King** | 1 cell, 8 dirs | By stepping | Objective | ❌ |
| **Invoker** | 2 cells diagonal | ❌ never | Must be on row 4 to invoke | ❌ |
| **Knight** | L-shape (2+1), jumps | By stepping | — | ✅ |
| **Assassin** | 3 cells straight or diagonal (no jump) | Diagonal adjacent only (1 cell) | After capture: optional retreat to origin (same turn) | ✅ |
| **Archer** | 1 cell orthogonal | Move OR shoot (not both) | Shoot: exactly 2 cells orthogonal, stays in place. Ignores Guardian protection | ✅ |
| **Mage** | 1 cell diagonal | Move OR shoot (not both) | Shoot: exactly 3 cells any direction, stays in place. Fragile: capturable by any enemy ≤2 cells | ✅ |
| **Guardian** | 2 cells orthogonal, no jump | By stepping | Passive: adjacent allies (8 cells) cannot be captured. Archer ignores this | ✅ |
| **Paladin** | 1 cell, 8 dirs | By stepping | Passive protection (Archer does NOT ignore). 1×/game: invoke adjacent piece (full action) | ✅ |
| **Enchanter** | 1 cell, 8 dirs | ❌ never | 1×/game: place Invocation Totem (3×3 zone, 3 captures or enemy steps on it → destroyed) | ✅ |

### Draft (per player, before match)
- Slot 1: **Knight** OR **Assassin**
- Slot 2: **Archer** OR **Mage**
- Slot 3: **Guardian** OR **Paladin** OR **Enchanter**
- Default (prototype): Knight + Archer + Guardian

### Reserve system
- Captured pieces go to the **capturing team's** reserve (not the victim's)
- Kings and Invokers are **never** in the reserve (removed from game)
- Any Invoker on the team can invoke from the shared reserve

### Turn structure (Proposition B — implemented)
- 20-second shared timer per team
- 3 players act in any order; each does **exactly 1 action**
- Turn ends when all 3 players have acted OR timer expires
- Actions: `move`, `shoot`, `invoke`, `paladin_inv`, `place_totem`, `suicide`, `pass`

### Win condition (Proposition A — implemented)
- **Capture 2 out of 3 enemy Kings** while keeping at least 1 allied King

### Momentum system
| Event | Δ |
|---|---|
| Capture enemy piece | +10 |
| Successful invoke | +5 |
| Put enemy King in threat (first turn) | +15 |
| Lose a piece | −10 |
| Lose a King | −20 |

At 100 momentum (1×/game), team chooses an **Ultimate**:
- `mass_invoke` — invoke 3 pieces this turn
- `divine_shield` — immune to all captures next enemy turn
- `teleport` — swap any 2 allied pieces across boards
- `resurrection` — place any captured allied piece directly on board

---

## What is already implemented

- [x] Full project structure
- [x] All constants, utils, piece class
- [x] Board class with totem support
- [x] GameState (3 boards, reserves, momentum, turn management, win check)
- [x] GameEngine (execute_move, execute_shoot, execute_invoke, execute_paladin_invoke, execute_place_totem, execute_suicide, execute_pass, execute_ultimate)
- [x] Movement rules for all 8 piece types
- [x] Full validation (protection, fragility, Assassin diagonal-only capture, etc.)
- [x] 2D renderer: 3 boards side-by-side, coloured zones, piece labels, totem overlay
- [x] HUD: turn banner, timer, momentum bars, reserve list, kings alive, win screen
- [x] Mouse input: click-to-select → click-to-act, cross-board Invoker invocation
- [x] Keyboard: Space/Enter = end turn, Escape = deselect, R = reset

---

## What still needs to be built (roadmap)

### Immediate / Phase 1

- [ ] **Draft screen** — before game starts, let each player pick Slot 1/2/3 pieces
- [ ] **Reserve picker UI** — when invoking, show a list of pieces in reserve to choose from (currently auto-picks first)
- [ ] **Assassin retreat UI** — after a capture, offer the player the option to retreat
- [ ] **Check/threat highlighting** — highlight King cells that are threatened
- [ ] **Suicide action UI** — player should be able to select "Suicide" for a piece via UI
- [ ] **Totem invocation** — Enchanter totem should also expand the invocation zone it covers
- [ ] **AI opponent (basic)** — greedy or random bot so solo play is possible
- [ ] **Sound effects** — capture sound, invoke fanfare, turn start ding

### Phase 2 (3D + online)

- [ ] **Menori integration** — replace 2D board renderer with 3D scene graph
- [ ] **3D piece models** — load GLTF models via Menori
- [ ] **Network layer** — 6-player real-time sync (authoritative server)
- [ ] **Matchmaking** — lobby, ranked queue
- [ ] **Elo system** — 60% team result + 40% individual performance

---

## Unresolved design questions (to discuss with Dorian)

| # | Question | Options |
|---|---|---|
| 1 | Board orientation | Each player sees own board from "their side"? Or single fixed global view? |
| 2 | Assassin: straight movement | Can it move straight without capturing, up to 3 cells? (Currently yes) |
| 3 | Mage fragility exact rule | Capturable by any enemy ≤2 cells — does this bypass Guardian protection? |
| 4 | Invocation cross-board | Currently all 3 boards are mutually reachable. Should it be strictly adjacent only? |
| 5 | Farming / phase after King captured | Implement Proposition B (Sabotage mode) or Proposition C (redistribution)? |
| 6 | Turn system | Proposition B (sequential 20s) is implemented. Confirm or switch to A (simultaneous reveal)? |

---

## Key conventions

- **All coordinates**: `col` = 1–5 (a–e), `row` = 1–7 (bottom to top for Team A)
- **Team IDs**: `C.TEAM_A = 1`, `C.TEAM_B = 2`
- **Player IDs**: 1, 2, 3 per team (matches board index they start on)
- **Piece IDs**: auto-incrementing integers, reset on `Piece.reset_ids()`
- **Require paths**: always from project root, e.g. `require("src.logic.movement")`
- **No global state**: everything flows through `GameState` and `GameEngine`
- **Validation first**: always call `validation.lua` before mutating state in engine

---

## Coding guidelines

- Keep `game_state.lua` as a **pure data container** — no game logic
- All action logic lives in `game_engine.lua`
- All movement geometry lives in `logic/movement.lua`
- All legality checks live in `logic/validation.lua`
- UI files (`src/ui/`) must **never mutate** game state — read only
- New piece types: add to `constants.lua` first, then `movement.lua`, `validation.lua`, `board_view.lua` labels
- New actions: add to `C.ACTION`, implement `V.xxx` in `validation.lua`, `execute_xxx` in `game_engine.lua`
