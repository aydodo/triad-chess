# TRIAD CHESS - Spécifications complètes pour prototype

**Version :** 3.0  
**Date :** Mai 2026  
**Créateur :** Dorian Ayllón  
**Objectif :** Document de transmission pour développement prototype

---

## 1. VISION DU PROJET

### Concept
Triad Chess est un jeu tactique multijoueur 3v3 qui fusionne :
- La profondeur stratégique des échecs classiques
- L'interdépendance d'équipe des MOBA (DotA 2, League of Legends)
- Les mécaniques d'invocation du Bughouse Chess
- La structure territoriale du Hnefatafl

### Proposition de valeur unique
"Le premier jeu d'échecs tactique en équipe où vos décisions individuelles influencent directement le succès de vos coéquipiers à travers un système d'invocation partagée"

### Cible
- Joueurs d'échecs cherchant une dimension collaborative
- Joueurs de MOBA cherchant un gameplay plus tactique et accessible
- Format de partie : 10-20 minutes
- Positioning : Plus accessible que LoL, plus profond que les échecs classiques
- Comparable à Rocket League en termes de courbe d'apprentissage

---

## 2. RÈGLES DU JEU - CONFIGURATION

### 2.1 Plateaux

**3 plateaux** rectangulaires de **5 colonnes × 7 lignes** (a-e, 1-7)

```
┌─────────┐  ┌─────────┐  ┌─────────┐
│ Plat. 1 │──│ Plat. 2 │──│ Plat. 3 │
│  5×7    │  │  5×7    │  │  5×7    │
└─────────┘  └─────────┘  └─────────┘
     └───────────┴───────────┘
```

**Notation:** `[Plateau][Colonne][Ligne]` (ex: `1c4`, `2a1`, `3e7`)

### 2.2 Zones

| Zone | Lignes | Description |
|------|--------|-------------|
| Base joueur | 1-3 | Zone de départ et d'invocation |
| Zone neutre | 4 | Ligne centrale |
| Base adverse | 5-7 | Zone adverse |

**Zone d'invocation:** Lignes 1-3 du joueur

### 2.3 Disposition initiale

Ligne 1 (joueur Sud) ou ligne 7 (joueur Nord):

| a | b | c | d | e |
|---|---|---|---|---|
| Slot 3 | Slot 2 | Roi | Invocateur | Slot 1 |

---

## 3. CLASSES ET MOUVEMENTS

### 3.1 Classes obligatoires

**ROI**
- Déplacement: 1 case toutes directions
- Attaque: Contact (adjacent)
- Spécial: Ne peut pas être invoqué

**INVOCATEUR**
- Déplacement: 2 cases diagonale (ne saute pas)
- Attaque: Aucune
- Spécial: Invocation depuis ligne 4
  - Place pièce de réserve en zone 1-3
  - Peut invoquer sur plateaux alliés connectés
  - Coûte action complète
- Ne peut pas être invoqué

### 3.2 Classes sélectionnables (draft 3 slots)

**SLOT 1 - Mobile:**

**Cavalier**
- Déplacement: L (2+1), saute

**Assassin**
- Déplacement: 3 cases L/D (ne saute pas)
- Attaque: Diagonale adjacente uniquement
- Spécial: Retour immédiat optionnel après capture

**SLOT 2 - Distance:**

**Archer**
- Déplacement: 1 case ligne droite
- Attaque: Distance 2 (ligne droite, reste sur place)
- Action: Bouger OU tirer (pas les deux)
- Ignore protection Gardien

**Mage**
- Déplacement: 1 case diagonale
- Attaque: Distance 3 (toutes directions, traverse pièces)
- Action: Bouger OU tirer (pas les deux)
- Fragile: Capturable par pièces portée ≤2

**SLOT 3 - Support/Défense:**

**Gardien**
- Déplacement: 1-2 cases ligne (ne saute pas)
- Attaque: Contact
- Spécial: Pièces adjacentes immunisées (sauf vs Archer)

**Paladin**
- Déplacement: 1 case toutes directions
- Attaque: Contact
- Spécial: Protection passive + Invocation 1×/partie

**Enchanteur**
- Déplacement: 1 case toutes directions
- Attaque: Aucune
- Spécial: Totem d'Invocation 3×3 (1×/partie, destructible après 3 invocations)

---

## 4. DÉROULEMENT DU JEU

### 4.1 Tours séquentiels (RECOMMANDÉ prototype)

```
Tour Équipe A (20s):
  Joueur A1 → action
  Joueur A2 → action
  Joueur A3 → action

Tour Équipe B (20s):
  Joueur B1 → action
  Joueur B2 → action
  Joueur B3 → action
```

### 4.2 Actions possibles

- Déplacement
- Capture
- Tir distance (Archer/Mage)
- Invocation (Invocateur depuis ligne 4)
- Invocation Paladin (1×/partie)
- Poser Totem (Enchanteur 1×/partie)
- Passer

**Règle: 1 action par joueur par tour**

---

## 5. SYSTÈME DE RÉSERVE ET INVOCATION

### 5.1 Réserve d'équipe

- Commune aux 3 coéquipiers
- Visible par tous (information complète)
- Contient pièces capturées

### 5.2 Invocation

**Conditions:**
- Invocateur doit être ligne 4
- Case cible: vide, zone 1-3
- Coûte action complète
- Pièces non-invocables: Roi, Invocateur

---

## 6. CONDITIONS DE VICTOIRE

**Option A - Simple (RECOMMANDÉ prototype):**
- Capturer 2 rois adverses + conserver 1 roi allié
- Partie termine immédiatement

**Options alternatives (pour versions ultérieures):**
- B) Farming: Mode Sabotage/Bonus après victoire plateau
- C) Redistribution: Fusion plateaux après élimination

---

## 7. SYSTÈME MOMENTUM (Capacité Ultime)

### 7.1 Jauge Momentum (0-100)

| Événement | Points |
|-----------|--------|
| Capturer pièce | +10 |
| Invoquer | +5 |
| Menacer roi | +15 |
| Perdre pièce | −10 |
| Perdre roi | −20 |

### 7.2 Capacités Ultimes (à 100 Momentum, 1×/partie)

1. **Invocation Masse**: 3 pièces simultanées
2. **Bouclier Divin**: Immunité 1 tour
3. **Téléportation**: Échanger 2 pièces entre plateaux
4. **Résurrection**: Ramener pièce sans réserve

---

## 8. RÈGLES ANTI-STAGNATION

| Seuil | Effet |
|-------|-------|
| 8 tours sans capture | Zone neutre: +1 portée |
| 12 tours | Colonnes a/e fermées → 3×7 |
| 16 tours | Rois sans protection |

---

## 9. SYSTÈME ELO ET PROGRESSION

### 9.1 Classement

Bronze → Argent → Or → Platine → Diamant → Maître → Grand Maître

### 9.2 Calcul points

```
Δ Elo = (Résultat équipe × 0.6) + (Performance indiv × 0.4)

Performance = Captures×2 + Survie×1/pièce + Invocations×3 + Protections×1
```

### 9.3 Daily Missions

- Faciles: +50 XP
- Moyennes: +100 XP
- Difficiles: +200 XP

---

## 10. STACK TECHNIQUE

### 10.1 Client (Prototype)

```
Langage: Lua
Framework: LÖVE2D
Rendu 3D: Menori (https://github.com/rozenmad/Menori)
  Alternatives: g3d, LÖVE3D

Structure:
/client/
  /src/
    main.lua
    /game/
      board.lua       # 3 plateaux 5×7
      pieces.lua      # Classes
      rules.lua       # Validation coups
      reserve.lua     # Réserve équipe
      momentum.lua    # Jauge
    /rendering/
      scene.lua       # Scène 3D Menori
      camera.lua      # Caméra orbitale
      models.lua      # Modèles 3D
    /network/
      client.lua      # WebSocket client
      protocol.lua    # Messages
    /ui/
      hud.lua         # Interface
      menu.lua        # Menus
  /assets/
    /models/          # .obj/.gltf
    /textures/
    /fonts/
```

### 10.2 Serveur

```
Langage: Rust
Framework: Tokio + Axum
WebSocket: tokio-tungstenite

Dépendances Cargo.toml:
[dependencies]
tokio = { version = "1", features = ["full"] }
axum = "0.7"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
tokio-tungstenite = "0.21"
uuid = { version = "1", features = ["v4", "serde"] }

Structure:
/server/
  /src/
    main.rs
    /game/
      state.rs        # GameState
      rules.rs        # Validation
      actions.rs      # Actions
    /network/
      websocket.rs    # WebSocket handler
      protocol.rs     # Sérialisation
    /matchmaking/
      queue.rs        # File attente
      room.rs         # Salles 6 joueurs
```

---

## 11. PROTOCOLE RÉSEAU

### 11.1 Messages WebSocket (JSON)

**Client → Serveur: Action**
```json
{
  "type": "action",
  "player_id": "uuid",
  "action": {
    "type": "move"|"capture"|"invoke"|"special",
    "piece_id": "uuid",
    "from": "1a1",
    "to": "1a3",
    "timestamp": 1234567890
  }
}
```

**Serveur → Client: État**
```json
{
  "type": "game_state",
  "boards": [
    {
      "id": 1,
      "pieces": [
        {
          "id": "uuid",
          "type": "king"|"summoner"|"knight"...,
          "owner": "player1",
          "position": "1c1"
        }
      ]
    }
  ],
  "reserve": {
    "team_a": ["knight", "archer"],
    "team_b": []
  },
  "momentum": {
    "team_a": 45,
    "team_b": 30
  },
  "current_turn": "team_a",
  "timer": 20.0
}
```

---

## 12. STRUCTURES DE DONNÉES

### 12.1 Lua (Client)

```lua
GameState = {
    boards = {
        {
            id = 1,
            pieces = {
                {
                    id = "uuid",
                    type = "king",
                    owner = "player1",
                    position = {col = 3, row = 1}
                }
            }
        }
    },
    reserve = {
        team_a = {"knight", "archer"},
        team_b = {}
    },
    momentum = {team_a = 45, team_b = 30},
    current_turn = "team_a",
    timer = 20.0
}
```

### 12.2 Rust (Serveur)

```rust
#[derive(Serialize, Deserialize)]
pub struct GameState {
    pub boards: [Board; 3],
    pub reserve: Reserve,
    pub momentum: Momentum,
    pub current_turn: Team,
    pub timer: f32,
}

#[derive(Serialize, Deserialize)]
pub enum PieceType {
    King, Summoner, Knight, Assassin,
    Archer, Mage, Guardian, Paladin, Enchanter
}

#[derive(Serialize, Deserialize)]
pub struct Position {
    pub board: u8,  // 1-3
    pub col: u8,    // 0-4 (a-e)
    pub row: u8,    // 0-6 (1-7)
}
```

---

## 13. ROADMAP DÉVELOPPEMENT

### Phase 1: Prototype 1v1 (3-4 semaines)
- 1 plateau 5×7
- 5 classes base (Roi, Invocateur, Cavalier, Archer, Gardien)
- Rendu 3D basique
- Hot-seat local

### Phase 2: Extension 3v3 local (4-6 semaines)
- 3 plateaux connectés
- 8 classes complètes
- Système invocation + Momentum
- Hot-seat 6 joueurs

### Phase 3: Networking (6-8 semaines)
- Serveur Rust WebSocket
- Matchmaking simple
- Synchronisation 6 joueurs
- Alpha en ligne

### Phase 4: Polish (4-6 semaines)
- Système Elo
- Daily missions
- Tutorial
- Beta ouverte

**Total: 15-21 mois**

---

## 14. COMMANDES DÉMARRAGE

### Client LÖVE

```bash
# Installer LÖVE2D
brew install love      # macOS
sudo apt install love  # Linux

# Structure projet
mkdir triad-chess-client
cd triad-chess-client
mkdir -p src/game src/rendering src/ui assets

# Créer main.lua
touch main.lua

# Lancer
love .
```

### Serveur Rust

```bash
cargo new triad-chess-server
cd triad-chess-server

# Cargo.toml
[dependencies]
tokio = { version = "1", features = ["full"] }
axum = "0.7"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
tokio-tungstenite = "0.21"
uuid = { version = "1", features = ["v4", "serde"] }

# Structure
mkdir -p src/game src/network src/matchmaking

# Compiler
cargo run
```

---

## 15. PROCHAINES ÉTAPES IMMÉDIATES

### Pour Claude Code

**Étape 1: Setup**
1. Créer structure client (Lua/LÖVE)
2. Créer structure serveur (Rust)
3. Initialiser fichiers base

**Étape 2: Prototype 1 plateau**
1. Board.lua (plateau 5×7)
2. 5 classes de base
3. Règles validation
4. Interface sélection/mouvement

**Étape 3: Tests**
1. Tester chaque classe
2. Tester captures
3. Tester mouvements illégaux
4. Tester victoire

**Étape 4: Rendu 3D**
1. Intégrer Menori
2. Modèles primitives
3. Caméra orbitale
4. Tests performance

---

## 16. QUESTIONS À TRANCHER

**Pour le prototype:**

1. **Victoire:** Option A (simple) recommandée
2. **Tours:** Séquentiel recommandé
3. **Archer:** Doit choisir bouger OU tirer
4. **Draft:** Après validation mécaniques
5. **Modèles 3D:** Primitives géométriques

---

## 17. POINTS D'ATTENTION

### Équilibrage
- Mage semble faible (fragile + mobilité limitée)
- Assassin potentiellement trop puissant
- Surveiller combos Enchanteur + Paladin

### Performance
- Synchronisation 6 joueurs = défi majeur
- Latence cible: 50-200ms
- Rollback netcode peut être nécessaire

### Conception
- Phase farming à bien définir ou supprimer
- Règles anti-stagnation à tester
- Draft influence grandement la méta

---

## 18. EXEMPLES DE COMPOSITIONS

**Offensive:**
```
J1: Assassin + Mage + Paladin
J2: Cavalier + Archer + Enchanteur
J3: Assassin + Archer + Gardien
```

**Défensive:**
```
J1: Cavalier + Archer + Gardien
J2: Cavalier + Archer + Gardien
J3: Assassin + Mage + Paladin
```

**Invocation:**
```
J1: Cavalier + Archer + Enchanteur
J2: Assassin + Mage + Enchanteur
J3: Cavalier + Archer + Paladin
```

---

## 19. FORMULES MATHÉMATIQUES

### Facteur branchement
```
~20-25 mouvements/joueur × 3 = 60-75 décisions/tour équipe
```

### Complexité
```
États possibles ≈ 10^45
Profondeur moyenne: 30-40 coups avant victoire
```

### Équilibrage Elo
```
Δ Elo = (Résultat_Équipe × 0.6) + (Performance_Indiv × 0.4)

Performance = (Captures × 2) + (Survie × 1) + (Invocations × 3) + (Protections × 1)
```

---

## 20. RÉFÉRENCES

### Documentation
- LÖVE2D: https://love2d.org/
- Menori: https://github.com/rozenmad/Menori
- Tokio: https://tokio.rs/
- Axum: https://docs.rs/axum/

### Jeux référence
- Bughouse Chess (invocation)
- Hnefatafl (territorial)
- Auto Chess (draft)
- Rocket League (courbe apprentissage)

---

**FIN DU DOCUMENT**

**Contact:** Dorian Ayllón  
**Version:** 3.0  
**Date:** Mai 2026  
**Statut:** PRÊT POUR DÉVELOPPEMENT PROTOTYPE