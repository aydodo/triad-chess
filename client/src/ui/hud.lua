--[[
    hud.lua — 2D overlay HUD for Triad Chess Phase 1.

    Draws on top of the 3D scene using love.graphics 2D primitives.

    Layout (1280×720 reference):
      Top bar    : current player, turn number
      Bottom-left: south reserve
      Bottom-right: north reserve
      Centre-top : game-over banner
      Bottom-centre: last action / error message
      Right panel: invoke mode indicator + instructions
]]

local Pieces = require("src.game.pieces")

local HUD = {}
HUD.__index = HUD

-- ─── Piece label abbreviations ─────────────────────────────────────────────
local LABELS = {
    [Pieces.TYPE.KING]     = "ROI",
    [Pieces.TYPE.INVOKER]  = "INV",
    [Pieces.TYPE.KNIGHT]   = "CAV",
    [Pieces.TYPE.ARCHER]   = "ARC",
    [Pieces.TYPE.GUARDIAN] = "GAR",
}

-- ─── Colors ───────────────────────────────────────────────────────────────────
local C = {
    bg          = {0, 0, 0, 0.55},
    text        = {1, 1, 1, 1},
    text_dim    = {0.75, 0.75, 0.75, 1},
    south       = {0.35, 0.60, 1.00, 1},
    north       = {1.00, 0.38, 0.32, 1},
    error       = {1.00, 0.35, 0.30, 1},
    success     = {0.35, 1.00, 0.50, 1},
    winner_bg   = {0.05, 0.05, 0.05, 0.82},
    invoke_mode = {0.95, 0.88, 0.25, 1},
    key_hint    = {0.65, 0.65, 0.65, 1},
}

-- ─── Constructor ─────────────────────────────────────────────────────────────
function HUD.new()
    local self = setmetatable({}, HUD)
    self.font_large  = love.graphics.newFont(22)
    self.font_medium = love.graphics.newFont(16)
    self.font_small  = love.graphics.newFont(12)
    return self
end

-- ─── Update (nothing dynamic yet) ────────────────────────────────────────────
function HUD:update(dt, state)
    -- placeholder for future animations / timers
end

-- ─── Draw ─────────────────────────────────────────────────────────────────────
function HUD:draw(state, input, sw, sh)
    local lg = love.graphics
    lg.push('all')

    -- ── Top bar: current player + turn ──────────────────────────────────────
    self:_draw_top_bar(state, input, sw, sh)

    -- ── Reserve panels ───────────────────────────────────────────────────────
    self:_draw_reserve_panel(state, input, "south", 10, sh - 100, sw, sh)
    self:_draw_reserve_panel(state, input, "north", sw - 210, sh - 100, sw, sh)

    -- ── Last action / error message ───────────────────────────────────────
    self:_draw_status_line(state, input, sw, sh)

    -- ── Invoke mode indicator ─────────────────────────────────────────────
    if input and input.mode == "invoke_select_type" then
        self:_draw_invoke_selector(state, input, sw, sh)
    end

    -- ── Game over banner ──────────────────────────────────────────────────
    if state.winner then
        self:_draw_game_over(state, sw, sh)
    end

    -- ── Key hints ─────────────────────────────────────────────────────────
    self:_draw_hints(sw, sh)

    lg.pop()
end

-- ─── Top bar ─────────────────────────────────────────────────────────────────
function HUD:_draw_top_bar(state, input, sw, sh)
    local lg = love.graphics
    local h  = 38

    -- Background
    lg.setColor(C.bg)
    lg.rectangle('fill', 0, 0, sw, h)

    -- Player indicator
    local player = state.current_player
    local color  = player == "south" and C.south or C.north
    local label  = player == "south" and "SOUTH (bleu)" or "NORTH (rouge)"
    lg.setColor(color)
    lg.rectangle('fill', 0, 0, 5, h)

    lg.setFont(self.font_large)
    lg.setColor(color)
    lg.print("Tour " .. state.current_player:upper(), 14, 8)

    -- Turn number
    lg.setColor(C.text_dim)
    lg.setFont(self.font_medium)
    lg.printf("Tour n° " .. state.turn_number, 0, 11, sw, 'center')

    -- Invoke mode label
    if input and input.mode ~= "idle" and input.mode ~= "piece_selected" then
        local mode_labels = {
            invoke_select_type = "Sélectionner type à invoquer",
            invoke_place       = "Choisir case d'invocation",
        }
        local ml = mode_labels[input.mode] or input.mode
        lg.setColor(C.invoke_mode)
        lg.printf(ml, 0, 11, sw, 'right')
        lg.printf("", 0, 0, sw - 10, 'right')  -- padding
    end
end

-- ─── Reserve panel ────────────────────────────────────────────────────────────
function HUD:_draw_reserve_panel(state, input, owner, x, y, sw, sh)
    local lg      = love.graphics
    local reserve = state.reserves[owner]
    local color   = owner == "south" and C.south or C.north
    local is_mine = (state.current_player == owner)

    -- Background box
    local bw, bh = 200, 90
    lg.setColor(C.bg)
    lg.rectangle('fill', x, y, bw, bh, 4)
    lg.setColor(color)
    lg.rectangle('line', x, y, bw, bh, 4)

    -- Title
    lg.setFont(self.font_small)
    lg.setColor(color)
    lg.print((owner == "south" and "RÉSERVE SUD" or "RÉSERVE NORD"), x + 6, y + 6)

    -- Pieces in reserve
    lg.setFont(self.font_medium)
    if reserve:is_empty() then
        lg.setColor(C.text_dim)
        lg.print("(vide)", x + 6, y + 28)
    else
        -- Count unique types
        local types = reserve:unique_types()
        local cx = x + 6
        for i, ptype in ipairs(types) do
            local count = reserve:count(ptype)
            local label = (LABELS[ptype] or ptype:upper()) .. (count > 1 and ("×"..count) or "")

            -- Highlight if this is the selected invoke type
            if input and input.invoke_type == ptype then
                lg.setColor(C.invoke_mode)
            elseif is_mine then
                lg.setColor(C.text)
            else
                lg.setColor(C.text_dim)
            end
            lg.print(label, cx, y + 28)
            cx = cx + 65
            if cx > x + bw - 10 then
                cx = x + 6
                y = y + 20
            end
        end
    end

    -- Invoke hint
    if is_mine and not reserve:is_empty() and input and input.mode == "idle" then
        lg.setFont(self.font_small)
        lg.setColor(C.key_hint)
        lg.print("[I] Invoquer", x + 6, y + 65)
    end
end

-- ─── Status / error line ──────────────────────────────────────────────────────
function HUD:_draw_status_line(state, input, sw, sh)
    local lg = love.graphics
    local msg, color

    if state.last_error then
        msg   = "✗ " .. state.last_error
        color = C.error
    elseif state.last_action then
        local a = state.last_action
        if a.type == "pass" then
            msg = "Passage de tour."
        elseif a.type == "move" then
            msg = (a.piece and a.piece.type or "?") .. " déplacé."
        elseif a.type == "shoot" then
            msg = "Archer tire !"
        elseif a.type == "invoke" then
            msg = (a.summoned_type or "?") .. " invoqué en (" .. (a.dest_col or "?") .. "," .. (a.dest_row or "?") .. ")."
        end
        color = C.success
    end

    if msg then
        local tw = sw - 20
        lg.setFont(self.font_medium)
        local padding = 6
        local text_h  = 24
        local bx = (sw - tw) / 2
        local by = sh - text_h - 14

        lg.setColor(C.bg)
        lg.rectangle('fill', bx, by - padding, tw, text_h + padding * 2, 4)
        lg.setColor(color or C.text)
        lg.printf(msg, bx + 4, by, tw - 8, 'center')
    end
end

-- ─── Invoke type selector ─────────────────────────────────────────────────────
function HUD:_draw_invoke_selector(state, input, sw, sh)
    local lg      = love.graphics
    local reserve = state.reserves[state.current_player]
    local types   = reserve:unique_types()

    if #types == 0 then return end

    local bw   = math.min(#types * 110 + 20, sw - 40)
    local bh   = 60
    local bx   = (sw - bw) / 2
    local by   = sh / 2 - bh / 2

    lg.setColor({0.05, 0.05, 0.05, 0.90})
    lg.rectangle('fill', bx, by, bw, bh, 6)
    lg.setColor(C.invoke_mode)
    lg.rectangle('line', bx, by, bw, bh, 6)

    lg.setFont(self.font_medium)
    lg.setColor(C.invoke_mode)
    lg.printf("Choisir type à invoquer :", bx, by - 24, bw, 'center')

    local cx = bx + 10
    for i, ptype in ipairs(types) do
        local count = reserve:count(ptype)
        local label = "[" .. i .. "] " .. (LABELS[ptype] or ptype:upper()) .. " ×" .. count
        if input.invoke_type == ptype then
            lg.setColor(C.invoke_mode)
            lg.rectangle('fill', cx - 4, by + 8, 100, 30, 4)
            lg.setColor({0,0,0,1})
        else
            lg.setColor(C.text)
        end
        lg.print(label, cx, by + 16)
        cx = cx + 110
    end
end

-- ─── Game over banner ────────────────────────────────────────────────────────
function HUD:_draw_game_over(state, sw, sh)
    local lg    = love.graphics
    local color = state.winner == "south" and C.south or C.north
    local label = (state.winner == "south" and "SOUTH" or "NORTH") .. " GAGNE !"

    local bw, bh = 460, 120
    local bx     = (sw - bw) / 2
    local by     = (sh - bh) / 2

    lg.setColor(C.winner_bg)
    lg.rectangle('fill', bx, by, bw, bh, 8)
    lg.setColor(color)
    lg.rectangle('line', bx, by, bw, bh, 8)

    lg.setFont(self.font_large)
    lg.setColor(color)
    lg.printf(label, bx, by + 28, bw, 'center')

    lg.setFont(self.font_medium)
    lg.setColor(C.text_dim)
    lg.printf("[R] Nouvelle partie   [Esc] Quitter", bx, by + 72, bw, 'center')
end

-- ─── Key hints ────────────────────────────────────────────────────────────────
function HUD:_draw_hints(sw, sh)
    local lg = love.graphics
    lg.setFont(self.font_small)
    lg.setColor(C.key_hint)

    local hints = {
        "[Clic G] Sélectionner / Déplacer / Tirer",
        "[I] Mode Invocation (si Invocateur sélectionné)",
        "[P] Passer le tour",
        "[Clic D drag] Pivoter caméra   [Molette] Zoom",
        "[R] Réinitialiser   [Esc] Quitter",
    }
    local x = 8
    local y = sh - (#hints * 16) - 6
    for _, h in ipairs(hints) do
        lg.print(h, x, y)
        y = y + 16
    end
end

return HUD
