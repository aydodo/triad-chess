--[[
    board.lua — Single 5×7 board for Triad Chess Phase 1.

    Columns: 1-5  (maps to letters a-e in the full spec)
    Rows:    1-7  (row 1 = south edge, row 7 = north edge)
    Neutral: row 4
    South invoke zone: rows 1-3 (south player's starting side)
    North invoke zone: rows 5-7 (north player's starting side)
]]

local Board = {}
Board.__index = Board

Board.COLS        = 5
Board.ROWS        = 7
Board.NEUTRAL_ROW = 4

-- ─── Constructor ──────────────────────────────────────────────────────────────
-- grid[row][col] = piece object | nil
function Board.new()
    local self = setmetatable({}, Board)
    self.grid = {}
    for r = 1, Board.ROWS do
        self.grid[r] = {}
        for c = 1, Board.COLS do
            self.grid[r][c] = nil
        end
    end
    return self
end

-- ─── Cell queries ─────────────────────────────────────────────────────────────
function Board:is_valid(col, row)
    return col >= 1 and col <= Board.COLS
       and row >= 1 and row <= Board.ROWS
end

function Board:get(col, row)
    if not self:is_valid(col, row) then return nil end
    return self.grid[row][col]
end

function Board:set(col, row, piece)
    if self:is_valid(col, row) then
        self.grid[row][col] = piece
    end
end

function Board:is_empty(col, row)
    return self:get(col, row) == nil
end

-- ─── Zone helpers ─────────────────────────────────────────────────────────────
-- owner: "south" | "north"
function Board:in_invoke_zone(row, owner)
    if owner == "south" then
        return row >= 1 and row <= 3
    else
        return row >= 5 and row <= 7
    end
end

function Board:is_neutral_row(row)
    return row == Board.NEUTRAL_ROW
end

-- ─── Iteration ───────────────────────────────────────────────────────────────
-- Calls fn(piece, col, row) for every non-nil cell.
function Board:each_piece(fn)
    for r = 1, Board.ROWS do
        for c = 1, Board.COLS do
            local p = self.grid[r][c]
            if p then fn(p, c, r) end
        end
    end
end

-- Returns a list of all pieces matching optional predicate pred(piece)->bool.
function Board:pieces(pred)
    local result = {}
    self:each_piece(function(p, c, r)
        if not pred or pred(p) then
            result[#result + 1] = p
        end
    end)
    return result
end

-- ─── Convenience ─────────────────────────────────────────────────────────────
-- Move a piece from (fc,fr) to (tc,tr). Does not validate — caller must validate first.
function Board:move_piece(from_col, from_row, to_col, to_row)
    local p = self:get(from_col, from_row)
    self:set(from_col, from_row, nil)
    self:set(to_col, to_row, p)
    if p then
        p.col = to_col
        p.row = to_row
    end
end

return Board
