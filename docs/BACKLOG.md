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

Indicators are toggleable in settings, off by default, decided: marking every
destination is a real training aid but in a game it announces your intent before
you commit to it, so neither default suits both players and it is a lobby choice
rather than a rule. Delivered as the same thin frame in two brightnesses rather
than the dot and ring above, because the board already spends one frame shape
that the player learns once and a capture is distinguished by loudness, which is
what brightness has been carrying all along. Castling is marked on the king's
destination square only. Still to come:

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

**Corrected by measurement.** This was believed on a device and never tested, and
the test says something different. Measured with
`_e2_reachability_checks` in `tools/test_movement.gd`:

- A tap on the **pawn's own body** reaches the pawn, at pitch 45 and at 50. This
  is the tap a player actually makes, so the pawn is not unreachable.
- A tap on the **bare centre of the e2 square** reaches the **king**, at 45 and at
  50 alike. Raising the pitch does not help, because both pieces are centred on
  their own squares and the ray still passes through the king's body.

So the pitch is not the cause and 50 is not a fix; it is only a different view to
be judged by eye, and it is currently set to 50 for exactly that. The real problem
is narrower than this note claimed: the centre of a square can sit behind a piece
that stands in front of it, which picking by ray alone cannot resolve. That is
what needs deciding, and it applies to any piece standing in front of any square,
not specially to the e-file or to pawns.

Two possible fixes, not yet decided:
- ~~Raise the default pitch to 50.~~ Tried, measured, and put back: it fixed nothing,
  because the pitch was never the cause. See the correction above.
- Make picking prefer a piece that is behind a nearer blocker. Riskier: it changes
  what every tap means, not just this one case.

## Temporary: everything visible while building

**These defaults are for review, not chosen. Put them back before this ships.**

| What | Now | Shipping | Where |
| --- | --- | --- | --- |
| Legal-destination hints | **on** | **off** | `Indicators.DEV_DEFAULT`, `settings/indicators.gd` |
| Voice control | shown | follows `ai_opponent` | `Main.DEV_SHOW_VOICE`, `main.gd` |

Both are on so every feature can be watched working while the game is still being
built, which is worth more than the intent they give away: nothing can be judged
before it has been seen at all. The shipping values are the deliberate ones.

Legal hints default to off in a real game because every marked square announces
your intent a beat before you commit to it, which is noise for an experienced
opponent and the single most useful teaching aid there is for a beginner. That
tension is why it is a lobby setting and not a rule. Castling is the one place it
costs something concrete: with the hints off there is no cue at all that a king
moves two squares, which is worth checking in a real game before it stays off.

The tests pin both settings explicitly instead of asserting the defaults, so
correcting these values will not break anything that was testing behaviour.

## Rules not yet implemented

The move generator refuses these rather than mishandling them, which is safe but
incomplete. `Rules` is the only place that needs to change.

- **Castling.** Done. Rights live on `BoardState` and are part of `hash` and
  `to_array`, because two peers can agree on every square and still be in
  different games. `can_castle_kingside()` and `can_castle_queenside()` exist for
  the indicator. The rook moves with the king and the right is spent.
- **En passant.** Done. The square is recorded on a double push, captured on
  landing, and cleared by everything else. Verified against perft position 3 at
  14, 191 and 2812, which is the standard test for the case that caught the first
  implementation: an en passant capture vacates two squares, not one, and
  simulating only the mover's own left a shield in place and let a capture
  through that exposed the king along a rank.

- **Draws.** Done: threefold repetition, the fifty-move rule, and insufficient material.
  All three are cheap on top of a move history that already exists
  (`ChessGame.position_counts`), except insufficient material, which is a piece-count test.
- **Draw claims.** All three draws end the game automatically here. Under the real
  rules only the fifty-move rule and threefold repetition are claims a player has to
  make, and a fivefold repetition and a seventy-five-move draw are automatic.

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
- **New game / rematch.** Attempted and **reverted, not shipped**, because it could
  not be made to pass. `Main.start_new_game()` was written and worked by hand:
  `game.reset()` plus a full rebuild of the piece views, clearing selection, last
  move, check marker, destination hints, capture trays and the banner. `game.reset()`
  alone is genuinely not enough, since a capture frees the victim node and a finished
  game leaves the scene short of the thirty-two it began with.
  What is stuck: one failure in `_side_ownership_checks`, which runs *first* in the
  suite and so cannot be caused by code added later in it. Ruled out: `face_opponent`
  on rebuilt pieces (piece meshes are cached globally, so it was a fair suspect, but
  matching the generator exactly changed nothing); the new button intercepting taps
  (`set_game_over` never runs in that path, so it was never visible); and moving the
  button clear of the board. Two other failures were cross-scene pollution from a
  destructive test running mid-sequence and were fixed by running it last.
  Next thing to try: run the new-game section alone in a fresh process, to tell a
  global cache problem apart from genuine order dependence, before touching
  `_rebuild_pieces` again.
- **Move list / notation.** None. The last-move markers are the only record of what
  has been played.
- **Illegal-move feedback.** Nothing happens when a tap is refused. Agreed in the
  indicator vocabulary: a brief shake or flash, and no indicator for the attempt.
- **Draw claims.** Threefold and the fifty-move rule end the game automatically here.
  Under the real rules they are claims the player makes. This becomes a button rather
  than a rule, and a clock is what gives players a reason to press it.
- **The mic moved from top-right to top-left. It was** 244px in from the right edge
  and 180px from it, `VOICE_GAP` (160) to the left of the menu's centre, clustered
  with the menu as one corner of controls. It is now `MENU_INSET` (84) from the left
  edge, the same inset the menu keeps from the right. The contract in `test_hud` is
  now measured from the left edge rather than from the menu, deliberately, so the two
  sides cannot quietly collapse back into the same corner.
  The `RemoteDot`, which lights when the opponent is speaking, lives inside the mic's
  touch target and travelled with it. If a frame is ever built here, it must be
  `MOUSE_FILTER_IGNORE`: overlaying the board is how the reverted new-game button
  caught taps aimed at squares.
- **Top-left reserved for a call frame, if ever wanted.** Not planned and not to be
  built: noted only so the mic's move is not undone later for no reason. The
  reasoning is that a mic beside a small video frame of the opponent reads as one
  communication corner, where a mic alone in a corner is a little orphaned, so the
  mic would sit top-left with a frame above or beside it if video were ever needed.
  Worth being clear that the mic move is justified on its own: the right edge
  carries five controls and the left none, so balancing it is worth doing whether or
  not a frame ever appears. Do not let a speculative feature hold the layout
  hostage, and do not build the frame.
  If it ever were built, it would be mostly incremental work, since capture, encode
  and transport are the same work voice needs first. One thing to get right from the
  start: a frame sitting over the board must be `MOUSE_FILTER_IGNORE`. Overlaying the
  board is how the new-game button caught taps aimed at squares, and a panel the size
  of a video frame is a far bigger offender.
- **Network status indicator.** Agreed in principle, for the corner the mic leaves.
  Belongs with the clock work: a connection indicator and a clock that pauses on
  disconnect are the two halves of the same requirement.
- ~~**Hint the legal moves** for the selected piece.~~ Done, behind the
  `Indicators.show_legal_moves` setting, on temporarily for review.

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