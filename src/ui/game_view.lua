-- Triad Chess — GameView
-- Orchestrates 3 BoardViews + HUD, handles mouse input.

local C         = require("src.constants")
local BoardView = require("src.ui.board_view")
local HUD       = require("src.ui.hud")
local Mov       = require("src.logic.movement")

local GameView = {}
GameView.__index = GameView

-- Layout
local SIDE_PAD    = 30   -- left/right screen margin
local TOP_PAD     = 40   -- top margin (room for board titles)
local BOARD_GAP   = 20   -- horizontal gap between boards
local HUD_GAP     = 24   -- gap between last board and HUD
local HUD_W       = 210

-- ─── Constructor ─────────────────────────────────────────────────────────────

function GameView.new(engine)
    local self    = setmetatable({}, GameView)
    self.engine   = engine

    -- Selection state
    self.sel_piece    = nil   -- currently selected Piece or nil
    self.sel_board    = nil   -- board_idx of selection

    self:_build_layout()
    return self
end

function GameView:_build_layout()
    local sw = love.graphics.getWidth()

    -- Compute board dimensions from BoardView
    local dummy = BoardView.new(1, 0, 0)
    local bw    = dummy:width()
    local bh    = dummy:height()

    -- 3 boards horizontally centred (leaving room for HUD)
    local total_boards_w = C.NUM_BOARDS * bw + (C.NUM_BOARDS - 1) * BOARD_GAP
    local start_x = SIDE_PAD

    self.board_views = {}
    for i = 1, C.NUM_BOARDS do
        local bx = start_x + (i - 1) * (bw + BOARD_GAP)
        local by = TOP_PAD
        self.board_views[i] = BoardView.new(i, bx, by)
    end

    local hud_x = start_x + total_boards_w + HUD_GAP
    local hud_y = TOP_PAD
    self.hud = HUD.new(hud_x, hud_y, HUD_W)
end

-- ─── Draw ─────────────────────────────────────────────────────────────────────

function GameView:draw()
    local state = self.engine.state

    for i, bv in ipairs(self.board_views) do
        bv:draw(state.boards[i])
    end

    self.hud:draw(state)

    -- Invoke mode overlay (shown when selection is an Invoker on row 4)
    if self.sel_piece and self.sel_piece.type == C.PIECE.INVOKER
       and self.sel_piece.row == C.NEUTRAL_ROW then
        self:_draw_invoke_hint()
    end
end

function GameView:_draw_invoke_hint()
    love.graphics.setColor(0.9, 0.85, 0.3, 0.9)
    love.graphics.printf(
        "Invoker ready — click an invocation zone cell to place a reserve piece",
        10, love.graphics.getHeight() - 24,
        love.graphics.getWidth() - 20, "center")
end

-- ─── Input ───────────────────────────────────────────────────────────────────

function GameView:mouse_pressed(mx, my, button)
    if button ~= 1 then return end
    local state = self.engine.state
    if state.game_over then return end

    -- Find clicked board
    for i, bv in ipairs(self.board_views) do
        local col, row = bv:from_screen(mx, my)
        if col and row then
            self:_on_board_click(i, col, row)
            return
        end
    end

    -- Click outside any board → deselect
    self:_deselect()
end

function GameView:_on_board_click(board_idx, col, row)
    local state        = self.engine.state
    local clicked_piece = state:piece_at(board_idx, col, row)

    if self.sel_piece then
        local sp = self.sel_piece

        -- ── Try MOVE or CAPTURE ───────────────────────────────────────────
        if sp.board_idx == board_idx then
            -- Check if destination is in valid moves
            local bv = self.board_views[board_idx]
            for _, m in ipairs(bv.valid_moves) do
                if m.col == col and m.row == row then
                    local ok, result = self.engine:execute_move(sp.id, col, row)
                    if ok then
                        -- Assassin retreat prompt (auto-skip for now; UI can extend)
                        self:_deselect()
                    else
                        self:_status("Move failed: " .. (result or ""))
                    end
                    return
                end
            end
            -- Check shoot
            for _, m in ipairs(bv.valid_shoots) do
                if m.col == col and m.row == row then
                    local ok, err = self.engine:execute_shoot(sp.id, col, row)
                    if ok then
                        self:_deselect()
                    else
                        self:_status("Shoot failed: " .. (err or ""))
                    end
                    return
                end
            end
        end

        -- ── Invoker cross-board invocation ────────────────────────────────
        if sp.type == C.PIECE.INVOKER and sp.row == C.NEUTRAL_ROW then
            local target_board = state.boards[board_idx]
            if target_board:in_invoke_zone(col, row, sp.team_id)
               and target_board:is_empty(col, row) then
                -- Open reserve picker (simplified: auto-pick first available)
                local reserve = state.reserves[sp.team_id]
                if #reserve > 0 then
                    local piece_type = state.all_pieces[reserve[1]].type
                    local ok, err = self.engine:execute_invoke(
                        sp.id, piece_type, board_idx, col, row)
                    if ok then
                        self:_deselect()
                    else
                        self:_status("Invoke failed: " .. (err or ""))
                    end
                    return
                end
            end
        end

        -- ── Re-select another own piece ───────────────────────────────────
        if clicked_piece and clicked_piece.team_id == state.current_team
           and not clicked_piece.has_acted then
            self:_select(clicked_piece)
            return
        end

        self:_deselect()
    else
        -- ── First click: select own active piece ──────────────────────────
        if clicked_piece
           and clicked_piece.team_id == state.current_team
           and not clicked_piece.has_acted
           and not clicked_piece.is_captured then
            self:_select(clicked_piece)
        end
    end
end

-- ─── Selection helpers ───────────────────────────────────────────────────────

function GameView:_select(piece)
    self.sel_piece = piece
    local state    = self.engine.state
    local board    = state.boards[piece.board_idx]
    local bv       = self.board_views[piece.board_idx]

    -- Compute valid moves (filter out allied destinations)
    local raw_moves = Mov.move_targets(piece, board)
    local valid_moves = {}
    for _, m in ipairs(raw_moves) do
        local occ = board:get(m.col, m.row)
        if not occ or occ.team_id ~= piece.team_id then
            -- Extra: Assassin straight-capture restriction handled in validation,
            -- but we remove straight-line enemy cells from display to avoid confusion
            if piece.type == C.PIECE.ASSASSIN and occ and occ.team_id ~= piece.team_id then
                local is_diag = math.abs(piece.col - m.col) == math.abs(piece.row - m.row)
                local is_one  = math.abs(piece.col - m.col) == 1
                if is_diag and is_one then
                    valid_moves[#valid_moves+1] = m
                end
            else
                valid_moves[#valid_moves+1] = m
            end
        end
    end

    -- Shoot targets with an enemy on them
    local raw_shoots = Mov.shoot_targets(piece, board)
    local valid_shoots = {}
    for _, m in ipairs(raw_shoots) do
        local occ = board:get(m.col, m.row)
        if occ and occ.team_id ~= piece.team_id then
            valid_shoots[#valid_shoots+1] = m
        end
    end

    -- Clear all boards, set only the piece's board
    for _, b in ipairs(self.board_views) do b:clear_selection() end
    bv:set_selection(piece, valid_moves, valid_shoots)
end

function GameView:_deselect()
    self.sel_piece = nil
    for _, bv in ipairs(self.board_views) do bv:clear_selection() end
end

function GameView:_status(msg)
    print("[GameView] " .. msg)
end

-- ─── Keyboard ────────────────────────────────────────────────────────────────

function GameView:key_pressed(key)
    if key == "escape" then
        self:_deselect()
    elseif key == "space" or key == "return" then
        self:_deselect()
        self.engine:end_turn()
    end
end

-- ─── Resize ──────────────────────────────────────────────────────────────────

function GameView:on_resize(w, h)
    self:_build_layout()
    -- Restore selection visuals if any
    if self.sel_piece then
        self:_select(self.sel_piece)
    end
end

return GameView
