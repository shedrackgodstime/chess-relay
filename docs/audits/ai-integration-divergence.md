# AI integration divergence audit — 2026-10-08

This is a record of a discovered integration divergence while wiring the AI
client into the Godot game screen. It is intentionally kept separate from the
normative application architecture. The purpose of this document is to retain
the failure, its surrounding risks, and the safeguards that must remain while
the bridge and multiplayer work continue.

## Executive finding

The AI did not have different chess rules. The authoritative move path was
correct, and the legal-capture preview was correct. The divergence happened in
the Godot input path:

1. Rust exposed a legal capture destination.
2. The player tapped the AI-owned piece on that destination.
3. The piece surface emitted its signal before the board surface.
4. Godot applied the multiplayer ownership guard to the tapped destination.
5. The handler returned `Waiting for opponent` before routing the tap to
   `SubmitMove`.

Local/hotseat mode did not have that ownership guard, so the same capture worked
there. The visible symptom looked like an AI or rules failure, but the actual
failure was a presentation/input boundary failure.

The immediate correction is in
`godot/src/ui/screens/game/game_screen.gd`: a legal selected destination is
handled before source-piece ownership is checked.

## Why this matters

This was not an isolated ordering typo. It exposed a larger class of risks:

- the same board gesture can enter through more than one surface;
- source selection and destination execution are different operations but were
  sharing one handler;
- mode flags (`local`, `multiplayer`, `AI`) can silently change input behavior;
- a correct legal-move query can be made useless by a later UI gate;
- a user-visible status such as `Waiting for opponent` can be technically
  plausible while being completely wrong for the gesture;
- bridge integration can appear healthy while the real `GameScreen` event path
  is not exercised;
- changing a guard for one client mode can alter another mode without changing
  any Rust rule code.

The painful part is that the system can be correct at each individual layer
and still be inconsistent end to end. Legal move generation, bridge loading,
piece rendering, and AI search may all pass while a tap is discarded between
rendering and command submission.

## Boundary that must hold

### Source selection

In AI and multiplayer games, Godot may select only the local player's own
piece. This is a presentation/input convenience and an interaction guard; it
is not the authority that decides whether a move is legal.

### Destination execution

After a local source has been selected, a tap on any legal destination must be
treated as a move attempt. If that destination is occupied by the opponent,
the occupant is a capture target, not a source-selection candidate.

The destination path must therefore run before the ownership guard:

```text
piece tap
  -> selected source + legal destination?
       yes -> submit source+destination
       no  -> source ownership check
               own piece -> select source
               other piece -> waiting / no selection
```

### Authority

Every human and AI move must converge on the same application command path:

```text
Godot input or AI search
  -> SubmitMove
  -> application/session validation
  -> MoveApplied or MoveRejected
  -> Godot re-render
```

The AI must not remove an opponent piece directly, mutate the rendered board,
or bypass the application validation path. The UI must not decide that a move
is legal merely because a dot is visible. The preview is an observation; the
accepted event is the fact.

## Mode matrix

| Concern | Local / hotseat | AI | Multiplayer |
| --- | --- | --- | --- |
| Select source | Either side | Local side only | Local side only |
| Tap legal opponent destination | Submit capture | Submit capture | Submit capture |
| Validate move | Application core | Application core | Application core / remote authority |
| Produce opponent move | Human input | AI adapter | Remote peer |
| Direct board mutation | Never | Never | Never |
| Ownership message | Optional | Waiting only when selecting opponent source | Waiting only when selecting opponent source |
| Save/session owner | Local screen/bridge | Local AI session | App/network owner |

The AI column must not become a second chess implementation. Its only special
behavior is choosing a move for its side and submitting it through the same
contract.

## Failure modes found or exposed

### 1. Capture surface precedence

Piece nodes sit above the board surface. A capture tap can therefore invoke the
piece handler first. A fix that only changes the board-square handler is
insufficient.

### 2. Source and destination conflation

`_on_piece_pressed` receives both a possible source piece and a possible target
piece. It must first ask whether a source is already selected and whether this
square is a legal destination. Only otherwise is the tapped piece a candidate
source.

### 3. Mode-gate broadening

Changing a condition from “multiplayer” to “multiplayer or AI” is not a harmless
refactor. Every branch under that condition must be reviewed for whether it
describes ownership, transport, persistence, resigning, draw offers, or
presentation. Those concerns do not automatically share the same mode set.

### 4. False correctness from previews

Legal dots are generated from a query. They do not prove that the eventual tap
will be routed to the command path. The end-to-end check must exercise the
actual piece surface, not only call `legal_moves_from()`.

### 5. Incorrect user feedback

`Waiting for opponent` is valid when the user tries to select an opponent's
piece as a source. It is invalid when the user is completing a legal capture.
Feedback must describe the rejected operation, not merely the object that was
tapped.

### 6. Borrowed versus owned bridge state

AI/local screens can own a bridge and persistence path. A networked game can
borrow a bridge owned by the app root. Treating those as one lifecycle can
cause unrelated save, resume, resign, or shutdown behavior to leak between
modes. This is a separate boundary from move legality, but the same integration
mistake pattern applies: one convenient mode condition hides several contracts.

### 7. Event-order assumptions

The move path depends on signal order, deferred freeing, board rebuilds, and
bridge event delivery. A handler that changes the board while another surface
is still emitting can invalidate the second handler. Input routing must remain
safe when both piece and board surfaces participate in one gesture.

## Safeguards required before calling the integration complete

### Behavioral checks

Each client mode needs the same minimal interaction table:

- select a local source;
- show legal quiet destinations;
- show legal capture destinations;
- tap a quiet destination;
- tap an opponent piece on a legal capture destination;
- tap an opponent piece on an illegal destination;
- tap an opponent piece with no source selected;
- verify the move event, board re-render, turn, and feedback.

The capture case must be driven through the actual `ChessPieceView` input
surface. A bridge-only `submit_move("e2e4")` test cannot detect this class of
failure.

### Contract checks

- A move preview never authorizes a move by itself.
- `SubmitMove` is the only move mutation entry point for human and AI clients.
- `MoveApplied` is the trigger for authoritative re-rendering.
- `MoveRejected` must leave the rendered position unchanged.
- AI turns must be gated by the authoritative turn, not only a Godot boolean.
- A stale AI result must be ignored after a new generation/session begins.
- A networked screen must not write to the local AI or local-game save path.
- Leaving a session must stop its worker and prevent late results from mutating a
  new session.

### Review checks for future mode changes

When adding or widening a mode condition, review every affected branch under
these headings independently:

1. source selection;
2. destination execution;
3. turn/ownership feedback;
4. move submission;
5. persistence;
6. resign/draw behavior;
7. bridge ownership and shutdown;
8. asynchronous result cancellation;
9. end-to-end test coverage.

Do not assume that “AI behaves like multiplayer” means every multiplayer
condition should include AI. AI shares move semantics, not transport ownership.

## Current status

- The capture-routing regression is corrected in `game_screen.gd`.
- Rust AI search and the bridge command path remain unchanged by this fix.
- UI smoke checks pass after the correction.
- The AI bridge smoke test passes for human move → AI reply → authoritative turn
  advancement.
- A dedicated real `GameScreen` AI capture regression remains required. The
  existing bridge smoke test proves command wiring, not the full occupied-piece
  tap path.
- This audit remains open until the mode matrix above is represented in tests,
  especially for AI and multiplayer capture gestures.

## Audit conclusion

The lesson is not “put the capture branch above one `if`.” The lesson is that
client-mode integration creates a second correctness surface around the real
application core. The core can be right while the client fails to deliver the
intent. Every mode-specific UI guard must therefore be treated as a boundary
change, reviewed against the complete gesture lifecycle, and tested from the
actual input surface through the application event and back to the rendered
position.
