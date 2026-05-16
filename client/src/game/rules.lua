--[[
    rules.lua — Validation layer for Triad Chess Phase 1.

    All public functions return:
        true, nil           — action is legal
        false, "reason"     — action is illegal with human-readable reason

    Callers must check the first return value before applying any state mutation.
]]

local Pieces = require("src.game.pieces")

local Rules = {}

-- ─── Capture legality ────────────────────────────────────────────────────────
-- Can `attacker` capture `defender` in melee (landing on the square)?
-- Returns true/false.  Archer shots bypass Guardian — use Rules.can_shoot instead.
function Rules.can_capture(attacker, defender, board)
    if defender == nil then return true end          -- empty square, no capture
    if defender.owner == attacker.owner then
        return false -- cannot capture own pieces
    end
    -- Guardian aura protection blocks melee capture
    if Pieces.is_guardian_protected(defender, board) then
        return false
    end
    return true
end

-- Can `archer` shoot the piece at (tc, tr)?
-- Guardian aura does NOT protect against Archer shots.
function Rules.can_shoot(archer, tc, tr, board)
    local target = board:get(tc, tr)
    if target == nil then return false, "no target at destination" end
    if target.owner == archer.owner then return false, "cannot shoot own piece" end
    return true
end

-- ─── Move validation ─────────────────────────────────────────────────────────
function Rules.validate_move(piece, dest_col, dest_row, board)
    if piece.has_acted then
        return false, "piece has already acted this turn"
    end
    if not board:is_valid(dest_col, dest_row) then
        return false, "destination out of bounds"
    end
    -- Check the piece's move target list
    local targets = Pieces.move_targets(piece, board)
    local found = false
    for _, t in ipairs(targets) do
        if t.col == dest_col and t.row == dest_row then
            found = true
            break
        end
    end
    if not found then
        return false, "destination not reachable by this piece"
    end
    -- If destination is occupied by enemy, check capture legality
    local occupant = board:get(dest_col, dest_row)
    if occupant then
        if occupant.owner == piece.owner then
            return false, "cannot move onto own piece"
        end
        if not Rules.can_capture(piece, occupant, board) then
            return false, "target piece is protected by a Guardian"
        end
    end
    return true, nil
end

-- ─── Shoot validation (Archer only) ──────────────────────────────────────────
function Rules.validate_shoot(piece, dest_col, dest_row, board)
    if piece.type ~= Pieces.TYPE.ARCHER then
        return false, "only the Archer can shoot"
    end
    if piece.has_acted then
        return false, "piece has already acted this turn"
    end
    if not board:is_valid(dest_col, dest_row) then
        return false, "destination out of bounds"
    end
    local targets = Pieces.shoot_targets(piece, board)
    local found = false
    for _, t in ipairs(targets) do
        if t.col == dest_col and t.row == dest_row then
            found = true
            break
        end
    end
    if not found then
        return false, "target not in archer range or not an enemy"
    end
    return true, nil
end

-- ─── Invoke validation ────────────────────────────────────────────────────────
-- invoker   : the Invoker piece on the board
-- piece_type: string — which type to summon from reserve
-- dest_col, dest_row: where to place the summoned piece
-- board, reserve: current game state
function Rules.validate_invoke(invoker, piece_type, dest_col, dest_row, board, reserve)
    if invoker.type ~= Pieces.TYPE.INVOKER then
        return false, "only the Invoker can summon pieces"
    end
    if invoker.has_acted then
        return false, "Invoker has already acted this turn"
    end
    if Pieces.UNSUMMONABLE[piece_type] then
        return false, "King and Invoker cannot be summoned"
    end
    if not reserve:has(piece_type) then
        return false, "piece not available in reserve"
    end
    if not board:is_valid(dest_col, dest_row) then
        return false, "destination out of bounds"
    end
    if not board:is_empty(dest_col, dest_row) then
        return false, "destination square must be empty"
    end
    if not board:in_invoke_zone(dest_row, invoker.owner) then
        return false, "can only summon into own invoke zone (rows 1-3 for south, 5-7 for north)"
    end
    return true, nil
end

-- ─── Win condition ────────────────────────────────────────────────────────────
-- Returns "south", "north", or nil.
-- Win = the enemy King has been captured (no longer on board).
-- In Phase 1 the King is never in the reserve (captured → game over).
function Rules.check_win(board)
    local south_king = false
    local north_king = false
    board:each_piece(function(p)
        if p.type == "king" then
            if p.owner == "south" then south_king = true end
            if p.owner == "north" then north_king = true end
        end
    end)
    if not north_king then return "south" end
    if not south_king then return "north" end
    return nil
end

return Rules
