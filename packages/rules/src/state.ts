// Triad Chess — GameState (pure data, no logic)
// All fields are readonly; state is replaced, never mutated.

import type {
  BoardId, Col, PieceId, PieceKind, PlayerId, Position, Row,
  Squad, TeamId, UltimateKind,
} from "@triad-chess/shared";
import type { Action } from "./actions/index.js";

// ─── Pieces ──────────────────────────────────────────────────────────────────

export interface PieceBase {
  readonly pieceId: PieceId;
  readonly kind: PieceKind;
  readonly ownerPlayerId: PlayerId;
  readonly ownerTeamId: TeamId;
  /** On-board position, or "reserve" if captured and waiting to be summoned. */
  readonly position: Position | "reserve";
}

export interface RoiPiece       extends PieceBase { readonly kind: "Roi" }
export interface InvocateurPiece extends PieceBase { readonly kind: "Invocateur" }
export interface CavalierPiece  extends PieceBase { readonly kind: "Cavalier" }
export interface AssassinPiece  extends PieceBase {
  readonly kind: "Assassin";
  /** Set to origin after a capture; cleared when retreat is taken or turn ends. */
  readonly retreatOrigin: Position | undefined;
}
export interface ArcherPiece    extends PieceBase { readonly kind: "Archer" }
export interface MagePiece      extends PieceBase { readonly kind: "Mage" }
export interface GardienPiece   extends PieceBase { readonly kind: "Gardien" }
export interface PaladinPiece   extends PieceBase {
  readonly kind: "Paladin";
  readonly summonUsed: boolean; // 1×/game
}
export interface EnchanteurPiece extends PieceBase {
  readonly kind: "Enchanteur";
  readonly totemUsed: boolean;  // 1×/game
}

export type Piece =
  | RoiPiece | InvocateurPiece | CavalierPiece | AssassinPiece
  | ArcherPiece | MagePiece | GardienPiece | PaladinPiece | EnchanteurPiece;

// ─── Board ───────────────────────────────────────────────────────────────────

export interface Totem {
  readonly boardId: BoardId;
  readonly col: Col;
  readonly row: Row;
  readonly ownerTeamId: TeamId;
  /** Decrements on each capture in the 3×3 zone. Destroyed at 0. */
  readonly capturesLeft: number; // 3 → 2 → 1 → removed
}

// ─── Turn ────────────────────────────────────────────────────────────────────

export interface TurnState {
  readonly teamId: TeamId;
  readonly turnNumber: number;
  /** IDs of players who have already acted this turn. */
  readonly actedPlayerIds: ReadonlySet<PlayerId>;
  /** Seconds remaining (managed by the shell / server). */
  readonly timerSeconds: number;
}

// ─── Player ──────────────────────────────────────────────────────────────────

export interface Player {
  readonly playerId: PlayerId;
  readonly teamId: TeamId;
  readonly boardId: BoardId;
  readonly side: "south" | "north"; // south = rows 1-3 (Team A), north = rows 5-7 (Team B)
  readonly squad: Squad;
  /** False when Roi is captured — player keeps playing, but king is gone. */
  readonly kingAlive: boolean;
}

// ─── Game state ───────────────────────────────────────────────────────────────

export interface GameState {
  readonly matchId: string;

  // Entities
  readonly players: ReadonlyMap<PlayerId, Player>;
  /** All pieces, indexed by pieceId. Includes captured ones (position = "reserve"). */
  readonly pieces: ReadonlyMap<PieceId, Piece>;
  /** Active totems, indexed by boardId. */
  readonly totems: ReadonlyMap<BoardId, readonly Totem[]>;

  // Team state
  readonly momentum: { readonly A: number; readonly B: number };
  readonly ultimateUsed: { readonly A: boolean; readonly B: boolean };
  /**
   * Pieces in each team's reserve, available for summoning.
   * Roi and Invocateur are never added here; their capture is permanent.
   */
  readonly reserves: { readonly A: ReadonlySet<PieceId>; readonly B: ReadonlySet<PieceId> };
  readonly kingsAlive: { readonly A: number; readonly B: number };

  // Turn
  readonly turn: TurnState;

  // Event log (append-only, used for replay and networking)
  readonly history: readonly Action[];

  // Anti-stagnation
  readonly stagnationCounter: number; // turns since last capture

  // Terminal state
  readonly winner: TeamId | undefined;
}

// ─── Board zone helpers (pure) ────────────────────────────────────────────────

export const NEUTRAL_ROW: Row = 4;
export const SUMMON_ROWS_SOUTH: ReadonlyArray<Row> = [1, 2, 3];
export const SUMMON_ROWS_NORTH: ReadonlyArray<Row> = [5, 6, 7];
export const COLS: ReadonlyArray<Col> = ["a", "b", "c", "d", "e"];
export const ROWS: ReadonlyArray<Row> = [1, 2, 3, 4, 5, 6, 7];

export function summonRowsFor(side: "south" | "north"): ReadonlyArray<Row> {
  return side === "south" ? SUMMON_ROWS_SOUTH : SUMMON_ROWS_NORTH;
}

export function colIndex(col: Col): number {
  return COLS.indexOf(col); // 0-based
}

export function rowIndex(row: Row): number {
  return row - 1; // 0-based
}

/** Boards connected to a given board (triangular: P1↔P2, P2↔P3, P3↔P1). */
export function adjacentBoards(boardId: BoardId): readonly [BoardId, BoardId] {
  const map: Record<BoardId, [BoardId, BoardId]> = {
    P1: ["P2", "P3"],
    P2: ["P1", "P3"],
    P3: ["P1", "P2"],
  };
  return map[boardId];
}

/** All pieces currently on a given board. */
export function piecesOnBoard(state: GameState, boardId: BoardId): Piece[] {
  return [...state.pieces.values()].filter(
    (p) => p.position !== "reserve" && p.position.boardId === boardId
  );
}

/** Piece at a specific position, or undefined. */
export function pieceAt(state: GameState, pos: Position): Piece | undefined {
  return [...state.pieces.values()].find(
    (p) =>
      p.position !== "reserve" &&
      p.position.boardId === pos.boardId &&
      p.position.col === pos.col &&
      p.position.row === pos.row
  );
}
