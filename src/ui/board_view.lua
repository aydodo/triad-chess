-- Triad Chess — BoardView
-- Renders one 5×7 board and handles cell selection.

local C   = require("src.constants")
local Mov = require("src.logic.movement")

local BoardView = {}
BoardView.__index = BoardView

-- ─── Layout constants ────────────────────────────────────────────────────────
local CELL      = 62    -- pixels per cell
local PAD       = 6     -- inner padding around the grid
local LABEL_W   = 18    -- width for row labels on the left

-- ─── Palette ─────────────────────────────────────────────────────────────────
local COL = {
    bg_light    = {0.88, 0.83, 0.72},
    bg_dark     = {0.52, 0.42, 0.32},
    neutral_row = {0.65, 0.72, 0.48},
    invoke_a    = {0.50, 0.78, 0.55, 0.35},
    invoke_b    = {0.45, 0.58, 0.82, 0.35},
    border      = {0.22, 0.18, 0.14},
    highlight   = {1.00, 1.00, 0.00, 0.55},   -- selected piece
    move_dot    = {0.10, 0.85, 0.30, 0.50},   -- valid move
    shoot_ring  = {1.00, 0.50, 0.10, 0.60},   -- valid shoot
    piece_a     = {0.95, 0.90, 0.78},
    piece_b     = {0.18, 0.22, 0.32},
    text_a      = {0.08, 0.08, 0.08},
    text_b      = {0.92, 0.92, 0.92},
    totem       = {0.80, 0.40, 0.90, 0.40},
    king_crown  = {1.00, 0.80, 0.00},
}

-- ─── Constructor ─────────────────────────────────────────────────────────────

function BoardView.new(board_idx, sx, sy)
    local self     = setmetatable({}, BoardView)
    self.board_idx = board_idx
    self.sx        = sx        -- screen top-left x
    self.sy        = sy        -- screen top-left y
    self.cell      = CELL
    -- Selection state
    self.sel_piece    = nil
    self.valid_moves  = {}
    self.valid_shoots = {}
    return self
end

function BoardView:width()  return LABEL_W + PAD + C.BOARD_COLS * CELL + PAD end
function BoardView:height() return PAD + C.BOARD_ROWS * CELL + PAD + 20 end  -- +20 bottom label

-- ─── Coordinate conversion ───────────────────────────────────────────────────

-- Board (col, row) → screen pixel top-left of that cell
function BoardView:cell_px(col, row)
    local px = self.sx + LABEL_W + PAD + (col - 1) * CELL
    local py = self.sy + PAD + (C.BOARD_ROWS - row) * CELL
    return px, py
end

-- Screen (sx, sy) → board (col, row).  Returns nil,nil if outside.
function BoardView:from_screen(sx, sy)
    local lx = sx - (self.sx + LABEL_W + PAD)
    local ly = sy - (self.sy + PAD)
    if lx < 0 or ly < 0 then return nil, nil end
    local col = math.floor(lx / CELL) + 1
    local row = C.BOARD_ROWS - math.floor(ly / CELL)
    if col < 1 or col > C.BOARD_COLS or row < 1 or row > C.BOARD_ROWS then
        return nil, nil
    end
    return col, row
end

-- ─── Selection ───────────────────────────────────────────────────────────────

function BoardView:set_selection(piece, moves, shoots)
    self.sel_piece    = piece
    self.valid_moves  = moves  or {}
    self.valid_shoots = shoots or {}
end

function BoardView:clear_selection()
    self.sel_piece    = nil
    self.valid_moves  = {}
    self.valid_shoots = {}
end

-- ─── Draw ─────────────────────────────────────────────────────────────────────

function BoardView:draw(board)
    self:_draw_background()
    self:_draw_cells(board)
    self:_draw_totems(board)
    self:_draw_overlays()
    self:_draw_pieces(board)
    self:_draw_labels()
end

function BoardView:_draw_background()
    local w = self:width()
    local h = self:height()
    love.graphics.setColor(COL.border)
    love.graphics.rectangle("fill", self.sx, self.sy, w, h - 20, 5)
end

function BoardView:_draw_cells(board)
    for row = 1, C.BOARD_ROWS do
        for col = 1, C.BOARD_COLS do
            local px, py = self:cell_px(col, row)

            -- Base colour
            local c
            if row == C.NEUTRAL_ROW then
                c = COL.neutral_row
            elseif (col + row) % 2 == 0 then
                c = COL.bg_light
            else
                c = COL.bg_dark
            end
            love.graphics.setColor(c)
            love.graphics.rectangle("fill", px, py, CELL, CELL)

            -- Invocation zone tint
            local in_a = false
            for _, r in ipairs(C.INVOKE_ROWS_A) do if r == row then in_a = true end end
            local in_b = false
            for _, r in ipairs(C.INVOKE_ROWS_B) do if r == row then in_b = true end end
            if in_a then
                love.graphics.setColor(COL.invoke_a)
                love.graphics.rectangle("fill", px, py, CELL, CELL)
            elseif in_b then
                love.graphics.setColor(COL.invoke_b)
                love.graphics.rectangle("fill", px, py, CELL, CELL)
            end
        end
    end
end

function BoardView:_draw_totems(board)
    for _, t in ipairs(board.totems) do
        local px, py = self:cell_px(t.col, t.row)
        -- 3×3 tint
        for dr = -1, 1 do
            for dc = -1, 1 do
                local nc, nr = t.col + dc, t.row + dr
                if board:is_valid(nc, nr) then
                    local ppx, ppy = self:cell_px(nc, nr)
                    love.graphics.setColor(COL.totem)
                    love.graphics.rectangle("fill", ppx, ppy, CELL, CELL)
                end
            end
        end
        -- Centre marker
        love.graphics.setColor(0.80, 0.30, 0.90, 0.9)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", px+4, py+4, CELL-8, CELL-8, 3)
        love.graphics.setColor(1,1,1,0.9)
        love.graphics.printf(tostring(t.captures_left), px, py + CELL/2 - 8, CELL, "center")
    end
end

function BoardView:_draw_overlays()
    -- Selected cell highlight
    if self.sel_piece and self.sel_piece.board_idx == self.board_idx then
        local px, py = self:cell_px(self.sel_piece.col, self.sel_piece.row)
        love.graphics.setColor(COL.highlight)
        love.graphics.rectangle("fill", px, py, CELL, CELL)
    end

    -- Valid move dots
    for _, m in ipairs(self.valid_moves) do
        local px, py = self:cell_px(m.col, m.row)
        love.graphics.setColor(COL.move_dot)
        local r = CELL * 0.22
        love.graphics.circle("fill", px + CELL/2, py + CELL/2, r)
    end

    -- Valid shoot rings
    for _, m in ipairs(self.valid_shoots) do
        local px, py = self:cell_px(m.col, m.row)
        love.graphics.setColor(COL.shoot_ring)
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", px + CELL/2, py + CELL/2, CELL * 0.35)
    end
end

function BoardView:_draw_pieces(board)
    for row = 1, C.BOARD_ROWS do
        for col = 1, C.BOARD_COLS do
            local p = board:get(col, row)
            if p then self:_draw_piece(p) end
        end
    end
end

function BoardView:_draw_piece(p)
    local px, py = self:cell_px(p.col, p.row)
    local cx, cy = px + CELL/2, py + CELL/2
    local r      = CELL/2 - 5

    -- Piece circle
    local fill_col = p.team_id == C.TEAM_A and COL.piece_a or COL.piece_b
    love.graphics.setColor(fill_col)
    love.graphics.circle("fill", cx, cy, r)

    -- Outline (thicker if selected)
    local is_sel  = self.sel_piece and self.sel_piece.id == p.id
    local outline = is_sel and {1, 1, 0, 1} or {0.4, 0.4, 0.4, 0.8}
    love.graphics.setColor(outline)
    love.graphics.setLineWidth(is_sel and 3 or 1.5)
    love.graphics.circle("line", cx, cy, r)

    -- King crown dot
    if p.type == C.PIECE.KING then
        love.graphics.setColor(COL.king_crown)
        love.graphics.circle("fill", cx, cy - r * 0.3, 4)
    end

    -- Label
    local label     = C.PIECE_LABEL[p.type] or "?"
    local text_col  = p.team_id == C.TEAM_A and COL.text_a or COL.text_b
    love.graphics.setColor(text_col)
    love.graphics.printf(label, px, cy - 7, CELL, "center")

    -- "acted" dim overlay
    if p.has_acted then
        love.graphics.setColor(0, 0, 0, 0.35)
        love.graphics.circle("fill", cx, cy, r)
    end
end

function BoardView:_draw_labels()
    love.graphics.setColor(0.75, 0.75, 0.75, 1)
    -- Column letters (a-e) at bottom
    for col = 1, C.BOARD_COLS do
        local px = self.sx + LABEL_W + PAD + (col-1) * CELL
        local py = self.sy + PAD + C.BOARD_ROWS * CELL + 4
        love.graphics.printf(
            string.char(string.byte('a') + col - 1),
            px, py, CELL, "center")
    end
    -- Row numbers (1-7) on left
    for row = 1, C.BOARD_ROWS do
        local py = self.sy + PAD + (C.BOARD_ROWS - row) * CELL + CELL/2 - 8
        love.graphics.printf(tostring(row), self.sx, py, LABEL_W, "center")
    end
    -- Board title above
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.printf(
        "Board " .. self.board_idx,
        self.sx, self.sy - 20, self:width(), "center")
end

return BoardView
