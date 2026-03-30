-- Triad Chess — GameState
-- Pure data container; no action logic (that lives in game_engine.lua)

local C     = require("src.constants")
local Board = require("src.board")
local Piece = require("src.piece")
local Utils = require("src.utils")

local GameState = {}
GameState.__index = GameState

-- ─── Constructor ─────────────────────────────────────────────────────────────

function GameState.new(draft_config)
    local self = setmetatable({}, GameState)

    -- 3 boards
    self.boards = {}
    for i = 1, C.NUM_BOARDS do
        self.boards[i] = Board.new(i)
    end

    -- All pieces by id (includes captured ones still referenced)
    self.all_pieces = {}

    -- players[team_id][player_id] = list of pieces (including captured)
    self.players = {}
    for tid = C.TEAM_A, C.TEAM_B do
        self.players[tid] = {}
        for pid = 1, C.NUM_PLAYERS do
            self.players[tid][pid] = {}
        end
    end

    -- Shared capture reserves per team
    -- (pieces captured FROM the enemy go HERE — invocable by this team)
    self.reserves = { [C.TEAM_A] = {}, [C.TEAM_B] = {} }

    -- Kings alive per team
    self.kings_alive = { [C.TEAM_A] = 0, [C.TEAM_B] = 0 }

    -- Momentum
    self.momentum = { [C.TEAM_A] = 0, [C.TEAM_B] = 0 }

    -- Ultimate ability: false = available, true = used
    self.ultimate_used = { [C.TEAM_A] = false, [C.TEAM_B] = false }

    -- Active ultimate effects (e.g. divine shield pending)
    self.active_effects = { [C.TEAM_A] = {}, [C.TEAM_B] = {} }

    -- Turn state
    self.current_team  = C.TEAM_A
    self.turn_number   = 1
    self.turn_timer    = C.TURN_SECONDS
    self.game_over     = false
    self.winning_team  = nil

    -- Draft: default is Knight + Archer + Guardian for everyone
    -- draft_config = {[TEAM_A]={[1]={slot1,slot2,slot3}, [2]=..., [3]=...}, [TEAM_B]=...}
    self.draft = draft_config or self:_default_draft()

    Piece.reset_ids()
    self:_init_pieces()

    return self
end

-- ─── Draft ───────────────────────────────────────────────────────────────────

function GameState:_default_draft()
    local d = {}
    for tid = C.TEAM_A, C.TEAM_B do
        d[tid] = {}
        for pid = 1, C.NUM_PLAYERS do
            d[tid][pid] = { C.PIECE.KNIGHT, C.PIECE.ARCHER, C.PIECE.GUARDIAN }
        end
    end
    return d
end

-- ─── Piece initialisation ────────────────────────────────────────────────────
--[[
  Starting layout (Team A, row 1):
    col 1(a): Invoker
    col 2(b): Draft slot 1
    col 3(c): King
    col 4(d): Draft slot 2
    col 5(e): Draft slot 3

  Team B mirrors on row 7:
    col 1(a): Draft slot 3
    col 2(b): Draft slot 2
    col 3(c): King
    col 4(d): Draft slot 1
    col 5(e): Invoker
--]]
function GameState:_init_pieces()
    for pid = 1, C.NUM_PLAYERS do
        local board_idx = pid
        local draft_a   = self.draft[C.TEAM_A][pid]
        local draft_b   = self.draft[C.TEAM_B][pid]

        -- Team A — bottom (row 1)
        self:_spawn(C.PIECE.INVOKER, C.TEAM_A, pid, board_idx, 1, 1)
        self:_spawn(draft_a[1],      C.TEAM_A, pid, board_idx, 2, 1)
        self:_spawn(C.PIECE.KING,    C.TEAM_A, pid, board_idx, 3, 1)
        self:_spawn(draft_a[2],      C.TEAM_A, pid, board_idx, 4, 1)
        self:_spawn(draft_a[3],      C.TEAM_A, pid, board_idx, 5, 1)

        -- Team B — top (row 7, mirrored)
        self:_spawn(draft_b[3],      C.TEAM_B, pid, board_idx, 1, 7)
        self:_spawn(draft_b[2],      C.TEAM_B, pid, board_idx, 2, 7)
        self:_spawn(C.PIECE.KING,    C.TEAM_B, pid, board_idx, 3, 7)
        self:_spawn(draft_b[1],      C.TEAM_B, pid, board_idx, 4, 7)
        self:_spawn(C.PIECE.INVOKER, C.TEAM_B, pid, board_idx, 5, 7)
    end
end

function GameState:_spawn(piece_type, team_id, player_id, board_idx, col, row)
    local p = Piece.new(piece_type, team_id, player_id, board_idx, col, row)
    self.all_pieces[p.id] = p
    self.boards[board_idx]:place(p)
    table.insert(self.players[team_id][player_id], p)
    if piece_type == C.PIECE.KING then
        self.kings_alive[team_id] = self.kings_alive[team_id] + 1
    end
    return p
end

-- ─── Lookup helpers ──────────────────────────────────────────────────────────

function GameState:piece(id)
    return self.all_pieces[id]
end

function GameState:piece_at(board_idx, col, row)
    return self.boards[board_idx]:get(col, row)
end

function GameState:opponent(team_id)
    return Utils.opponent(team_id)
end

-- ─── Capture ─────────────────────────────────────────────────────────────────

function GameState:capture(target_piece, by_team)
    if target_piece.is_captured then return end

    self.boards[target_piece.board_idx]:remove(target_piece)
    target_piece.is_captured = true

    -- Momentum
    self:add_momentum(by_team, C.MOMENTUM_CAPTURE)

    if target_piece.type == C.PIECE.KING then
        self.kings_alive[target_piece.team_id] = self.kings_alive[target_piece.team_id] - 1
        self:add_momentum(target_piece.team_id, C.MOMENTUM_LOSE_KING)
        -- King goes to reserve? No — Kings are never re-invocable; just remove.
    elseif target_piece.type == C.PIECE.INVOKER then
        -- Invoker permanently removed (not invocable)
        self:add_momentum(target_piece.team_id, C.MOMENTUM_LOSE_PIECE)
    else
        -- Piece goes to CAPTURING team's reserve
        table.insert(self.reserves[by_team], target_piece.id)
        self:add_momentum(target_piece.team_id, C.MOMENTUM_LOSE_PIECE)
    end

    -- Notify totem zones
    self.boards[target_piece.board_idx]:on_capture_in_zone(
        target_piece.col, target_piece.row)
end

-- ─── Invocation ──────────────────────────────────────────────────────────────

-- Place a piece of `piece_type` from `team`'s reserve onto the board.
-- Returns the placed piece, or nil + err.
function GameState:invoke_piece(team, piece_type, board_idx, col, row)
    -- Find first matching piece in reserve
    for i, pid in ipairs(self.reserves[team]) do
        local p = self.all_pieces[pid]
        if p and p.type == piece_type then
            table.remove(self.reserves[team], i)
            p.is_captured = false
            p:set_pos(board_idx, col, row)
            self.boards[board_idx]:place(p)
            self:add_momentum(team, C.MOMENTUM_INVOKE)
            return p
        end
    end
    return nil, "No " .. piece_type .. " in reserve"
end

-- ─── Momentum ────────────────────────────────────────────────────────────────

function GameState:add_momentum(team_id, amount)
    self.momentum[team_id] = Utils.clamp(
        self.momentum[team_id] + amount, 0, C.MOMENTUM_MAX)
end

function GameState:has_ultimate(team_id)
    return self.momentum[team_id] >= C.MOMENTUM_MAX
       and not self.ultimate_used[team_id]
end

-- ─── Win condition ───────────────────────────────────────────────────────────

-- Returns winning team_id or nil
function GameState:check_win()
    for tid = C.TEAM_A, C.TEAM_B do
        local opp       = self:opponent(tid)
        local caps      = C.NUM_PLAYERS - self.kings_alive[opp]   -- enemy kings captured
        local my_kings  = self.kings_alive[tid]
        if caps >= C.WIN_KINGS_TO_CAPTURE and my_kings > 0 then
            self.game_over    = true
            self.winning_team = tid
            return tid
        end
    end
    return nil
end

-- ─── Turn management ─────────────────────────────────────────────────────────

-- Reset has_acted for all pieces of current team
function GameState:begin_turn()
    for pid = 1, C.NUM_PLAYERS do
        for _, p in ipairs(self.players[self.current_team][pid]) do
            p:reset_for_turn()
        end
    end
    self.turn_timer = C.TURN_SECONDS
end

function GameState:end_turn()
    self.current_team = self:opponent(self.current_team)
    self.turn_number  = self.turn_number + 1
    self:begin_turn()
end

-- True if every active player on current team has had at least one piece act
function GameState:all_acted()
    local team = self.current_team
    for pid = 1, C.NUM_PLAYERS do
        local acted = false
        local has_piece = false
        for _, p in ipairs(self.players[team][pid]) do
            if not p.is_captured then
                has_piece = true
                if p.has_acted then acted = true end
            end
        end
        if has_piece and not acted then return false end
    end
    return true
end

return GameState
