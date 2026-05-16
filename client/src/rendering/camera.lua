--[[
    camera.lua — Orbital camera for Triad Chess Phase 1.

    Controls:
      Right mouse drag  → orbit (yaw / pitch)
      Scroll wheel      → zoom in/out
      Middle mouse drag → pan (future extension, not wired in Phase 1)

    Defaults: sitting at 45° elevation, looking down at the board centre.
    Yaw and pitch are clamped so the board stays visible.
]]

local Camera = {}
Camera.__index = Camera

-- ─── Defaults ─────────────────────────────────────────────────────────────────
local DEFAULT_YAW   =  0.0           -- radians, 0 = looking toward +Z
local DEFAULT_PITCH = -math.pi / 3   -- ~-60°, looking downward
local DEFAULT_DIST  = 14.0           -- world units from origin

local MIN_PITCH = -math.pi * 0.85    -- just past top-down
local MAX_PITCH = -0.15              -- slight above-horizon
local MIN_DIST  = 4.0
local MAX_DIST  = 30.0

-- ─── Constructor ─────────────────────────────────────────────────────────────
function Camera.new(sw, sh)
    local self = setmetatable({}, Camera)

    self.yaw   = DEFAULT_YAW
    self.pitch = DEFAULT_PITCH
    self.dist  = DEFAULT_DIST
    self.center = menori.ml.vec3(0, 0, 0)

    -- Right-drag state
    self._dragging = false
    self._drag_sensitivity = 0.005  -- radians per pixel

    -- Menori camera object
    self.cam = menori.PerspectiveCamera(55, sw / sh, 0.1, 200)
    self:_update_position()

    return self
end

-- ─── Internal: recompute eye from spherical coords ───────────────────────────
function Camera:_update_position()
    local r   = self.dist
    local py  = self.pitch
    local ya  = self.yaw
    -- Spherical → Cartesian (Y-up)
    local x   = r * math.cos(py) * math.sin(ya)
    local y   = r * math.sin(-py)   -- negative: pitch is negative when looking down
    local z   = r * math.cos(py) * math.cos(ya)

    self.cam.eye    = menori.ml.vec3(x, y, z)
    self.cam.center = self.center:clone()
    self.cam.up     = menori.ml.vec3(0, 1, 0)
    self.cam:update_view_matrix()
end

-- ─── Input callbacks ──────────────────────────────────────────────────────────
function Camera:mouse_pressed(x, y, btn)
    if btn == 2 then   -- right mouse button
        self._dragging  = true
        self._drag_x    = x
        self._drag_y    = y
    end
end

function Camera:mouse_released(x, y, btn)
    if btn == 2 then
        self._dragging = false
    end
end

function Camera:mouse_moved(x, y, dx, dy)
    if self._dragging then
        self.yaw   = self.yaw   + dx * self._drag_sensitivity
        self.pitch = self.pitch + dy * self._drag_sensitivity
        -- Clamp pitch
        self.pitch = math.max(MIN_PITCH, math.min(MAX_PITCH, self.pitch))
        self:_update_position()
    end
end

function Camera:wheel_moved(wx, wy)
    self.dist = self.dist - wy * 1.2
    self.dist = math.max(MIN_DIST, math.min(MAX_DIST, self.dist))
    self:_update_position()
end

-- ─── Resize ───────────────────────────────────────────────────────────────────
function Camera:resize(w, h)
    local ml = menori.ml
    self.cam.m_projection = ml.mat4():perspective_RH_NO(55, w / h, 0.1, 200)
    self:_update_position()
end

-- ─── Accessors ────────────────────────────────────────────────────────────────
function Camera:get()
    return self.cam
end

-- ─── Ray for mouse picking ────────────────────────────────────────────────────
-- Returns {origin, direction} ray in world space for screen coords (mx, my).
function Camera:ray_at(mx, my, sw, sh)
    return self.cam:screen_point_to_ray(mx, my, {0, 0, sw, sh})
end

return Camera
