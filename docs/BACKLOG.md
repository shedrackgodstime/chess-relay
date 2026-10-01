# Backlog

Things that are decided and owed, kept here so they are not rediscovered or
quietly dropped. Ordered by what is likely to bite the player next.

## Open

### Indicator vocabulary

Agreed: the indicator means **"this square is a legal destination"**, not one
special effect per rule. A castling square gets the normal dot; an en-passant
square gets the normal capture indicator; only promotion needs a popup, because
the destination alone does not say which piece the pawn becomes. The unusual
parts belong to the rules engine, not to the visuals.

| Situation | Indicator |
| --- | --- |
| Empty legal destination | small dot |
| Legal capture | ring or outlined dot, or highlight the piece |
| Selected piece | highlighted square, border or glow |
| Castling | an ordinary destination dot |
| En passant | an ordinary capture indicator |
| Promotion | piece-selection popup, already built |
| Last move | subtle highlight on both squares |
| King in check | strong highlight on the king's square, then the ordinary escape dots |
| Checkmate | no indicators at all; the game-over banner, already built |
| Illegal attempt | a brief shake or flash. No indicator for it |

Indicators should be toggleable in settings. Worth deciding the default, and
whether the last-move highlight is part of the same toggle or separate, since it
is the one players tend to want permanently.

Legal-move hints are already available: `Rules.pseudo_legal_moves` gives the
destinations and `Rules.is_attacked` tells a capture from a quiet move, so the
whole table above needs no rules work.

Castling indicator specifically: when the king on its own square is selected, the
kingside and queenside destinations get ordinary destination dots. That needs
`can_castle_kingside()` and `can_castle_queenside()` on `Rules`, which do not
exist yet because castling is not written. Noted so it is not forgotten when it
is.

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

Done. `board/last_move_marker.gd` marks both ends of the move just played,
deliberately faint and separate from the selection highlight: selection says
"this is what you are holding", the marker says "this is what just happened",
and the marker has to stay visible when nothing is selected, which is most of
the time.

Also done, and the correction matters: the king-in-check highlight is the
**same frame as the selection marker, in red**. A first attempt built a separate
pulsing wash-and-border design, which was wrong. A check is not a new visual
idea, it is the marker already in use saying something urgent instead, so
reusing the frame means one shape to recognise and colour carrying the message.
`SquareHighlight` now takes a colour, with gold for selection and red for check,
and the emission follows the albedo so a red frame glows red rather than glowing
the same gold. Read from the position, so it is right at game start, after a side
change, and after a position is restored.

### Choosing a side

**The lobby's job, not the board's.** Built here by mistake once and pulled
again: a full-screen chooser over the board stops mouse input, so the game is
unplayable while it is up.

What already exists and must keep working, because the lobby will depend on it:
`Main.player_side`, `opponent_side()` derived from it, and `Main.yaw_for_side()`,
which the reset view and flip are both derived from so the camera faces whichever
side the player took. All of that is tested.

So the lobby needs to do two things: set `player_side` before the game starts,
and make sure whatever screen it uses has been dismissed by the time play
begins. A test asserts nothing full-screen is left over the board at start.

### Promotion

Done. The move is held until the player chooses, and the pawn is rebuilt in place
as the chosen piece.

### The game should end

Done. `ChessGame.result()` reports the outcome from the position, `apply_move`
refuses once it is over, and the HUD shows a banner.

### The e-file cannot be tapped at the default pitch

The camera sits behind the player's own back rank, so the king on e1 hides the
e2 pawn completely: every point on the pawn resolves to the king. Only the e-file
is affected, the other seven files are fine. It clears at pitch 50 and above; the
default is 41.9, chosen deliberately.

Two possible fixes, not yet decided:
- Raise the default pitch to 50.
- Make picking prefer a piece that is behind a nearer blocker. Riskier: it changes
  what every tap means, not just this one case.

## Open bug

### Perft position 3 is two moves over

`8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - -` should give 191 at depth 2 and we give
**193**. Depth 1 is exact at 14, Kiwipete is exact at 48 and 2039, and the direct
en passant tests pass, so the en passant mechanism itself works: the square is
recorded behind a double push, the capture is offered, the victim is removed from
where it stood rather than where it was taken, and the capture is counted.

So something else in this position over-generates. Position 3 is the standard
test for en passant captures that expose a king along a rank, which is the first
thing to look at. The suite asserts 193 rather than 191 so the number is visible
and cannot quietly drift further, and the assertion is named so it reads as
known-broken rather than as a passing test.

## Rules not yet implemented

The move generator refuses these rather than mishandling them, which is safe but
incomplete. `Rules` is the only place that needs to change.

- **Castling.** Done. Rights live on `BoardState` and are part of `hash` and
  `to_array`, because two peers can agree on every square and still be in
  different games. `can_castle_kingside()` and `can_castle_queenside()` exist for
  the indicator. The rook moves with the king and the right is spent.
- **En passant.** Done, apart from the perft position 3 bug above. The square is
  recorded on a double push, captured on landing, and cleared by everything else.

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