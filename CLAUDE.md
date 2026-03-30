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
| 3D (Phase 2) | [Menori](https://github.com/rozenmad/Menori) — place as `libs/menori/` |
| Entry point | `main.lua` + `conf.lua` |

**Run the game:**
```bash
love .
# or
love /path/to/triad_chess
```

---

## Architecture

```
main.lua            ← love.load / love.update / love.draw / input callbacks
conf.lua            ← window config (1400×760, resizable)
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
    board_view.lua  ← renders one board; handles cell ↔ screen coords
    hud.lua         ← timer, momentum bars, reserves, kings, game-over
    game_view.lua   ← orchestrates 3 BoardViews + HUD + mouse input
```

**Data flow:**
```
love.mousepressed → GameView → GameEngine:execute_*() → GameState mutation
love.update       → GameEngine:update(dt)              → turn timer / auto-end
love.draw         → GameView:draw() → BoardView:draw() + HUD:draw()
```

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
