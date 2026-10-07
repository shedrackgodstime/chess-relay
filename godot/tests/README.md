# UI checks

Run every Godot gate from the repository root:

```sh
bash godot/tests/run_all_checks.sh
```

Three gates, cheapest first:

1. **parse** — every first-party `.gd` is parsed individually with the
   project's warning keys escalated to errors (`godot/project.godot`,
   `[debug]`). Per file, so a failure names a file rather than "the project".
2. **drift** — `tools/check_warning_drift.py` fails if Godot registers a
   warning key this project has neither set nor recorded in
   `tools/warning_baseline.txt`, or if `project.godot` sets a key Godot does
   not register.
3. **suites** — every `*_test.gd` in this directory, each on its own, with any
   `SCRIPT ERROR` or `Parse Error` on stderr treated as a failure regardless of
   exit code.

## What the suites cover

- **`ui_smoke_test.gd`** — screens load and navigate; reusable components behave
  as configured; setup, invite, and discovery interactions update their states;
  modal actions exist; responsive breakpoints choose the expected columns;
  theme focus and badge styles resolve; the board renders squares, highlights,
  legal-move markers, coordinate labels and piece meshes; camera input routing
  and touch gestures; the clock strip and its states.
- **`bridge_spike_test.gd`** — the Rust core is loaded and answering: session
  start, legal-move queries, `submit_move`, FEN after a move, turn tracking, and
  refusal of illegal moves.

Chess legality, move generation, and the move log are tested in Rust, in
`rust/tests/`. This directory does not re-test them, apart from the round-trip
through the bridge above.

## Why the harness looks the way it does

A GDScript runtime error does not propagate. It prints, the function stops, and
an `await` on a coroutine that died resumes the caller as if it returned
normally. Verified against 4.7.2.

That is why this suite used to report success while 78 of its 146 checks had
never run: a phase crashed partway and the run carried on. Three defences, all
of which have been proved red on purpose:

- **Per-phase sentinels.** Each phase calls `_phase_done()` as its last
  statement; `_phase_run` then asserts it was reached.
- **Declared versus executed counts.** `run_all_checks.sh` counts `_check(` call
  sites and passes the total in as `--expected-checks`. The suite compares that
  against what it counted. Adding a check updates the expectation automatically;
  skipping one is a loud failure.
- **stderr gating.** A suite that exits 0 while printing `SCRIPT ERROR` still
  fails the run.

## Running one suite by hand

```sh
godot --headless --path godot --script res://tests/ui_smoke_test.gd
```

The `--expected-checks` count check is a no-op in that form (it defaults to 0),
so use the runner for the real gate.

## A note on the bridge suites

`bridge_spike_test.gd` fails when the Rust core is not loaded. On a host that
cannot load a GDExtension library at all — including an Android device running
the Termux glibc sysroot, which has `libdl.so.2` but no `libdl.so` — it prints
which of the three causes it was and still fails. That is deliberate: the suite
exists because a missing core was once reported as a pass, and swapping "always
green" for "always red for an environment reason" would trade one lie for
another. CI on a stock Linux runner is the authority for this gate.
