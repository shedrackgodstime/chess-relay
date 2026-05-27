# Chess Rules — Complete Reference
> Full official rules for game development. Covers board setup, all piece movement, special moves, game-ending conditions, draw rules, clocks, and disambiguation notation.

---

## Table of Contents

1. [The Board](#1-the-board)
2. [Piece Inventory](#2-piece-inventory)
3. [Starting Position](#3-starting-position)
4. [Turn Structure](#4-turn-structure)
5. [Piece Movement Rules](#5-piece-movement-rules)
   - 5.1 [King](#51-king)
   - 5.2 [Queen](#52-queen)
   - 5.3 [Rook](#53-rook)
   - 5.4 [Bishop](#54-bishop)
   - 5.5 [Knight](#55-knight)
   - 5.6 [Pawn](#56-pawn)
6. [Capture Rules](#6-capture-rules)
7. [Special Moves](#7-special-moves)
   - 7.1 [Castling](#71-castling)
   - 7.2 [En Passant](#72-en-passant)
   - 7.3 [Pawn Promotion](#73-pawn-promotion)
8. [Check](#8-check)
9. [Checkmate](#9-checkmate)
10. [Stalemate](#10-stalemate)
11. [Draw Conditions](#11-draw-conditions)
12. [Illegal Move Handling](#12-illegal-move-handling)
13. [Chess Notation (Algebraic)](#13-chess-notation-algebraic)
14. [Chess Clocks and Time Controls](#14-chess-clocks-and-time-controls)
15. [Edge Cases and Clarifications](#15-edge-cases-and-clarifications)
16. [Piece Value Reference](#16-piece-value-reference)
17. [FEN — Forsyth-Edwards Notation](#17-fen--forsyth-edwards-notation)

---

## 1. The Board

- A chessboard is an **8×8 grid** of 64 alternating light and dark squares.
- **Files** are columns labeled `a` through `h` (left to right from White's perspective).
- **Ranks** are rows labeled `1` through `8` (bottom to top from White's perspective).
- Each square is identified by a file-rank pair, e.g. `e4`, `d7`, `h1`.
- The **bottom-right** square from White's perspective is always **light** (`h1`).
- The **bottom-left** square from White's perspective is always **dark** (`a1`).

```
  a   b   c   d   e   f   g   h
8 [r] [n] [b] [q] [k] [b] [n] [r]  ← Black's back rank
7 [p] [p] [p] [p] [p] [p] [p] [p]  ← Black's pawns
6 [ ] [ ] [ ] [ ] [ ] [ ] [ ] [ ]
5 [ ] [ ] [ ] [ ] [ ] [ ] [ ] [ ]
4 [ ] [ ] [ ] [ ] [ ] [ ] [ ] [ ]
3 [ ] [ ] [ ] [ ] [ ] [ ] [ ] [ ]
2 [P] [P] [P] [P] [P] [P] [P] [P]  ← White's pawns
1 [R] [N] [B] [Q] [K] [B] [N] [R]  ← White's back rank
```

> **Notation convention:** Uppercase = White pieces, lowercase = Black pieces.

---

## 2. Piece Inventory

Each player starts with **16 pieces**:

| Count | Piece  | Symbol (W/B) | Unicode |
|-------|--------|--------------|---------|
| 1     | King   | K / k        | ♔ / ♚  |
| 1     | Queen  | Q / q        | ♕ / ♛  |
| 2     | Rooks  | R / r        | ♖ / ♜  |
| 2     | Bishops| B / b        | ♗ / ♝  |
| 2     | Knights| N / n        | ♘ / ♞  |
| 8     | Pawns  | P / p        | ♙ / ♟  |

> The **Knight** uses `N` (not K) to avoid conflict with King.

---

## 3. Starting Position

```
Rank 8 (Black back rank): r n b q k b n r
Rank 7 (Black pawns):     p p p p p p p p
Ranks 6–3:                (empty)
Rank 2 (White pawns):     P P P P P P P P
Rank 1 (White back rank): R N B Q K B N R
```

**Square assignments (White):**

| Piece   | Square |
|---------|--------|
| Ra1     | a1     |
| Nb1     | b1     |
| Bc1     | c1     |
| Qd1     | d1     |
| Ke1     | e1     |
| Bf1     | f1     |
| Ng1     | g1     |
| Rh1     | h1     |
| Pawns   | a2–h2  |

**Square assignments (Black):**

| Piece   | Square |
|---------|--------|
| Ra8     | a8     |
| Nb8     | b8     |
| Bc8     | c8     |
| Qd8     | d8     |
| Ke8     | e8     |
| Bf8     | f8     |
| Ng8     | g8     |
| Rh8     | h8     |
| Pawns   | a7–h7  |

**Key rule:** The queen always starts on her own color (White queen on d1, a light square; Black queen on d8, a dark square). The mnemonic is **"queen on her own color."**

---

## 4. Turn Structure

1. **White always moves first.**
2. Players alternate turns. A player may not pass or skip a turn.
3. Each turn consists of exactly **one legal move**.
4. A move is not complete (and the clock does not switch) until the piece is released on its destination square (over-the-board rule; for engines, until the move is submitted).
5. If a player **touches** a piece of their own color with the intent to move, they **must** move it if a legal move exists (touch-move rule — relevant to over-the-board play; may be enforced in game dev if desired).
6. If a player touches an opponent's piece, they must capture it if capture is legal.

---

## 5. Piece Movement Rules

### 5.1 King

- Moves **exactly one square** in any direction: horizontally, vertically, or diagonally.
- **Cannot** move to a square that is attacked by any enemy piece.
- **Cannot** move to a square occupied by a friendly piece.
- Is the most important piece — its capture is the goal of the game.

**Movement offsets (Δfile, Δrank):**
```
(-1,+1) (0,+1) (+1,+1)
(-1, 0)        (+1, 0)
(-1,-1) (0,-1) (+1,-1)
```

**Special ability:** Castling (see Section 7.1).

---

### 5.2 Queen

- Moves **any number of squares** in any of 8 directions: horizontally, vertically, or diagonally.
- Cannot jump over pieces — movement is blocked by the first piece encountered in any direction.
- If that first piece is an enemy, the queen **can** capture it (landing on its square).
- If that first piece is friendly, the queen **cannot** move to or past it.

> The queen is the most powerful piece, combining the power of the rook and bishop.

**Directions:**
```
N, NE, E, SE, S, SW, W, NW
```

---

### 5.3 Rook

- Moves **any number of squares** horizontally or vertically (along ranks or files).
- Cannot jump over pieces.
- Captures by landing on an enemy-occupied square.

**Directions:**
```
N (file same, rank+), S (file same, rank-),
E (file+, rank same), W (file-, rank same)
```

**Special ability:** Participates in Castling (see Section 7.1).

**Rook activity tips (for AI/engine dev):** Rooks are most powerful on open files (no pawns blocking), on the 7th rank, or doubled (two rooks on the same file).

---

### 5.4 Bishop

- Moves **any number of squares diagonally**.
- Cannot jump over pieces.
- Captures by landing on an enemy-occupied square.
- A bishop **always remains on the same color square** it started on for the entire game.
  - White's c1 bishop → always on light squares.
  - White's f1 bishop → always on dark squares.

**Directions:**
```
NE (file+, rank+), SW (file-, rank-),
NW (file-, rank+), SE (file+, rank-)
```

**Each player starts with one light-squared and one dark-squared bishop.**

---

### 5.5 Knight

- Moves in an **L-shape**: 2 squares in one cardinal direction, then 1 square perpendicular (or vice versa).
- The **only piece that can jump over other pieces** — intervening pieces are irrelevant.
- Captures by landing on an enemy-occupied square.
- Always alternates between light and dark squares.

**8 possible destination offsets (Δfile, Δrank):**
```
(+1, +2)   (+2, +1)
(+2, -1)   (+1, -2)
(-1, -2)   (-2, -1)
(-2, +1)   (-1, +2)
```

> A knight on e4 can reach: d2, f2, c3, g3, c5, g5, d6, f6 — up to 8 squares, fewer near the edges.

---

### 5.6 Pawn

Pawns are the most complex piece due to their asymmetric and special rules.

#### 5.6.1 Normal Forward Move

- Moves **forward only** (toward the opponent's back rank).
  - White pawns move from rank 2 toward rank 8 (increasing rank).
  - Black pawns move from rank 7 toward rank 1 (decreasing rank).
- Moves **one square forward** to an empty square.
- **Cannot move forward if the square directly ahead is occupied** (by either color).

#### 5.6.2 Initial Two-Square Advance

- On a pawn's **very first move**, it may advance **two squares forward** (instead of one), provided:
  - **Both** the square directly ahead and the square two ahead are empty.
- This two-square option is lost permanently once the pawn has moved.
- This move enables the en passant rule (see Section 7.2).

#### 5.6.3 Pawn Capture

- Pawns **capture diagonally forward** — one square diagonally ahead (left or right).
- A pawn **cannot** capture directly forward.
- A pawn **cannot** move diagonally unless capturing.

**White pawn capture offsets (Δfile, Δrank):** `(-1, +1)` and `(+1, +1)`
**Black pawn capture offsets (Δfile, Δrank):** `(-1, -1)` and `(+1, -1)`

#### 5.6.4 Promotion

- When a pawn reaches the **opposite back rank** (rank 8 for White, rank 1 for Black), it **must immediately** be promoted (see Section 7.3).

#### 5.6.5 En Passant

- Special pawn capture available under specific conditions (see Section 7.2).

---

## 6. Capture Rules

- A capture occurs when a piece moves to a square occupied by an **enemy piece**.
- The captured piece is **removed from the board** immediately and permanently.
- You **cannot** capture your own pieces.
- The **king cannot be captured** — the game ends before any king capture occurs (via checkmate or resignation).
- Captures are **not mandatory** (except when it is the only way to escape check).
- A piece captures using its own movement rules (except pawns, which capture diagonally but move forward).

---

## 7. Special Moves

### 7.1 Castling

Castling is a combined king-and-rook move that occurs once per side per game, if conditions are met.

#### Mechanics

**Kingside castling (O-O):**
- King moves from `e1` to `g1` (White) or `e8` to `g8` (Black).
- Rook moves from `h1` to `f1` (White) or `h8` to `f8` (Black).

**Queenside castling (O-O-O):**
- King moves from `e1` to `c1` (White) or `e8` to `c8` (Black).
- Rook moves from `a1` to `d1` (White) or `a8` to `d8` (Black).

#### Conditions — ALL must be true

1. **The king has never moved** since the start of the game.
2. **The rook involved has never moved** since the start of the game.
3. **No pieces occupy the squares between** the king and the rook.
4. **The king is not currently in check.**
5. **The king does not pass through a square that is attacked** by an enemy piece.
6. **The king does not land on a square that is attacked** by an enemy piece.

> Note: The rook **may** pass through an attacked square. Only the king's path matters.

#### Common invalid castling scenarios

| Scenario | Legal? |
|----------|--------|
| King has previously moved, even if returned to e1 | ❌ No |
| Rook has previously moved, even if returned to h1 | ❌ No |
| King is in check | ❌ No |
| King passes through an attacked square | ❌ No |
| King lands on an attacked square | ❌ No |
| Rook passes through an attacked square | ✅ Yes (allowed) |
| Piece blocks the path between king and rook | ❌ No |

#### Castling rights tracking (for implementation)

Track 4 boolean flags:
- `white_can_castle_kingside`
- `white_can_castle_queenside`
- `black_can_castle_kingside`
- `black_can_castle_queenside`

Set to `false` when:
- The respective king moves (both kingside and queenside rights lost).
- The respective rook moves or is captured.

---

### 7.2 En Passant

En passant (French: "in passing") is a special pawn capture.

#### Trigger condition

An enemy pawn uses its **two-square initial advance** and lands **beside** your pawn on the **5th rank** (rank 5 for White, rank 4 for Black).

#### Mechanics

- Your pawn captures the enemy pawn **as if it had only moved one square**.
- Your pawn moves diagonally to the square the enemy pawn passed through (the square behind the enemy pawn).
- The enemy pawn is **removed from its current square** (not the square your pawn lands on).

**Example:**
- White pawn on `e5`, Black pawn advances from `d7` to `d5`.
- White can play `exd6` — the White pawn moves to `d6`, the Black pawn on `d5` is captured.

#### Rules

1. En passant is only available to **pawns** — no other piece can execute it.
2. It must be played **immediately on the very next move** — if the capturing player makes any other move first, the right to capture en passant is permanently lost for that pawn.
3. It is **optional** — the capturing player is not forced to take en passant.
4. En passant can result in **check or checkmate** if the position allows.
5. After capturing en passant, the capturing pawn is now on the file of the captured pawn.

#### Implementation

- After any pawn two-square advance, store the **en passant target square** (the square the pawn passed through).
- On the next move, if the opponent plays en passant to that square, execute the capture and remove the pawn from the square it actually landed on (not the target square).
- Clear the en passant target square at the start of every move (it only lasts one turn).

---

### 7.3 Pawn Promotion

#### Trigger

A pawn reaches the **last rank**:
- White pawn reaches **rank 8**.
- Black pawn reaches **rank 1**.

#### Rules

1. **Promotion is mandatory** — the pawn cannot remain a pawn on the last rank.
2. The pawn must be replaced **immediately**, before the opponent's turn.
3. The player may promote to a **queen, rook, bishop, or knight** of the same color.
4. The player **cannot** promote to a king.
5. The player **can** promote to a piece already on the board (e.g., having two or more queens is legal).
6. The promoted piece is active **immediately** — it can give check on the same move it is created.

#### Underpromotion

Promoting to anything other than a queen is called **underpromotion**. It is legal and sometimes strategically superior:
- Promoting to a **knight** can create a fork or deliver check that a queen cannot.
- Promoting to a **rook** instead of a queen can avoid stalemate (if queening would leave the opponent with no legal moves, making it a draw).

---

## 8. Check

- The king is **in check** when it is under attack by one or more enemy pieces.
- When in check, the player **must** resolve it on their next move.

#### Three ways to escape check

1. **Move the king** to a safe square not attacked by any enemy piece.
2. **Capture the attacking piece** (with any legal piece, including the king if it can safely reach the attacker).
3. **Block the attack** by interposing a friendly piece between the king and the attacker.
   - Blocking is only possible against **sliding pieces** (queen, rook, bishop).
   - You **cannot** block a knight or pawn check — only capture or move the king.

#### Double check

- When the king is attacked by **two pieces simultaneously** (usually caused by a discovered check), only moving the king is legal.
- Capturing or blocking can address only one attacker at a time, so the king must move.

#### Rules about check

- You **may never make a move that leaves your own king in check** — this applies even if it would otherwise be a legal move.
- You may **not** move into check voluntarily.
- Moving a pinned piece that exposes the king to check is **illegal**.

---

## 9. Checkmate

Checkmate ends the game immediately. The side that delivers checkmate **wins**.

#### Definition

The king is in check **and** there is no legal move that removes the check.

A position is checkmate if all of the following are true simultaneously:
1. The king is currently in check (attacked by at least one enemy piece).
2. The king cannot move to any safe square.
3. No friendly piece can capture the attacker(s).
4. No friendly piece can block the attack (or double-check makes blocking impossible).

#### Common checkmate patterns (for game dev AI reference)

| Pattern | Description |
|---------|-------------|
| Back-rank mate | Rook or queen delivers checkmate on the opponent's 1st/8th rank while pawns trap the king |
| Scholar's mate | Quick queen-bishop attack on f7 (4-move mate) |
| Fool's mate | Fastest checkmate in 2 moves (Black queen to h4) |
| Smothered mate | Knight delivers checkmate while the king is surrounded by its own pieces |
| Arabian mate | Knight and rook combine to mate a cornered king |
| Anastasia's mate | Knight and rook combine on an edge file |
| Boden's mate | Two bishops deliver checkmate on criss-crossing diagonals |
| Epaulette mate | Rook mates a king flanked on both sides by its own pieces |

---

## 10. Stalemate

Stalemate is a **draw**. Neither player wins.

#### Definition

The side to move has **no legal moves** and is **not in check**.

#### Key distinction from checkmate

| Condition | Result |
|-----------|--------|
| In check + no legal moves | **Checkmate** → opponent wins |
| Not in check + no legal moves | **Stalemate** → Draw |

#### Notes

- Stalemate can arise intentionally as a defensive resource (the losing side traps itself to force a draw).
- Offering or avoiding stalemate is a critical consideration in endgame play.
- A common beginner mistake: assuming a trapped king is automatically a loss — it is only a loss if the king is also in check.

---

## 11. Draw Conditions

A game ends in a draw when any of the following occur:

### 11.1 Stalemate
The side to move has no legal moves and is not in check. (See Section 10.)

### 11.2 Threefold Repetition (Claim)
- The **exact same position** (same pieces, same squares, same castling rights, same en passant possibilities, same side to move) has occurred **three times** during the game (not necessarily consecutively).
- The player whose turn it is may **claim** a draw. They are not forced to — the game continues if neither player claims.
- Under FIDE rules (since 2014), if a position is repeated a 5th time, it is an **automatic draw** (see 11.5).

### 11.3 Fifty-Move Rule (Claim)
- If **50 consecutive moves** have been made by both sides (i.e., 50 full moves = 100 half-moves/plies) **without**:
  - A pawn move, or
  - A capture,
- Either player may **claim** a draw.
- The count resets to zero on any pawn move or capture.

### 11.4 75-Move Rule (Automatic — FIDE)
- If **75 consecutive moves** have been made by both sides without a pawn move or capture, the game is automatically a draw — **no claim required**.
- This overrides the 50-move rule claim.

### 11.5 Fivefold Repetition (Automatic — FIDE)
- If the **same position occurs 5 times**, the game is automatically a draw — no claim required.

### 11.6 Insufficient Material
The game is automatically a draw when neither player has enough material to deliver checkmate by any legal sequence of moves. FIDE recognizes the following as insufficient material:

| Pieces remaining | Draw? |
|-----------------|-------|
| King vs King | ✅ Yes |
| King + Bishop vs King | ✅ Yes |
| King + Knight vs King | ✅ Yes |
| King + Bishop vs King + Bishop (same color bishops) | ✅ Yes |
| King + 2 Knights vs King | ✅ Yes (technically — cannot force mate) |

> Note: K+2N vs K is a theoretical draw because checkmate cannot be forced, though it is possible if the opponent plays into it. Some implementations treat this as a draw; FIDE rules require agreement or time forfeit.

### 11.7 Mutual Agreement
Both players may agree to a draw at any point during the game. Typically one player offers a draw and the other accepts.

### 11.8 Timeout with Insufficient Material (FIDE)
If a player's clock runs out (time forfeit) but the opponent has **insufficient material** to checkmate, the game is a draw rather than a loss.

---

## 12. Illegal Move Handling

In over-the-board play, if an illegal move is made, it must be corrected. In digital implementations:

- **Reject illegal moves** before they are applied to the game state.
- A move is illegal if:
  - It does not conform to the piece's movement rules.
  - It leaves the player's own king in check.
  - It violates any special move condition (castling, en passant, promotion).
  - It is a null move (no piece selected, destination equals origin).

---

## 13. Chess Notation (Algebraic)

Standard algebraic notation (SAN) is used universally to record moves.

### 13.1 Basic format

```
[Piece][from-disambiguation][x][destination][promotion][+/++/#]
```

- **Piece letter:** K, Q, R, B, N (omitted for pawns)
- **Capture:** `x` between origin disambiguation and destination
- **Destination:** file + rank, e.g. `e4`
- **Check:** `+`
- **Double check:** `++` (some sources use `+` for both)
- **Checkmate:** `#`
- **Promotion:** `=Q`, `=R`, `=B`, `=N` after destination
- **Castling:** `O-O` (kingside), `O-O-O` (queenside)

### 13.2 Disambiguation

If two identical pieces can move to the same square, the origin is specified:
- Add the **file** of the moving piece: `Rad1` (rook from a-file to d1)
- Add the **rank** of the moving piece: `R1d3` (rook from rank 1 to d3)
- Add both **file and rank** if still ambiguous: `Qa1b2`

### 13.3 Examples

| Move | Meaning |
|------|---------|
| `e4` | Pawn moves to e4 |
| `Nf3` | Knight moves to f3 |
| `Bxc5` | Bishop captures on c5 |
| `O-O` | Kingside castling |
| `O-O-O` | Queenside castling |
| `e8=Q` | Pawn promotes to queen on e8 |
| `exd6` | Pawn on e-file captures on d6 (en passant or regular diagonal) |
| `Rfe1+` | Rook from f-file moves to e1, delivering check |
| `Qxf7#` | Queen captures on f7, delivering checkmate |

### 13.4 Full-game notation format

```
1. e4 e5
2. Nf3 Nc6
3. Bb5 a6
(Ruy López Opening)
```

Moves are numbered by full move. White's move comes first, then Black's.

### 13.5 Coordinate Notation (UCI format)

Used by most chess engines (e.g., Stockfish). Format: `[from][to][promotion]`

```
e2e4     — pawn from e2 to e4
g1f3     — knight from g1 to f3
e1g1     — white kingside castling
e7e8q    — pawn promotes to queen on e8
```

---

## 14. Chess Clocks and Time Controls

In timed games, each player has a **separate clock**. After completing a move, the player stops their clock, starting the opponent's.

### Common time controls

| Format | Time |
|--------|------|
| Bullet | 1 minute per player (or 1+0, 2+1) |
| Blitz | 3–5 minutes per player (e.g., 3+2, 5+0) |
| Rapid | 10–25 minutes per player (e.g., 15+10) |
| Classical | 60–120+ minutes per player |

### Time increment (bonus)

Many time controls include an **increment** — extra seconds added to a player's clock after each move. Notation: `[base]+[increment]` (e.g., `5+3` = 5 minutes + 3 seconds per move).

### Delay

A **delay** (or Bronstein delay) gives a player additional seconds at the start of each turn without adding them to the clock if unused. Different from increment.

### Flagging (time forfeit)

A player whose clock reaches **zero** loses — unless the opponent has **insufficient material** to checkmate (see Section 11.8).

---

## 15. Edge Cases and Clarifications

### 15.1 Discovered Check
A piece moves, unmasking an attack from a piece behind it, putting the opponent's king in check. The piece that moves does not have to attack the king itself.

### 15.2 Double Check
Two pieces simultaneously attack the king. Only a king move can resolve it (blocking or capturing only removes one attacker).

### 15.3 Self-Pin
Moving a piece would expose the player's own king to check. Such a move is **illegal** even if it appears to be a valid move for the piece type.

### 15.4 Absolute Pin
A piece is absolutely pinned when it is on the line between its king and an enemy sliding piece (queen, rook, or bishop). Moving the pinned piece would expose the king to check, making the move illegal.

### 15.5 Relative Pin (Skewer)
A piece is pinned against a less valuable piece. Moving reveals the attack on the more valuable piece behind. The move is legal but may be strategically inadvisable.

### 15.6 Castling After Rook Capture
If a rook is captured by the opponent, the castling right on that side is lost. Castling is only possible with rooks that have never moved — a new rook (via pawn promotion) does **not** gain castling rights.

### 15.7 Promoting to a Second Queen
It is entirely legal to have two (or more) queens of the same color on the board. Use a physical representation (inverted rook, extra piece) or a digital representation that supports multiple queens.

### 15.8 En Passant and Check
- En passant can expose a discovered check on the capturing pawn's king if a rook or queen is aligned along the 5th/4th rank.
- If taking en passant would expose the player's own king to check, the capture is **illegal**.
- En passant can deliver **check or checkmate** if the pawn lands on a square from which it attacks the enemy king.

### 15.9 Last Rank and Stalemate via Promotion
If promoting to a queen would leave the opponent with no legal moves while not in check (stalemate = draw), the promoting player may instead underpromote to a rook or other piece to avoid the stalemate and win the game.

### 15.10 Move Order and Clock
A move is only complete when the piece is placed on the destination square and released (OTB) or submitted (digital). The clock is not switched until the move is complete.

---

## 16. Piece Value Reference

Standard relative values (centipawn scale, pawn = 100):

| Piece  | Value (centipawns) | Value (pawns) |
|--------|--------------------|---------------|
| Pawn   | 100                | 1             |
| Knight | 300–320            | ~3            |
| Bishop | 300–330            | ~3.2          |
| Rook   | 500                | 5             |
| Queen  | 900–950            | ~9            |
| King   | ∞ (cannot be exchanged) | — |

> These values are heuristic approximations. In specific positions, a piece's value depends on the pawn structure, king safety, and activity.

**Bishop pair bonus:** Having both bishops is worth approximately 50 centipawns extra — two bishops complement each other by covering all square colors.

---

## 17. FEN — Forsyth-Edwards Notation

FEN is a single-line string used to represent a complete board state. Every valid chess position can be expressed and reconstructed from FEN.

### Format

```
<piece placement> <active color> <castling> <en passant> <halfmove clock> <fullmove number>
```

### Starting position FEN

```
rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1
```

### Field breakdown

| Field | Meaning |
|-------|---------|
| Piece placement | Ranks 8 to 1, separated by `/`. Numbers = consecutive empty squares. Letters = pieces (uppercase = White, lowercase = Black). |
| Active color | `w` = White to move, `b` = Black to move |
| Castling | `K` = White kingside, `Q` = White queenside, `k` = Black kingside, `q` = Black queenside. `-` if none available. |
| En passant | Target square (e.g., `e6`) if en passant is possible, `-` if not. |
| Halfmove clock | Number of half-moves since last pawn move or capture (for 50-move rule). |
| Fullmove number | Starts at 1, increments after Black's move. |

### Example FEN (after 1. e4)

```
rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1
```

- `4P3` on rank 4 = 4 empty, white pawn, 3 empty.
- Active color = `b` (Black to move).
- En passant = `e3` (Black can capture en passant to e3 if they have a pawn on d4 or f4).
- Halfmove clock = `0` (pawn moved).

---

## Summary — Quick Rules Reference

| Rule | Answer |
|------|--------|
| Who moves first? | White |
| Can you pass your turn? | No |
| Can you capture your own pieces? | No |
| Does the king get captured? | No — the game ends at checkmate before capture |
| Can a pawn move backward? | No |
| Can a pawn capture forward? | No — only diagonally |
| Can a knight jump over pieces? | Yes |
| What piece can a pawn NOT promote to? | King |
| How long does en passant last? | One move only |
| Can you castle out of check? | No |
| Can you castle through check? | No |
| Can you castle if the rook is attacked? | Yes (rook's path doesn't matter) |
| Is stalemate a win? | No — it's a draw |
| Can you have two queens? | Yes |
| Is a draw by agreement mandatory? | No — both players must consent |

---

*Document generated for game development reference. Rules conform to FIDE Laws of Chess (2023 edition).*
