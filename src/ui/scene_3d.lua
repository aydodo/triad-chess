-- Triad Chess — Scene3D  (Phase 2)
-- Menori-based 3D renderer. Replaces board_view.lua for Phase 2.
-- READ-ONLY: never mutates GameState or GameEngine.
--
-- Usage (main.lua Phase 2):
--   local Scene3D = require("src.ui.scene_3d")
--   local scene3d = Scene3D.new(engine)
--   -- in love.draw():  scene3d:draw()
--   -- in love.update(): scene3d:update(dt)

local C      = require("src.constants")
local menori = require("libs.menori.menori")
local ml     = menori.ml

-- ─── Layout ──────────────────────────────────────────────────────────────────
-- Each cell is 1 unit wide/deep.  Boards are spaced 8 units apart on X axis.
local CELL_SIZE   = 1.0
local BOARD_GAP   = 8.0       -- world-space X distance between board centres
local PIECE_H     = 1.0       -- piece box height

-- World position of a board's cell centre
local function cell_world(board_idx, col, row)
    local bx = (board_idx - 2) * BOARD_GAP          -- boards at -8, 0, +8
    local x  = bx + (col - 3) * CELL_SIZE           -- centre col=3 at board origin
    local z  = (row - 4) * CELL_SIZE                -- centre row=4 at 0
    return x, 0, z
end

-- ─── Colours ─────────────────────────────────────────────────────────────────
local TILE_LIGHT   = {0.88, 0.83, 0.72, 1}
local TILE_DARK    = {0.52, 0.42, 0.32, 1}
local TILE_NEUTRAL = {0.60, 0.68, 0.44, 1}
local TILE_INV_A   = {0.50, 0.75, 0.52, 1}
local TILE_INV_B   = {0.42, 0.55, 0.80, 1}
local PIECE_A_COL  = {0.95, 0.90, 0.78, 1}
local PIECE_B_COL  = {0.18, 0.22, 0.32, 1}
local SEL_COL      = {1.00, 1.00, 0.10, 1}
local MOVE_COL     = {0.15, 0.90, 0.30, 1}
local SHOOT_COL    = {1.00, 0.50, 0.10, 1}

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function make_tile(board_idx, col, row)
    local node = menori.ModelNode(menori.Plane(CELL_SIZE, CELL_SIZE))
    local x, y, z = cell_world(board_idx, col, row)
    node:set_position(x, y, z)
    node.board_idx = board_idx
    node.col       = col
    node.row       = row
    return node
end

local function make_piece_node(piece)
    -- Placeholder: Box mesh.  Swap with glTFLoader when models are ready:
    --   local loader = menori.glTFLoader.load("assets/models/"..piece.type..".glb")
    --   return menori.NodeTreeBuilder.create(loader, ...)
    local node = menori.ModelNode(menori.Box(0.65, PIECE_H, 0.65))
    local x, _, z = cell_world(piece.board_idx, piece.col, piece.row)
    node:set_position(x, PIECE_H * 0.5, z)
    node.piece_id = piece.id
    return node
end

local function tile_colour(board_idx, col, row)
    local in_a = false; for _,r in ipairs(C.INVOKE_ROWS_A) do if r==row then in_a=true end end
    local in_b = false; for _,r in ipairs(C.INVOKE_ROWS_B) do if r==row then in_b=true end end
    if row == C.NEUTRAL_ROW then return TILE_NEUTRAL
    elseif in_a             then return TILE_INV_A
    elseif in_b             then return TILE_INV_B
    elseif (col+row)%2 == 0 then return TILE_LIGHT
    else                         return TILE_DARK
    end
end

-- ─── Scene3D class ───────────────────────────────────────────────────────────

local Scene3D = {}
Scene3D.__index = Scene3D

function Scene3D.new(engine)
    local self    = setmetatable({}, Scene3D)
    self.engine   = engine

    -- Canvas (depth-enabled)
    local sw, sh  = love.graphics.getDimensions()
    self.canvas   = love.graphics.newCanvas(sw, sh, {format="rgba8", depth=true})

    -- Camera: isometric-ish perspective above the 3-board layout
    self.camera   = menori.PerspectiveCamera(55, sw/sh, 0.1, 500)
    self.camera:set_position(0, 18, 16)
    self.camera:look_at(ml.vec3(0, 0, 0))

    -- Environment + scene
    self.env      = menori.Environment(self.camera)
    self.scene    = menori.Scene()

    -- Root node
    self.root     = menori.Node()

    -- Node maps for fast updates
    self.tile_nodes  = {}   -- [board][col][row] = ModelNode
    self.piece_nodes = {}   -- [piece_id]        = ModelNode

    -- Selection state (mirrors GameView)
    self.sel_piece_id = nil
    self.valid_moves  = {}  -- list of {board,col,row}
    self.valid_shoots = {}

    self:_build_boards()

    return self
end

-- ─── Build static board tiles ────────────────────────────────────────────────

function Scene3D:_build_boards()
    for b = 1, C.NUM_BOARDS do
        self.tile_nodes[b] = {}
        for col = 1, C.BOARD_COLS do
            self.tile_nodes[b][col] = {}
            for row = 1, C.BOARD_ROWS do
                local node   = make_tile(b, col, row)
                local colour = tile_colour(b, col, row)
                -- TODO: apply colour via material uniform when Menori material API finalised
                -- node.material:set_uniform("base_color", colour)
                self.tile_nodes[b][col][row] = node
                self.root:attach(node)
            end
        end
    end
end

-- ─── Sync piece nodes from GameState ─────────────────────────────────────────

function Scene3D:_sync_pieces(state)
    local seen = {}

    -- Create / move existing nodes
    for _, piece in pairs(state.all_pieces) do
        if not piece.is_captured then
            seen[piece.id] = true
            local node = self.piece_nodes[piece.id]
            if not node then
                node = make_piece_node(piece)
                -- TODO: tint by team colour via material uniform
                self.piece_nodes[piece.id] = node
                self.root:attach(node)
            else
                -- Move to current position
                local x, _, z = cell_world(piece.board_idx, piece.col, piece.row)
                node:set_position(x, PIECE_H * 0.5, z)
            end
        end
    end

    -- Remove captured pieces from scene
    for pid, node in pairs(self.piece_nodes) do
        if not seen[pid] then
            node:detach()
            self.piece_nodes[pid] = nil
        end
    end
end

-- ─── Highlight selected + valid cells ────────────────────────────────────────

function Scene3D:set_selection(piece_id, moves, shoots)
    self.sel_piece_id = piece_id
    self.valid_moves  = moves  or {}
    self.valid_shoots = shoots or {}
    -- TODO: update tile materials to show sel/move/shoot colours
    -- for now, highlights are drawn as 2D quads in the HUD overlay layer
end

function Scene3D:clear_selection()
    self.sel_piece_id = nil
    self.valid_moves  = {}
    self.valid_shoots = {}
end

-- ─── Update / Draw ───────────────────────────────────────────────────────────

function Scene3D:update(dt)
    local state = self.engine.state
    self:_sync_pieces(state)
    self.scene:update_nodes(self.root, self.env)
end

function Scene3D:draw()
    local sw, sh = love.graphics.getDimensions()

    -- Resize canvas if window changed
    local cw, ch = self.canvas:getDimensions()
    if cw ~= sw or ch ~= sh then
        self.canvas = love.graphics.newCanvas(sw, sh, {format="rgba8", depth=true})
        self.camera.aspect = sw / sh
    end

    -- Render 3D scene into canvas
    love.graphics.setCanvas({self.canvas, depth=true})
    love.graphics.clear(0.08, 0.08, 0.10, 1)
    love.graphics.setDepthMode("less", true)

    self.scene:render_nodes(self.root, self.env)

    love.graphics.setDepthMode()
    love.graphics.setCanvas()

    -- Blit canvas to screen
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.canvas, 0, 0)
end

-- ─── Mouse picking (ray–AABB) ─────────────────────────────────────────────────
-- Returns {board_idx, col, row} of the cell under the screen cursor, or nil.

function Scene3D:pick(mx, my)
    local sw, sh = love.graphics.getDimensions()

    -- NDC
    local nx = (2 * mx / sw) - 1
    local ny = 1 - (2 * my / sh)

    -- Unproject two points to form a ray
    local inv_vp = ml.mat4()
    inv_vp:copy(self.camera.m_projection)
    inv_vp:mul(self.camera.m_view)
    inv_vp:inverse()

    local near = inv_vp * ml.vec4(nx, ny, -1, 1)
    local far  = inv_vp * ml.vec4(nx, ny,  1, 1)
    near = ml.vec3(near.x/near.w, near.y/near.w, near.z/near.w)
    far  = ml.vec3(far.x/far.w,   far.y/far.w,   far.z/far.w)

    local ray_dir = (far - near):normalize()

    -- Intersect with y=0 plane (board floor)
    if math.abs(ray_dir.y) < 1e-6 then return nil end
    local t = -near.y / ray_dir.y
    if t < 0 then return nil end

    local hit_x = near.x + ray_dir.x * t
    local hit_z = near.z + ray_dir.z * t

    -- Find which board / cell was hit
    for b = 1, C.NUM_BOARDS do
        local bx = (b - 2) * BOARD_GAP
        local local_x = hit_x - bx
        local col = math.floor(local_x / CELL_SIZE + 3.5)  -- +3 centres col=3
        local row = math.floor(hit_z  / CELL_SIZE + 4.5)   -- +4 centres row=4
        if col >= 1 and col <= C.BOARD_COLS and row >= 1 and row <= C.BOARD_ROWS then
            return {board_idx=b, col=col, row=row}
        end
    end
    return nil
end

return Scene3D
