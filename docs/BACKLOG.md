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
| Network indicator | shown as **GOOD** | **IDLE** | `_network_indicator`, `tools/build_main_scene.gd` |

These are on so every feature can be watched working while the game is still being
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
- ~~**Regenerating `main.tscn` breaks picking, and the generator is non-deterministic.**~~
  **Fixed** in `c2056bc`: `build_main_scene.gd` strips the random `unique_id` Godot writes
  on every save, so the scene is byte-stable. Generated twice, identical checksums, and the
  full suite now passes against a regenerated scene, which is the first time that has been
  true.
  How it was found, kept because the reasoning still applies. The committed scene and the
  regenerated one disagreed on a `CylinderShape3D` **pick shape** height, 0.80592 against
  0.7500508. Those are the hit areas, so the board answered taps on different pixels and
  `_pick_square` resolved to the wrong square, putting pieces two ranks out. The menu was
  the obvious suspect and was not involved. It took this long to find because a five-line
  menu change produced a 1021-line scene diff and the two real numbers hid inside it. A
  diff you cannot read is a diff you cannot trust, which is the argument for the stripping
  and also why a suite should be read before committing rather than after.
- **The main menu exists and the game opens on it.** Title, `Vs computer`,
  `P2P game`, `Settings`, built in `ui/main_menu.gd` and shown on start. It is a
  **CanvasLayer over the loaded board**, not a second scene, so nothing is built when
  a game starts and the thing behind the menu is a chessboard rather than a placeholder.
  P2P and Settings exist and say they cannot work yet, which is honest while it is
  clearly unwired; a button that silently does nothing is worse than one that explains.
  This is the entry point the lobby hangs off: the lobby is a screen reached *from*
  here, not a replacement for it.
- **`Exit` is now `Quit game`,** and it returns to the main menu rather than closing
  the process. Exit was the word for leaving a screen and there is more than one to
  leave now; a player who reads Exit as closing the app and finds it does not will not
  read it again. Closing the app is a decision the main menu should make, since only it
  knows whether there is anywhere to go back to.
- **Nothing pauses the board for the menu.** The dim backdrop is a Control that stops
  mouse input, so a tap on it never reaches `_unhandled_input` and becomes a move. An
  earlier version also set a board-paused flag as a backstop: the same rule stated
  twice, and the second copy broke every test that drives the board directly. Do not add
  it back.
- ~~**The main menu exists and the game opens on it.**~~ Superseded: it was a layer over
  the board rather than a scene of its own, and is now the home screen above.
- **`Exit` is now `Quit game`,** and it returns to the main menu rather than closing
  the process. Exit was the word for leaving a screen and there is more than one to
  leave now; a player who reads Exit as closing the app and finds it does not will not
  read it again. Closing the app is a decision the main menu should make, since only it
  knows whether there is anywhere to go back to.
- **Nothing pauses the board for the menu.** The dim backdrop is a Control that stops
  mouse input, so a tap on it never reaches `_unhandled_input` and becomes a move. An
  earlier version also set a board-paused flag as a backstop: the same rule stated
  twice, and the second copy broke every test that drives the board directly. Do not add
  it back.
- **The lobby exists for a computer game, and is UI only.** `res://lobby.tscn`, built by
  `tools/build_lobby_scene.gd`. Home asks *what kind of game*; the lobby asks *how this
  one goes*, and it asks three things and hands them over: difficulty, side, go.
  Difficulty and side are rows of buttons rather than dropdowns, so every option is
  visible at once and the player reads the panel instead of opening it, and the chosen
  one is visibly chosen rather than hidden behind a tap.
  **`MatchConfig` is the seam between the lobby and the game.** They are separate scenes
  with no object in common, so the choices live in one small static holder and nothing
  else crosses. It holds only what the player chose, never game state, so the game stays
  the only source of truth for a match.
  **Random resolves in the lobby, before the board exists.** Main reads the side before
  it aims the camera and places pieces, so the first frame is already correct and the
  board is never seen turning around after it appears.
  **Difficulty is UI only and is not acted on.** The AI plays a random legal move
  whatever it says. Marking it is a lie in three buttons, and that matters more here
  than anywhere else, because it is the most prominent control on the panel: a player who
  picks Hard and loses to nonsense concludes the game is broken. It ships visible and
  unbacked, and the search behind it is the next piece of work. It needs to be off the
  main thread when it arrives, since `AiPlayer.choose_move` is synchronous and a
  three-second freeze per move is not shippable.
  Not built, deliberately: a room list, chat, and the clock. All three need the
  transport, and a list of rooms that cannot be joined is the most misleading thing this
  project could ship.
  `tools/test_lobby.gd` is its own suite for the same reason as the home screen: a parse
  error here is a game that cannot be started at all.
- **Home is its own scene and the project's entry point.** `res://home.tscn`, built by
  `tools/build_home_scene.gd`, set as `run/main_scene`. It was a CanvasLayer over the
  loaded board first and that was wrong: the whole 3D world stayed alive behind a menu,
  costing memory and startup on a phone, and it let a player drag the camera and pick up
  pieces before choosing to play. `main.tscn` is now loaded only when a game is asked
  for, and quitting tears it down rather than hiding it, so nothing carries over.
  `ui/main_menu.gd` is gone; `ui/home_screen.gd` replaces it.
  The picture is `home_bg.jpg`, a lit king, drawn to **cover** rather than fit, so no
  black bars appear on any aspect ratio.
  **The wash over it is `HomeScreen.SHADE`, at 0.90.** It went 0.55, then 0.72, both too
  light, then 0.86 which was a touch too dark, so 0.90. All four judged on a real
  screen. The lesson is that the glow behind the king survives a light wash almost
  intact, because it is a large luminance *contrast* rather than a bright area, and
  dimming a contrast is not the same as dimming a highlight. If it ever wants to be
  brighter, the fix is a vignette that darkens the middle where the title sits, not a
  lighter wash. Flat rather than a gradient for the same reason: a gradient with a clear
  window in the middle puts the brightest part of the art exactly where the title is.
  The image is a mood; the words are the content.
  `tools/test_home.gd` is a suite of its own: a parse error here is a game that opens
  on a blank window, and nothing in the in-game tests would catch it. It asserts the
  wash really dims the picture, because the first version only checked that a node
  named HomeShade existed, which is how 0.55 passed review while the picture still
  shouted over the words.

- **The menu rows sit in an opaque card that hugs them.** A dimmed backdrop says the
  game is paused; the card is what the words are legible on. Sized by its contents
  rather than by fixed numbers, so a row cannot end up hanging outside it when the list
  changes. It has its own stylebox because the margins are content margins and sharing
  the buttons' would push every button on the board out by eighteen pixels.
- **The in-game menu exists.** Menu button, hidden-while-playing panel: New game
  (confirmed), Resign (confirmed), a legal-hints toggle, a graphics-quality option, and
  Exit (confirmed). Nothing destructive fires on the first tap; the confirmation
  occupies the space the list just vacated, so there is nothing else on screen to hit
  by mistake. Exit quits the process for now, since there is no main screen, and that
  one line is all that changes later.
  Still deferred from the discussion, recorded so they are not rediscovered: sound,
  coordinates, undo (no meaning against a human, so a permanently awkward button),
  draw offer (nothing to offer against today), animation speed, and a how-to-play
  rules reference (cheap, and people forget castling exists). The menu is not yet
  connection-aware, which it needs to be once there is an opponent.
- **New game: works, but its test is blocked.** `Main.start_new_game()` resets the
  position and rebuilds every piece view, clearing selection, last move, check marker,
  destination hints, trays and banner. A test that plays a capture and then rebuilds
  passes on its own but makes `_side_ownership_checks` fail later with the wrong piece
  selected, so it is not in the suite. Earlier I blamed an always-present new-game
  button intercepting taps; that was **wrong**, and putting the action in the menu
  fixed a different problem. The real cause is still unknown and it is shared-state
  pollution from `_rebuild_pieces`, most likely piece meshes or pick areas cached
  globally across scenes. Next thing to try: rebuild in one scene, then assert a piece
  built in a *second* fresh scene has the same mesh and pick area.

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
- ~~**Network status indicator.**~~ Built, in the corner the mic left, next to the menu.
  `Hud.NetworkState` is IDLE / CONNECTING / DEGRADED / LOST, drawn as Lucide signal
  bars, and it currently has nothing driving it, so it sits at IDLE, which is true
  today: there is no transport. Wiring it is one call once there is.
  Two decisions worth keeping. **Bars, not the wifi arcs:** this is a direct
  peer-to-peer link and nested arcs say router, they survive being drawn small less
  well, and `wifi-off`'s diagonal slash would dominate a passive corner for something
  that is only status. **Four states, three colours plus a neutral grey,** because
  connecting and not-connected are not the same thing and amber cannot honestly mean
  both; idle is grey rather than a colour because there is nothing to judge yet and
  painting it as a status would cry wolf every time the game opened.
  The bar count is the real channel and colour only reinforces it, because red and
  green are not separable for everyone and this board already decided brightness and
  shape carry the meaning. LOST shares one bar with CONNECTING and is separated by
  red, because it is the state that must not be read as progress.
  The whole set of bars is always drawn, faintly, under the live ones. That frame is
  what makes the glyph readable at all: a bare dot says nothing about what the control
  is or what it could show, and an idle state with nothing drawn looks identical to a
  broken one. With the frame in place idle says "a meter, at nothing". The frame is
  white at low opacity rather than a state colour, so it reads as capacity and never
  as a level. **The first attempt at 0.22 alpha was invisible on a real screen:** the
  test counted the pixels, confirmed they were drawn and correctly separated from the
  live bars, and the control still read as nothing but a stray dot, which is worse than
  no frame because it looks broken. Drawn is not visible, and a headless pixel count
  cannot tell the difference. It was then judged **too strong** at 0.42 and **still too
  strong** at 0.32, and is now 0.26 with strokes wider than Lucide's 2. Every value
  was judged by eye on a real screen and the first three were wrong: 0.22 in the
  invisible direction, the next two in the prominent one. Alpha is not perceived
  linearly and the low end is far harder to see than the high end, which is why
  stepping up from the bottom overshot twice while the arithmetic midpoint did not
  land. The strokes were widened and the control enlarged after the first reading, so
  0.26 now is not the same quantity 0.22 was, and treating them as comparable would
  be the wrong conclusion.
  The test bounds the frame between 0.22 and 0.30. That is deliberately a weak claim:
  it keeps the number out of the range already known to fail and does not pretend to
  know where inside it belongs, since three separate guesses were wrong.
  **It is shown as GOOD rather than IDLE, temporarily.** IDLE is the truthful state
  with no transport, but IDLE is four faint bars and no live ones, so it could not
  show whether the frame is faint enough to sit behind the bars it frames, and there
  was nothing to compare it against. GOOD also turned out to be a genuinely missing
  state rather than a display convenience: it is where a player spends the entire game
  and there was no way at all to say "connected and fine". Three bars, not four,
  because a peer link has no meaningful good/excellent distinction and a fifth bar
  would imply one. Returning to IDLE costs one line.
  The test pins that the drawn frame is the same size in every state, by
  lit-plus-unlit, since a lit bar covers the frame beneath it.
  It is `MOUSE_FILTER_IGNORE` and takes no input: a control that looks live but does
  nothing is worse than none, and anything over the board can catch taps aimed at
  squares.
  Belongs with the clock work, and is its other half: a connection indicator and a
  clock that pauses on disconnect are the same requirement.
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