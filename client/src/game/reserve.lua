--[[
    reserve.lua — Captured piece reserve for each team.

    When a piece is captured it goes into the capturing team's reserve
    (mirroring Bughouse Chess). KING and INVOKER are never summonable;
    they are simply removed from play permanently when captured.

    The Invoker can summon any reserve piece into the owner's invoke zone.
]]

local Pieces = require("src.game.pieces")

local Reserve = {}
Reserve.__index = Reserve

-- ─── Constructor ─────────────────────────────────────────────────────────────
function Reserve.new()
    local self = setmetatable({}, Reserve)
    -- list of piece type strings (not full piece objects — we recreate on summon)
    self.pieces = {}
    return self
end

-- ─── Mutators ─────────────────────────────────────────────────────────────────
-- Add a captured piece (by type string) to the reserve.
-- KING and INVOKER are discarded (never summonable).
function Reserve:add(piece_type)
    if not Pieces.UNSUMMONABLE[piece_type] then
        self.pieces[#self.pieces + 1] = piece_type
    end
end

-- Remove and return one piece of the given type, or nil if not available.
function Reserve:take(piece_type)
    for i, pt in ipairs(self.pieces) do
        if pt == piece_type then
            table.remove(self.pieces, i)
            return piece_type
        end
    end
    return nil
end

-- ─── Queries ──────────────────────────────────────────────────────────────────
function Reserve:has(piece_type)
    for _, pt in ipairs(self.pieces) do
        if pt == piece_type then return true end
    end
    return false
end

function Reserve:count(piece_type)
    local n = 0
    for _, pt in ipairs(self.pieces) do
        if pt == piece_type then n = n + 1 end
    end
    return n
end

-- Returns sorted list of unique types (for HUD display).
function Reserve:unique_types()
    local seen = {}
    local result = {}
    for _, pt in ipairs(self.pieces) do
        if not seen[pt] then
            seen[pt] = true
            result[#result + 1] = pt
        end
    end
    table.sort(result)
    return result
end

function Reserve:is_empty()
    return #self.pieces == 0
end

function Reserve:size()
    return #self.pieces
end

return Reserve
