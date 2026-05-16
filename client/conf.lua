-- conf.lua — LÖVE2D window configuration for Triad Chess Phase 1
function love.conf(t)
    t.title          = "Triad Chess — Phase 1 Prototype"
    t.version        = "11.4"
    t.window.width   = 1280
    t.window.height  = 720
    t.window.resizable = true
    t.window.vsync   = 1

    -- Enable depth buffer for 3D rendering (required by Menori)
    t.window.depth   = 16

    -- Disable unused modules to keep startup fast
    t.modules.joystick = false
    t.modules.touch    = false
    t.modules.video    = false
end
