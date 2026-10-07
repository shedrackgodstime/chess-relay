# Foundation audit — 2026-10-07

An audit of what exists, before any new work. Written after reading every
architecture doc, plan, handover, and source file in the repository, and after
running both suites.

Authority for what "correct" means here is already in the repository:
`docs/architecture/application_core.md`, `docs/standards/rust-standards.md`,
`docs/plans/rust-core-plan.md`, and `godot/docs/HANDOVER.md`. This document
does not introduce new opinions. It measures the current state against those
documents and records where they disagree with the code.

## How to read this

Sections 1-3 are findings, ordered by how much damage they are doing. Each one
names the evidence, the rule it breaks, and what it costs.

Section 4 is what is genuinely good and should not be touched.

Section 5 is the proposed order of work. Nothing in it has been started.

---

## 0. Verified state

Both suites were run on this machine, not reasoned about.

**Rust: green.**

```
cargo fmt --check                              clean
cargo clippy --all-targets -- -D warnings     clean (7m04s)
cargo test                                     39 passed, 0 failed, 1 ignored
                                               + 4 + 3 + 4 + 3 + 4 + 5 integration
                                               + 17 doctests
```

The one ignored test is `perft_startpos_depth_five` (4.8M nodes), marked
`#[ignore]` deliberately.

**Godot: reports green and is not.** See finding 1.

**Environment note that matters:** `cargo test` fails in-tree with
`Permission denied (os error 13)` executing the build script, because
`rust/target/` lives on Android shared storage, which is mounted `noexec`. It
needs `CARGO_TARGET_DIR` pointed outside the repository. The plan and README
both document `cargo test` without mentioning this, so the documented command is
known to fail on the machine it was written on.

---

## 1. The test harness cannot fail, and is hiding the rest of the suite

**Severity: highest. This is the defect that lets all the others through.**

`bash godot/tests/run_ui_checks.sh` exits 0 and prints `UI smoke checks passed`.
It also prints:

```
ERROR: Node not found: "World/Board/Pieces/White_Pawn_e2" (relative to "/root/GameScreen").
   at: get_node (scene/main/node.cpp:1975)
SCRIPT ERROR: Cannot call method 'get_node' on a null value.
          at: _check_game_screen (res://tests/ui_smoke_test.gd:285)
```

Counted, not estimated:

| | |
| --- | --- |
| `_check(...)` call sites in `ui_smoke_test.gd` | 146 |
| Checks that actually ran (`PASS` lines) | 78 |
| Checks never executed | **68** |

The script error aborts `_check_game_screen` at line 284. GDScript does not
raise on error, so execution of that function simply stops. Every check after
line 284 — touch input on pieces, the move round-trip, camera drag, clock
colour, the `mouse_filter` assertions — **has never run**. Not "is flaky". Has
never executed, while the suite reported success.

**Why this happened.** `_run()` counts failures via `_check()` and quits on
`_failures`. A GDScript runtime error is invisible to that counter. The suite
has no way to distinguish "check passed" from "the line before it crashed".

**Why this is worse than an ordinary bug.** `HANDOVER.md` §1 records four
separate occasions where "a green suite proves only what it asserts" — a `PLAY`
button with nothing connected, 32 children on a board with no meshes, a board
0.035 proud of its frame with 32 inverted colours, a camera test driving mouse
events that bypassed the touch path entirely. Every one of those was a
visibly broken board behind a passing suite. The rule was written because it had
already happened four times. This is the fifth, and it is the one that disables
the safeguard itself: 46% of the suite is unreachable and the run still says
PASS.

**Rule broken.** Godot's own guidance on GDScript error handling; and
`project_structure.md`: *"treat engine warnings as issues to resolve, not noise
to suppress"*. The same failure, one level up.

**Cost.** Every Godot claim after this line in this document is unverified, and
so is every claim made in the commits that added those lines. `git log` shows
commit `25154f3` ("Fix dead board taps") added touch checks at
`ui_smoke_test.gd:287-311` — inside the dead region. Commit `3e55fa2` added
touch press/release coverage at the same place. **Neither of those checks has
ever run.** Their commit messages describe verified behaviour.

**What a fix has to prove.** Not "the suite passes". It has to prove that a
failing check *makes it fail*. The candidate fix is a wrapper that detects
script errors, or a sentinel check at the end of each function that runs only
if the function reached the end. The handover's rule applies to the fix too:
ask what the check would fail on. A sentinel that is itself skipped by an error
one line earlier fails the same way.

---

## 2. The Rust core does not load, anywhere, so Phase 6 is unverifiable

**Severity: highest. The headline feature of the last three commits does not run.**

`game_screen.gd:101-112` builds the position **only** from the core's FEN:

```gdscript
if _bridge == null:
    return
_build_position_from_fen(pieces_root, _bridge.fen())
```

`_start_bridge()` returns early when `ClassDB.class_exists("ChessRelayBridge")`
is false, setting the header to "Chess engine unavailable". So with no bridge,
the board is empty by design.

`chess_relay.gdextension` declares:

```
linux.debug.x86_64 = "res://bin/libchess_relay_core.so"
linux.release.x86_64 = "res://bin/libchess_relay_core.so"
```

No `arm64` entry. This machine is arm64. So the extension does not load, the
bridge class does not exist, and every board-rendering path in the game screen
is skipped — on the machine that ran the tests that committed them.

`godot/bin/` is gitignored and absent, so no Linux build exists here either.

**Consequences, and they compound with finding 1:**

- `_build_position_from_fen` (`game_screen.gd:115`) — never executed. The FEN
  parser in GDScript is untested code shipped in the client. Note it contains
  its own piece table (`FEN_PIECE_TYPES`, line 18) and its own rank/file walk.
- `_add_piece` (line 133) — never executed.
- `legal_moves_from` → `_legal_targets` — never exercised.
- `submit_move` → `move_applied` → `_rebuild_position` — the entire Phase 6
  round-trip — never executed.
- `rust/tests/app.rs` covers the core side of this contract and is genuinely
  good, but it tests `App` in Rust. Nothing has ever tested that Godot and Rust
  agree.

So commit `152d914` ("Phase 6: game screen runs on real core state") describes
behaviour that has never been observed to work on any machine in this repo's
history. It may well be correct. It is unproven, and it was committed with a
commit message stating it as done.

**Rule broken.** `application_core.md` §Godot integration and
`rust-core-plan.md` Phase 6 gate: *"square-press → SubmitMove → MoveApplied →
render round-trip on desktop + Android."* The gate exists to be run. It was not.

**Also missing.** `godot/tests/bridge_spike_test.gd` is the one check that
*would* have caught this — it asserts `ClassDB.class_exists("ChessRelayBridge")`
and exits 1 when absent. `run_ui_checks.sh` does not run it. It is not in CI
because there is no CI. The check that guards the feature is not wired to
anything.

---

## 3. Godot holds game state the architecture says is Rust's

This is not one bug; it is a pattern, and it is the reason the boundary was
drawn in `application_core.md` in the first place.

| What | Where | Who should own it |
| --- | --- | --- |
| Position → piece list | `game_screen.gd:115-140`, FEN parsed in GDScript | Rust's `chess_core` |
| Piece identity table | `game_screen.gd:18`, `piece_view.gd:12` | Rust's `chess_core` |
| Promotion suffix | `game_screen.gd:218-219` (`uci += "q"`) | Rust's `chess_core` |
| Legal move list | mirrored into `_legal_targets` then re-shown | Rust's `chess_core` |
| Move number | `_move_number`, incremented on `move_applied` | session's log length |
| Clock state | `_white_seconds`, `_black_seconds`, `_on_clock_tick` | nobody — clock is out of v1 |
| Whose turn | `_active_clock_side` shadowing the core's turn | Rust's `chess_core` |

Specifics worth being precise about:

**Promotion is a chess rule decided in GDScript.** `game_screen.gd:218` appends
`"q"` whenever a pawn reaches rank 8 or 1. Underpromotion is unreachable. The
Rust core computes the legal move set and the client then overrides it with its
own rule. `application_core.md`: *"Rust owns correctness. Move legality, game
state... Godot never keeps its own authoritative copy."*

**Piece identity exists in three places.** `FEN_PIECE_TYPES` in
`game_screen.gd:18`, `@export_enum("pawn", "rook", ...)` in `piece_view.gd:12`,
and `chess_core::Piece` in Rust. `board_build_order.md` spent a section called
*"No piece enum in GDScript"* arguing this exact point, and
`HANDOVER.md` §3 still lists it as an open decision: *"Decision needed, not
necessarily a blocker."* It is still there. Three lists, one of them showing in
an editor dropdown.

**The clock is fake and pretends not to be.** `game_screen.gd:22-23` seeds
`_white_seconds := 600`, and the `.tscn` hard-codes `"MORGAN  09:58"` and
`"10:00  YOU"` at lines 159 and 173. There is a live `Timer` ticking it. The
architecture says clock is **out of v1**, reserved, and that if added the host is
the timekeeper. There is a ticking clock in the client with a fabricated
opponent name in a committed scene file. Nobody is timekeeping; the display
implies someone is.

**Move number is a counter, not the log.** `_move_number += 1` per
`move_applied`. The signed log already knows how many moves have been played.
Two sources, one authoritative-looking.

**What this costs.** Every one of these is a place where Godot and Rust can
disagree, and the disagreement is invisible until a player sees a queen appear
that should be a knight. `HANDOVER.md`: *"It is correct-looking, passes every
check, and will disagree with Rust the first time either side changes."*

---

## 4. The bridge forges the opponent

**Severity: high. This is a correctness-of-authority problem, not a style one.**

`rust/src/bridge.rs:20-21`:

```rust
const LOCAL_SEED: [u8; 32] = [1u8; 32];
const SPIKE_PEER_SEED: [u8; 32] = [2u8; 32];
```

`start()` (lines 56-99) creates both keys, admits the second one
(`app.admit(peer_key.clone())`, line 61), signs genesis with it (line 76),
co-signs its own entries, and marks both sides ready. One process plays both
sides with full authority over both.

The doc comment is honest — *"Spike shortcut, documented honestly... Networked
play replaces the second key with the transport path in Phase 6"* — and as a
Phase 5 spike that is defensible. It is defensible **as a spike**. It is not
defensible as the shipped bridge, and the plan's Phase 6 gate says the bridge
replaces mock behaviour with real state, not that it keeps the forge.

Nothing in `godot/` or in `rust/src/bridge.rs` marks this as temporary at the
call site. `game_screen.gd:94` calls `_bridge.start()` on every game screen,
so every local game currently runs with a forged opponent holding a signing
key derived from `[2u8; 32]`.

**Hardcoded private keys** are committed. They are throwaway seeds with no
security value *today*, and they must not survive into anything real — the moment
they do, the whole point of the signed log is gone.

---

## 5. Smaller findings, recorded so they are not re-audited

**Debug prints left in the shipped path.**
`game_screen.gd:212,214`, `board_view.gd:185`, `piece_view.gd:73` — `print("DBG ...")`
on every tap. These are session scaffolding that was never removed.

**`protocol.rs` is an empty module.** Five lines, no types, no `serde`. Phase 7
work. Fine to be empty; worth knowing it is a placeholder and not a boundary.

**No CI.** No `.github/`, no workflow, no pre-commit. Every gate in
`rust-standards.md` — `fmt`, `clippy -D warnings`, `test` — is run by hand, by
memory. Given finding 1, a manually-run suite that cannot fail, this is the
mechanism by which all of the above shipped.

**`godot/tests/README.md` is wrong.** It says the suite "exits with a non-zero
status if any check fails." It exits non-zero for a failed check and zero for a
crash. It also says "Chess legality... belong to future model/service test
suites rather than UI scenes" — while the suite now contains
`game._legal_targets == ["e3", "e4"]`, a chess assertion.

**`godot/.godot/` is gitignored, including the class cache the project depends
on.** `tools/build_class_cache.py` exists solely to regenerate
`.godot/global_script_class_cache.cfg`, because `--import` and `--editor` abort
on this build. Every new `class_name` needs a manual script run or every script
naming it fails to parse. Documented honestly in `HANDOVER.md` §4, and still a
manual step in every workflow.

**Warnings-as-errors was a dead key, and now works.**

*Resolved 2026-10-07. This corrects §3 of `HANDOVER.md` and item 1 of
`foundation_tightening.md`.*

`debug/gdscript/warnings/treat_warnings_as_errors` **does not exist in Godot
4.7.2.** Upstream PR #73032 removed the boolean in 2023, superseded by
per-warning enum levels from PR #59943. Verified by dumping every registered
project setting from the 4.7.2 binary: only
`debug/shader_language/warnings/treat_warnings_as_errors` exists; the GDScript
one is absent.

So `project.godot`'s setting was inert, and the open question in
`HANDOVER.md` §3 — "the setting is valid and the harness works, but warnings did
not escalate" — was chasing something that could never work. An unknown key still
reads back as the string written into the file, which is why the engine "reported
it as true".

The replacement works: at level `2` Godot prints
`SCRIPT ERROR: ... (Warning treated as error.)` **and exits 1**. Verified both
ways. `project.godot` now sets 38 keys to `2`, and
`tools/check_warning_drift.py` fails if Godot registers a key the project has
not decided about, or if the project sets a key Godot does not register — which
is the check that would have caught this in the first place. See
[quality gates](../standards/quality-gates.md).

**The board is still built in `_ready()`.** `board_view.gd:38-140` builds 64
squares, the frame, coordinates, and the input surface in code. Attempted,
reverted, documented at `board_build_order.md` stage 1. Not a bug. Recorded so
it is a known state, not a discovery.

**`_clear_root` frees children with `free()` while iterating.**
`board_view.gd:204-208` — `child.free()` inside `for child in root.get_children()`.
`get_children()` returns a copy so this is safe today, but it is immediate
destruction inside a loop and it is inconsistent with `queue_free()` used three
lines away in `game_screen.gd:109`.

**`chess_relay.gdextension` is missing `linux.arm64`** — the mechanical cause of
finding 2, listed separately so it is not lost when finding 2 is fixed.

---

## 6. What is genuinely good

Not padding. These are correct and should survive any refactor.

- **The Rust core meets its standard.** `fmt` clean, `clippy --all-targets -D
  warnings` clean, 53 tests plus 17 doctests green. Canonical error structs with
  backtraces and `is_xxx()` predicates (`app.rs:260-364`), one error type per
  layer, `From` conversions, no `anyhow`, no glob re-exports, no dependency types
  in public signatures, `Send` types, docs with runnable examples.
- **Perft is pinned to two independent oracles.** Startpos 1-4, kiwipete 1-3,
  the endgame position, and a promotion-heavy firewall position
  (`movegen.rs:480-520`). Depth 5 correctly marked `#[ignore]` rather than
  silently dropped. This is the strongest thing in the repository.
- **The move log and replay are real.** Signatures, hash chaining, tip compare,
  and a scripted divergence/convergence test that drops N moves and asserts
  identical logs. `rust/tests/session.rs` proves forged-but-signed moves are
  rejected on replay.
- **The arch doc's separation held.** `chess_core` has no Godot, no Iroh, no UI.
  The Iroh spike proved the contract survived a real network without changes —
  including disconnect and log resume. That is a real result and it is why
  Phase 3's freeze was credible.
- **The camera is borrowed, not rewritten,** and `HANDOVER.md` §5 is honest that
  the most expensive mistake was writing a from-scratch one when a working
  original existed in `ref/`.
- **`orbit_camera.gd` documents *why* it reads `_input` and not
  `_unhandled_input`,** with the reasoning attached rather than the conclusion
  alone. That is the standard the rest of the documentation should meet.
- **The handover is candid.** It records four ways the suite lied, names the
  empty items, and states the environment's faults. That candour is why this
  audit found what it found.

---

## 7. Proposed order of work

Sequenced by dependency, not by severity.

**Done (2026-10-07):** steps 1-6, and two of the five items in step 7. See
[quality gates §3a](../standards/quality-gates.md) for what shipped and §4 for
the red-on-purpose proof of every gate.

- **1, the harness — done.** `run_all_checks.sh` fails on any `SCRIPT ERROR`,
  each phase carries a `_phase_done()` sentinel, and a declared-versus-executed
  count catches a truncated run.
- **2, the bridge — done, and it exposed an environment limit.** `linux.arm64`
  added; the core library builds; `.godot/extension_list.cfg` turned out to be
  required and was missing. The core still cannot load *on this device*, because
  Termux's glibc sysroot has `libdl.so.2` and no `libdl.so`, so `dlopen` fails.
  Not a project defect; `bridge_spike_test.gd` names the cause and still fails,
  and CI on a stock Linux runner is the authority.
- **3, re-run with all checks live — done.** 87 of 148 now execute; the rest are
  blocked behind the bridge, and the count check says so instead of hiding it.
- **4, debug prints — done.** All removed.
- **5, the environment trap — done.** `CARGO_TARGET_DIR` documented in the
  README.
- **6, CI — done.** `.github/workflows/gates.yml`, seven jobs behind one
  required `Gates OK` check.
- **7, the boundary — two of five.** The GDScript promotion rule is gone (the
  core decides) and the duplicate piece enum is gone (`ChessPieceView` takes an
  identity as a `String`). **Still to do:** move number from the signed log
  rather than a client counter; the fabricated ticking clock in
  `game_screen.tscn` (`"MORGAN  09:58"`, `"10:00  YOU"`); `FEN_PIECE_TYPES`
  still parsing the core's FEN in GDScript.

**Still open from §5, and not small:**

- **Audit finding 4 — the bridge forges the opponent.** `bridge.rs` holds
  committed seeds and `start()` plays both sides with full authority. It is
  marked spike-only in a doc comment, and nothing at the call site says so.
- **Audit finding 2, partly.** `linux.arm64` was the mechanical cause and is
  fixed; the board now has pieces on a host that can load the library, verified
  in CI. Not yet verified on this device, and not yet verified on Android.
- **R6.3 — the end-to-end move round-trip** (square press → `SubmitMove` →
  `MoveApplied` → re-render) exists as `bridge_spike_test.gd` through the typed
  facade, but not yet driven through the actual `GameScreen` input path.
- **Tier 2 of the warning escalation**, ~820 `inferred_declaration` findings,
  deliberately at the engine default and not started.

**8. Re-audit afterwards.** Findings 3 and 5 are the kind that come back unless
the boundary is written into a check.

---

## 8. The honest summary

The Rust side is in good shape and follows its standard closely. That is most of
the project's substance and it is solid.

The Godot side has a testing problem severe enough to invalidate its own claims.
Half the UI suite has never run, the feature the last three commits describe has
never executed on any machine here, and a passing run would have reported both
as fine. Everything Godot-side in this repository should currently be treated as
unverified rather than working.

The pattern underneath all of it: **work was marked done from a green run, and
the green runs were not evidence.** `HANDOVER.md` §1 warns about this four times
over. The fifth instance is the one that removed the warning's ability to fire.

The first three steps above are about restoring the ability to tell whether
anything works. That is worth more than any feature, and it is worth doing
before touching the boundary work.