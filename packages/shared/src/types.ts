// Triad Chess — shared types
// Imported by both packages/rules (core) and apps/server, apps/web.

// ─── Branded IDs ─────────────────────────────────────────────────────────────

declare const __brand: unique symbol;
type Brand<T, B> = T & { readonly [__brand]: B };

export type MatchId  = Brand<string, "MatchId">;
export type PlayerId = Brand<string, "PlayerId">;
export type PieceId  = Brand<string, "PieceId">;
export type BoardId  = "P1" | "P2" | "P3";
export type TeamId   = "A" | "B";

// ─── Board coordinates ────────────────────────────────────────────────────────

export type Col = "a" | "b" | "c" | "d" | "e";
export type Row = 1 | 2 | 3 | 4 | 5 | 6 | 7;

export interface Position {
  readonly boardId: BoardId;
  readonly col: Col;
  readonly row: Row;
}

// ─── Piece kinds ─────────────────────────────────────────────────────────────
// French proper nouns — kept as-is per coding conventions (§9).

export type PieceKind =
  | "Roi"
  | "Invocateur"
  | "Cavalier"
  | "Assassin"
  | "Archer"
  | "Mage"
  | "Gardien"
  | "Paladin"
  | "Enchanteur";

// Draft slot options
export type Slot1Kind = "Cavalier" | "Assassin";
export type Slot2Kind = "Archer" | "Mage";
export type Slot3Kind = "Gardien" | "Paladin" | "Enchanteur";

export interface Squad {
  readonly slot1: Slot1Kind;
  readonly slot2: Slot2Kind;
  readonly slot3: Slot3Kind;
}

// ─── Action kinds ─────────────────────────────────────────────────────────────

export type ActionKind =
  | "Move"       // move (implicit capture if enemy on dest)
  | "Shoot"      // Archer / Mage ranged attack
  | "Summon"     // Invocateur places piece from reserve
  | "PaladinSummon" // Paladin 1×/game adjacent summon
  | "PlaceTotem" // Enchanteur places invocation totem
  | "Pass"
  | "Suicide"    // sacrifice own piece → own reserve
  | "Ultimate";  // activate ultimate ability

export type UltimateKind =
  | "MassInvoke"    // summon 3 pieces this turn
  | "DivineShield"  // immune next enemy turn
  | "Teleport"      // swap 2 allied pieces cross-board
  | "Resurrection"; // place captured piece directly on board

// ─── Result / Option utilities ────────────────────────────────────────────────

export type Result<T, E> =
  | { readonly ok: true;  readonly value: T }
  | { readonly ok: false; readonly error: E };

export const ok  = <T>(value: T): Result<T, never>        => ({ ok: true,  value });
export const err = <E>(error: E): Result<never, E>        => ({ ok: false, error });
export const isOk  = <T, E>(r: Result<T, E>): r is { ok: true;  value: T } => r.ok;
export const isErr = <T, E>(r: Result<T, E>): r is { ok: false; error: E } => !r.ok;

// ─── Rule violations ─────────────────────────────────────────────────────────

export type RuleViolationKind =
  | "PIECE_NOT_FOUND"
  | "NOT_YOUR_PIECE"
  | "PIECE_ALREADY_ACTED"
  | "INVALID_DESTINATION"
  | "DESTINATION_OCCUPIED_BY_ALLY"
  | "CANNOT_CAPTURE"
  | "TARGET_PROTECTED"
  | "INVOKER_NOT_ON_NEUTRAL_ROW"
  | "TARGET_NOT_IN_SUMMON_ZONE"
  | "PIECE_NOT_IN_RESERVE"
  | "ABILITY_ALREADY_USED"
  | "NOT_YOUR_TURN"
  | "GAME_ALREADY_OVER"
  | "WRONG_PIECE_KIND";

export interface RuleViolation {
  readonly kind: RuleViolationKind;
  readonly message: string;
}
