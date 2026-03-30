-- Triad Chess — movement rules
-- Returns candidate cells; capture legality is checked separately in validation.lua

local C = require("src.constants")

local M = {}

-- All 8 orthogonal + diagonal directions
local DIR8 = {{0,1},{0,-1},{1,0},{-1,0},{1,1},{1,-1},{-1,1},{-1,-1}}
-- 4 orthogonal directions
local DIR4 = {{0,1},{0,-1},{1,0},{-1,0}}
-- 4 diagonal directions
local DIAG = {{1,1},{1,-1},{-1,1},{-1,-1}}

-- ─── Move targets (piece stays → new cell) ──────────────────────────────────
-- Returns list of {col, row}.  Does NOT filter allied-piece destinations —
-- the caller (game_view / validation) removes those for display / legality.

function M.move_targets(piece, board)
    local t    = piece.type
    local col  = piece.col
    local row  = piece.row
    local out  = {}

    local function push(nc, nr)
        if board:is_valid(nc, nr) then
            out[#out+1] = {col=nc, row=nr}
        end
    end

    -- Helper: slide up to `max_dist` in one direction, stopping when blocked
    local function slide(dc, dr, max_dist, can_capture_target)
        for d = 1, max_dist do
            local nc, nr = col + dc*d, row + dr*d
            if not board:is_valid(nc, nr) then break end
            local occ = board:get(nc, nr)
            if occ then
                if can_capture_target then push(nc, nr) end
                break
            end
            push(nc, nr)
        end
    end

    -- ── Mandatory pieces ──────────────────────────────────────────────────

    if t == C.PIECE.KING then
        for _, d in ipairs(DIR8) do push(col+d[1], row+d[2]) end

    elseif t == C.PIECE.INVOKER then
        -- 2 diagonal, destination must be EMPTY (Invoker never captures)
        for _, d in ipairs(DIAG) do
            local nc, nr = col+d[1]*2, row+d[2]*2
            if board:is_valid(nc, nr) and board:is_empty(nc, nr) then
                push(nc, nr)
            end
        end

    -- ── Draft slot 1 (mobile) ─────────────────────────────────────────────

    elseif t == C.PIECE.KNIGHT then
        -- L-shape, jumps over pieces
        for _, d in ipairs({{2,1},{2,-1},{-2,1},{-2,-1},{1,2},{1,-2},{-1,2},{-1,-2}}) do
            push(col+d[1], row+d[2])
        end

    elseif t == C.PIECE.ASSASSIN then
        -- Moves up to 3 cells straight or diagonal (no jump)
        -- Captures only diagonally adjacent (handled separately — Assassin cannot
        -- capture by walking straight; straight moves stop if blocked)
        for _, d in ipairs(DIR4) do
            slide(d[1], d[2], 3, false)  -- straight: cannot capture by stepping
        end
        for _, d in ipairs(DIAG) do
            -- diagonal: can step 1 cell to capture OR move up to 3 without capturing
            -- We include all 3 diagonal cells; validation filters capture legality
            slide(d[1], d[2], 3, true)
        end

    -- ── Draft slot 2 (ranged) ─────────────────────────────────────────────

    elseif t == C.PIECE.ARCHER then
        -- Moves 1 cell orthogonal (no diagonal move, no capture-by-move)
        for _, d in ipairs(DIR4) do push(col+d[1], row+d[2]) end

    elseif t == C.PIECE.MAGE then
        -- Moves 1 cell diagonal only
        for _, d in ipairs(DIAG) do push(col+d[1], row+d[2]) end

    -- ── Draft slot 3 (support/defence) ───────────────────────────────────

    elseif t == C.PIECE.GUARDIAN then
        -- 2 cells orthogonal, cannot jump over blocking piece
        for _, d in ipairs(DIR4) do
            slide(d[1], d[2], 2, true)
        end

    elseif t == C.PIECE.PALADIN then
        -- 1 cell all 8 directions
        for _, d in ipairs(DIR8) do push(col+d[1], row+d[2]) end

    elseif t == C.PIECE.ENCHANTER then
        -- 1 cell all 8 directions (but cannot capture — validated elsewhere)
        for _, d in ipairs(DIR8) do push(col+d[1], row+d[2]) end
    end

    return out
end

-- ─── Shoot targets (ranged attack — piece stays on origin) ──────────────────
-- Returns cells an Archer / Mage can fire at (regardless of occupant).

function M.shoot_targets(piece, board)
    local t   = piece.type
    local col = piece.col
    local row = piece.row
    local out = {}

    if t == C.PIECE.ARCHER then
        -- Exactly 2 cells orthogonal
        for _, d in ipairs(DIR4) do
            local nc, nr = col+d[1]*2, row+d[2]*2
            if board:is_valid(nc, nr) then
                out[#out+1] = {col=nc, row=nr}
            end
        end

    elseif t == C.PIECE.MAGE then
        -- Exactly 3 cells in any of 8 directions
        for _, d in ipairs(DIR8) do
            local nc, nr = col+d[1]*3, row+d[2]*3
            if board:is_valid(nc, nr) then
                out[#out+1] = {col=nc, row=nr}
            end
        end
    end

    return out
end

-- ─── Convenience: all cells a piece THREATENS (for check detection) ──────────
-- Combines move captures + shoot targets.

function M.threat_cells(piece, board)
    local cells = {}
    local seen  = {}

    local function add(nc, nr)
        local key = nc * 100 + nr
        if not seen[key] then
            seen[key] = true
            cells[#cells+1] = {col=nc, row=nr}
        end
    end

    -- Move-based threats (cells where piece would land to capture)
    for _, m in ipairs(M.move_targets(piece, board)) do
        add(m.col, m.row)
    end
    -- Ranged threats
    for _, s in ipairs(M.shoot_targets(piece, board)) do
        add(s.col, s.row)
    end

    return cells
end

return M
