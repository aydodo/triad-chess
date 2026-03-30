-- Triad Chess — global constants

local C = {}

-- ─── Board ───────────────────────────────────────────────────────────────────
C.BOARD_COLS = 5   -- columns a-e
C.BOARD_ROWS = 7   -- rows 1-7
C.NUM_BOARDS = 3

-- Row zones (same for every board; rows 1-3 belong to Team A, 5-7 to Team B)
C.NEUTRAL_ROW    = 4                      -- Invoker must stand here to invoke
C.INVOKE_ROWS_A  = {1, 2, 3}             -- Team A invocation zone (receive pieces)
C.INVOKE_ROWS_B  = {5, 6, 7}             -- Team B invocation zone

-- ─── Teams ───────────────────────────────────────────────────────────────────
C.TEAM_A = 1
C.TEAM_B = 2
C.NUM_PLAYERS = 3  -- per team

-- ─── Piece types ─────────────────────────────────────────────────────────────
C.PIECE = {
    KING      = "king",
    INVOKER   = "invoker",
    -- Draft slot 1 (mobile)
    KNIGHT    = "knight",
    ASSASSIN  = "assassin",
    -- Draft slot 2 (ranged)
    ARCHER    = "archer",
    MAGE      = "mage",
    -- Draft slot 3 (support/defence)
    GUARDIAN  = "guardian",
    PALADIN   = "paladin",
    ENCHANTER = "enchanter",
}

-- Draft options per slot
C.DRAFT_SLOT = {
    [1] = { C.PIECE.KNIGHT,   C.PIECE.ASSASSIN },
    [2] = { C.PIECE.ARCHER,   C.PIECE.MAGE     },
    [3] = { C.PIECE.GUARDIAN, C.PIECE.PALADIN, C.PIECE.ENCHANTER },
}

-- Short display labels
C.PIECE_LABEL = {
    [C.PIECE.KING]      = "K",
    [C.PIECE.INVOKER]   = "I",
    [C.PIECE.KNIGHT]    = "N",
    [C.PIECE.ASSASSIN]  = "As",
    [C.PIECE.ARCHER]    = "Ar",
    [C.PIECE.MAGE]      = "M",
    [C.PIECE.GUARDIAN]  = "G",
    [C.PIECE.PALADIN]   = "Pa",
    [C.PIECE.ENCHANTER] = "En",
}

-- ─── Actions ─────────────────────────────────────────────────────────────────
C.ACTION = {
    MOVE         = "move",      -- move (+ implicit capture if enemy on dest)
    SHOOT        = "shoot",     -- Archer / Mage ranged attack (stays in place)
    INVOKE       = "invoke",    -- Invoker summons piece from team reserve
    PALADIN_INV  = "paladin_inv", -- Paladin 1×/game invoke adjacent
    PLACE_TOTEM  = "place_totem", -- Enchanter places totem
    PASS         = "pass",
    SUICIDE      = "suicide",   -- Sacrifice own piece to add it to own reserve
}

-- ─── Momentum ────────────────────────────────────────────────────────────────
C.MOMENTUM_MAX          =  100
C.MOMENTUM_CAPTURE      =   10
C.MOMENTUM_INVOKE       =    5
C.MOMENTUM_KING_THREAT  =   15   -- first turn king is put in check
C.MOMENTUM_LOSE_PIECE   =  -10
C.MOMENTUM_LOSE_KING    =  -20

-- Ultimate abilities (chosen at activation)
C.ULTIMATE = {
    MASS_INVOKE    = "mass_invoke",    -- invoke 3 pieces this turn
    DIVINE_SHIELD  = "divine_shield",  -- immune next enemy turn
    TELEPORT       = "teleport",       -- swap 2 allied pieces across boards
    RESURRECTION   = "resurrection",   -- place captured piece directly on board
}

-- ─── Win condition ────────────────────────────────────────────────────────────
C.WIN_KINGS_TO_CAPTURE = 2   -- capture 2/3 enemy kings to win (Proposition A)

-- ─── Turn ────────────────────────────────────────────────────────────────────
C.TURN_SECONDS = 20          -- Proposition B: 20 s shared timer per team

return C
