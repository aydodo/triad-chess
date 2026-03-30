-- Triad Chess — Piece class

local C = require("src.constants")

local Piece = {}
Piece.__index = Piece

local _next_id = 1

function Piece.new(piece_type, team_id, player_id, board_idx, col, row)
    local self = setmetatable({}, Piece)
    self.id          = _next_id;  _next_id = _next_id + 1
    self.type        = piece_type
    self.team_id     = team_id    -- C.TEAM_A or C.TEAM_B
    self.player_id   = player_id  -- 1 / 2 / 3
    self.board_idx   = board_idx  -- 1 / 2 / 3
    self.col         = col        -- 1-5
    self.row         = row        -- 1-7

    -- State flags
    self.is_captured = false
    self.has_acted   = false   -- reset at start of owning team's turn

    -- Per-piece one-shot abilities
    self.paladin_invoke_used  = false  -- Paladin: 1×/game adjacent invoke
    self.enchanter_totem_used = false  -- Enchanter: 1×/game totem placement

    -- Assassin: stores origin for optional retreat (set during execute_move)
    self.assassin_last_origin = nil  -- {col, row} or nil

    return self
end

-- ─── Position helpers ────────────────────────────────────────────────────────

function Piece:pos()
    return self.board_idx, self.col, self.row
end

function Piece:set_pos(board_idx, col, row)
    self.board_idx = board_idx
    self.col       = col
    self.row       = row
end

-- ─── Queries ─────────────────────────────────────────────────────────────────

function Piece:is_invocable()
    return self.type ~= C.PIECE.KING and self.type ~= C.PIECE.INVOKER
end

function Piece:can_capture()
    -- Invoker and Enchanter can never capture
    return self.type ~= C.PIECE.INVOKER and self.type ~= C.PIECE.ENCHANTER
end

function Piece:is_ranged()
    return self.type == C.PIECE.ARCHER or self.type == C.PIECE.MAGE
end

-- Returns true if this piece type provides Guardian-style protection
function Piece:provides_protection()
    return self.type == C.PIECE.GUARDIAN or self.type == C.PIECE.PALADIN
end

-- Mage special vulnerability: can be captured by ANY enemy within ≤2 cells
function Piece:is_fragile()
    return self.type == C.PIECE.MAGE
end

-- ─── Reset ───────────────────────────────────────────────────────────────────

function Piece:reset_for_turn()
    self.has_acted            = false
    self.assassin_last_origin = nil
end

-- ─── Debug ───────────────────────────────────────────────────────────────────

function Piece:__tostring()
    local label = C.PIECE_LABEL[self.type] or "?"
    local status = self.is_captured and "[CAP]" or ""
    return string.format("%s T%dP%d @P%d-%s%d %s",
        label, self.team_id, self.player_id,
        self.board_idx, string.char(string.byte('a') + self.col - 1), self.row,
        status)
end

-- Reset the global ID counter (call on game reset)
function Piece.reset_ids()
    _next_id = 1
end

return Piece
