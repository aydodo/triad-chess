--[[
    main.lua — Triad Chess Phase 1 entry point
    Hot-seat 1v1 prototype, single 5×7 board, 5 piece classes.
    South = rows 1-3 (bottom), North = rows 5-7 (top).
]]

-- Adjust package path so requires inside client/ work correctly.
-- Menori's gltf.lua hard-codes `require 'libs.json'`, so we need the Menori
-- submodule root on the package path for that to resolve.
local base = love.filesystem.getSource()
package.path = table.concat({
    base .. "/?.lua",
    base .. "/?/init.lua",
    base .. "/libs/menori/?.lua",
    base .. "/libs/menori/?/init.lua",
    package.path,
}, ";")

-- Menori internally uses love.filesystem.read() to load its shader .glsl
-- files, assuming Menori sits at the LOVE filesystem root.  Since we placed
-- it at libs/menori/, those reads would return nil.  Wrap love.filesystem.read
-- so any failed lookup falls back to the submodule directory.
do
    local native_read = love.filesystem.read
    local function fallback(path)
        if type(path) ~= "string" then return nil end
        local f = io.open(base .. "/libs/menori/" .. path, "rb")
        if not f then return nil end
        local content = f:read("*a")
        f:close()
        return content
    end
    function love.filesystem.read(a, b, c)
        local data, size = native_read(a, b, c)
        if data ~= nil then return data, size end
        -- love.filesystem.read can be called as (path[, size]) or
        -- (container, path[, size]). We only handle the string-container form.
        local path
        if a == "string" then
            path = b
        elseif a == "data" then
            return data, size  -- leave FileData form to the native impl
        else
            path = a
        end
        local content = fallback(path)
        if content then return content, #content end
        return data, size
    end
end

-- Load Menori (stored as git submodule at libs/menori)
menori = require("menori")

-- Game modules
local State   = require("src.game.state")
local Scene   = require("src.rendering.scene")
local HUD     = require("src.ui.hud")
local Input   = require("src.ui.input")

-- ─── Globals ─────────────────────────────────────────────────────────────────
local state   -- GameState
local scene   -- 3D Menori scene
local hud     -- 2D overlay
local input   -- mouse/keyboard handler

-- ─── love.load ───────────────────────────────────────────────────────────────
function love.load()
    love.graphics.setDefaultFilter("linear", "linear")
    love.window.setTitle("Triad Chess — Phase 1")

    local sw, sh = love.graphics.getDimensions()

    state  = State.new()
    scene  = Scene.new(sw, sh)
    hud    = HUD.new()
    input  = Input.new(state, scene, hud)

    scene:sync(state)
end

-- ─── love.update ─────────────────────────────────────────────────────────────
function love.update(dt)
    scene:update(dt)
    hud:update(dt, state)
end

-- ─── love.draw ───────────────────────────────────────────────────────────────
function love.draw()
    local sw, sh = love.graphics.getDimensions()
    scene:draw(state, input, sw, sh)
    hud:draw(state, input, sw, sh)
end

-- ─── Input callbacks — forwarded to Input module ────────────────────────────
function love.mousepressed(x, y, btn)
    input:mouse_pressed(x, y, btn)
end

function love.mousereleased(x, y, btn)
    input:mouse_released(x, y, btn)
end

function love.mousemoved(x, y, dx, dy)
    input:mouse_moved(x, y, dx, dy)
end

function love.wheelmoved(wx, wy)
    input:wheel_moved(wx, wy)
end

function love.keypressed(key)
    if key == "r" then
        -- Reset: rebuild everything
        local sw, sh = love.graphics.getDimensions()
        state  = State.new()
        scene  = Scene.new(sw, sh)
        hud    = HUD.new()
        input  = Input.new(state, scene, hud)
        scene:sync(state)
        return
    elseif key == "escape" and (not input or input.mode == "idle") then
        love.event.quit()
        return
    elseif key == "tab" then
        -- Toggle free-orbit camera (debug)
        scene.camera:toggle_free_orbit()
        return
    end
    -- Forward to input FSM
    if input then input:love_keypressed(key) end
end

function love.resize(w, h)
    scene:resize(w, h)
end
