--[[
    Triad Chess — Love2D prototype
    3v3 tactical chess/MOBA hybrid with shared invocation mechanics.

    Phase 1: 2D local prototype (1 board or all 3 boards, 2 human teams)
    Phase 2: 3D rendering via Menori (libs/menori/)

    Controls:
        Left click   — select piece, then click destination to act
        Space/Enter  — end current team's turn manually
        Escape       — deselect piece
        R            — reset game
--]]

local GameEngine = require("src.game_engine")
local GameView   = require("src.ui.game_view")

local engine
local view

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setLineStyle("smooth")

    local font = love.graphics.newFont(13)
    love.graphics.setFont(font)

    engine = GameEngine.new()
    view   = GameView.new(engine)

    print("[TriadChess] Loaded — Turn 1, Team A to move")
    print("[TriadChess] Boards: 3 × (5 cols × 7 rows)")
    print("[TriadChess] Default draft: Knight + Archer + Guardian per player")
end

function love.update(dt)
    if not engine.state.game_over then
        engine:update(dt)
    end
end

function love.draw()
    love.graphics.clear(0.11, 0.11, 0.13, 1)
    view:draw()
end

function love.mousepressed(x, y, button)
    view:mouse_pressed(x, y, button)
end

function love.keypressed(key)
    if key == "r" then
        engine = GameEngine.new()
        view   = GameView.new(engine)
    else
        view:key_pressed(key)
    end
end

function love.resize(w, h)
    view:on_resize(w, h)
end
