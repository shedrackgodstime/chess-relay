# Board foundation

Observations on the 3D board and pieces, in `main` and in the reference
prototype, recorded before the piece system is written so the decision is made
with the evidence in front of us rather than after.

The prototype is `prototype` on the remote. It is not a runtime dependency and
nothing here is being ported from it; it is the reference for how Godot behaves.

## The short answer to "why can I drag-rotate in the prototype and not here"

**The prototype's scene root is a `Node3D`. This project's game screen root is a
full-rect `Control`.**

```text
prototype/main.tscn     [node name="Main" type="Node3D"]
main/…/game_screen.tscn [node name="GameScreen" type="Control"]   anchors_preset = 15
```

`Control.mouse_filter` defaults to `0`, which is `MOUSE_FILTER_STOP`. Asked of
the engine rather than assumed:

```text
Control mouse_filter default = 0        # MOUSE_FILTER_STOP
PanelContainer default       = 0        # MOUSE_FILTER_STOP
MarginContainer default      = 1        # MOUSE_FILTER_PASS
```

A full-rect `Control` with `MOUSE_FILTER_STOP` consumes mouse button and motion
events. They therefore **never reach `_unhandled_input`**, and
`GameOrbitCamera` does all of its input there. Exactly one node in the whole game
scene sets `mouse_filter` at all — a single `mouse_filter = 2` on one HUD child
— so everything else, the root included, is stopping.

This also explains why tapping squares works while dragging does not. The board's
input surface is an `Area3D`, and `Area3D` receives `input_event` from the
physics server, which is a different path from GUI input and is unaffected by
`mouse_filter`. So taps arrive and drags do not.

Two ways to fix it, and the second is the one already argued for elsewhere in
this project:

1. Set `mouse_filter` to `IGNORE` on the screen root and on every full-rect
   container that is not itself interactive. This works, and it is a list that has
   to be kept correct as the screen grows.
2. Take the drag in `_input` instead of `_unhandled_input`, or have the screen
   forward it. This does not depend on a list of filters being right.

The prototype avoids the problem by construction: a `Node3D` root cannot swallow
anything, and the HUD is a `CanvasLayer` that only takes input where its own
controls are.

## The second difference: touch is not handled here

Prototype's camera, 157 lines, handles:

| Event | Prototype | This project |
| --- | --- | --- |
| `InputEventMouseButton` | yes | yes |
| `InputEventMouseMotion` | yes | yes |
| `InputEventScreenTouch` | yes | **no** |
| `InputEventScreenDrag` | yes | **no** |
| `InputEventMagnifyGesture` | yes — pinch zoom | **no** |

Godot's `emulate_mouse_from_touch` defaults to `true`, so a single-finger drag
would arrive as emulated mouse motion — but only if it reaches the camera at all,
which is the problem above.

The prototype also does something that is easy to miss and matters on a phone:

> Single-finger drags also arrive as emulated mouse events, so the touch tracker
> suppresses mouse rotation while two fingers are down — otherwise pinching would
> also spin the view.

Without that suppression, a two-finger pinch arrives as two streams of emulated
mouse motion and the board spins while the player is trying to zoom.

## Why rotation itself is safe in both

Not because of the camera. Neither project ever converts a square into screen
space, so no camera angle can invalidate a stored mapping.

- **Here:** an `Area3D` over the board reports `event_position`; `world_to_square`
  calls `to_local()` and does floor arithmetic. Camera angle is not consulted.
- **Prototype:** `project_ray_origin` / `project_ray_normal` from the active
  camera, an `intersect_ray` against piece colliders, and an analytic
  intersection with the y = 0 plane as the fallback. Camera angle decides the ray
  and nothing else.

What the prototype has that this project does not is **the first half of picking**:
the ray is tested against pieces before the board, so a tall piece is tappable.
Once pieces exist, that is the difference between "the piece is there and I can
tap it" and "the piece is there and I hit the square under it instead".

### On `Area3D.input_event` and the docs

The `Area3D` class page lists only `area_entered`, `body_entered` and their
shape-level variants. `input_event` is inherited from `CollisionObject3D` and is
not listed there either. Its signature, asked of the engine:

```text
input_event(camera, event, event_position: Vector3, normal: Vector3, shape_idx: int)
```

Five arguments, and `board_view.gd`'s handler matches it exactly. Recorded
because it was reasonable to assume the 3D signal carried only
`(viewport, event, shape_idx)` — that is the shape of `CollisionObject2D`'s — and
that assumption would have been wrong.

## The prototype's pitch experiment, and why it was reverted

Prototype tried raising the camera from 45° to 50° because the e2 pawn was
believed untappable at 45°. It was measured, and the belief was wrong:

> A tap on the pawn reaches it at both angles, so the pawn was never unreachable.
> A tap on the bare centre of the e2 square reaches the king at both, and the
> pitch does not change that, because both pieces are centred on their own
> squares and the ray still passes through the king. What is left is the centre of
> a square sitting behind a piece, which picking by ray alone cannot resolve.

**Camera pitch does not fix occlusion.** It cost a change and a revert to find
out, and it is written down here so nobody spends it again. It belongs in
`game_screen_3d.md` beside the board stages.

## What the touch investigation actually established

Recorded because it was got wrong three times and the answer is short.

**Pinch zoom worked and one-finger drag did not.** That pair of facts identifies the
fault exactly: a two-finger pinch needs `InputEventScreenTouch` and
`InputEventScreenDrag` to arrive, so both of those were being delivered. A one-finger
drag went through emulated `InputEventMouseMotion`, and those were not arriving on
that device.

So a finger rotates the board, and the emulated mouse stands aside whenever **any**
finger is down rather than only when two are.

Two things that were believed and were not:

- **`Input.is_emulating_mouse_from_touch()` returning `true` proves nothing.** It
  reports the project setting's value, which defaults to true. It says nothing about
  whether the events are delivered on a given device. Three attempts reasoned from it.
- **The check that was supposed to cover this could not have caught it.** It drove
  `InputEventMouseMotion`, so it passed whether or not the touch path worked at all —
  it exercised the one thing that turned out not to work. It now drives touch events.

The prototype stands aside only for two fingers, because with one the emulated mouse
does the rotating. That is the single assumption that does not survive being copied,
and it is noted in the camera.

The lesson for the next device-only bug: **a setting read back from the engine is not
evidence that the engine is doing the thing.** Ask what arrived, not what is
configured — and the cheapest way to ask is to notice which features work.

## Both scenes are empty shells

```text
board_view.tscn   [node name="ChessBoardView" type="Node3D"] + script
piece_view.tscn   [node name="ChessPieceView"   type="Node3D"] + script
```

Six lines each. The board's 64 squares, its frame, its plinth, its coordinate
labels, the highlight overlays and the input surface are all constructed in
`_ready()`. None of it is visible in the editor, and none of it can be adjusted
without running the game and reading code.

This is the same finding as item 2 of `foundation_tightening`, in 3D. It was not
in that document because the audit was scoped to the UI.

| | This project | Prototype |
| --- | --- | --- |
| Board node | `Node3D`, 64 children built in code | `MeshInstance3D`, one procedural mesh |
| Geometry | box primitives | a `geometry/` library: extrude, lathe, profile curve, mesh builder |
| Highlight | four overlay roots | a reusable `SquareHighlight` object |
| Piece | two colour constants, nothing else | 30 lines, reusable, with colliders |
| Trays | none | `TrayView`, one per side |

The prototype's board being a single mesh is cheaper and is why it does not have
this problem; a mesh cannot be built out of sixty-four invisible nodes.

## What has to be decided before the piece is written

1. **The piece must be a real scene.** It is used on the board, in two trays, and
   possibly in a preview, so it has to be geometry that can be instantiated. It
   cannot be something `_ready()` constructs.
2. **It needs a collider.** Prototype established that ray picking against pieces
   is required for tall pieces to be tappable. Deciding this after the piece is
   drawn means redoing the picking.
3. **The 3D palette**, which is item 4 of `foundation_tightening` and is deferred
   to exactly this point. `Theme` does not apply to 3D materials, so this cannot
   simply move into `chess_relay_theme.tres`. The options are a shared script
   resource, exported colours on one scene, or project settings.
4. **Whether the board keeps being built in code.** Fixing it is not urgent for
   correctness — it works, and the tests pass — but it is the same decision item 2
   already made for the UI, and the board is where the pieces go.