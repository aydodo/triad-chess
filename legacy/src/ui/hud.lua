-- Triad Chess — HUD
-- Draws turn info, timers, momentum bars, reserves, and win screen.

local C = require("src.constants")

local HUD = {}
HUD.__index = HUD

function HUD.new(sx, sy, width)
    local self  = setmetatable({}, HUD)
    self.sx     = sx
    self.sy     = sy
    self.width  = width
    return self
end

local TEAM_NAME  = { [C.TEAM_A] = "Team A", [C.TEAM_B] = "Team B" }
local TEAM_COLOR = {
    [C.TEAM_A] = {0.95, 0.85, 0.40, 1},
    [C.TEAM_B] = {0.45, 0.65, 0.95, 1},
}

function HUD:draw(state)
    local x, y, w = self.sx, self.sy, self.width

    -- ── Current team banner ───────────────────────────────────────────────
    local tc = TEAM_COLOR[state.current_team]
    love.graphics.setColor(tc[1], tc[2], tc[3], 0.15)
    love.graphics.rectangle("fill", x - 8, y, w + 8, 54, 4)

    love.graphics.setColor(tc)
    love.graphics.printf(
        TEAM_NAME[state.current_team] .. "'s Turn",
        x, y + 4, w, "center")

    love.graphics.printf(
        "Turn " .. state.turn_number,
        x, y + 22, w, "center")

    -- Timer colour flashes red when < 5 s
    local tc2 = state.turn_timer < 5
        and {1, 0.25, 0.25, 1} or {1, 1, 1, 0.85}
    love.graphics.setColor(tc2)
    love.graphics.printf(
        string.format("%.1f s", math.max(0, state.turn_timer)),
        x, y + 38, w, "center")

    y = y + 70

    -- ── Momentum bars ─────────────────────────────────────────────────────
    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.printf("Momentum", x, y, w, "center")
    y = y + 18

    for _, tid in ipairs({ C.TEAM_A, C.TEAM_B }) do
        y = self:_draw_momentum(state, tid, x, y, w) + 6
    end

    y = y + 10

    -- ── Kings alive ───────────────────────────────────────────────────────
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.printf("Kings alive", x, y, w, "center")
    y = y + 18

    for _, tid in ipairs({ C.TEAM_A, C.TEAM_B }) do
        love.graphics.setColor(TEAM_COLOR[tid])
        local crowns = ""
        for i = 1, state.kings_alive[tid] do crowns = crowns .. "♛ " end
        for i = state.kings_alive[tid] + 1, C.NUM_PLAYERS do crowns = crowns .. "✕ " end
        love.graphics.printf(
            TEAM_NAME[tid] .. ": " .. crowns,
            x, y, w, "left")
        y = y + 18
    end

    y = y + 12

    -- ── Reserves ──────────────────────────────────────────────────────────
    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.printf("Reserves (invocable)", x, y, w, "center")
    y = y + 18

    for _, tid in ipairs({ C.TEAM_A, C.TEAM_B }) do
        love.graphics.setColor(TEAM_COLOR[tid])
        local parts = {}
        for _, pid in ipairs(state.reserves[tid]) do
            local p = state.all_pieces[pid]
            if p then
                parts[#parts+1] = C.PIECE_LABEL[p.type] or "?"
            end
        end
        local str = TEAM_NAME[tid] .. ": "
              .. (#parts > 0 and table.concat(parts, " ") or "—")
        love.graphics.printf(str, x, y, w, "left")
        y = y + 18
    end

    y = y + 16

    -- ── Controls hint ─────────────────────────────────────────────────────
    love.graphics.setColor(0.55, 0.55, 0.55, 1)
    love.graphics.printf(
        "Click piece → click target\nSpace/Enter: end turn\nR: reset",
        x, y, w, "left")

    -- ── Game over overlay ─────────────────────────────────────────────────
    if state.game_over then
        self:_draw_winner(state)
    end
end

function HUD:_draw_momentum(state, team_id, x, y, w)
    local momentum = state.momentum[team_id]
    local bar_w    = w - 60
    local bar_h    = 16
    local fill     = (momentum / C.MOMENTUM_MAX) * bar_w

    -- Label
    love.graphics.setColor(TEAM_COLOR[team_id])
    love.graphics.printf(TEAM_NAME[team_id], x, y, 55, "left")

    -- BG
    love.graphics.setColor(0.18, 0.18, 0.18)
    love.graphics.rectangle("fill", x + 58, y, bar_w, bar_h, 3)

    -- Fill
    local fc = team_id == C.TEAM_A
        and {0.95, 0.65, 0.10, 1}
        or  {0.30, 0.55, 0.95, 1}
    if momentum >= C.MOMENTUM_MAX then fc = {1, 0.95, 0.2, 1} end
    love.graphics.setColor(fc)
    if fill > 0 then
        love.graphics.rectangle("fill", x + 58, y, fill, bar_h, 3)
    end

    -- Border
    love.graphics.setColor(0.45, 0.45, 0.45)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x + 58, y, bar_w, bar_h, 3)

    -- Value
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.printf(
        string.format("%d", momentum),
        x + 58, y, bar_w, "center")

    local next_y = y + bar_h + 2

    -- Ultimate ready badge
    if state:has_ultimate(team_id) then
        love.graphics.setColor(1, 0.9, 0.1, 1)
        love.graphics.printf("⚡ ULTIMATE READY", x, next_y, w, "center")
        next_y = next_y + 16
    end

    return next_y
end

function HUD:_draw_winner(state)
    local sw = love.graphics.getWidth()
    local sh = love.graphics.getHeight()

    -- Dim overlay
    love.graphics.setColor(0, 0, 0, 0.65)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    local winner = TEAM_NAME[state.winning_team]
    love.graphics.setColor(TEAM_COLOR[state.winning_team])
    love.graphics.printf(
        winner .. " wins!\n\nPress R to play again",
        sw / 2 - 200, sh / 2 - 40, 400, "center")
end

return HUD
