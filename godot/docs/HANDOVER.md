# Handover

For whoever picks this project up. Read this before reading the architecture docs,
and read the docs: several decisions here only make sense with their reasons attached.

Nothing in here is aspirational. Everything was paid for.

**Last updated 2026-10-07**, after a full audit and a quality-gate pass. Three things
changed and they are the ones to know before anything else:

- The test suite used to report success while **78 of 146 checks had never executed**.
  Fixed, and the harness now cannot report success without saying how many ran. §7.
- The Rust core **had never loaded** on the machine that ran those tests, so the last
  three commits' "runs on real core state" was unproven. Fixed on the project's side;
  this device cannot load it at all, for an environment reason. §4, §7.
- `treat_warnings_as_errors` **was not a Godot setting** and never had been since 2023.
  It looked set, it reported `true`, it did nothing. §3.

The worst thing still in the repository is the bridge forging the opponent. §3.

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

**This law was broken by a project setting, and the §7 version says so.** Reading
`ProjectSettings` back is not the same check as reading a resolved theme value: an
unknown key still reads back as whatever string is in the file. `treat_warnings_as_errors`
reported `true` for months and had not existed since 2023.

The difference: a *resolved theme value* comes from the engine, and reading it proves the
engine supplied it. A *project setting* is what you wrote. To read that one back
meaningfully, ask the engine what it has — list its registered property names — and check
yours is among them. `tools/check_warning_drift.py` does exactly that for warning keys.

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
- **Checks:** `bash godot/tests/run_all_checks.sh` — per-file parse with
  warnings-as-errors, a warning-key drift gate, and every `*_test.gd` suite with
  stderr treated as a failure. Backed by `.github/workflows/gates.yml`.
  **61 of 148 UI checks do not execute on this device**, all of them behind the
  bridge; see §4 on why, and §3 for what that means for the evidence.

### Not started

- **Chess rules.** None in Godot. They belong to Rust's `chess_core`, per
  `application_core.md`. Do not write them here.
- **Multiplayer.** The mock service is a presentation fixture. There is no transport.
- **Clocks, trays, promotion UI, captures.**

### Half-live, and it matters

- **Movement.** The command/event boundary *is* wired: `game_screen.gd` goes
  through `ChessCoreBridge` for legal moves, `submit_move`, and FEN. It has never
  run to completion on a device that can load the core, so treat it as written but
  unproven.
- **The clock is fabricated.** `_white_seconds := 600` in `game_screen.gd`, and
  `game_screen.tscn` hard-codes `"MORGAN  09:58"` and `"10:00  YOU"`. A `Timer`
  ticks it down. `application_core.md` puts clocks **out of v1** and says the host
  would be the timekeeper. Nobody is timekeeping; the display implies someone is.
  Either delete it or label it in the scene as out-of-scope furniture. Leaving it
  looking real is the worst of the three.

### Staged plan

`board_build_order.md` is the current plan and says where each stage stands.

- **Stage 1, board shell — not started.** Squares are still built in `_ready()` rather
  than authored. Attempted once and reverted; read the original first this time.
- **Stage 2, world — done.**
- **Stage 3, pieces — done, differently than planned.** See §3.
- **Stage 7, contract — written, never verified.** The bridge is wired and typed; it has
  not completed a round-trip on any device. This is the gap §7 is about.

### What to do next, in order

1. **Look at the board.** Open the project on a desktop, where the core can load. 61 UI
   checks have never executed and the round-trip has never run. Expect real findings;
   they are information, not regression.
2. **Watch the first CI run.** It builds the core and runs those 61 checks on a stock
   Linux runner, where `dlopen` works. The workflow has never executed either, so treat
   a syntax or action-tag failure as a workflow bug rather than a project one.
3. **Stop the bridge forging the opponent.** `bridge.rs` holds committed seeds and
   `game_screen.gd` calls `start()` on every game screen. Mark it spike-only at the call
   site at minimum. See §3.
4. **Then the boundary:** move number from the signed log rather than a client counter;
   decide the fabricated clock's fate; stop parsing the core's FEN in GDScript.

---

## 3. Flags on the current implementation

These are live concerns, not closed questions. Each has a reason attached.

### Piece identity was duplicated in GDScript — now resolved

**Was:** `ChessPieceView.piece_type` was `@export_enum("pawn", "rook", "knight", …)`,
a second list of piece types beside `chess_core`'s. This section used to end with
"Decision needed, not necessarily a blocker."

**Now:** `piece_type` is a plain `String` that arrives over the bridge, and
`ChessPieceView` also carries `square` as data. `board_build_order.md` argued for
exactly this under the heading *"No piece enum in GDScript"*, and the decision was
made rather than deferred.

The editor dropdown is gone. That was the correct trade: a dropdown implies this
project is the authority on which pieces exist, and it is not.

`FEN_PIECE_TYPES` in `game_screen.gd` is still a mapping in GDScript — see the
flags below.

### The theme lost 268 lines and gained 229

Landed in the same commit as the assets, which is the part to be suspicious of. Nothing
was found broken, but a diff that size arriving unannounced is exactly where a variation
gets dropped. **Worth a read before trusting it is complete.**

### `PIECE_SCALE := 16.0` is a magic number

It is applied uniformly to all six pieces, which is right *only because* the set is
consistent. A different set needs per-piece factors. Not a bug — a thing to know before
adding a model.

### Warnings-as-errors was a dead key for its whole life

**Corrected 2026-10-07.** The section this replaces said the setting was "set but
unverified", and suggested confirming it in the editor. It was not unverified. It
**did not exist.**

`debug/gdscript/warnings/treat_warnings_as_errors` was removed from Godot in
upstream PR #73032 (2023) and replaced by per-warning enum levels (`0` Ignore /
`1` Warn / `2` Error) from PR #59943. Dumping every registered project setting from
the 4.7.2 binary on this machine returns `debug/shader_language/warnings/treat_warnings_as_errors`
and no GDScript counterpart.

An unknown key still reads back as whatever string is in the file, which is exactly
why the engine "reported it as true" and why a deliberately unused local compiled
clean. The setting could never have worked, so no amount of confirming in the editor
would have found it.

The replacement does work, and was verified both ways: at level `2` Godot prints
`SCRIPT ERROR: ... (Warning treated as error.)` **and exits 1**; at level `1` it
prints nothing and exits 0. `project.godot` now sets 38 keys to `2`, the parse gate
runs per file, and `tools/check_warning_drift.py` fails on a key the project has
neither set nor recorded in `tools/warning_baseline.txt` — which is the check that
catches a dead key now.

**The lesson, and it belongs next to the ones above:** a setting that reports a
value is not a setting that is read. I read the resolved value back for theme items
and declared victory; I did not do it for a project setting. See
`docs/standards/quality-gates.md` and `docs/audits/foundation_audit.md`.

### Squares are still built in code

`board_view.gd` constructs 64 squares, the overlay roots and the coordinate labels in
`_ready()`. Nothing is visible in the editor. This is item 2 of `foundation_tightening.md`
applied to 3D, and it is not done.

### The frame is still built in code too

Deliberate. `_build_frame()` makes four raised rails around a plinth, and the generator
that was replacing it emitted a slab — same name, different silhouette. It moves when it
moves as rails.

### The bridge forges the opponent, and nothing at the call site says so

`rust/src/bridge.rs` holds `LOCAL_SEED = [1u8; 32]` and `SPIKE_PEER_SEED = [2u8; 32]`
as committed constants. `start()` creates both keys, admits the second, signs genesis
with it, co-signs entries, and marks both sides ready — one process playing both sides
with full authority over both.

The Rust doc comment is honest that this is a Phase 5 spike shortcut. **The GDScript
side is not.** `game_screen.gd` calls `_bridge.start()` on every game screen, so every
local game runs against a forged opponent holding a signing key derived from `[2u8; 32]`,
and nothing in `godot/` marks it temporary.

Defensible as a spike. Not defensible as the shipped bridge, and it is the single
worst thing left in the repository. Mark it spike-only at the call site today, and
replace it with the transport path before anyone builds a feature on local play.

### The core's FEN is still parsed in GDScript

`game_screen.gd` has `FEN_PIECE_TYPES` and `_build_position_from_fen()`, which walks the
placement field and calls `_add_piece`. That is a second reader of the position, in the
client, beside `chess_core`.

Rendering from an arriving FEN is legitimate — the arch doc says Godot renders the
board. The concern is that this is *parsing*, in GDScript, and that the same file also
holds `FEN_PIECE_TYPES` as a piece table. Under the escalating warning gate these are
now typed and checked, which is an improvement and not the same thing as being one
source of truth.

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
- **`rust/target/` cannot be used here.** Shared storage is mounted `noexec`, so an
  in-tree cargo build fails with `Permission denied (os error 13)` trying to run a build
  script. Use `CARGO_TARGET_DIR=/tmp/...`. The documented `cargo test` never worked on the
  machine that wrote it.

### This device cannot load the Rust core at all

**This is the single most useful thing to know before touching the bridge, and it is not
a project defect.**

Termux's `godot-headless` is a wrapper. It runs the Linux glibc Godot binary through
Termux's glibc sysroot:

```sh
exec "$L/lib/ld-linux-aarch64.so.1" --library-path "$L/lib" \
  /data/data/com.termux/files/usr/share/godot/Godot_v4.7.2-stable_linux.arm64 "$@"
```

That sysroot ships **`libdl.so.2` and no `libdl.so`**. `dlopen` needs the unversioned
name, so every GDExtension `.so` fails with `libdl.so: cannot open shared object file`.
Adding a `libdl.so` symlink to the library path instead makes the loader resolve `libc.so`
— a linker script, not an ELF — and fail with `invalid ELF header`. Both verified with a
minimal probe project.

So on this device: `ClassDB.class_exists("ChessRelayBridge")` is always false, the game
screen renders no pieces, and every bridge-dependent check fails. **That is the 61 checks
that do not run.**

`bridge_spike_test.gd` prints which of three causes it is — extension missing, library not
built, host cannot `dlopen` — and **fails in all of them**. That is deliberate. The suite
exists because a missing core was once reported as a pass, and swapping "always green" for
"always red for an environment reason" would trade one lie for another.

**Verify the bridge on a desktop or in CI.** CI runs on a stock Linux x86_64 runner, where
`dlopen` works, and builds the core before running the suites.

### `.godot/extension_list.cfg` is gitignored and required

It is the file that tells Godot which `.gdextension` files exist. `.godot/` is gitignored,
so on a fresh clone it does not exist, Godot never considers `chess_relay.gdextension`,
and the class never registers — which looks exactly like a missing `linux.arm64` library
entry. Both were true here at once, and chasing them in the wrong order costs an afternoon.

CI writes it explicitly. Locally:

```sh
mkdir -p godot/.godot
echo "res://chess_relay.gdextension" > godot/.godot/extension_list.cfg
```

### Running things

```sh
bash godot/tests/run_all_checks.sh         # every gate, non-zero on failure
python3 godot/tools/build_class_cache.py  # after adding a class_name
```

`tools/runall.sh` from the earlier prototype is **gone** — the temp directory was
wiped mid-session and it was never tracked. `run_ui_checks.sh` replaced it, and
`run_all_checks.sh` replaced that.

**`run_all_checks.sh` is the only supported way to run the Godot gates.** It does
three things: parses every `.gd` individually with the project's warnings-as-errors,
runs the warning-key drift check, and runs every `*_test.gd` with stderr treated as
a failure. It replaced `run_ui_checks.sh`, which ran one suite and could report
success while half of it had never executed — see
`docs/audits/foundation_audit.md` finding 1.

Two things it needs that are not obvious:

- **The Rust core library must be built and copied to `godot/bin/`.** Without it,
  `chess_relay.gdextension` registers nothing, the board renders no pieces, and
  every bridge-dependent check fails. The runner says which of the three causes it
  is. On this device it is *always* the third one: Termux's glibc sysroot has
  `libdl.so.2` but no `libdl.so`, so the Linux Godot binary run through the
  `godot-headless` wrapper cannot `dlopen` any extension. Verify that gate on a
  desktop or in CI.
- **`.godot/extension_list.cfg` must list the extension.** It is git-ignored with
  the rest of `.godot/`, and without it Godot never considers the
  `.gdextension` file at all — which looks exactly like a missing library entry.

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

### Then, on 2026-10-07, a fifth occurrence

Six thousand lines across the Rust core, the Godot client and every gate were fixed
against `docs/standards/quality-gates.md`. The rules governing that work were not new —
they are §1, "a number is not a judgement" and "a green suite proves only what it
asserts", both written down after being ignored.

**What went wrong was not the code. It was that each phase was marked done from a green
run, and the green runs were not evidence.** Three commits in a row described the Godot
client running on real core state; the core had never loaded on that machine. See §7.

A fourth law, written 2026-10-07, and it belongs with the others:

> **Mark a phase done only with the gate that proves it, run and green.**
> Not with the intent to run it. Not with the suite that exists to run it.
> The gate, run.

Its practical form: **if you cannot make a gate go red on purpose, you do not yet know
what it is checking.**

---

## 6. If you have to learn one thing

Look at what is on screen before believing any document, including this one.

The empty board is the clearest case: every check passed, the commit message was
confident, and there was nothing on the board. **Measure, then look, then believe.**

---

## 7. The fifth time, and what it cost

The fifth occurrence of "a green suite proves only what it asserts" is worth its own
section, because it is the one that disabled the safeguard.

Measured 2026-10-07: `ui_smoke_test.gd` declared 146 checks, **78 executed**, and the run
printed `UI smoke checks passed` and exited 0. A `SCRIPT ERROR: Node not found` killed
`_check_game_screen` partway; GDScript errors do not propagate, so the function simply
stopped and the suite carried on. Commits `25154f3` and `3e55fa2` both added checks
*inside* the dead region and described them as verified.

And the Rust core had never loaded on the machine that ran those tests, so every
bridge-dependent check was skipped too. `bridge_spike_test.gd` — which asserts the class
exists and exits 1 when it does not — existed the whole time and was not wired into
anything.

Full accounting in [`docs/audits/foundation_audit.md`](../../docs/audits/foundation_audit.md).
The rules are in [`docs/standards/quality-gates.md`](../../docs/standards/quality-gates.md).

### What replaced it

- Per-phase `_phase_done()` sentinels. A crash one line above cannot skip the sentinel,
  because the sentinel is what the caller checks after the `await`.
- A declared-versus-executed count, with the declared number derived from `_check(` call
  sites rather than hand-maintained.
- stderr gating: any `SCRIPT ERROR` fails regardless of exit code.
- `check_warning_drift.py`, which catches a project setting Godot does not register —
  the check that would have caught `treat_warnings_as_errors` being dead from the start.

### The law, restated

**Every gate was proved red on purpose before it was trusted.** Ten deliberate
injections, all caught; the table is in `quality-gates.md` §4.

A gate nobody has seen fail is a gate nobody can trust. That is the sentence to carry
to the next session, and it applies to the CI workflow too, which has not run yet.

### Read the resolved value back — including for project settings

Already in §1 as a law about theme items, and it was already violated. I read
`ProjectSettings` back, saw `treat_warnings_as_errors` report `true`, and believed it.
The key had been removed from Godot in 2023. **A setting that reports a value is not a
setting that is read.**

The same failure took an afternoon to misdiagnose: the core would not load, and the
reason turned out to be two separate things at once — a genuinely missing
`linux.arm64` entry (my fault, fixed) *and* an environment that cannot `dlopen` at all
(not my fault). Fixing the real one did not fix the symptom. **Separate what you broke
from what was already broken, before you start fixing.**