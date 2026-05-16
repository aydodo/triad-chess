# CLAUDE.md — Triad Chess

> Context file for Claude Code / Claude chat sessions working on this project.
> **Before doing anything, read `triad_chess_rules_v2.md` as the single source of truth for game mechanics.** This file tells you *how to work*, not *what the rules are*.

---

## 1. Project identity

**Triad Chess** is a 3v3 tactical game fusing mechanics from Bughouse Chess (shared reserve + summoning), Hnefatafl (asymmetric territorial structure), and MOBAs (draft, ultimates, momentum). Positioned as more accessible than LoL, deeper than classical chess, in a Rocket League-style competitive format (short matches, high ceiling).

**Target audience.** Competitive / esport. Match length: **10–15 min** standard, **20 min** hard cap.

**North star.** Every mechanic must serve at least one of:
1. Create interesting decisions.
2. Reward team coordination.
3. Maintain dynamic pacing.

If a feature fails all three, it does not ship.

---

## 2. Current phase

We are **pre-Phase 1**: ruleset is stabilized (v2.0), prototype not yet started.

| Phase | Duration | Deliverable |
|---|---|---|
| **Phase 1** | 3–4 mo | **1v1 prototype**, validate core mechanics on a single board |
| Phase 2 | 6–8 mo | 3v3 MVP, networking, alpha (~100 testers) |
| Phase 3 | 4–6 mo | Full Elo, Battle Pass, beta (~10K+ players) |
| Phase 4 | 2–3 mo | Release, tournaments, mobile |

**Total: 15–21 months.** Iterative, validate-before-scale.

**Right now, work targets Phase 1 only.** Anything labeled Phase 2+ is premature unless explicitly requested.

---

## 3. Tech stack

Primary stack — TypeScript end-to-end. No Rust/native modules in Phase 1.

| Layer | Choice | Why |
|---|---|---|
| Frontend | **Next.js + React + Three.js** | SSR for marketing pages, Three.js for 3D board rendering |
| Backend | **Node.js + Hono** | Lightweight, edge-friendly, matches personal stack |
| Realtime | **WebSockets** (native or `ws`) | Phase 2+; Phase 1 is local-only |
| Persistence | **PostgreSQL** | Game history, Elo, accounts |
| Cache / pubsub | **Redis** | Matchmaking queue, live game state broadcast (Phase 2+) |
| Validation | **Zod** | Runtime schema validation at all API and WebSocket boundaries |
| Testing | **Vitest** + **fast-check** (property-based) | Rule engine is the crown jewel — test it like it |

**Language.** TypeScript, `strict: true`, `noUncheckedIndexedAccess: true`. No `any` escapes without a `// eslint-disable` comment that explains why.

**Node version.** 20 LTS or later.

---

## 4. Architecture principles

### 4.1 Domain-first, always

Dorian works backwards from the end goal and models the domain before the infrastructure. So do you.

Before writing any handler, route, or UI component, we model:
1. **Entities** (Game, Board, Player, Team, Piece, Move, Reserve, MomentumGauge).
2. **Invariants** (rules that must always hold — e.g. "a team has at most 3 living Kings across boards").
3. **State transitions** (pure functions: `(state, action) -> state | Error`).
4. **Commands and events** (what players send; what the system broadcasts).

Only then do we write the thing that executes those transitions.

### 4.2 Pure core, imperative shell

- **Core** (`/packages/rules`): pure TypeScript. No I/O, no Date.now(), no randomness without an injected seed. Given the same `(state, action)`, it returns the same `(newState | error)`.
- **Shell** (`/apps/server`, `/apps/web`): handles WebSockets, DB, rendering, time, RNG. Calls into the core.

This split is non-negotiable. The core must be runnable in a browser, a Node server, a Web Worker, and a test harness without modification.

### 4.3 Event-sourced game state

A game is a sequence of validated **Actions** (Move, Capture, Shoot, Summon, UltimateActivation, …). Current state is a fold over history.

Benefits: instant replay, clean undo (Phase 1 design aid), networking via event stream, spectator mode for free, reproducible bug reports.

### 4.4 Command pattern for actions

Every action is a first-class object that knows how to `validate(state) -> Result` and `apply(state) -> state`. Matches Option C from the architecture discussion and makes rule evolution painless.

```ts
interface Action {
  readonly kind: ActionKind;
  readonly playerId: PlayerId;
  readonly timestamp: number;  // server-assigned in multiplayer
  validate(state: GameState): Result<void, RuleViolation>;
  apply(state: GameState): GameState;  // only called after validate passes
}
```

### 4.5 Make illegal states unrepresentable

Prefer discriminated unions over optional fields. Prefer branded types (`type PieceId = string & { __brand: 'PieceId' }`) over raw strings. Prefer `Result<T, E>` over thrown exceptions in the core.

---

## 5. Domain model sketch

Not prescriptive — sketch to anchor discussion. Refine before coding.

```
Game
├── matchId, seed, createdAt
├── teams: [Team, Team]                      // A, B
├── boards: [Board, Board, Board]            // P1, P2, P3
├── turn: TurnState                          // whose team, timer, actions played
├── momentum: { A: 0..100, B: 0..100 }
├── ultimatesUsed: { A: boolean, B: boolean }
├── reserves: { A: Piece[], B: Piece[] }     // captured pieces available to summon
├── history: Action[]                        // event-sourced
└── stagnationCounter: number                // turns since last capture

Team
├── teamId: 'A' | 'B'
└── players: [Player, Player, Player]

Player
├── playerId
├── teamId
├── boardId: 'P1' | 'P2' | 'P3'              // which board they sit at
├── side: 'south' | 'north'                  // rows 1-3 or 5-7
├── squad: [Slot1Class, Slot2Class, Slot3Class]   // draft result
└── kingAlive: boolean                        // player keeps playing after king capture

Board
├── boardId
├── grid: 5 cols × 7 rows                     // Cell[][]
├── adjacents: [Board, Board]                 // triangular connection (P1<->P2, P2<->P3, P3<->P1)
└── totems: Totem[]                           // Enchanteur totems, if any

Piece
├── pieceId (branded)
├── kind: Roi | Invocateur | Cavalier | Assassin | Archer | Mage | Gardien | Paladin | Enchanteur
├── ownerPlayerId
├── position: { boardId, col: 'a'..'e', row: 1..7 } | 'reserve'
└── flags: { paladinSummonUsed, enchanteurTotemUsed, ... }
```

Pieces ship as a discriminated union keyed on `kind`. Each class has its own module exporting `moves(state, piece) -> Position[]`, `canCapture(state, from, to) -> boolean`, and any special action handler.

---

## 6. Real-time & networking (Phase 2+ — skip in Phase 1)

Noted here so you don't accidentally architect Phase 1 in a way that blocks Phase 2.

**Target latency.** 50–200 ms for 6 simultaneous players.

**Planned approach.**
- **Server-authoritative.** Clients send intents (`Action` candidates), server validates, broadcasts confirmed actions.
- **Client prediction** for the acting player's own moves (optimistic local apply, reconcile on server response).
- **Rollback netcode** is the ideal; lock-step with a short buffer is the fallback.
- **Conflict resolution** for the reserve (two players summoning the same piece): first server-timestamped action wins.

**Phase 1 consequence.** Design the `Action` interface and state reducer as if they already run in a multiplayer context (pure, serializable, idempotent when reapplied with the same timestamp). Do not assume single-process state mutation.

---

## 7. Game design — non-negotiables

These are **locked** design decisions. Do not suggest overturning them without strong justification.

- **5 pieces per player.** 2 mandatory (Roi, Invocateur) + 3 drafted.
- **8 total classes** (the original set). No new classes without explicit discussion.
- **Roi and Invocateur are never summonable.** Their loss is permanent.
- **Player whose Roi is captured keeps playing.** No early elimination.
- **Victory = capture 2 enemy Kings while retaining ≥1 ally King.** Team-only; no individual victory condition.
- **No post-victory farming phase.** Match ends immediately on the winning capture.
- **Momentum gauge (0–100)** replaces the old "optimal move" concept. It is transparent and measurable.
- **Ultimate is 1×/game** regardless of how many times the gauge fills.
- **Gardien vs Paladin distinction is critical.** Archer ignores Gardien's aura but *not* Paladin's. Don't conflate them.
- **Enchanteur Totem is single-use per game**, permanent until destroyed (3 summons or enemy steps on it).

---

## 8. Open design questions (still live)

If work touches these areas, flag it and propose before implementing. Do not silently commit to one option.

1. **Turn structure.** Current rules v2 lock in *sequential-per-team* with a shared 20s timer. The *simultaneous-with-reveal-phase* option (15s plan → reveal → 5s execute) is archived but not dead. If we validate 1v1 with sequential and it feels flat in 3v3 playtests, simultaneous is the fallback.
2. **Draft vs predefined comps.** Leaning draft (12 comps/player). Tournament Ban/Pick layer is optional.
3. **Visual orientation of the triangular board connection.** UX-level decision, unresolved. Affects how pieces visually "cross" between boards (if ever — currently they don't, but Ultimate Teleportation does).
4. **Ideal match duration sweet spot.** Target 10–15 min. Anti-stagnation thresholds (8/12/16 turns) are a first guess; may need rebalancing after playtesting.
5. **Archer move + shoot in one turn?** Resolved in v2: **NO, it's one or the other.** Keep locked unless playtesting shows it's too weak.

---

## 9. Coding conventions

### TypeScript

- `strict: true`, `noUncheckedIndexedAccess: true`, `exactOptionalPropertyTypes: true`.
- Branded types for all IDs: `PieceId`, `PlayerId`, `MatchId`, `BoardId`.
- Discriminated unions (`type Piece = Roi | Invocateur | ...`) over class hierarchies.
- `readonly` by default on all domain state fields.
- No `null` in the core. Use `undefined` or better, `Option<T>` / `Result<T, E>` via a tiny local helper.
- No exceptions thrown from the core. The core returns `Result`. The shell may throw for truly exceptional infra errors (DB down).

### File layout

```
/packages/rules          # pure core — the rules engine
  /src
    /pieces              # one file per class: roi.ts, cavalier.ts, ...
    /actions             # Action implementations: move.ts, shoot.ts, summon.ts, ultimate.ts
    state.ts             # GameState type + initial state factory
    reducer.ts           # (state, action) -> Result<state, error>
    invariants.ts        # runtime assertions for tests
    index.ts             # public API surface
  /tests
/packages/shared         # types reused by client & server
  /src
    types.ts             # branded IDs, enums, shared interfaces
    index.ts
/apps/server             # Hono + WebSocket gateway
  /src
    index.ts
/apps/web                # Next.js + React + Three.js client
  /src
    /app
    /components
    /game                # Three.js scene, board renderer
/apps/cli                # scriptable match runner for playtesting
  /src
    index.ts
```

### Naming

- English in code and types. French is fine in comments and in user-facing strings.
- **Exception:** piece class names stay in French in code (`Cavalier`, `Assassin`, `Mage`, `Gardien`, `Paladin`, `Enchanteur`, `Roi`, `Invocateur`). They are proper nouns of the game.

### Commits

Conventional commits (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`). Keep them small; the event-sourced core means regressions are easy to bisect if commits are atomic.

---

## 10. Testing strategy

The rules engine is the product's heart. Test it like it.

1. **Unit tests** per piece class: valid moves, capture patterns, special abilities.
2. **Property-based tests** (fast-check) for invariants that must *always* hold:
   - No piece occupies two cells.
   - A team never has more than 3 living Kings.
   - Momentum is always in `[0, 100]`.
   - A captured piece lands in exactly one reserve.
   - Every action is either fully applied or not at all (no partial mutation on validation failure).
3. **Replay tests.** Given `Action[]` and an initial seed, the fold must be deterministic. Same input → same final state, bit-for-bit.
4. **Scenario tests** (integration): encode known tactical situations from the rules doc as fixture games.
5. **Snapshot tests** for serialized game states so we catch accidental schema drift.

No UI test infrastructure in Phase 1. Manual playtesting is enough until 1v1 prototype validates.

---

## 11. How to work with Dorian

- **Reason through the problem independently and reach the most logical answer before inviting follow-up.** Don't ask 5 clarifying questions up front. Propose, explain trade-offs, then open the floor.
- **Work in comprehensive passes** (rules → math → architecture) within a single session when the scope allows.
- **Produce structured reference documents** suitable for handoff. Markdown with clear headers, tables where useful, no filler prose.
- **Analogies help** when introducing unfamiliar concepts.
- **Backwards planning.** Start from the end state and derive the steps.
- **Simplicity over cleverness.** If there's a boring way that works, use it.

**When Dorian says "think through X":** structured analysis with trade-offs, not a single recommendation.
**When Dorian says "decide X":** pick one, state why, own it.

---

## 12. Critical risks to track

1. **Real-time sync of 6 players** with 50–200 ms latency.
2. **Simultaneous action conflict resolution** (if we revisit simultaneous turns).
3. **Fair 3v3 Elo** — 40% individual + 60% team; anti-boosting enforcement.
4. **Balance across 144 matchups** (12 comps × 12 enemy comps). Build telemetry early.

---

## 13. Key references

- **`triad_chess_rules_v2.md`** — canonical ruleset. Source of truth for all mechanics. If something in code contradicts it, the code is wrong.
- **Reference games:** Bughouse Chess, Hnefatafl, DotA 2, League of Legends, Rocket League.
- **Legacy Lua prototype:** `legacy/` — original Love2D/Menori proof-of-concept. Archived, not active.

---

## 14. Quick checklist for new work

Before you write code, confirm:

- [ ] Did I read `triad_chess_rules_v2.md` for the mechanics involved?
- [ ] Is this Phase 1 scope? If not, should it wait?
- [ ] Does this touch a locked design decision (§7)? If so, stop and flag.
- [ ] Does this touch an open question (§8)? If so, propose before implementing.
- [ ] Am I writing in the pure core or in the shell? (§4.2)
- [ ] Is the action serializable, deterministic, and testable in isolation?
- [ ] Have I sketched the domain model before the code? (§4.1)
- [ ] Is there a property-based test I can write alongside the feature? (§10)

---

*Last updated: April 2026. Revisit when Phase 1 prototype validates and Phase 2 scope becomes current.*
