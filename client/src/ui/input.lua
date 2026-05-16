--[[
    input.lua — Mouse + keyboard input handler for Triad Chess Phase 1.

    Interaction finite-state machine:

      idle
        Left-click on own piece → piece_selected
        [P]                     → pass
        [I] (any own piece)     → invoke_select_type (if invoker on board)

      piece_selected (selected_piece set)
        Left-click on valid move/attack target → apply_move / apply_shoot
        Left-click elsewhere                   → back to idle
        [I] (if selected is Invoker)           → invoke_select_type

      invoke_select_type  (must have Invoker alive + reserve non-empty)
        [1..N] key                             → pick type → invoke_place
        [Esc] / [I]                            → idle

      invoke_place  (invoke_type chosen)
        Left-click valid invoke cell           → apply_invoke → idle
        [Esc]                                  → idle

    Camera input (right-drag, scroll) is forwarded to scene.camera regardless
    of the current interaction mode.

    Public fields (read by scene.lua and hud.lua):
      input.mode            : string  — FSM state
      input.selected_piece  : piece | nil
      input.invoke_type     : string | nil  — chosen reserve type
      input.valid_targets   : list of {col, row}  (move+shoot targets)
      input.invoke_targets  : list of {col, row}  (valid invoke cells)
]]

local Pieces = require("src.game.pieces")
local Rules  = require("src.game.rules")

local Input = {}
Input.__index = Input

-- ─── Constructor ─────────────────────────────────────────────────────────────
function Input.new(state, scene, hud)
    local self = setmetatable({}, Input)

    self.state  = state
    self.scene  = scene
    self.hud    = hud

    -- FSM
    self.mode           = "idle"
    self.selected_piece = nil
    self.invoke_type    = nil
    self.valid_targets  = {}
    self.invoke_targets = {}

    return self
end

-- ─── Mouse pressed ────────────────────────────────────────────────────────────
function Input:mouse_pressed(mx, my, btn)
    -- Forward right-click to camera for orbit
    if btn == 2 then
        self.scene.camera:mouse_pressed(mx, my, btn)
        return
    end

    if btn ~= 1 then return end           -- only handle left click below

    if self.state:is_game_over() then return end
    if self.state.current_player == nil  then return end

    local sw, sh = love.graphics.getDimensions()
    local col, row = self.scene:pick(mx, my, sw, sh)

    if self.mode == "idle" then
        self:_handle_idle_click(col, row)

    elseif self.mode == "piece_selected" then
        self:_handle_selected_click(col, row)

    elseif self.mode == "invoke_place" then
        self:_handle_invoke_place_click(col, row)

    end
end

-- ─── Mouse released ───────────────────────────────────────────────────────────
function Input:mouse_released(mx, my, btn)
    self.scene.camera:mouse_released(mx, my, btn)
end

-- ─── Mouse moved ─────────────────────────────────────────────────────────────
function Input:mouse_moved(mx, my, dx, dy)
    self.scene.camera:mouse_moved(mx, my, dx, dy)
end

-- ─── Wheel moved ──────────────────────────────────────────────────────────────
function Input:wheel_moved(wx, wy)
    self.scene.camera:wheel_moved(wx, wy)
end

-- ─── Keyboard ─────────────────────────────────────────────────────────────────
function Input:keypressed(key)
    if self.state:is_game_over() then return end

    -- Pass turn
    if key == "p" then
        self.state:apply_pass()
        self:_reset()
        return
    end

    -- Invoke mode toggle / select type
    if key == "i" then
        if self.mode == "idle" or self.mode == "piece_selected" then
            self:_enter_invoke_select()
        elseif self.mode == "invoke_select_type" or self.mode == "invoke_place" then
            self:_reset()
        end
        return
    end

    -- Escape: cancel
    if key == "escape" then
        if self.mode ~= "idle" then
            self:_reset()
        end
        return
    end

    -- Number keys 1-9: pick invoke type
    if self.mode == "invoke_select_type" then
        local n = tonumber(key)
        if n then
            local types = self.state.reserves[self.state.current_player]:unique_types()
            local ptype = types[n]
            if ptype then
                self.invoke_type = ptype
                self.mode = "invoke_place"
                self:_compute_invoke_targets()
            end
        end
        return
    end
end

-- ─── FSM helpers ─────────────────────────────────────────────────────────────
function Input:_reset()
    self.mode           = "idle"
    self.selected_piece = nil
    self.invoke_type    = nil
    self.valid_targets  = {}
    self.invoke_targets = {}
end

function Input:_handle_idle_click(col, row)
    if col == nil then self:_reset(); return end

    local piece = self.state.board:get(col, row)
    if piece and piece.owner == self.state.current_player and not piece.has_acted then
        self:_select_piece(piece)
    else
        self:_reset()
    end
end

function Input:_handle_selected_click(col, row)
    if col == nil then self:_reset(); return end

    local piece = self.selected_piece

    -- Clicking the same piece: deselect
    if piece.col == col and piece.row == row then
        self:_reset()
        return
    end

    -- Clicking another friendly piece: reselect
    local target = self.state.board:get(col, row)
    if target and target.owner == self.state.current_player and not target.has_acted then
        self:_select_piece(target)
        return
    end

    -- Try move
    local ok_move, _ = Rules.validate_move(piece, col, row, self.state.board)
    if ok_move then
        self.state:apply_move(piece, col, row)
        self:_reset()
        return
    end

    -- Try shoot (Archer)
    if piece.type == Pieces.TYPE.ARCHER then
        local ok_shoot, _ = Rules.validate_shoot(piece, col, row, self.state.board)
        if ok_shoot then
            self.state:apply_shoot(piece, col, row)
            self:_reset()
            return
        end
    end

    -- Nothing matched: deselect
    self:_reset()
end

function Input:_handle_invoke_place_click(col, row)
    if col == nil then self:_reset(); return end

    -- Find the current player's Invoker
    local invoker = self:_find_invoker()
    if not invoker then self:_reset(); return end

    local reserve = self.state.reserves[self.state.current_player]
    local ok, _ = Rules.validate_invoke(invoker, self.invoke_type, col, row,
                                         self.state.board, reserve)
    if ok then
        self.state:apply_invoke(invoker, self.invoke_type, col, row)
        self:_reset()
    else
        -- Show error (state.last_error already set by apply_invoke fail path)
        -- stay in invoke_place mode so player can retry
    end
end

function Input:_select_piece(piece)
    self.selected_piece = piece
    self.mode           = "piece_selected"
    self.valid_targets  = self:_compute_move_targets(piece)
    self.invoke_targets = {}
end

function Input:_enter_invoke_select()
    local invoker = self:_find_invoker()
    if not invoker then
        self.state.last_error = "Pas d'Invocateur disponible ou il a déjà agi."
        return
    end
    if self.state.reserves[self.state.current_player]:is_empty() then
        self.state.last_error = "La réserve est vide."
        return
    end
    self:_reset()
    self.mode = "invoke_select_type"
end

function Input:_compute_move_targets(piece)
    local targets = Pieces.move_targets(piece, self.state.board)
    -- Also add shoot targets for Archer (distinct highlight type would be nice,
    -- but for Phase 1 we merge them into valid_targets)
    if piece.type == Pieces.TYPE.ARCHER then
        local shoot = Pieces.shoot_targets(piece, self.state.board)
        for _, t in ipairs(shoot) do
            targets[#targets + 1] = t
        end
    end
    -- Filter out Guardian-protected squares for melee
    local filtered = {}
    for _, t in ipairs(targets) do
        local occ = self.state.board:get(t.col, t.row)
        if occ then
            -- It's a capture attempt — check legality
            if occ.owner ~= piece.owner then
                -- Archer shoot bypass
                local is_shoot_target = false
                if piece.type == Pieces.TYPE.ARCHER then
                    local shoots = Pieces.shoot_targets(piece, self.state.board)
                    for _, s in ipairs(shoots) do
                        if s.col == t.col and s.row == t.row then
                            is_shoot_target = true; break
                        end
                    end
                end
                if is_shoot_target or not Pieces.is_guardian_protected(occ, self.state.board) then
                    filtered[#filtered + 1] = t
                end
            end
        else
            filtered[#filtered + 1] = t
        end
    end
    return filtered
end

function Input:_compute_invoke_targets()
    local board  = self.state.board
    local owner  = self.state.current_player
    local result = {}
    for col = 1, 5 do
        for row = 1, 7 do
            if board:in_invoke_zone(row, owner) and board:is_empty(col, row) then
                result[#result + 1] = { col = col, row = row }
            end
        end
    end
    self.invoke_targets = result
end

function Input:_find_invoker()
    local invoker = nil
    self.state.board:each_piece(function(p)
        if p.owner == self.state.current_player
           and p.type == Pieces.TYPE.INVOKER
           and not p.has_acted then
            invoker = p
        end
    end)
    return invoker
end

-- ─── Expose keypressed to main.lua ───────────────────────────────────────────
-- main.lua calls love.keypressed → input:keypressed forwarded from there.
-- Wire it up:
function Input:love_keypressed(key)
    self:keypressed(key)
end

return Input
