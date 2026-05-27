--[[
    camera.lua — Underlords-style fixed tactical camera.

    Locked plunging view, frontal, slight perspective.  No orbital rotation
    by default (the board never spins in Underlords).  Wheel still zooms.

    Toggle free-orbit mode with [TAB] for debugging.

    Controls:
      Scroll wheel       → zoom in/out  (clamped tight)
      Right mouse drag   → orbit only when free_orbit is on
]]

local Camera = {}
Camera.__index = Camera

-- ─── Defaults — Underlords look ───────────────────────────────────────────────
local DEFAULT_YAW   =  0.0                  -- frontal
local DEFAULT_PITCH = -math.rad(48)         -- plunging ~48° down
local DEFAULT_DIST  = 11.5                  -- frames a 5×7 board comfortably
local DEFAULT_FOV   = 48                    -- tactical / cinematic feel

-- Zoom clamps (tight on purpose — Underlords doesn't let you zoom much)
local MIN_DIST  = 8.0
local MAX_DIST  = 16.0

-- Free-orbit clamps (only used when toggled on)
local MIN_PITCH = -math.pi * 0.85
local MAX_PITCH = -0.15

-- ─── Constructor ─────────────────────────────────────────────────────────────
function Camera.new(sw, sh)
    local self = setmetatable({}, Camera)

    self.yaw   = DEFAULT_YAW
    self.pitch = DEFAULT_PITCH
    self.dist  = DEFAULT_DIST
    self.center = menori.ml.vec3(0, 0, 0)
    self.fov   = DEFAULT_FOV

    -- Free-orbit toggle (off by default for Underlords feel)
    self.free_orbit = false

    -- Right-drag state
    self._dragging = false
    self._drag_sensitivity = 0.005

    self.cam = menori.PerspectiveCamera(self.fov, sw / sh, 0.1, 200)
    self:_update_position()

    return self
end

-- ─── Spherical → Cartesian ────────────────────────────────────────────────────
function Camera:_update_position()
    local r  = self.dist
    local py = self.pitch
    local ya = self.yaw
    local x  = r * math.cos(py) * math.sin(ya)
    local y  = r * math.sin(-py)
    local z  = r * math.cos(py) * math.cos(ya)

    self.cam.eye    = menori.ml.vec3(x, y, z)
    self.cam.center = self.center:clone()
    self.cam.up     = menori.ml.vec3(0, 1, 0)
    self.cam:update_view_matrix()
end

-- ─── Input callbacks ──────────────────────────────────────────────────────────
function Camera:mouse_pressed(x, y, btn)
    if btn == 2 and self.free_orbit then
        self._dragging = true
    end
end

function Camera:mouse_released(x, y, btn)
    if btn == 2 then
        self._dragging = false
    end
end

function Camera:mouse_moved(x, y, dx, dy)
    if self._dragging and self.free_orbit then
        self.yaw   = self.yaw   + dx * self._drag_sensitivity
        self.pitch = self.pitch + dy * self._drag_sensitivity
        self.pitch = math.max(MIN_PITCH, math.min(MAX_PITCH, self.pitch))
        self:_update_position()
    end
end

function Camera:wheel_moved(wx, wy)
    self.dist = self.dist - wy * 0.6
    self.dist = math.max(MIN_DIST, math.min(MAX_DIST, self.dist))
    self:_update_position()
end

-- ─── Toggle free orbit (debug aid) ───────────────────────────────────────────
function Camera:toggle_free_orbit()
    self.free_orbit = not self.free_orbit
    if not self.free_orbit then
        -- Snap back to default tactical view
        self.yaw   = DEFAULT_YAW
        self.pitch = DEFAULT_PITCH
        self:_update_position()
    end
    return self.free_orbit
end

-- ─── Resize ───────────────────────────────────────────────────────────────────
function Camera:resize(w, h)
    local ml = menori.ml
    self.cam.m_projection = ml.mat4():perspective_RH_NO(self.fov, w / h, 0.1, 200)
    self:_update_position()
end

-- ─── Accessors ────────────────────────────────────────────────────────────────
function Camera:get()
    return self.cam
end

function Camera:ray_at(mx, my, sw, sh)
    return self.cam:screen_point_to_ray(mx, my, {0, 0, sw, sh})
end

return Camera
