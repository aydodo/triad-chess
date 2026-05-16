--[[
    pieces.lua — Piece data and move/attack generation for Phase 1.

    Phase 1 piece classes (5):
      KING     — moves 1 square in any direction (8 dirs), cannot be summoned
      INVOKER  — moves 1 square orthogonally (4 dirs), cannot be summoned,
                  can summon reserve pieces into own invoke zone
      KNIGHT   — L-shape (chess knight), can jump over pieces
      ARCHER   — moves like Invoker (1 orthogonal); OR shoots orthogonally
                  up to 2 squares (no piece-blocking on shot, can shoot through
                  empty squares); one action per turn (move OR shoot, not both)
      GUARDIAN — moves 1 square orthogonally; adjacent friendly pieces
                  cannot be captured by melee (Guardian aura).
                  NOTE: Archer ignores Guardian aura (ranged bypass).

    All pieces: 1 action per turn (move OR invoke OR shoot/attack).
    Capture = land on enemy piece (melee), or shoot enemy (archer only).
    Guardian aura: adjacent (ortho + diag) friendlies cannot be captured in melee.
]]

local Pieces = {}

-- ─── Piece types ─────────────────────────────────────────────────────────────
Pieces.TYPE = {
    KING     = "king",
    INVOKER  = "invoker",
    KNIGHT   = "knight",
    ARCHER   = "archer",
    GUARDIAN = "guardian",
}

-- Pieces that can never enter the reserve / be summoned.
Pieces.UNSUMMONABLE = { king = true, invoker = true }

-- ─── Constructor ─────────────────────────────────────────────────────────────
-- Returns a new piece table.
--   piece_type : string (one of Pieces.TYPE values)
--   owner      : "south" | "north"
--   col, row   : integer position on board (nil if in reserve)
function Pieces.new(piece_type, owner, col, row)
    return {
        type      = piece_type,
        owner     = owner,
        col       = col,   -- nil when in reserve
        row       = row,   -- nil when in reserve
        has_acted = false, -- reset each turn
    }
end

-- ─── Direction tables ─────────────────────────────────────────────────────────
local DIR_ORTHO = { {0,1},{0,-1},{1,0},{-1,0} }
local DIR_DIAG  = { {1,1},{1,-1},{-1,1},{-1,-1} }
local DIR_ALL8  = { {0,1},{0,-1},{1,0},{-1,0},{1,1},{1,-1},{-1,1},{-1,-1} }
local KNIGHT_JUMPS = {
    {1,2},{-1,2},{1,-2},{-1,-2},
    {2,1},{-2,1},{2,-1},{-2,-1},
}

-- ─── Move target generation ───────────────────────────────────────────────────
-- Returns a list of {col, row} destinations the piece can move TO
-- (empty squares or enemy-occupied squares that can be captured).
-- Does NOT filter out Guardian-protected squares — that is Rules.can_capture's job.
function Pieces.move_targets(piece, board)
    local targets = {}
    local col, row = piece.col, piece.row
    local ptype = piece.type

    if ptype == Pieces.TYPE.KING then
        for _, d in ipairs(DIR_ALL8) do
            local nc, nr = col + d[1], row + d[2]
            if board:is_valid(nc, nr) then
                local occ = board:get(nc, nr)
                if occ == nil or occ.owner ~= piece.owner then
                    targets[#targets + 1] = { col = nc, row = nr }
                end
            end
        end

    elseif ptype == Pieces.TYPE.INVOKER then
        for _, d in ipairs(DIR_ORTHO) do
            local nc, nr = col + d[1], row + d[2]
            if board:is_valid(nc, nr) then
                local occ = board:get(nc, nr)
                if occ == nil or occ.owner ~= piece.owner then
                    targets[#targets + 1] = { col = nc, row = nr }
                end
            end
        end

    elseif ptype == Pieces.TYPE.KNIGHT then
        for _, j in ipairs(KNIGHT_JUMPS) do
            local nc, nr = col + j[1], row + j[2]
            if board:is_valid(nc, nr) then
                local occ = board:get(nc, nr)
                if occ == nil or occ.owner ~= piece.owner then
                    targets[#targets + 1] = { col = nc, row = nr }
                end
            end
        end

    elseif ptype == Pieces.TYPE.ARCHER then
        -- Archer moves 1 orthogonal (like Invoker)
        for _, d in ipairs(DIR_ORTHO) do
            local nc, nr = col + d[1], row + d[2]
            if board:is_valid(nc, nr) then
                local occ = board:get(nc, nr)
                if occ == nil or occ.owner ~= piece.owner then
                    targets[#targets + 1] = { col = nc, row = nr }
                end
            end
        end

    elseif ptype == Pieces.TYPE.GUARDIAN then
        for _, d in ipairs(DIR_ORTHO) do
            local nc, nr = col + d[1], row + d[2]
            if board:is_valid(nc, nr) then
                local occ = board:get(nc, nr)
                if occ == nil or occ.owner ~= piece.owner then
                    targets[#targets + 1] = { col = nc, row = nr }
                end
            end
        end
    end

    return targets
end

-- ─── Shoot target generation (Archer only) ────────────────────────────────────
-- Returns a list of {col, row} squares the Archer can shoot at.
-- Range: up to 2 squares orthogonally. The shot travels through the first
-- empty square and can hit a piece in the second square (or the first if occupied).
-- Returns only squares that contain an enemy piece (valid shoot targets).
function Pieces.shoot_targets(piece, board)
    assert(piece.type == Pieces.TYPE.ARCHER, "Only Archer can shoot")
    local targets = {}
    local col, row = piece.col, piece.row

    for _, d in ipairs(DIR_ORTHO) do
        for dist = 1, 2 do
            local nc, nr = col + d[1] * dist, row + d[2] * dist
            if not board:is_valid(nc, nr) then break end
            local occ = board:get(nc, nr)
            if occ then
                if occ.owner ~= piece.owner then
                    targets[#targets + 1] = { col = nc, row = nr }
                end
                break -- blocked by any piece (friendly or enemy)
            end
        end
    end

    return targets
end

-- ─── Guardian aura check ──────────────────────────────────────────────────────
-- Returns true if `target_piece` is protected by at least one friendly Guardian.
-- Protection = a Guardian of the same owner is orthogonally or diagonally adjacent
-- to the target. This blocks melee capture only (not Archer shots).
function Pieces.is_guardian_protected(target_piece, board)
    local tc, tr = target_piece.col, target_piece.row
    for _, d in ipairs(DIR_ALL8) do
        local nc, nr = tc + d[1], tr + d[2]
        if board:is_valid(nc, nr) then
            local adj = board:get(nc, nr)
            if adj
               and adj.owner == target_piece.owner
               and adj.type  == Pieces.TYPE.GUARDIAN then
                return true
            end
        end
    end
    return false
end

-- ─── Threat cells (for future check/king danger UI) ───────────────────────────
-- Returns all cells threatened by `piece` (squares it attacks, not just moves to).
-- For Phase 1 this is the same as move_targets + shoot_targets for Archer.
function Pieces.threat_cells(piece, board)
    if piece.type == Pieces.TYPE.ARCHER then
        local t = Pieces.move_targets(piece, board)
        local s = Pieces.shoot_targets(piece, board)
        for _, v in ipairs(s) do t[#t + 1] = v end
        return t
    end
    return Pieces.move_targets(piece, board)
end

return Pieces
