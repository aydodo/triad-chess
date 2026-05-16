-- Triad Chess — Board class (5 cols × 7 rows)

local C = require("src.constants")

local Board = {}
Board.__index = Board

function Board.new(board_idx)
    local self = setmetatable({}, Board)
    self.idx = board_idx

    -- grid[row][col] = Piece or nil
    self.grid = {}
    for r = 1, C.BOARD_ROWS do
        self.grid[r] = {}
        for c = 1, C.BOARD_COLS do
            self.grid[r][c] = nil
        end
    end

    -- Active Enchanter totems: list of {col, row, captures_left, owner_team}
    self.totems = {}

    return self
end

-- ─── Validation ──────────────────────────────────────────────────────────────

function Board:is_valid(col, row)
    return col >= 1 and col <= C.BOARD_COLS
       and row >= 1 and row <= C.BOARD_ROWS
end

-- ─── Grid access ─────────────────────────────────────────────────────────────

function Board:get(col, row)
    if not self:is_valid(col, row) then return nil end
    return self.grid[row][col]
end

function Board:is_empty(col, row)
    return self:get(col, row) == nil
end

-- ─── Piece placement ─────────────────────────────────────────────────────────

function Board:place(piece)
    assert(self:is_valid(piece.col, piece.row),
        string.format("Board %d: invalid placement at %d,%d", self.idx, piece.col, piece.row))
    self.grid[piece.row][piece.col] = piece
end

function Board:remove(piece)
    if self.grid[piece.row] and self.grid[piece.row][piece.col] == piece then
        self.grid[piece.row][piece.col] = nil
    end
end

function Board:move(piece, new_col, new_row)
    self:remove(piece)
    piece:set_pos(self.idx, new_col, new_row)
    self.grid[new_row][new_col] = piece
end

-- ─── Queries ─────────────────────────────────────────────────────────────────

-- Returns all non-captured pieces on this board (optionally filtered by team)
function Board:pieces(team_id)
    local result = {}
    for r = 1, C.BOARD_ROWS do
        for c = 1, C.BOARD_COLS do
            local p = self.grid[r][c]
            if p and (team_id == nil or p.team_id == team_id) then
                table.insert(result, p)
            end
        end
    end
    return result
end

-- Is a cell in the invocation zone for a given team?
function Board:in_invoke_zone(col, row, team_id)
    local rows = (team_id == C.TEAM_A) and C.INVOKE_ROWS_A or C.INVOKE_ROWS_B
    for _, r in ipairs(rows) do
        if r == row then return true end
    end
    return false
end

-- Is a cell protected by a Guardian or Paladin of team_id?
-- Returns: protected (bool), protector (Piece or nil)
function Board:guardian_protected(col, row, team_id)
    for dr = -1, 1 do
        for dc = -1, 1 do
            if dr ~= 0 or dc ~= 0 then
                local p = self:get(col + dc, row + dr)
                if p and p.team_id == team_id and p:provides_protection() then
                    return true, p
                end
            end
        end
    end
    return false, nil
end

-- ─── Totem helpers ───────────────────────────────────────────────────────────

function Board:add_totem(col, row, owner_team)
    table.insert(self.totems, {
        col = col, row = row,
        captures_left = 3,
        owner_team = owner_team,
    })
end

-- Returns totem at position (or nil)
function Board:get_totem(col, row)
    for _, t in ipairs(self.totems) do
        if t.col == col and t.row == row then return t end
    end
    return nil
end

-- Check if a cell is inside any totem's 3×3 zone belonging to owner_team
function Board:in_totem_zone(col, row, owner_team)
    for _, t in ipairs(self.totems) do
        if t.owner_team == owner_team
           and math.abs(col - t.col) <= 1
           and math.abs(row - t.row) <= 1 then
            return true, t
        end
    end
    return false, nil
end

-- Notify a capture inside totem zones; destroys totem if captures_left reaches 0
function Board:on_capture_in_zone(col, row)
    for i = #self.totems, 1, -1 do
        local t = self.totems[i]
        if math.abs(col - t.col) <= 1 and math.abs(row - t.row) <= 1 then
            t.captures_left = t.captures_left - 1
            if t.captures_left <= 0 then
                table.remove(self.totems, i)
            end
        end
    end
end

-- Destroy totem if enemy steps on its cell
function Board:on_enemy_step(col, row, stepping_team)
    for i = #self.totems, 1, -1 do
        local t = self.totems[i]
        if t.col == col and t.row == row and t.owner_team ~= stepping_team then
            table.remove(self.totems, i)
        end
    end
end

return Board
