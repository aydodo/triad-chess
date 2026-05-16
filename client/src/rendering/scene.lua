--[[
    scene.lua — Menori 3D scene for Triad Chess Phase 1.

    Board coordinate mapping:
      CELL = 1.1  (world units between cell centres)
      cell_world(col, row) = ((col-3)*CELL, 0, (row-4)*CELL)
      col 3, row 4 = board centre = world origin

    Scene layout (Y-up, right-hand):
      Board tiles: Plane nodes lying flat in XZ (rotated -90° around X in Models)
      Piece nodes: Box nodes standing upright on the board
      Selection / highlight: tile material color is swapped each frame in sync()

    Render loop:
      1. Render 3D scene into color+depth canvas
      2. Blit color canvas to screen with love.graphics.draw
      3. HUD draws its own 2D overlay on top (handled by hud.lua)
]]

local Camera = require("src.rendering.camera")
local Models = require("src.rendering.models")
local Board  = require("src.game.board")

local Scene = {}
Scene.__index = Scene

local CELL = 1.1  -- world units per board cell

-- ─── Helpers ──────────────────────────────────────────────────────────────────
local function cell_world(col, row)
    return (col - 3) * CELL, 0, (row - 4) * CELL
end

-- ─── Constructor ─────────────────────────────────────────────────────────────
function Scene.new(sw, sh)
    local self = setmetatable({}, Scene)

    self.sw = sw
    self.sh = sh

    -- Camera
    self.camera = Camera.new(sw, sh)

    -- Menori scene + environment
    self.m_scene = menori.Scene()
    self.env     = menori.Environment(self.camera:get())

    -- Root node
    self.root = menori.Node("root")

    -- Canvases for 3D rendering (color + depth)
    self:_init_canvases(sw, sh)

    -- Static tile nodes: tile_nodes[col][row] = ModelNode
    self.tile_nodes = {}
    self:_build_board()

    -- Dynamic piece nodes: keyed by piece identity (col*10+row at creation, or a unique id)
    -- We rebuild piece nodes each sync() call.
    self.piece_nodes = {}  -- list of {node, piece} pairs attached to root

    return self
end

function Scene:_init_canvases(sw, sh)
    self.color_canvas = love.graphics.newCanvas(sw, sh)
    -- Depth canvas — use 'depth16' (widely supported)
    local ok, depth_canvas = pcall(love.graphics.newCanvas, sw, sh, { format = 'depth16' })
    if ok then
        self.depth_canvas = depth_canvas
    else
        -- Fallback: some drivers need 'depth24'
        ok, depth_canvas = pcall(love.graphics.newCanvas, sw, sh, { format = 'depth24' })
        self.depth_canvas = ok and depth_canvas or nil
    end
end

-- ─── Build static board tiles ────────────────────────────────────────────────
function Scene:_build_board()
    for col = 1, Board.COLS do
        self.tile_nodes[col] = {}
        for row = 1, Board.ROWS do
            local color = Models.tile_base_color(col, row)
            local node  = Models.make_tile_node(color)
            local wx, wy, wz = cell_world(col, row)
            node:set_position(wx, wy, wz)
            self.root:attach(node)
            self.tile_nodes[col][row] = node
        end
    end
end

-- ─── Sync piece nodes to game state ──────────────────────────────────────────
-- Called after every state change.  Rebuilds piece node list from scratch.
-- `input` is optional (nil safe) — used for selection/highlight highlight.
function Scene:sync(state, input)
    -- Remove old piece nodes
    for _, entry in ipairs(self.piece_nodes) do
        entry.node:detach_from_parent()
    end
    self.piece_nodes = {}

    -- Reset tile colors to base
    for col = 1, Board.COLS do
        for row = 1, Board.ROWS do
            local color = Models.tile_base_color(col, row)
            self.tile_nodes[col][row].material:set('baseColor', color)
        end
    end

    -- Highlight selected piece and its valid targets
    if input then
        local sel = input.selected_piece
        if sel and sel.col then
            -- Selected tile
            self.tile_nodes[sel.col][sel.row].material:set('baseColor', Models.COLORS.tile_selected)
            -- Valid move/shoot targets
            for _, t in ipairs(input.valid_targets or {}) do
                if t.col and t.row and self.tile_nodes[t.col] and self.tile_nodes[t.col][t.row] then
                    self.tile_nodes[t.col][t.row].material:set('baseColor', Models.COLORS.tile_highlight)
                end
            end
        end
        -- Highlight invoke destination targets
        for _, t in ipairs(input.invoke_targets or {}) do
            if t.col and t.row and self.tile_nodes[t.col] and self.tile_nodes[t.col][t.row] then
                self.tile_nodes[t.col][t.row].material:set('baseColor', Models.COLORS.tile_highlight)
            end
        end
    end

    -- Create piece nodes
    local board = state.board
    board:each_piece(function(piece, col, row)
        local node = Models.make_piece_node(piece.type, piece.owner)
        local d    = Models.PIECE_DIM[piece.type] or {0.5, 0.7, 0.5}
        local wx, _, wz = cell_world(col, row)
        node:set_position(wx, d[2] / 2, wz)  -- sit on Y=0 floor
        self.root:attach(node)
        self.piece_nodes[#self.piece_nodes + 1] = { node = node, piece = piece }
    end)
end

-- ─── Update ───────────────────────────────────────────────────────────────────
function Scene:update(dt)
    self.m_scene:update_nodes(self.root, self.env)
end

-- ─── Draw ─────────────────────────────────────────────────────────────────────
function Scene:draw(state, input, sw, sh)
    -- Sync visual state to latest game/input state each frame
    self:sync(state, input)

    local lovg = love.graphics

    -- ── 3D render pass ──────────────────────────────────────────────────────
    if self.depth_canvas then
        lovg.setCanvas({ self.color_canvas, depthstencil = self.depth_canvas })
    else
        lovg.setCanvas(self.color_canvas)
    end

    lovg.clear(0.08, 0.10, 0.14, 1)  -- dark background

    if self.depth_canvas then
        lovg.setDepthMode('less', true)
    end

    self.m_scene:render_nodes(self.root, self.env, {
        clear = false,
        node_sort_comp = menori.Scene.alpha_mode_comp,
    })

    if self.depth_canvas then
        lovg.setDepthMode()
    end

    lovg.setCanvas()

    -- ── Blit 3D canvas to screen ─────────────────────────────────────────────
    lovg.setColor(1, 1, 1, 1)
    lovg.draw(self.color_canvas, 0, 0)
end

-- ─── Mouse picking — ray → board cell ────────────────────────────────────────
-- Returns col, row (integers) or nil, nil if the ray misses the board.
function Scene:pick(mx, my, sw, sh)
    local ray = self.camera:ray_at(mx, my, sw, sh)
    local orig = ray.origin
    local dir  = ray.direction

    -- Intersect with y = 0 plane
    if math.abs(dir.y) < 1e-6 then return nil, nil end
    local t = -orig.y / dir.y
    if t < 0 then return nil, nil end

    local hx = orig.x + t * dir.x
    local hz = orig.z + t * dir.z

    -- Convert world → grid
    local col = math.floor(hx / CELL + 3 + 0.5)
    local row = math.floor(hz / CELL + 4 + 0.5)

    if col >= 1 and col <= Board.COLS and row >= 1 and row <= Board.ROWS then
        return col, row
    end
    return nil, nil
end

-- ─── Resize ───────────────────────────────────────────────────────────────────
function Scene:resize(w, h)
    self.sw = w
    self.sh = h
    self.camera:resize(w, h)
    self:_init_canvases(w, h)
end

return Scene
