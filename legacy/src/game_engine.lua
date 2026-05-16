-- Triad Chess — GameEngine
-- Executes validated actions and mutates GameState.

local C    = require("src.constants")
local GS   = require("src.game_state")
local V    = require("src.logic.validation")

local GameEngine = {}
GameEngine.__index = GameEngine

function GameEngine.new(draft_config)
    local self    = setmetatable({}, GameEngine)
    self.state    = GS.new(draft_config)
    self.history  = {}   -- list of action records for replay / logging
    self.state:begin_turn()
    return self
end

-- ─── Update (timer) ──────────────────────────────────────────────────────────

function GameEngine:update(dt)
    if self.state.game_over then return end

    self.state.turn_timer = self.state.turn_timer - dt

    -- Auto-end turn when timer expires OR all players acted
    if self.state.turn_timer <= 0 or self.state:all_acted() then
        self.state:end_turn()
    end
end

-- ─── Action: MOVE (+ implicit capture) ───────────────────────────────────────

function GameEngine:execute_move(piece_id, dest_col, dest_row)
    local s     = self.state
    local piece = s:piece(piece_id)
    if not piece then return false, "Piece not found" end

    local board = s.boards[piece.board_idx]
    local ok, err = V.move(piece, dest_col, dest_row, board, s)
    if not ok then return false, err end

    local occupant = board:get(dest_col, dest_row)

    -- Assassin: remember origin for optional retreat
    if piece.type == C.PIECE.ASSASSIN then
        piece.assassin_last_origin = {col = piece.col, row = piece.row}
    end

    -- Capture occupant if enemy
    if occupant then
        s:capture(occupant, piece.team_id)
    end

    -- Move piece
    board:move(piece, dest_col, dest_row)

    -- Totem: destroy if enemy stepped on it
    board:on_enemy_step(dest_col, dest_row, piece.team_id)

    piece.has_acted = true
    self:_record(C.ACTION.MOVE, piece_id, piece.board_idx, dest_col, dest_row)

    s:check_win()
    return true, { assassin_origin = piece.assassin_last_origin }
end

-- ─── Action: Assassin retreat ─────────────────────────────────────────────────
-- Optional; called right after execute_move for Assassin captures.

function GameEngine:execute_assassin_retreat(piece_id)
    local s     = self.state
    local piece = s:piece(piece_id)
    if not piece                          then return false, "Piece not found" end
    if piece.type ~= C.PIECE.ASSASSIN    then return false, "Not an Assassin" end
    if not piece.assassin_last_origin    then return false, "No retreat origin stored" end
    if piece.team_id ~= s.current_team   then return false, "Not your turn" end

    local origin = piece.assassin_last_origin
    local board  = s.boards[piece.board_idx]

    if not board:is_empty(origin.col, origin.row) then
        return false, "Origin cell is no longer empty"
    end

    board:move(piece, origin.col, origin.row)
    piece.assassin_last_origin = nil
    -- has_acted stays true; retreat is part of the same action
    self:_record("assassin_retreat", piece_id, piece.board_idx, origin.col, origin.row)
    return true
end

-- ─── Action: SHOOT ───────────────────────────────────────────────────────────

function GameEngine:execute_shoot(piece_id, target_col, target_row)
    local s     = self.state
    local piece = s:piece(piece_id)
    if not piece then return false, "Piece not found" end

    local board = s.boards[piece.board_idx]
    local ok, err = V.shoot(piece, target_col, target_row, board, s)
    if not ok then return false, err end

    local target = board:get(target_col, target_row)
    s:capture(target, piece.team_id)
    board:on_capture_in_zone(target_col, target_row)

    piece.has_acted = true
    self:_record(C.ACTION.SHOOT, piece_id, piece.board_idx, target_col, target_row)

    s:check_win()
    return true
end

-- ─── Action: INVOKE ──────────────────────────────────────────────────────────

function GameEngine:execute_invoke(invoker_id, piece_type, target_board_idx, target_col, target_row)
    local s       = self.state
    local invoker = s:piece(invoker_id)
    if not invoker then return false, "Invoker not found" end

    local ok, err = V.invoke(invoker, piece_type, target_board_idx, target_col, target_row, s)
    if not ok then return false, err end

    local placed, inv_err = s:invoke_piece(invoker.team_id, piece_type,
                                            target_board_idx, target_col, target_row)
    if not placed then return false, inv_err end

    invoker.has_acted = true
    self:_record(C.ACTION.INVOKE, invoker_id, target_board_idx, target_col, target_row,
                 {piece_type = piece_type})

    return true
end

-- ─── Action: PALADIN INVOKE ───────────────────────────────────────────────────

function GameEngine:execute_paladin_invoke(paladin_id, piece_type, target_col, target_row)
    local s      = self.state
    local paladin = s:piece(paladin_id)
    if not paladin then return false, "Paladin not found" end

    local board = s.boards[paladin.board_idx]
    local ok, err = V.paladin_invoke(paladin, piece_type, target_col, target_row, board, s)
    if not ok then return false, err end

    local placed, inv_err = s:invoke_piece(paladin.team_id, piece_type,
                                            paladin.board_idx, target_col, target_row)
    if not placed then return false, inv_err end

    paladin.paladin_invoke_used = true
    paladin.has_acted           = true
    self:_record(C.ACTION.PALADIN_INV, paladin_id, paladin.board_idx, target_col, target_row,
                 {piece_type = piece_type})

    return true
end

-- ─── Action: PLACE TOTEM ──────────────────────────────────────────────────────

function GameEngine:execute_place_totem(enchanter_id)
    local s         = self.state
    local enchanter = s:piece(enchanter_id)
    if not enchanter then return false, "Enchanter not found" end

    local board = s.boards[enchanter.board_idx]
    local ok, err = V.place_totem(enchanter, board, s)
    if not ok then return false, err end

    board:add_totem(enchanter.col, enchanter.row, enchanter.team_id)
    enchanter.enchanter_totem_used = true
    enchanter.has_acted            = true
    self:_record(C.ACTION.PLACE_TOTEM, enchanter_id, enchanter.board_idx,
                 enchanter.col, enchanter.row)

    return true
end

-- ─── Action: SUICIDE ─────────────────────────────────────────────────────────

function GameEngine:execute_suicide(piece_id)
    local s     = self.state
    local piece = s:piece(piece_id)
    if not piece then return false, "Piece not found" end

    local ok, err = V.suicide(piece, s)
    if not ok then return false, err end

    s.boards[piece.board_idx]:remove(piece)
    piece.is_captured = true
    -- Goes to OWN team's reserve (not the enemy's)
    table.insert(s.reserves[piece.team_id], piece.id)

    piece.has_acted = true
    self:_record(C.ACTION.SUICIDE, piece_id, piece.board_idx, piece.col, piece.row)
    return true
end

-- ─── Action: PASS ────────────────────────────────────────────────────────────

function GameEngine:execute_pass(piece_id)
    local s     = self.state
    local piece = s:piece(piece_id)
    if not piece then return false, "Piece not found" end
    if piece.team_id ~= s.current_team then return false, "Not your turn" end
    if piece.has_acted then return false, "Piece already acted" end

    piece.has_acted = true
    self:_record(C.ACTION.PASS, piece_id, piece.board_idx, piece.col, piece.row)
    return true
end

-- ─── Action: ULTIMATE ────────────────────────────────────────────────────────

function GameEngine:execute_ultimate(team_id, ability, params)
    local s = self.state
    if not s:has_ultimate(team_id) then
        return false, "Ultimate not available"
    end

    -- Apply the chosen ability
    if ability == C.ULTIMATE.DIVINE_SHIELD then
        s.active_effects[team_id].divine_shield = true

    elseif ability == C.ULTIMATE.TELEPORT then
        -- params = {piece_id_a, piece_id_b}
        local pa = s:piece(params[1])
        local pb = s:piece(params[2])
        if not pa or not pb then return false, "Invalid pieces for teleport" end
        if pa.team_id ~= team_id or pb.team_id ~= team_id then
            return false, "Can only teleport own pieces"
        end
        -- Swap boards (pieces keep col/row, boards swap)
        local ba, bb = pa.board_idx, pb.board_idx
        s.boards[ba]:remove(pa); s.boards[bb]:remove(pb)
        pa:set_pos(bb, pa.col, pa.row)
        pb:set_pos(ba, pb.col, pb.row)
        s.boards[bb]:place(pa); s.boards[ba]:place(pb)

    elseif ability == C.ULTIMATE.RESURRECTION then
        -- params = {piece_id, target_board, target_col, target_row}
        local p = s:piece(params[1])
        if not p or not p.is_captured or p.type == C.PIECE.KING or p.type == C.PIECE.INVOKER then
            return false, "Invalid resurrection target"
        end
        -- Remove from whichever reserve it's in
        for _, reserves in pairs(s.reserves) do
            for i, pid in ipairs(reserves) do
                if pid == p.id then table.remove(reserves, i); break end
            end
        end
        p.is_captured = false
        p:set_pos(params[2], params[3], params[4])
        s.boards[params[2]]:place(p)

    elseif ability == C.ULTIMATE.MASS_INVOKE then
        -- Grants 2 extra invocations this turn (tracked as effect)
        s.active_effects[team_id].mass_invoke_extra = 2
    end

    s.momentum[team_id]       = 0
    s.ultimate_used[team_id]  = true
    self:_record("ultimate", nil, nil, nil, nil, {ability=ability, team=team_id})
    return true
end

-- ─── Manual end turn ─────────────────────────────────────────────────────────

function GameEngine:end_turn()
    if not self.state.game_over then
        self.state:end_turn()
    end
end

-- ─── History ─────────────────────────────────────────────────────────────────

function GameEngine:_record(action, piece_id, board_idx, col, row, extra)
    table.insert(self.history, {
        turn      = self.state.turn_number,
        team      = self.state.current_team,
        action    = action,
        piece_id  = piece_id,
        board_idx = board_idx,
        col       = col,
        row       = row,
        extra     = extra,
    })
end

return GameEngine
