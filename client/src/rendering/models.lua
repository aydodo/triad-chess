--[[
    models.lua — Material and mesh factories for Triad Chess Phase 1.

    All 3D visuals use primitive Menori shapes (no GLTF in Phase 1):
      Board tiles    — menori.Plane(0.95, 0.95) rotated flat, coloured by team zone
      Piece nodes    — menori.Box(W, H, D)  coloured by owner + type

    Colour palette (approx):
      South pieces  : steel-blue shades
      North pieces  : terracotta/red shades
      Tile (light)  : beige / cream
      Tile (dark)   : warm grey
      South zone    : subtle blue tint overlay
      North zone    : subtle red tint overlay
      Neutral row   : muted green
      Selected       : bright yellow
      Highlighted   : pale cyan (valid move targets)
]]

local Models = {}

-- ─── Colour definitions ──────────────────────────────────────────────────────
Models.COLORS = {
    -- Tile colours
    tile_light      = {0.85, 0.80, 0.72, 1},
    tile_dark       = {0.55, 0.52, 0.48, 1},
    tile_south_zone = {0.65, 0.72, 0.85, 1},  -- blue tint
    tile_north_zone = {0.85, 0.65, 0.62, 1},  -- red tint
    tile_neutral    = {0.60, 0.72, 0.60, 1},  -- green tint
    tile_selected   = {0.95, 0.88, 0.25, 1},  -- yellow
    tile_highlight  = {0.55, 0.90, 0.90, 1},  -- cyan

    -- Piece colours by owner
    south = {
        king     = {0.20, 0.45, 0.80, 1},
        invoker  = {0.25, 0.55, 0.75, 1},
        knight   = {0.30, 0.60, 0.85, 1},
        archer   = {0.15, 0.50, 0.90, 1},
        guardian = {0.20, 0.40, 0.70, 1},
    },
    north = {
        king     = {0.85, 0.25, 0.20, 1},
        invoker  = {0.78, 0.30, 0.25, 1},
        knight   = {0.90, 0.35, 0.22, 1},
        archer   = {0.80, 0.22, 0.30, 1},
        guardian = {0.75, 0.28, 0.20, 1},
    },
}

-- ─── Piece dimensions (W, H, D) ───────────────────────────────────────────────
-- H is taller for more important pieces.
Models.PIECE_DIM = {
    king     = {0.55, 0.90, 0.55},
    invoker  = {0.50, 0.80, 0.50},
    knight   = {0.52, 0.75, 0.52},
    archer   = {0.40, 0.72, 0.40},
    guardian = {0.60, 0.65, 0.60},
}

-- ─── Material factory ─────────────────────────────────────────────────────────
-- Creates a fresh Material with the given RGBA color table {r,g,b,a}.
function Models.make_material(color)
    local mat = menori.Material()
    mat:set('baseColor', color)
    return mat
end

-- ─── Tile mesh (shared) ───────────────────────────────────────────────────────
-- One Plane mesh is reused for all tiles; colours differ per ModelNode material.
local _tile_mesh = nil
function Models.tile_mesh()
    if not _tile_mesh then
        _tile_mesh = menori.Plane(0.95, 0.95)
    end
    return _tile_mesh
end

-- ─── Piece mesh (per type) ────────────────────────────────────────────────────
local _piece_meshes = {}
function Models.piece_mesh(piece_type)
    if not _piece_meshes[piece_type] then
        local d = Models.PIECE_DIM[piece_type] or {0.50, 0.70, 0.50}
        _piece_meshes[piece_type] = menori.Box(d[1], d[2], d[3])
    end
    return _piece_meshes[piece_type]
end

-- ─── Tile node factory ────────────────────────────────────────────────────────
-- Returns a ModelNode for a board tile at the given color, rotated flat (XZ plane).
function Models.make_tile_node(color)
    local mat  = Models.make_material(color)
    local node = menori.ModelNode(Models.tile_mesh(), mat)
    -- Rotate plane from XY to XZ (-90° around X axis)
    node:set_rotation(menori.ml.quat.from_angle_axis(-math.pi / 2, 1, 0, 0))
    return node
end

-- ─── Piece node factory ───────────────────────────────────────────────────────
-- Returns a ModelNode for a piece.
function Models.make_piece_node(piece_type, owner)
    local color = (Models.COLORS[owner] or {})[piece_type] or {1, 1, 1, 1}
    local mat   = Models.make_material(color)
    return menori.ModelNode(Models.piece_mesh(piece_type), mat)
end

-- ─── Tile colour logic ────────────────────────────────────────────────────────
-- Returns the base colour for a tile at (col, row) based on board zones.
function Models.tile_base_color(col, row)
    local Board = require("src.game.board")
    if row == Board.NEUTRAL_ROW then
        return Models.COLORS.tile_neutral
    elseif row <= 3 then
        -- South zone — alternate dark/light with blue tint
        local is_dark = (col + row) % 2 == 0
        if is_dark then
            return {0.45, 0.50, 0.68, 1}
        else
            return Models.COLORS.tile_south_zone
        end
    elseif row >= 5 then
        -- North zone — alternate dark/light with red tint
        local is_dark = (col + row) % 2 == 0
        if is_dark then
            return {0.68, 0.45, 0.42, 1}
        else
            return Models.COLORS.tile_north_zone
        end
    else
        -- Should not happen (row 4 is neutral above), but fallback
        local is_dark = (col + row) % 2 == 0
        return is_dark and Models.COLORS.tile_dark or Models.COLORS.tile_light
    end
end

return Models
