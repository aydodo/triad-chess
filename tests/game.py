# -*- coding: utf-8 -*-
"""
Simulation de Triad Chess avec notation pseudo-PGN.

Ce script Python définit les structures de données pour représenter l'état du jeu
et les actions des joueurs, et simule une séquence de tours basée sur une notation
pseudo-PGN. Il sert de base pour un futur protocole de jeu.
"""

import collections
import random

# --- Constantes du Jeu ---
BOARD_ROWS = 5
BOARD_COLS = 7
NUM_BOARDS = 3
NUM_PLAYERS_PER_TEAM = 3
TOTAL_PLAYERS = NUM_BOARDS * 2 # 3 joueurs par équipe, 2 équipes = 6 joueurs

# Types de pièces
PIECE_KING = "Roi"
PIECE_INVOKER = "Invocateur"
PIECE_KNIGHT = "Cavalier"
PIECE_ARCHER = "Archer"
PIECE_GUARDIAN = "Gardien"

# Actions possibles
ACTION_MOVE = "MOVE"
ACTION_CAPTURE = "CAPTURE" # Implicite lors d'un MOVE sur une pièce adverse
ACTION_INVOKE = "INVOKE"
ACTION_SPECIAL_ARCHER = "SPECIAL_ARCHER" # Capture à distance de l'Archer
ACTION_SPECIAL_GUARDIAN = "SPECIAL_GUARDIAN" # Protection du Gardien (passif ici, mais peut être une action si activable)
ACTION_SUICIDE = "SUICIDE"

# --- Classes de Représentation du Jeu ---

class Piece:
    """Représente une pièce sur le plateau."""
    def __init__(self, piece_id, type, team_id, player_id, board_idx, row, col):
        self.id = piece_id # Identifiant unique de la pièce
        self.type = type
        self.team_id = team_id # 0 ou 1
        self.player_id = player_id # 0, 1, 2 pour chaque équipe
        self.board_idx = board_idx # Index du plateau (0, 1, 2)
        self.row = row
        self.col = col
        self.is_captured = False
        self.has_moved_in_turn = False # Pour la gestion des actions simultanées

    def get_position(self):
        """Retourne la position de la pièce sous forme de tuple (board_idx, row, col)."""
        return (self.board_idx, self.row, self.col)

    def set_position(self, board_idx, row, col):
        """Définit la nouvelle position de la pièce."""
        self.board_idx = board_idx
        self.row = row
        self.col = col

    def __repr__(self):
        """Représentation de la pièce pour le débogage."""
        status = " (Capturée)" if self.is_captured else ""
        return (f"{self.type}(T{self.team_id}P{self.player_id}) "
                f"@{self.board_idx},{self.row},{self.col}{status}")

class Board:
    """Représente un plateau de jeu 5x7."""
    def __init__(self, board_idx):
        self.board_idx = board_idx
        # Grille du plateau, stocke les IDs des pièces
        self.grid = [[None for _ in range(BOARD_COLS)] for _ in range(BOARD_ROWS)]
        self.pieces_on_board = {} # {piece_id: Piece_object}

    def place_piece(self, piece):
        """Place une pièce sur le plateau."""
        if self.grid[piece.row][piece.col] is not None:
            print(f"ATTENTION: Collision à {piece.board_idx},{piece.row},{piece.col} lors du placement.")
        self.grid[piece.row][piece.col] = piece.id
        self.pieces_on_board[piece.id] = piece

    def remove_piece(self, piece_id):
        """Retire une pièce du plateau."""
        piece = self.pieces_on_board.get(piece_id)
        if piece:
            self.grid[piece.row][piece.col] = None
            del self.pieces_on_board[piece_id]
            return piece
        return None

    def get_piece_at(self, row, col):
        """Retourne la pièce à une position donnée."""
        piece_id = self.grid[row][col]
        return self.pieces_on_board.get(piece_id)

    def move_piece(self, piece, new_row, new_col):
        """Déplace une pièce sur le plateau."""
        self.grid[piece.row][piece.col] = None
        piece.set_position(self.board_idx, new_row, new_col)
        self.grid[new_row][new_col] = piece.id

    def is_valid_position(self, row, col):
        """Vérifie si une position est valide sur ce plateau."""
        return 0 <= row < BOARD_ROWS and 0 <= col < BOARD_COLS

    def is_empty(self, row, col):
        """Vérifie si une case est vide."""
        return self.grid[row][col] is None

    def get_zone_invocation(self, player_team_id):
        """
        Retourne les cases de la zone d'invocation pour une équipe donnée.
        Simplifié pour l'exemple: les 2 premières lignes pour l'équipe 0, les 2 dernières pour l'équipe 1.
        La ligne centrale est la ligne 2 (index 0-4).
        Zone d'invocation: du bas du plateau jusqu'à la ligne centrale - 1.
        Pour l'équipe 0 (joueur en bas): lignes 0 et 1.
        Pour l'équipe 1 (joueur en haut): lignes 3 et 4.
        """
        invocation_zones = []
        if player_team_id == 0: # Joueur du bas
            for r in range(0, BOARD_ROWS // 2 - 1): # Lignes 0, 1
                for c in range(BOARD_COLS):
                    invocation_zones.append((r, c))
        else: # Joueur du haut
            for r in range(BOARD_ROWS // 2 + 2, BOARD_ROWS): # Lignes 3, 4
                for c in range(BOARD_COLS):
                    invocation_zones.append((r, c))
        return invocation_zones

    def get_central_line(self):
        """Retourne les cases de la ligne centrale."""
        central_row = BOARD_ROWS // 2 # Ligne 2 pour un plateau 5x7
        return [(central_row, c) for c in range(BOARD_COLS)]


class GameState:
    """Gère l'état global du jeu."""
    def __init__(self):
        self.boards = [Board(i) for i in range(NUM_BOARDS)]
        self.team_reserves = {0: [], 1: []} # Pièces capturées, prêtes à être invoquées
        self.active_pieces = {} # {piece_id: Piece_object}
        self.next_piece_id = 0
        self.current_team_turn = 0 # 0 ou 1
        self.turn_number = 0
        self.kings_alive = {0: NUM_PLAYERS_PER_TEAM, 1: NUM_PLAYERS_PER_TEAM} # Nombre de rois vivants par équipe

        self._initialize_pieces()

    def _initialize_pieces(self):
        """Initialise les pièces sur les plateaux."""
        initial_configs = {
            # Team 0 (bottom side, rows 0-1)
            0: {
                PIECE_KING: (0, 0, 3), # board, row, col
                PIECE_INVOKER: (0, 0, 0),
                PIECE_KNIGHT: (0, 0, 1),
                PIECE_ARCHER: (0, 0, 2),
                PIECE_GUARDIAN: (0, 0, 4),
            },
            1: {
                PIECE_KING: (1, 0, 3),
                PIECE_INVOKER: (1, 0, 0),
                PIECE_KNIGHT: (1, 0, 1),
                PIECE_ARCHER: (1, 0, 2),
                PIECE_GUARDIAN: (1, 0, 4),
            },
            2: {
                PIECE_KING: (2, 0, 3),
                PIECE_INVOKER: (2, 0, 0),
                PIECE_KNIGHT: (2, 0, 1),
                PIECE_ARCHER: (2, 0, 2),
                PIECE_GUARDIAN: (2, 0, 4),
            },
            # Team 1 (top side, rows 3-4, mirrored for opponent's perspective)
            # For a 5x7 board, row 4 is the "back" row for team 1.
            3: { # Player 0 of Team 1, on board 0
                PIECE_KING: (0, 4, 3),
                PIECE_INVOKER: (0, 4, 0),
                PIECE_KNIGHT: (0, 4, 1),
                PIECE_ARCHER: (0, 4, 2),
                PIECE_GUARDIAN: (0, 4, 4),
            },
            4: { # Player 1 of Team 1, on board 1
                PIECE_KING: (1, 4, 3),
                PIECE_INVOKER: (1, 4, 0),
                PIECE_KNIGHT: (1, 4, 1),
                PIECE_ARCHER: (1, 4, 2),
                PIECE_GUARDIAN: (1, 4, 4),
            },
            5: { # Player 2 of Team 1, on board 2
                PIECE_KING: (2, 4, 3),
                PIECE_INVOKER: (2, 4, 0),
                PIECE_KNIGHT: (2, 4, 1),
                PIECE_ARCHER: (2, 4, 2),
                PIECE_GUARDIAN: (2, 4, 4),
            },
        }

        for player_id, pieces_config in initial_configs.items():
            team_id = 0 if player_id < NUM_PLAYERS_PER_TEAM else 1
            for piece_type, (board_idx, row, col) in pieces_config.items():
                piece = Piece(self.next_piece_id, piece_type, team_id, player_id, board_idx, row, col)
                self.boards[board_idx].place_piece(piece)
                self.active_pieces[piece.id] = piece
                self.next_piece_id += 1

    def get_piece_by_id(self, piece_id):
        """Retourne une pièce par son ID."""
        return self.active_pieces.get(piece_id)

    def get_piece_at_coords(self, board_idx, row, col):
        """Retourne la pièce à des coordonnées globales."""
        if not (0 <= board_idx < NUM_BOARDS and self.boards[board_idx].is_valid_position(row, col)):
            return None
        return self.boards[board_idx].get_piece_at(row, col)

    def capture_piece(self, piece_to_capture):
        """Capture une pièce et la place dans la réserve de son équipe."""
        if piece_to_capture.is_captured:
            print(f"ATTENTION: La pièce {piece_to_capture.id} est déjà capturée.")
            return

        print(f"  Capture de {piece_to_capture.type} (ID: {piece_to_capture.id}) de l'équipe {piece_to_capture.team_id}")
        self.boards[piece_to_capture.board_idx].remove_piece(piece_to_capture.id)
        piece_to_capture.is_captured = True

        if piece_to_capture.type == PIECE_KING:
            self.kings_alive[piece_to_capture.team_id] -= 1
            print(f"  Roi de l'équipe {piece_to_capture.team_id} capturé. Rois restants: {self.kings_alive[piece_to_capture.team_id]}")
        elif piece_to_capture.type == PIECE_INVOKER:
            # L'invocateur ne peut pas être invoqué si capturé, donc ne va pas en réserve
            print(f"  Invocateur de l'équipe {piece_to_capture.team_id} capturé. Il ne peut pas être invoqué.")
            # On le retire complètement des pièces actives car il ne reviendra pas
            del self.active_pieces[piece_to_capture.id]
            return

        # Les autres pièces vont dans la réserve de leur équipe
        self.team_reserves[piece_to_capture.team_id].append(piece_to_capture.id)

    def check_win_condition(self):
        """Vérifie la condition de victoire globale."""
        winning_team = -1
        # Une équipe gagne si elle a capturé les 3 rois adverses
        # et possède encore au moins 1 roi en vie.
        for team_id in [0, 1]:
            opponent_team_id = 1 - team_id
            if self.kings_alive[opponent_team_id] == 0 and self.kings_alive[team_id] > 0:
                winning_team = team_id
                break
        return winning_team

    def check_board_win_condition(self, board_idx, player_id):
        """
        Vérifie si un plateau individuel est 'gagné' (toutes les pièces de l'adversaire sont capturées).
        Retourne l'ID du joueur gagnant le plateau, ou None.
        """
        board = self.boards[board_idx]
        player_team_id = self.active_pieces[list(board.pieces_on_board.keys())[0]].team_id if board.pieces_on_board else None
        if player_team_id is None: # Plateau vide
            return None

        opponent_pieces_on_board = False
        for piece_id in board.pieces_on_board:
            piece = self.active_pieces[piece_id]
            if piece.team_id != player_team_id: # Si une pièce adverse est encore sur le plateau
                opponent_pieces_on_board = True
                break
        
        if not opponent_pieces_on_board:
            # Le joueur dont le plateau est maintenant vide de pièces adverses a gagné ce plateau
            return player_id
        return None

    def display(self):
        """Affiche l'état actuel des plateaux et des réserves."""
        print(f"\n--- Tour {self.turn_number}, Équipe {self.current_team_turn} ---")
        for r in range(BOARD_ROWS):
            row_str = ""
            for b_idx in range(NUM_BOARDS):
                board = self.boards[b_idx]
                for c in range(BOARD_COLS):
                    piece_id = board.grid[r][c]
                    if piece_id is None:
                        row_str += ". "
                    else:
                        piece = self.active_pieces[piece_id]
                        char_map = {
                            PIECE_KING: "K", PIECE_INVOKER: "I", PIECE_KNIGHT: "N",
                            PIECE_ARCHER: "A", PIECE_GUARDIAN: "G"
                        }
                        char = char_map.get(piece.type, "?")
                        row_str += f"{char}{piece.team_id}" # K0, I1, etc.
                row_str += " | "
            print(row_str)

        print("\nRéserves d'équipe:")
        for team_id, reserve_ids in self.team_reserves.items():
            pieces_in_reserve = [self.active_pieces[pid].type for pid in reserve_ids if pid in self.active_pieces]
            print(f"  Équipe {team_id}: {', '.join(pieces_in_reserve)}")
        
        print(f"Rois en vie: Équipe 0: {self.kings_alive[0]}, Équipe 1: {self.kings_alive[1]}")


# --- Notation Pseudo-PGN ---

# Format d'une action dans le pseudo-PGN:
# (player_id, action_type, piece_id, start_pos, target_pos/params)
# start_pos: (board_idx, row, col)
# target_pos/params: (board_idx, row, col) ou (piece_type_to_invoke, target_board_idx, target_row, target_col)

# Exemple de pseudo-PGN pour une partie très simplifiée
pseudo_pgn_game = [
    # Tour 1 (Équipe 0)
    [
        (0, ACTION_MOVE, 0, (0,0,3), (0,1,3)), # Player 0 (Team 0), move King from 0,0,3 to 0,1,3
        (1, ACTION_MOVE, 4, (1,0,0), (1,1,1)), # Player 1 (Team 0), move Invoker from 1,0,0 to 1,1,1
        (2, ACTION_MOVE, 9, (2,0,4), (2,1,4))  # Player 2 (Team 0), move Guardian from 2,0,4 to 2,1,4
    ],
    # Tour 2 (Équipe 1)
    [
        (3, ACTION_MOVE, 15, (0,4,3), (0,3,3)), # Player 0 (Team 1), move King from 0,4,3 to 0,3,3
        (4, ACTION_MOVE, 19, (1,4,4), (1,3,4)), # Player 1 (Team 1), move Guardian from 1,4,4 to 1,3,4
        (5, ACTION_MOVE, 20, (2,4,0), (2,3,1))  # Player 2 (Team 1), move Invoker from 2,4,0 to 2,3,1
    ],
    # Tour 3 (Équipe 0) - Tentative de capture et invocation
    [
        (0, ACTION_MOVE, 0, (0,1,3), (0,2,3)), # King moves
        (1, ACTION_MOVE, 4, (1,1,1), (1,2,2)), # Invoker moves to central line
        (2, ACTION_MOVE, 9, (2,1,4), (2,2,4))  # Guardian moves
    ],
    # Tour 4 (Équipe 1) - Invocateur atteint la ligne centrale
    [
        (3, ACTION_MOVE, 15, (0,3,3), (0,2,3)), # King moves to central line (captures King of team 0)
        (4, ACTION_MOVE, 19, (1,3,4), (1,2,4)), # Guardian moves to central line
        (5, ACTION_INVOKE, 20, (2,3,1), (PIECE_ARCHER, 2, 4, 3)) # Invoker (ID 20) on board 2 invokes Archer to 2,4,3
    ],
    # Tour 5 (Équipe 0) - Suicide de pièce
    [
        (0, ACTION_SUICIDE, 1, None, None), # Player 0 (Team 0) suicides Knight (ID 1)
        (1, ACTION_MOVE, 5, (1,0,1), (1,1,1)), # Knight moves
        (2, ACTION_MOVE, 10, (2,0,0), (2,1,0)) # Invoker moves
    ]
]

# --- Logique de Simulation des Tours ---

def execute_action(game_state, player_id, action_type, piece_id, start_pos, target_pos_or_params):
    """
    Exécute une action individuelle et met à jour l'état du jeu.
    Retourne True si l'action a été exécutée avec succès, False sinon.
    """
    piece = game_state.get_piece_by_id(piece_id)
    if not piece or piece.is_captured or piece.player_id != player_id:
        print(f"  Action invalide: Pièce {piece_id} non trouvée, capturée, ou ne vous appartient pas.")
        return False

    current_board = game_state.boards[piece.board_idx]

    if action_type == ACTION_MOVE:
        target_board_idx, target_row, target_col = target_pos_or_params
        target_piece = game_state.get_piece_at_coords(target_board_idx, target_row, target_col)

        # Vérifier si le mouvement est valide pour le type de pièce (simplifié pour l'exemple)
        # Ici, on ne vérifie que la destination est sur le même plateau pour l'instant
        if piece.board_idx != target_board_idx:
            print(f"  Mouvement invalide: {piece.type} (ID {piece.id}) ne peut pas changer de plateau via MOVE.")
            return False
        
        # Vérifier les règles de mouvement spécifiques (très simplifié)
        if piece.type == PIECE_KING:
            if abs(piece.row - target_row) > 1 or abs(piece.col - target_col) > 1:
                print(f"  Mouvement invalide: Roi (ID {piece.id}) ne peut se déplacer que d'une case.")
                return False
        elif piece.type == PIECE_INVOKER:
            if not (abs(piece.row - target_row) == 2 and abs(piece.col - target_col) == 2):
                print(f"  Mouvement invalide: Invocateur (ID {piece.id}) ne peut se déplacer que de 2 cases en diagonale.")
                return False
            if not current_board.is_empty(target_row, target_col):
                print(f"  Mouvement invalide: Invocateur (ID {piece.id}) ne peut se déplacer que sur des cases vides.")
                return False
        elif piece.type == PIECE_KNIGHT:
            # Vérification simplifiée du L-move
            dr = abs(piece.row - target_row)
            dc = abs(piece.col - target_col)
            if not ((dr == 1 and dc == 2) or (dr == 2 and dc == 1)):
                print(f"  Mouvement invalide: Cavalier (ID {piece.id}) ne peut se déplacer qu'en L.")
                return False
        elif piece.type == PIECE_ARCHER:
            if not ((abs(piece.row - target_row) == 1 and piece.col == target_col) or \
                    (piece.row == target_row and abs(piece.col - target_col) == 1)):
                print(f"  Mouvement invalide: Archer (ID {piece.id}) ne peut se déplacer que d'une case en ligne droite.")
                return False
        elif piece.type == PIECE_GUARDIAN:
            if not ((abs(piece.row - target_row) == 2 and piece.col == target_col) or \
                    (piece.row == target_row and abs(piece.col - target_col) == 2)):
                print(f"  Mouvement invalide: Gardien (ID {piece.id}) ne peut se déplacer que de 2 cases en ligne droite.")
                return False


        if target_piece:
            if target_piece.team_id == piece.team_id:
                print(f"  Mouvement invalide: {piece.type} (ID {piece.id}) ne peut pas capturer une pièce alliée.")
                return False
            else:
                print(f"  {piece.type} (ID {piece.id}) de l'équipe {piece.team_id} capture {target_piece.type} (ID {target_piece.id}) de l'équipe {target_piece.team_id}.")
                game_state.capture_piece(target_piece)
        
        current_board.move_piece(piece, target_row, target_col)
        print(f"  {piece.type} (ID {piece.id}) déplacé de {start_pos[1]},{start_pos[2]} à {target_row},{target_col} sur plateau {piece.board_idx}.")
        return True

    elif action_type == ACTION_INVOKE:
        if piece.type != PIECE_INVOKER:
            print(f"  Action invalide: Seul l'Invocateur (ID {piece.id}) peut invoquer.")
            return False
        
        # L'invocateur doit être sur la ligne centrale pour invoquer
        if (piece.row, piece.col) not in current_board.get_central_line():
            print(f"  Action invalide: L'Invocateur (ID {piece.id}) doit être sur la ligne centrale pour invoquer.")
            return False

        piece_type_to_invoke, target_board_idx, target_row, target_col = target_pos_or_params
        
        # Vérifier si la pièce à invoquer est dans la réserve de l'équipe
        invokable_piece_id = None
        for pid in game_state.team_reserves[piece.team_id]:
            p = game_state.get_piece_by_id(pid)
            if p and p.type == piece_type_to_invoke:
                invokable_piece_id = pid
                break
        
        if invokable_piece_id is None:
            print(f"  Invocation invalide: Aucune pièce de type {piece_type_to_invoke} dans la réserve de l'équipe {piece.team_id}.")
            return False

        target_board = game_state.boards[target_board_idx]
        if not target_board.is_valid_position(target_row, target_col) or not target_board.is_empty(target_row, target_col):
            print(f"  Invocation invalide: La position {target_board_idx},{target_row},{target_col} est invalide ou occupée.")
            return False

        # Vérifier si la cible est une zone d'invocation alliée
        # Pour l'exemple, on suppose que l'invocation est toujours sur une zone d'invocation valide
        # (plus complexe à vérifier pour tous les cas de connexion inter-plateaux ici)
        
        invoked_piece = game_state.get_piece_by_id(invokable_piece_id)
        game_state.team_reserves[piece.team_id].remove(invokable_piece_id)
        invoked_piece.is_captured = False # N'est plus capturée
        invoked_piece.set_position(target_board_idx, target_row, target_col)
        target_board.place_piece(invoked_piece)
        print(f"  {piece.type} (ID {piece.id}) invoque {invoked_piece.type} (ID {invoked_piece.id}) à {target_board_idx},{target_row},{target_col}.")
        return True

    elif action_type == ACTION_SPECIAL_ARCHER:
        if piece.type != PIECE_ARCHER:
            print(f"  Action invalide: Seul l'Archer (ID {piece.id}) peut effectuer une capture spéciale.")
            return False
        
        target_board_idx, target_row, target_col = target_pos_or_params
        target_piece = game_state.get_piece_at_coords(target_board_idx, target_row, target_col)

        if not target_piece:
            print(f"  Capture spéciale invalide: Aucune pièce à la cible {target_board_idx},{target_row},{target_col}.")
            return False
        if target_piece.team_id == piece.team_id:
            print(f"  Capture spéciale invalide: Ne peut pas capturer une pièce alliée.")
            return False
        
        # Vérifier la distance de 2 cases en ligne droite
        dr = abs(piece.row - target_row)
        dc = abs(piece.col - target_col)
        if not ((dr == 2 and dc == 0) or (dr == 0 and dc == 2)):
            print(f"  Capture spéciale invalide: Cible hors de portée (2 cases en ligne droite).")
            return False
        
        # L'archer reste sur sa case après la capture
        print(f"  Archer (ID {piece.id}) capture {target_piece.type} (ID {target_piece.id}) à distance.")
        game_state.capture_piece(target_piece)
        return True

    elif action_type == ACTION_SUICIDE:
        # Le suicide est un pouvoir par équipe et par partie, géré au niveau supérieur
        # Ici, on simule juste le transfert de la pièce
        
        # Vérifier si la pièce est un Roi ou un Invocateur (ne peuvent pas être suicidés)
        if piece.type in [PIECE_KING, PIECE_INVOKER]:
            print(f"  Suicide invalide: Les Rois et Invocateurs ne peuvent pas être suicidés.")
            return False

        print(f"  {piece.type} (ID {piece.id}) de l'équipe {piece.team_id} se suicide.")
        current_board.remove_piece(piece.id)
        piece.is_captured = True
        game_state.team_reserves[piece.team_id].append(piece.id)
        # Marquer la pièce pour un tour d'attente supplémentaire avant d'être invoquable
        # (Cette logique serait gérée dans la phase d'invocation réelle)
        return True

    else:
        print(f"  Action inconnue: {action_type}")
        return False


def simulate_turn(game_state, team_actions):
    """
    Simule un tour de jeu pour une équipe donnée avec des actions simultanées.
    Gère les conflits basiques (premier arrivé, premier servi).
    """
    print(f"\n--- Début du Tour {game_state.turn_number} pour l'Équipe {game_state.current_team_turn} ---")

    # Réinitialiser le statut de mouvement pour le tour
    for piece in game_state.active_pieces.values():
        piece.has_moved_in_turn = False

    # Les actions sont traitées dans l'ordre où elles sont données pour simuler "premier arrivé, premier servi"
    # Dans un vrai jeu, cela dépendrait de la latence ou de l'ordre de validation.
    
    # Pour un tour simultané, il faudrait pré-valider toutes les actions
    # puis les exécuter dans un ordre déterministe (ex: priorité par type d'action, puis par joueur ID)
    # Pour cette simulation, on les exécute séquentiellement pour voir l'impact.
    
    # On pourrait aussi trier les actions par priorité si on voulait simuler cela:
    # action_priorities = {ACTION_CAPTURE: 3, ACTION_SPECIAL_ARCHER: 2, ACTION_MOVE: 1, ACTION_INVOKE: 0, ACTION_SUICIDE: -1}
    # team_actions.sort(key=lambda x: action_priorities.get(x[1], -1), reverse=True)

    executed_actions_count = 0
    for action in team_actions:
        player_id, action_type, piece_id, start_pos, target_pos_or_params = action
        
        piece = game_state.get_piece_by_id(piece_id)
        if piece and piece.team_id == game_state.current_team_turn and not piece.has_moved_in_turn:
            print(f"Tentative d'action par Joueur {player_id} ({action_type} avec {piece.type} ID {piece_id}):")
            if execute_action(game_state, player_id, action_type, piece_id, start_pos, target_pos_or_params):
                piece.has_moved_in_turn = True
                executed_actions_count += 1
            else:
                print(f"  Action de {player_id} échouée.")
        elif piece and piece.team_id != game_state.current_team_turn:
            print(f"  Action ignorée: Pièce (ID {piece_id}) n'appartient pas à l'équipe actuelle.")
        elif piece and piece.has_moved_in_turn:
            print(f"  Action ignorée: Pièce (ID {piece_id}) a déjà agi ce tour.")
        else:
            print(f"  Action ignorée: Pièce (ID {piece_id}) non trouvée ou déjà capturée.")

    print(f"--- Fin du Tour {game_state.turn_number} pour l'Équipe {game_state.current_team_turn}. Actions exécutées: {executed_actions_count}/3 ---")
    game_state.display()

    # Vérifier les conditions de victoire après chaque tour
    winning_team = game_state.check_win_condition()
    if winning_team != -1:
        print(f"\n!!! L'Équipe {winning_team} a gagné la partie !!!")
        return True # Fin de la partie

    # Passer au tour suivant
    game_state.turn_number += 1
    game_state.current_team_turn = 1 - game_state.current_team_turn # Changer d'équipe
    return False # La partie continue

# --- Fonction principale de simulation ---

def run_simulation(pgn_data):
    """Exécute la simulation de la partie à partir des données PGN."""
    game_state = GameState()
    game_state.display()

    game_over = False
    for turn_actions in pgn_data:
        if game_over:
            break
        game_over = simulate_turn(game_state, turn_actions)

    if not game_over:
        print("\n--- Fin de la simulation (PGN terminé) ---")
        winning_team = game_state.check_win_condition()
        if winning_team != -1:
            print(f"\n!!! L'Équipe {winning_team} a gagné la partie !!!")
        else:
            print("La partie n'est pas terminée selon les conditions de victoire.")

# --- Exécution de la simulation ---
if __name__ == "__main__":
    run_simulation(pseudo_pgn_game)

