Yes. If **Game Setup is reusable regardless of whether the opponent is AI or human**, I would make it the single configuration checkpoint between lobby/connection and the chessboard.

The important distinction is: **Game Setup contains choices that define the match. It does not contain board preferences or in-game controls.**

## GAME SETUP — Full Diagram

```text
                         ┌─────────────────────────┐
                         │       GAME SETUP        │
                         └─────────────────────────┘

             ┌───────────────────────────────────────────┐
             │              PLAYERS / SIDES              │
             │                                           │
             │  PLAYER 1              PLAYER 2           │
             │  You                   Opponent           │
             │                                           │
             │  ○ WHITE               ○ BLACK           │
             │  ○ RANDOM               —                 │
             └───────────────────────────────────────────┘


             ┌───────────────────────────────────────────┐
             │              GAME SETTINGS                │
             │                                           │
             │  TIME CONTROL                             │
             │                                           │
             │  ○ NO CLOCK                               │
             │  ○ 5 + 0                                  │
             │  ○ 5 + 3                                  │
             │  ○ 10 + 0                                 │
             │  ○ 10 + 5                                 │
             │  ○ 15 + 10                                │
             │                                           │
             │  [ More / Custom ]                        │
             └───────────────────────────────────────────┘


             ┌───────────────────────────────────────────┐
             │                VARIANT                    │
             │                                           │
             │  • STANDARD CHESS                         │
             │                                           │
             │  ○ CHESS960                               │
             │  ○ ...                                    │
             └───────────────────────────────────────────┘


             ┌───────────────────────────────────────────┐
             │           MODE-SPECIFIC OPTION            │
             │                                           │
             │  VS COMPUTER:                             │
             │      DIFFICULTY                           │
             │      ○ EASY   • MEDIUM   ○ HARD           │
             │                                           │
             │  P2P:                                     │
             │     Something for p2p if they is still any│
             │      PLAYER 2                             │
             └───────────────────────────────────────────┘


                         ┌─────────────────┐
                         │      PLAY       │
                         └─────────────────┘

                                  ↓

                         ┌─────────────────┐
                         │     CHESS       │
                         └─────────────────┘
```

But I would **not actually make it look like four giant boxes**. That's just the logical diagram.

The actual screen should remain closer to your existing VS Computer composition:

```text
                         GAME SETUP


       PLAY AS                         TIME CONTROL

       ♟ WHITE                        NO CLOCK
       ♙ BLACK                        5 + 0
       🎲 RANDOM                      5 + 3
                                      10 + 0
                                      10 + 5


       OPPONENT / MODE                VARIANT

       COMPUTER                       STANDARD
       PLAYER 2                       ...


                 [ DIFFICULTY ]
                 EASY • MEDIUM • HARD

                         [ PLAY ]
```

### However, there is one important design issue

**Not every option should necessarily be visible at once.**

For example, if you don't implement time controls yet:

```text
GAME SETUP

PLAY AS
♟ WHITE     ♙ BLACK     🎲 RANDOM


OPPONENT
COMPUTER / PLAYER 2


DIFFICULTY
EASY     • MEDIUM     HARD


VARIANT
• STANDARD


              [ PLAY ]
```

Then later, when time control exists:

```text
GAME SETUP

PLAY AS
♟ WHITE     ♙ BLACK     🎲 RANDOM


TIME
NO CLOCK     5+0     5+3     10+0     10+5


VARIANT
• STANDARD


DIFFICULTY
EASY     • MEDIUM     HARD


              [ PLAY ]
```

For P2P, the **same Game Setup structure** is reused:

```text
                         GAME SETUP

                 ● CONNECTED
                 PLAYER 2

       PLAY AS
       ♟ WHITE     ♙ BLACK     🎲 RANDOM


       TIME CONTROL
       NO CLOCK     5+0     5+3     10+0


       VARIANT
       • STANDARD


                         [ PLAY ]

                            ↓

                          CHESS
```

No separate:

```text
P2P SETUP
```

and no:

```text
VS COMPUTER SETUP
```

Just:

```text
                    GAME SETUP
                       ↑
             ┌─────────┴─────────┐
             │                   │
        VS COMPUTER             P2P
             │                   │
             └─────────┬─────────┘
                       ↓
                     CHESS
```

### The complete game lifecycle

```text
HOME
 │
 ├── VS COMPUTER
 │       │
 │       ↓
 │   GAME SETUP
 │       │
 │       ↓
 │     CHESS
 │
 └── P2P GAME
         │
         ├── CREATE GAME
         │      ↓
         │   CONNECTING
         │      ↓
         │   CONNECTED
         │      ↓
         │   GAME SETUP
         │      ↓
         │     CHESS
         │
         └── JOIN GAME
                ↓
             CONNECTING
                ↓
             CONNECTED
                ↓
             GAME SETUP
                ↓
               CHESS
```

And **Game Setup is the final gate**:

```text
CONNECTION / OPPONENT
          │
          ↓
     ┌───────────┐
     │ GAME SETUP│
     └─────┬─────┘
           │
      player chooses
      match parameters
           │
           ↓
      ┌─────────┐
      │  PLAY   │
      └────┬────┘
           │
           ↓
         CHESS
```

The main thing I'd lock down now is **exactly which parameters belong in that screen**. From the full chess inventory, the candidates are **side, time control, variant, and AI difficulty**. Everything else belongs to the board, Settings, game actions, or the chess engine.
