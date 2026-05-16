-- Triad Chess — utility helpers

local Utils = {}

-- ─── Table helpers ───────────────────────────────────────────────────────────

function Utils.contains(tbl, val)
    for _, v in ipairs(tbl) do
        if v == val then return true end
    end
    return false
end

function Utils.index_of(tbl, val)
    for i, v in ipairs(tbl) do
        if v == val then return i end
    end
    return nil
end

function Utils.remove_value(tbl, val)
    local i = Utils.index_of(tbl, val)
    if i then table.remove(tbl, i) end
end

-- ─── Math helpers ────────────────────────────────────────────────────────────

function Utils.sign(x)
    if x > 0 then return 1 elseif x < 0 then return -1 else return 0 end
end

function Utils.clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

-- ─── Board notation ──────────────────────────────────────────────────────────

-- Column index → letter  (1 → 'a', 5 → 'e')
function Utils.col_to_letter(col)
    return string.char(string.byte('a') + col - 1)
end

-- Column letter → index  ('a' → 1)
function Utils.letter_to_col(letter)
    return string.byte(letter) - string.byte('a') + 1
end

-- Encode position as string, e.g. "P2-c4"
function Utils.pos_str(board_idx, col, row)
    return string.format("P%d-%s%d", board_idx, Utils.col_to_letter(col), row)
end

-- ─── Opponent helper ─────────────────────────────────────────────────────────

local C -- lazy require to avoid circular deps
function Utils.opponent(team_id)
    if not C then C = require("src.constants") end
    return team_id == C.TEAM_A and C.TEAM_B or C.TEAM_A
end

return Utils
