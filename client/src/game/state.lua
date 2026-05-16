--[[
    state.lua — GameState and turn management for Phase 1 hot-seat.

    Initial layout (Phase 1, mirroring the spec):
      South row 1 (col 1-5):  Guardian, Archer, King, Invoker, Knight
      North row 7 (col 1-5):  Knight, Invoker, King, Archer, Guardian

    Turn flow:
      1. current_player (south | north) selects a piece and action.
      2. State:apply_*() validates, mutates, checks win.
      3. If no win, current_player flips.

    State is mutable (no immutable fold in Phase 1 — we keep it simple for
    the prototype; the TypeScript core will be event-sourced).
]]

local Board   = require("src.game.board")
local Pieces  = require("src.game.pieces")
local Reserve = require("src.game.reserve")
local Rules   = require("src.game.rules")

local State = {}
State.__index = State

-- ─── Constructor ─────────────────────────────────────────────────────────────
function State.new()
    local self = setmetatable({}, State)

    self.board          = Board.new()
    self.reserves       = { south = Reserve.new(), north = Reserve.new() }
    self.current_player = "south"
    self.winner         = nil  -- "south" | "north" | nil
    self.turn_number    = 1
    self.last_error     = nil  -- last validation failure message (for HUD)
    self.last_action    = nil  -- {type="move"|"shoot"|"invoke"|"pass", ...} for HUD

    self:_setup_initial_pieces()

    return self
end

-- ─── Initial piece placement ─────────────────────────────────────────────────
-- South row 1: Guardian@1, Archer@2, King@3, Invoker@4, Knight@5
-- North row 7: Knight@1, Invoker@2, King@3, Archer@4, Guardian@5
function State:_setup_initial_pieces()
    local layout = {
        { owner = "south", row = 1, pieces = {
            Pieces.TYPE.GUARDIAN,
            Pieces.TYPE.ARCHER,
            Pieces.TYPE.KING,
            Pieces.TYPE.INVOKER,
            Pieces.TYPE.KNIGHT,
        }},
        { owner = "north", row = 7, pieces = {
            Pieces.TYPE.KNIGHT,
            Pieces.TYPE.INVOKER,
            Pieces.TYPE.KING,
            Pieces.TYPE.ARCHER,
            Pieces.TYPE.GUARDIAN,
        }},
    }
    for _, side in ipairs(layout) do
        for col, ptype in ipairs(side.pieces) do
            local p = Pieces.new(ptype, side.owner, col, side.row)
            self.board:set(col, side.row, p)
        end
    end
end

-- ─── Move action ─────────────────────────────────────────────────────────────
-- Returns true on success, false + sets self.last_error on failure.
function State:apply_move(piece, dest_col, dest_row)
    if self.winner then return false end
    local ok, err = Rules.validate_move(piece, dest_col, dest_row, self.board)
    if not ok then
        self.last_error = err
        return false
    end

    -- Capture if enemy present
    local occupant = self.board:get(dest_col, dest_row)
    if occupant then
        self:_capture(occupant)
    end

    self.board:move_piece(piece.col, piece.row, dest_col, dest_row)
    piece.has_acted = true
    self.last_error = nil
    self.last_action = { type = "move", piece = piece }

    self:_check_and_end_turn()
    return true
end

-- ─── Shoot action (Archer only) ───────────────────────────────────────────────
function State:apply_shoot(archer, dest_col, dest_row)
    if self.winner then return false end
    local ok, err = Rules.validate_shoot(archer, dest_col, dest_row, self.board)
    if not ok then
        self.last_error = err
        return false
    end

    local target = self.board:get(dest_col, dest_row)
    self:_capture(target)
    archer.has_acted = true
    self.last_error = nil
    self.last_action = { type = "shoot", piece = archer, target_col = dest_col, target_row = dest_row }

    self:_check_and_end_turn()
    return true
end

-- ─── Invoke action ────────────────────────────────────────────────────────────
function State:apply_invoke(invoker, piece_type, dest_col, dest_row)
    if self.winner then return false end
    local reserve = self.reserves[invoker.owner]
    local ok, err = Rules.validate_invoke(invoker, piece_type, dest_col, dest_row, self.board, reserve)
    if not ok then
        self.last_error = err
        return false
    end

    reserve:take(piece_type)
    local new_piece = Pieces.new(piece_type, invoker.owner, dest_col, dest_row)
    self.board:set(dest_col, dest_row, new_piece)
    invoker.has_acted = true
    self.last_error = nil
    self.last_action = { type = "invoke", piece = invoker, summoned_type = piece_type,
                          dest_col = dest_col, dest_row = dest_row }

    self:_check_and_end_turn()
    return true
end

-- ─── Pass action ─────────────────────────────────────────────────────────────
-- Ends the turn without doing anything. Always succeeds.
function State:apply_pass()
    if self.winner then return false end
    self.last_error = nil
    self.last_action = { type = "pass" }
    self:_end_turn()
    return true
end

-- ─── Internal helpers ─────────────────────────────────────────────────────────
function State:_capture(piece)
    -- Remove from board
    self.board:set(piece.col, piece.row, nil)
    -- Add to the CAPTURING player's reserve (opposite of piece's owner)
    local capturer = self:opponent_of(piece.owner)
    self.reserves[capturer]:add(piece.type)
    -- Mark piece as off-board
    piece.col = nil
    piece.row = nil
end

function State:_check_and_end_turn()
    local w = Rules.check_win(self.board)
    if w then
        self.winner = w
    else
        self:_end_turn()
    end
end

function State:_end_turn()
    -- Reset has_acted for all pieces of the current player
    self.board:each_piece(function(p)
        if p.owner == self.current_player then
            p.has_acted = false
        end
    end)
    self.current_player = self:opponent()
    self.turn_number    = self.turn_number + 1
end

-- ─── Helpers ──────────────────────────────────────────────────────────────────
function State:opponent()
    return self.current_player == "south" and "north" or "south"
end

function State:opponent_of(owner)
    return owner == "south" and "north" or "south"
end

function State:is_game_over()
    return self.winner ~= nil
end

-- Returns all selectable pieces for the current player (not yet acted).
function State:active_pieces()
    local result = {}
    self.board:each_piece(function(p)
        if p.owner == self.current_player and not p.has_acted then
            result[#result + 1] = p
        end
    end)
    return result
end

return State
