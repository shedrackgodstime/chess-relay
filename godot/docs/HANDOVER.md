# Handover

For whoever picks this project up. Read this before reading the architecture docs,
and read the docs: several decisions here only make sense with their reasons attached.

Nothing in here is aspirational. Everything was paid for.

---

## 1. The laws

These are not style preferences. Each one is here because breaking it cost real time
or produced something visibly wrong.

### A number is not a judgement

Measure to narrow the field, then **look**. Four times, in order:

1. **Camera pitch.** The e2 pawn was "believed untappable at 45°". Raising the camera
   to 50° was tried and reverted. Measured: a tap on the pawn reaches it at *both*
   angles. Pitch was never the problem.
2. **Occlusion.** A tap on the centre of e2 reaches the king at every angle, because
   the king is in the ray. Camera pitch cannot fix a square behind a piece.
3. **Proportion.** A model set won every axis that can be measured — licence, vertex
   count, file size, footprint consistency, documented tournament proportions — and
   looked worse than a procedural generator.
4. **An empty board.** Thirty-two pieces, all with null meshes, and a passing test.

This rule was written twice and ignored three times. It is written a third time here.

### Read the original before replacing it

The board's 64 squares were replaced with scene instances. Two bugs went in: they were
placed at `y = 0` where the code they replaced placed them half a thickness lower, and
the light/dark parity was computed over 1-based ranks instead of 0-based, inverting
every colour on the board. Both were found afterwards, by diffing against git.

**A generator that writes a scene nobody read the previous version of is not an
improvement.**

### A setting read back from the engine is not evidence the engine is doing the thing

`Input.is_emulating_mouse_from_touch()` returning `true` says the project setting has
its default value. It says nothing about whether events are delivered on a device. Three
attempts reasoned from it, and all three were wrong.

The fault was actually identified by the user in one sentence: **pinch zoom works and
drag doesn't.** Pinch needs `ScreenTouch` and `ScreenDrag`, so those arrive; drag needed
emulated `MouseMotion`, so those don't. That is the shape of good debugging — ask what
arrived, not what is configured.

### A green suite proves only what it asserts

Four times the suite passed over something visibly broken:

- A `PLAY` button whose `pressed` signal nothing was connected to.
- 32 children counted on a board with no meshes.
- A board 0.035 too proud of its frame with 32 wrongly coloured squares.
- A camera test that drove `InputEventMouseMotion`, so it passed whether or not the
  touch path worked at all.

Ask what a check would *fail* on. If the answer is nothing, it is decoration.

### Read the resolved value back

A theme item name the engine does not recognise is **ignored without complaint**. A
misspelled variation looks perfectly correct in the file and changes nothing at run time.

Every theme item added since is asserted by reading the value back off a live control
and comparing it. That is also how it was settled that `colors/modulate` is a real
`TextureRect` theme item — which had been assumed.

### A check that leaves shared state changed makes the next check lie

This happened **three times** with the camera. Restoring state afterwards is not
optional; the camera is shared with the checks that follow.

### Test what a player touches, not the functions

A test that calls `orbit_by()` directly cannot detect that no input ever arrives. The
drag test now drives real `InputEventScreenTouch` / `InputEventScreenDrag`.

### When something is proven on a device, that beats anything reasoned at a desk

The camera was rewritten from scratch and patched three times without working. The
original worked. When the third attempt failed, the answer was to take the original and
adapt it, not to write a fourth version.

### Document the process, not just the code

`application_core.md`, `project_structure.md` and `pre_game_screen_audit.md` are why the
foundation is sound, and they will still be true after everyone forgets this session.
Keep writing them.

---

## 2. Where the project actually is

### Working, end to end

- **Screens:** home, game setup (VS Computer and P2P), multiplayer hub, game
- **Multiplayer hub:** create code, join code, invite a listed player, receive an invite,
  recover from a decline — all five states, driven by `MockMultiplayerService`
- **Board:** 64 squares, frame, plinth, coordinate labels, highlights, per-square picking
- **Camera:** orbit, flip, pinch zoom, touch drag — verified on a device
- **Pieces:** a 1k set imported as scenes with embedded meshes, both colourways, knights
  turned to face their opponent
- **Checks:** one headless suite, `tests/ui_smoke_test.gd`

### Not started

- **Chess rules.** None in Godot. They belong to Rust's `chess_core`, per
  `application_core.md`. Do not write them here.
- **Movement.** The board draws a static position because nothing has told it otherwise.
  The command/event boundary is not live.
- **Clocks, trays, promotion, captures.**
- **Multiplayer.** The mock service is a presentation fixture. There is no transport.

### Staged plan

`board_build_order.md` is the current plan and says where each stage stands.

- **Stage 1, board shell — not started.** Squares are still built in `_ready()` rather
  than authored. Attempted once and reverted; read the original first this time.
- **Stage 2, world — done.**
- **Stage 3, pieces — done, differently than planned.** See §3.

---

## 3. Flags on the current implementation

These are live concerns, not closed questions. Each has a reason attached.

### Piece identity is duplicated in GDScript

`ChessPieceView.piece_type` is `@export_enum("pawn", "rook", "knight", …)`.

`application_core.md` puts piece state in Rust's `chess_core` and says of Godot only that
it "renders the board". That enum is a second list of piece types. It is correct-looking,
passes every check, and will disagree with Rust the first time either side changes.

The cost of removing it is no editor dropdown — which is the right trade, because a
dropdown suggests this project is the authority. **Decision needed**, not necessarily a
blocker.

### The theme lost 268 lines and gained 229

Landed in the same commit as the assets, which is the part to be suspicious of. Nothing
was found broken, but a diff that size arriving unannounced is exactly where a variation
gets dropped. **Worth a read before trusting it is complete.**

### `PIECE_SCALE := 16.0` is a magic number

It is applied uniformly to all six pieces, which is right *only because* the set is
consistent. A different set needs per-piece factors. Not a bug — a thing to know before
adding a model.

### Warnings-as-errors is set but unverified

`project.godot` sets `debug/gdscript/warnings/treat_warnings_as_errors = true` and the
engine reports it as true. **A deliberately unused signal and a deliberately unused local
both compiled clean** under `--script --check-only`, while a syntax error in the same file
failed correctly.

So the setting is valid and the harness works, but warnings did not escalate in a
headless script run. **Confirm in the editor** before relying on it. This is item 1 of
`foundation_tightening.md` and it is the only item there not finished.

### Squares are still built in code

`board_view.gd` constructs 64 squares, the overlay roots and the coordinate labels in
`_ready()`. Nothing is visible in the editor. This is item 2 of `foundation_tightening.md`
applied to 3D, and it is not done.

### The frame is still built in code too

Deliberate. `_build_frame()` makes four raised rails around a plinth, and the generator
that was replacing it emitted a slab — same name, different silhouette. It moves when it
moves as rails.

---

## 4. The environment, which will waste your afternoon otherwise

### Godot

- `godot-headless` is a wrapper at `/usr/data/.../usr/bin/godot-headless` pointing at a
  binary in `/usr/share/godot/`. Godot 4.7.2 stable, arm64.
- **`--import` and `--editor` both abort** with `free(): invalid size` on this build. It
  reproduces on a pristine checkout, so it is the binary, not the project.

### Consequences

- **`.godot/global_script_class_cache.cfg` cannot be regenerated the normal way.**
  `tools/build_class_cache.py` rebuilds it by scanning for `class_name`. **Run it after
  adding any script with a new `class_name`**, or every script naming it will fail to
  parse.
- **`.glb` files are not loadable through `ResourceLoader`** without the import pipeline.
  The current pieces are `.tscn` with embedded meshes, so this no longer bites — which
  is part of why that route won.

### Storage quirks

- **The shell's working directory vanishes intermittently.** Use `git -C <path>` and the
  `workdir` parameter; do not rely on a relative `git` call.
- Paths under `ref/` on this Android storage are unreliable.

### Running things

```sh
bash godot/tests/run_ui_checks.sh          # the whole suite, non-zero on failure
python3 godot/tools/build_class_cache.py  # after adding a class_name
```

`tools/runall.sh` from the earlier prototype is **gone** — the temp directory was wiped
mid-session and it was never tracked. `run_ui_checks.sh` replaced it.

### Reference material

`ref/` is **gitignored** and exists only on the machine that cloned it:

- `ref/chess-relay` — the prototype. Working rotation camera, a procedural piece
  generator, 15 test suites, and the reasoning behind the pitch experiment. The single
  most useful thing in the repository.
- `ref/Godot-Chess-Prototype` — BSD-3, imported piece models, two cameras instead of free
  orbit
- `ref/models-candidates` — model sets that were tried and rejected

Because it is ignored, the doc citations in the architecture notes **cannot be re-checked
without that checkout.** Fetch them from `docs.godotengine.org/en/stable` instead.

---

## 5. What went wrong, briefly, so it is not repeated

Four model sets were tried before one looked right: a CSG revolved profile (cannot
express merlons, a crown or a cross), two imported packs (both technically superior,
both looked wrong), and finally a 1k set arriving as authored scenes.

**What won was not a better spec. It was arriving as authored scenes with embedded
meshes rather than as a pack chosen off a measurements table.**

The most expensive single mistake was writing a from-scratch camera when a working one
already existed in the reference. Three failed patches later it was replaced with the
original's design. **Check `ref/` before writing anything the prototype already solved.**

---

## 6. If you have to learn one thing

Look at what is on screen before believing any document, including this one.

The empty board is the clearest case: every check passed, the commit message was
confident, and there was nothing on the board. **Measure, then look, then believe.**