# Backlog

Things that are decided and owed, kept here so they are not rediscovered or
quietly dropped. Ordered by what is likely to bite the player next.

## Open

### Selection should switch, not wait

Tapping one of your own pieces while a different one of yours is already selected
should re-select, moving the highlight to the new piece. Currently the first tap
selects and a second tap on another of your pieces is treated as a move attempt
from the first, which is refused, so the player has to tap the board to clear the
selection before choosing the other piece.

Worth deciding first: tapping a selected piece again already deselects it. That
behaviour and the new one must not collide, and the difference between "reselect"
and "deselect" has to be based on whether the second tap is on the piece that is
already selected, not on some mode flag.

### Mark the last move

The move just played should be marked at both ends, from and to, so a player can
see what happened last without remembering it. Squares are already highlightable
(`board/square_highlight.gd`), so this is presentation over existing state.

Related and probably wanted in the same pass: mark the piece that is check, and
the last piece that moved. The turn label already says whose move it is.

### Promotion is a choice, not an automatic queen

**This is the current task.** See below.

### The e-file cannot be tapped at the default pitch

The camera sits behind the player's own back rank, so the king on e1 hides the
e2 pawn completely: every point on the pawn resolves to the king. Only the e-file
is affected, the other seven files are fine. It clears at pitch 50 and above; the
default is 41.9, chosen deliberately.

Two possible fixes, not yet decided:
- Raise the default pitch to 50.
- Make picking prefer a piece that is behind a nearer blocker. Riskier: it changes
  what every tap means, not just this one case.

## Rules not yet implemented

The move generator refuses these rather than mishandling them, which is safe but
incomplete. `Rules` is the only place that needs to change.

- **Castling.** Needs castling rights tracked on `BoardState` (has the king or the
  relevant rook moved), and it is why the king's own square currently has no
  long move. Also needs the spaces between to be empty and unattacked, which the
  existing attack detection already covers.
- **En passant.** Needs the previous move, or an en-passant square on `BoardState`.
  The capture is a pawn stepping diagonally onto a square that is empty, which is
  why `Rules._pawn_moves` currently never generates it.
- **Draws.** Threefold repetition, the fifty-move rule, and insufficient material.
  All three are cheap on top of a move history that already exists
  (`ChessGame.history`), except insufficient material, which is a piece-count test.

## Not started

- **Timer.** Still unanswered: with no server, does one peer own both clocks or
  does each side run its own? The answer changes the data model, so it needs
  settling before any code.
- **Lobby and settings**, behind the menu button. `menu_requested` currently goes
  nowhere and the menu button is a no-op.
- **Real P2P transport.** `net/protocol.gd` has message shapes only. The voice
  control depends on this; see `DEV_SHOW_VOICE` in `main.gd`.
- **Voice.** The button cycles off, requesting, live and emits
  `voice_state_changed`, which has no listener. Needs capture, an encode path,
  transport, and `RECORD_AUDIO` on Android.
- **New game / rematch.** There is no way back to the opening position in play.
  Note that `game.reset()` alone is not enough: capture frees the victim nodes, so
  the piece registry and the scene both have to be rebuilt.
- **Hint the legal moves** for the selected piece. `Rules.pseudo_legal_moves` is
  already available and it is a small addition.

## Decided, do not relitigate

- Pieces are generated and rebuilt from `piece_type` and `side`, never swapped for
  a different asset. A promoted pawn is the same node with a different
  `piece_type`, not a destroyed piece and a new one. This is why promotion is
  cheap and why the tray pieces reuse the same path.
- Board geometry and rule logic share `BoardState.BOARD_SIZE` as the single
  source of truth for the board's size.
- Capture trays are 3D objects on the table, one each side, filled in capture
  order.
- The default view looks in from the player's own side, so their pieces are at the
  bottom of the screen.
- The player controls one side; the opponent is derived from it. Flipping the
  board is cosmetic and cannot reassign sides.
- Brightness is not verifiable headlessly. Do not change lighting values without
  being told what to change; see the history for what happened last time.