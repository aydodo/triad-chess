-- Triad Chess — action validation
-- All public functions return (ok: bool, err: string|nil)

local C   = require("src.constants")
local Mov = require("src.logic.movement")

local V = {}

-- ─── Internal helpers ────────────────────────────────────────────────────────

-- Can `attacker` capture `target` on `board`?
local function capture_ok(attacker, target, board)
    if not attacker:can_capture() then
        return false, attacker.type .. " cannot capture"
    end
    if target.team_id == attacker.team_id then
        return false, "Cannot capture allied piece"
    end

    -- Guardian / Paladin protection
    local protected, protector = board:guardian_protected(target.col, target.row, target.team_id)
    if protected then
        -- Archer ignores Guardian but NOT Paladin
        local archer_bypass = attacker.type == C.PIECE.ARCHER
                           and protector.type == C.PIECE.GUARDIAN
        if not archer_bypass then
            return false, "Target is protected by " .. protector.type
        end
    end

    return true
end

-- Is the piece owned by the acting team & player?
local function owns(piece, team_id, player_id)
    if piece.team_id ~= team_id then
        return false, "Piece belongs to opponent"
    end
    if player_id and piece.player_id ~= player_id then
        return false, "Piece belongs to a different player on your team"
    end
    return true
end

-- ─── MOVE validation ─────────────────────────────────────────────────────────

function V.move(piece, dest_col, dest_row, board, game_state)
    if piece.has_acted        then return false, "Piece already acted this turn" end
    if piece.is_captured      then return false, "Piece is captured" end

    local ok, err = owns(piece, game_state.current_team)
    if not ok then return false, err end

    -- Is dest_col/row in legal move set?
    local targets = Mov.move_targets(piece, board)
    local valid = false
    for _, t in ipairs(targets) do
        if t.col == dest_col and t.row == dest_row then
            valid = true; break
        end
    end
    if not valid then return false, "Destination not reachable by " .. piece.type end

    -- Destination occupied?
    local occupant = board:get(dest_col, dest_row)
    if occupant then
        -- Assassin special: can only capture by moving DIAGONALLY (1 step)
        if piece.type == C.PIECE.ASSASSIN then
            local is_diag = math.abs(piece.col - dest_col) == math.abs(piece.row - dest_row)
            local is_one  = math.abs(piece.col - dest_col) == 1
            if not (is_diag and is_one) then
                return false, "Assassin can only capture diagonally adjacent (1 cell)"
            end
        end
        return capture_ok(piece, occupant, board)
    end

    -- Enchanter cannot move onto allied piece (already filtered above) and has no captures
    if piece.type == C.PIECE.ENCHANTER and occupant then
        return false, "Enchanter cannot capture"
    end

    return true
end

-- ─── SHOOT validation ────────────────────────────────────────────────────────

function V.shoot(piece, dest_col, dest_row, board, game_state)
    if piece.has_acted   then return false, "Piece already acted this turn" end
    if piece.is_captured then return false, "Piece is captured" end

    local ok, err = owns(piece, game_state.current_team)
    if not ok then return false, err end

    if not piece:is_ranged() then
        return false, "Only Archer and Mage can shoot"
    end

    local targets = Mov.shoot_targets(piece, board)
    local valid = false
    for _, t in ipairs(targets) do
        if t.col == dest_col and t.row == dest_row then
            valid = true; break
        end
    end
    if not valid then return false, "Out of shoot range" end

    local occupant = board:get(dest_col, dest_row)
    if not occupant then return false, "No piece at target" end

    return capture_ok(piece, occupant, board)
end

-- ─── INVOKE validation ───────────────────────────────────────────────────────

function V.invoke(invoker, piece_type, target_board_idx, target_col, target_row, game_state)
    if invoker.has_acted   then return false, "Invoker already acted this turn" end
    if invoker.is_captured then return false, "Invoker is captured" end
    if invoker.type ~= C.PIECE.INVOKER then
        return false, "Only the Invoker can use this action"
    end

    local ok, err = owns(invoker, game_state.current_team)
    if not ok then return false, err end

    -- Invoker must be on neutral row
    if invoker.row ~= C.NEUTRAL_ROW then
        return false, "Invoker must be on row " .. C.NEUTRAL_ROW .. " (neutral line)"
    end

    -- Can't invoke Kings or Invokers
    if piece_type == C.PIECE.KING or piece_type == C.PIECE.INVOKER then
        return false, "Kings and Invokers cannot be invoked"
    end

    -- Piece must be in team reserve
    local team = invoker.team_id
    local in_reserve = false
    for _, pid in ipairs(game_state.reserves[team]) do
        local p = game_state.all_pieces[pid]
        if p and p.type == piece_type then in_reserve = true; break end
    end
    if not in_reserve then
        return false, "No " .. piece_type .. " in team reserve"
    end

    -- Target board: Invoker can invoke on own board OR any connected board
    -- Connection rule: all 3 boards are mutually connected (triangle)
    if target_board_idx < 1 or target_board_idx > C.NUM_BOARDS then
        return false, "Invalid target board"
    end

    -- Target cell must be in team's invocation zone on target board
    local target_board = game_state.boards[target_board_idx]
    if not target_board:in_invoke_zone(target_col, target_row, team) then
        return false, "Target cell not in invocation zone (rows 1-3 for Team A, 5-7 for Team B)"
    end

    if not target_board:is_empty(target_col, target_row) then
        return false, "Target cell is occupied"
    end

    return true
end

-- ─── PLACE_TOTEM validation ──────────────────────────────────────────────────

function V.place_totem(enchanter, board, game_state)
    if enchanter.has_acted          then return false, "Already acted this turn" end
    if enchanter.is_captured        then return false, "Piece is captured" end
    if enchanter.type ~= C.PIECE.ENCHANTER then return false, "Only Enchanter can place totems" end
    if enchanter.enchanter_totem_used then return false, "Enchanter already used totem this game" end

    local ok, err = owns(enchanter, game_state.current_team)
    if not ok then return false, err end

    return true
end

-- ─── PALADIN_INVOKE validation ───────────────────────────────────────────────

function V.paladin_invoke(paladin, piece_type, target_col, target_row, board, game_state)
    if paladin.has_acted            then return false, "Already acted this turn" end
    if paladin.is_captured          then return false, "Piece is captured" end
    if paladin.type ~= C.PIECE.PALADIN then return false, "Only Paladin can use paladin_invoke" end
    if paladin.paladin_invoke_used  then return false, "Paladin already used invoke this game" end

    local ok, err = owns(paladin, game_state.current_team)
    if not ok then return false, err end

    -- Must be adjacent (within 1 cell)
    if math.abs(paladin.col - target_col) > 1 or math.abs(paladin.row - target_row) > 1 then
        return false, "Paladin invoke target must be adjacent (≤1 cell)"
    end
    if not board:is_empty(target_col, target_row) then
        return false, "Target cell is occupied"
    end

    if piece_type == C.PIECE.KING or piece_type == C.PIECE.INVOKER then
        return false, "Kings and Invokers cannot be invoked"
    end

    local team = paladin.team_id
    local in_reserve = false
    for _, pid in ipairs(game_state.reserves[team]) do
        local p = game_state.all_pieces[pid]
        if p and p.type == piece_type then in_reserve = true; break end
    end
    if not in_reserve then
        return false, "No " .. piece_type .. " in team reserve"
    end

    return true
end

-- ─── SUICIDE validation ──────────────────────────────────────────────────────

function V.suicide(piece, game_state)
    if piece.has_acted   then return false, "Already acted this turn" end
    if piece.is_captured then return false, "Already captured" end
    if piece.type == C.PIECE.KING or piece.type == C.PIECE.INVOKER then
        return false, "Kings and Invokers cannot be suicided"
    end

    local ok, err = owns(piece, game_state.current_team)
    if not ok then return false, err end

    return true
end

return V
