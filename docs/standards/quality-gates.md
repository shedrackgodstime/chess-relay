# Quality gates — what we enforce, and why

Binding rules for this repository, and the reasoning behind each. Written
2026-10-07 from internet research, then **verified against Godot 4.7.2 and the
project's own source on this machine**. Every number below was measured, not
assumed.

Read with:
- [`foundation_audit.md`](foundation_audit.md) — what is currently wrong.
- [`../standards/rust-standards.md`](../standards/rust-standards.md) — the Rust
  standard, still authoritative.
- [`godot/docs/HANDOVER.md`](../../godot/docs/HANDOVER.md) §1 — the laws, and why
  they exist.

The governing rule, from the handover: **a green run proves only what it
asserts.** Every gate here has to be one that can actually go red.

---

## 0. Two things the internet research changed our minds about

### `treat_warnings_as_errors` no longer exists

`godot/project.godot` has carried this line since `foundation_tightening.md`
item 1, and `HANDOVER.md` §3 has carried an open question about it:

```
gdscript/warnings/treat_warnings_as_errors=true
```

**That setting was removed from Godot.** Upstream PR #73032 ("GDScript: Remove
`treat_warnings_as_errors` project setting", merged 2023-02) deleted the
`GLOBAL_DEF` and changed the parser check from
`warn_level == ERROR || GLOBAL_GET("treat_warnings_as_errors")` to
`warn_level == ERROR` only. It was superseded by per-warning enum levels
(`0` Ignore / `1` Warn / `2` Error) from PR #59943. See also godot-proposals
#12922, which asks for it back and is currently declined on the grounds that
individual levels make it unnecessary.

**Verified on this machine.** Querying every registered project setting on the
4.7.2 binary:

```
SETTINGS-KEY: debug/shader_language/warnings/treat_warnings_as_errors   <- shaders only
debug/gdscript/warnings/treat_warnings_as_errors                        <- DOES NOT EXIST
debug/gdscript/warnings/enable                                          = true
per-warning settings under debug/gdscript/warnings/                     = 52
```

So our setting has been **inert**. `HANDOVER.md` §3's "warnings-as-errors is
set but unverified" was chasing a ghost: it could not work, because the key is
not read. The engine "reports it as true" because an unknown key still reads
back as the string that was written into the file.

### The replacement actually works, and it is loud

Godot emits parse **warnings** to stdout only when they are escalated to `2`.
At level `1` they are invisible headless. Verified both ways on a file with one
unused local:

| Setting | Headless output | Exit code |
| --- | --- | --- |
| `unused_variable=1` (default) | *(nothing)* | 0 |
| `unused_variable=2` | `SCRIPT ERROR: Parse Error: ... (Warning treated as error.)` | **1** |

Two properties we need, and this is the second reason to prefer it over the old
boolean:

1. It is a real error, so it produces a real non-zero exit code. No grepping.
2. Per-key levels mean we can be strict where strictness is free and honest
   about the keys that are noise.

**This closes the open item** in `foundation_tightening.md` §1 and
`HANDOVER.md` §3. The convention can now be a property of the project.

---

## 1. The measurement: 1383 findings

Escalated 49 warning keys to level `2` and ran
`--check-only --script` over every one of the 22 first-party `.gd` files.

**Total: 1383 findings across 22 of 22 files.** Every file is affected.

By category:

| Count | Warning | What it is |
| --- | --- | --- |
| 593 | `inferred_declaration` | `var x := f()` infers rather than declares |
| 222 | `return_value_discarded` | a call whose result is dropped |
| 129 | `unsafe_property_access` | property not on the static type |
| 121 | constants lack explicit type | same as above, for consts |
| 77 | `unsafe_method_access` | method not on the static type |
| 71 | `unsafe_call_argument` | `Variant` passed where a subtype is required |
| 66 | loop vars implicitly inferred | |
| 18 | functions with no return type | |
| 15 | params implicitly inferred | |
| 12 | unused parameters | |
| 11 | unsafe casts | |
| 8 | loop vars with no type at all | |
| 8 | ctor arg subtype mismatches | |
| 7 | variables with no type at all | |
| 6 | params shadowing a base-class property | |
| 5 | redundant `await` | |
| 4 | ctor arg mismatches (multi-type) | |
| 3 | class variables never used | |
| 3 | integer division | |
| 1 | ternary branches not compatible | |

Per file (worst first): `ui_smoke_test.gd` 558, `app_root.gd` 376,
`game_screen.gd` 99, `multiplayer_hub_screen.gd` 66, `board_view.gd` 59,
`game_setup_screen.gd` 37, `orbit_camera.gd` 30, `board_mesh.gd` 24,
`piece_view.gd` 20, `bridge_spike_test.gd` 17, `bridge_spike_scene.gd` 17,
`game_header.gd` 17, `network_indicator.gd` 14, `mock_multiplayer_service.gd`
12, `square_marker.gd` 7, `choice_group.gd` 8, `invite_flow_card.gd` 5,
`participant_card.gd` 5, `player_row.gd` 4, `discovery_dialog.gd` 4,
`home_screen.gd` 2, `piece_catalog.gd` 2.

### Which of these are bugs, and which are taste

This distinction is the whole design problem, and getting it wrong in either
direction is bad: escalate noise and people learn to ignore red; leave real
bugs at `WARN` and we have a gate that lies.

**Tier 1 — real defects. Escalate to `2` now.**

| Warning | Count | Why it is a bug |
| --- | --- | --- |
| `unsafe_property_access` / `unsafe_method_access` | 206 | Accessing a member that is not on the static type. Every one is a possible `null` deref or typo. This is the class of bug that produced the harness defect. |
| `unsafe_call_argument` | 71 | Passing `Variant` where a concrete type is required. Type confusion at the boundary. |
| `unsafe_cast` | 11 | Unchecked `as` casts that can silently produce `null`. |
| `incompatible_ternary` | 1 | Branch types disagree. |
| `integer_division` | 3 | `game_screen.gd:83` does `seconds / 60` on an `int`. Works today by luck of truncation, wrong for the values a real clock needs. `app_root.gd` and `ui_smoke_test.gd` likewise. |
| `redundant_await` | 5 | `mock_multiplayer_service.gd` awaits a coroutine it does not need. Latent behaviour change if the helper is ever made `async`. |

**Tier 2 — genuinely worth enforcing, mechanical to fix.**

| Warning | Count | Why |
| --- | --- | --- |
| `untyped_declaration` / `inferred_declaration` / constants / params / loops without a type | ~820 | 59% of all findings. The project rule in `project_structure.md` already says "Use typed GDScript for new code"; this enforces it for all code. A single mechanical pass fixes the lot. |

**Tier 3 — do NOT escalate. Leave at engine default.**

| Warning | Why not |
| --- | --- |
| `return_value_discarded` (222) | **Deliberately noisy in Godot.** It fires on `connect()`, which returns an `Error` nobody checks. 222 findings, near-zero real signal. Turning it on trains people to ignore the gate. |
| `missing_await` (5) | Opposite of `redundant_await` and it double-reports the same lines. Enabling both is contradictory. |
| `unused_parameter` (12) | Mostly `_on_` callbacks whose signature is fixed by the signal. Renaming to `_x` is correct but it is noise, not safety. |
| `unsafe_*` at aggressive levels beyond those listed | The engine team itself flags these as high-false-positive; see the maintainer objections quoted in godot-proposals #12922. |

The upstream debate on "all warnings as errors" is worth reading before we
revisit: several engine maintainers argue against it precisely because a
meaningless fraction of the keys are noise. Taking the strict subset that is
actually a defect is the position they are arguing for.

---

## 2. The rules

Written to be checkable. Each names the tool, the exact command, and what makes
it fail.

### R1 — Every GDScript file parses, warnings-as-errors, headless

**Tool:** Godot itself. No third-party linter.

**Command, per file** (not the whole project at once, so a failure names a
file):

```sh
godot --headless --path godot --check-only --script res://<path>.gd
```

Exit code is 1 on a parse error or an escalated warning. We read the exit
code, not the text.

**Why per-file.** A single whole-project run tells you the project has a problem.
A per-file loop tells you `game_screen.gd:83`. We also check files no scene
references, which a project-load run would miss.

**Known trap, verified.** `--check-only` is a no-op without `--script`
(engine source audit, 2026-05-27). And `--check-only --debug` prints warnings
but drops Godot into an interactive debugger that can hang the runner forever
(godotengine/godot#117123). **So: no `--debug`.** Level `2` gives us the
warnings without the flag.

**Caveat we accept.** `--check-only` fails on scripts referencing addon
singletons (godot-proposals forum report, 4.5). We have no addons, so this does
not bite; it is recorded so it is not rediscovered as a mystery if one is added.

### R2 — No GDScript warning is left at `1` by accident

The escalation set lives in `godot/project.godot` under `[debug]`, one line per
key, committed. Anyone adding a script must live with whatever that file says.

Because a future Godot release may add keys we have not set, the CI gate also
**diffs the engine's registered warning keys against ours** and fails if any
registered key is neither explicitly set nor listed in
`godot/tools/warning_baseline.txt` with a reason. That closes the loop that
proposal #12922 identifies as the fragile part: *"this breaks easily when
changing editor version."*

### R3 — The Rust gates, unchanged and now automated

`rust-standards.md` already defines these and they pass. CI runs them:

| Gate | Command | Currently |
| --- | --- | --- |
| Format | `cargo fmt --check` | clean |
| Lint | `cargo clippy --all-targets -- -D warnings` | clean |
| Test | `cargo test --locked` | 53 + 17 doctests green |
| Docs | `RUSTDOCFLAGS="-D warnings" cargo doc --no-deps` | to be confirmed |
| Supply chain | `cargo deny check` | new; needs `deny.toml` |

`--locked` is not optional. Without it CI silently accepts a `Cargo.lock`
update, which is how a breaking dependency arrives in a "small" commit.

`RUSTDOCFLAGS="-D warnings"` is new and worth having: our standard demands every
public item is documented, and this makes a missing `# Errors` section a build
failure rather than a review comment.

### R4 — Supply chain: advisories, licences, sources, bans

**Tools:** `cargo audit` (RustSec advisories) and `cargo deny` (policy).

`deny.toml` policy, from the project's own standards:

```toml
[advisories]
vulnerability = "deny"
yanked = "deny"

[licenses]
# Our standard: "our core stays MIT/Apache-compatible". ref/shakmaty is GPL-3.0
# and must never become a dependency, so copyleft is a hard deny, not a warning.
allow = ["MIT", "Apache-2.0", "Apache-2.0 WITH LLVM-exception",
         "BSD-2-Clause", "BSD-3-Clause", "ISC", "Zlib", "0BSD"]
copyleft = "deny"
default = "deny"

[bans]
multiple-versions = "warn"   # untidy, not dangerous
wildcards = "deny"           # no "1.0"-style loose requirements

[sources]
unknown-registry = "deny"    # crates.io only
unknown-git = "deny"
allow-registry = ["https://github.com/rust-lang/crates.io-index"]
```

**Why copyleft is `deny` and not `warn`.** `rust-standards.md` §Reference
policy is explicit: shakmaty is GPL-3.0, we learn from it and never depend on
it, because depending on it would infect the crate. A CI gate that enforces
that is worth more than the sentence saying it. This is the one place where a
licence rule is a correctness rule.

`multiple-versions = "warn"` deliberately: duplicate versions cost compile
time, not safety. Failing on them produces noise.

**Advisories are non-blocking on PRs.** The advisory database changes on its own
schedule; a PR must not go red for something the contributor did not do. The
common pattern is a matrix row with `continue-on-error` on advisories and a
hard failure on bans/licenses/sources, plus a scheduled run on `main`.

### R5 — The Godot suite must fail when it should

**This is R1's sibling and the more important one.** From
`foundation_audit.md` §1: 78 of 146 checks ran, a script error killed the rest
of the function, and the run reported success.

**Rules:**

- **R5.1** Any `SCRIPT ERROR`, `Parse Error`, or `ERROR:` on stderr fails the
  run. Non-negotiable. A GDScript error is a failure, not a warning about a
  failure.
- **R5.2** Every check function ends with a sentinel that can only run if the
  function reached its end. A crash one line above it cannot skip the sentinel.
  The handover's rule applied to the fix: a sentinel that is itself skippable
  fails exactly the way the harness already fails.
- **R5.3** A declared count of checks is compared against the count that ran.
  146 declared / 78 executed is a hard failure with a loud message, not a
  shrug.
- **R5.4** `--headless` only. No `--debug`: it can hang the runner.
- **R5.5** Every test file in `godot/tests/` is discovered by the runner.
  Nobody edits a list to add a test.

R5.3 is the one that directly prevents a repeat of the specific failure we hit.
It is deliberately blunt: if the numbers disagree, something was skipped.

### R6 — The bridge must load, and there must be a check that says so

From `foundation_audit.md` §2: the Rust core has never loaded on this machine,
so every Godot-side claim about it is unverified. `bridge_spike_test.gd`
already asserts `ClassDB.class_exists("ChessRelayBridge")` and exits 1 when
absent — and it is not wired into `run_ui_checks.sh`.

**Rules:**

- **R6.1** `run_ui_checks.sh` runs every test in `godot/tests/`. One command,
  all suites, non-zero on any failure.
- **R6.2** `chess_relay.gdextension` declares a `linux.arm64` entry alongside
  `linux.x86_64`. CI builds the core for the runner's architecture; the
  extension file must name every platform we build for.
- **R6.3** The end-to-end path — square press → `SubmitMove` → `MoveApplied` →
  board re-rendered — is a required check, not a spike. It is
  `rust-core-plan.md` Phase 6's gate and it has never run.

### R7 — Build output never lands in the working tree

`cargo test` currently **fails on this device** with
`Permission denied (os error 13)` when it tries to execute a build script from
`rust/target/`, because Android shared storage is mounted `noexec`.

- **R7.1** `CARGO_TARGET_DIR` points outside the repository, in CI and in the
  documented local command. `/rust/target/` stays gitignored either way.
- **R7.2** The documented commands in `README.md` and `rust-core-plan.md` are
  the commands that actually run here. A documented command that fails on the
  machine that wrote it is worse than no command.

### R8 — Third-party actions and tools are pinned

Every `uses:` is pinned to a tag or SHA, never `@main`. Every tool version is
pinned (`cargo-nextest@0.9.x`, not bare `cargo-nextest`). A CI gate that changes
under you stops being a gate.

This applies to downloading Godot itself: verify the published SHA-256 for the
release archive and fail closed on mismatch. `sha256sum -c -` exits non-zero and
aborts the step.

### R9 — No gate ships unproven

From the handover, verbatim in spirit: *"ask what a check would fail on."*

Before any gate is treated as working, someone breaks something on purpose and
confirms red. Specifically:

- R1: add an unused local to a script → must fail.
- R5: inject a `get_node` on a null → must fail.
- R5.3: comment out a check → the declared/reached mismatch must fire.
- R3: introduce a clippy warning → must fail.
- R4: add a crate with a yanked advisory → must fail.
- R6: remove the `linux.arm64` line → the bridge check must fail.

A gate nobody has seen fail is a gate nobody can trust. This is the rule that
`foundation_audit.md` §1 says was broken.

### R10 — Documentation claims are gates too

The audit found `godot/tests/README.md` asserting the suite "exits with a
non-zero status if any check fails" when it does not, and `HANDOVER.md`
describing a setting that does not exist.

- **R10.1** A test README states what the suite does and does not cover, and
  the exit-code contract is stated precisely.
- **R10.2** When a finding is fixed, the finding is corrected in the doc that
  recorded it. A stale finding is a lie told to the next reader.
- **R10.3** Docs that name a project setting are checked against the engine's
  registered settings by the R2 drift gate. This is how
  `treat_warnings_as_errors` gets caught.

---

## 3. CI layout

One required check name, aggregating the rest. From the research: pinning a
required check to an individual matrix row breaks the moment the matrix is
retuned; a single stable name never does.

```text
push / pull_request
  |
  +-- rust-fmt          cargo fmt --check
  +-- rust-clippy       cargo clippy --all-targets -- -D warnings
  +-- rust-test         cargo test --locked   (matrix: ubuntu, macos, windows)
  +-- rust-doc          RUSTDOCFLAGS=-D warnings cargo doc --no-deps
  +-- supply-chain      cargo audit  (continue-on-error on PRs)
  |                     cargo deny check bans licenses sources   (hard fail)
  +-- gdscript-parse    per-file --check-only, warnings-as-errors   [R1, R2]
  +-- gdscript-warnings drift: registered warning keys vs committed set  [R2]
  +-- godot-suite       run_ui_checks.sh — all suites, error-aware    [R5, R6]
  |
  +-- gates-ok          ONE required check. Asserts every job above
                        succeeded or was skipped, using `if: always()`.
```

**Design notes, each from a specific source:**

- **`gates-ok` uses `if: always()`** and tests for `failure`/`cancelled`
  explicitly. A path-filtered job that reports "skipped" must not be able to
  pass the aggregate by default.
- **`format` first, everything else `needs: format`.** Formatting is the
  cheapest gate; there is no point compiling if it is going to fail.
- **`--locked` everywhere.** Catches a forgotten lockfile update.
- **`fail-fast: false`** on the Rust matrix, so one broken OS row still reports
  the others.
- **`timeout-minutes: 10`** on test legs. A leg that has not finished in ten
  minutes is hung, not slow.
- **Cache but distrust it.** `Swatinem/rust-cache` cuts build time 50-80%; stale
  caches produce failures that do not reproduce locally. The
  godotengine/godot-proposals thread above records the same for
  `.godot/imported`.
- **`dorny/test-reporter`** for JUnit output, so a failure is visible in the PR
  rather than only in a log.

### Your PC ↔ this device

This is a first-class requirement, not an aside. The workflow is: work on the
PC, push; pull here, continue on small things. Consequences for CI:

- **CI is the shared floor.** Because this device cannot run the Rust build in
  tree (R7) and the Godot binary here has editor bugs (`--import` and `--editor`
  abort with `free(): invalid size`, `HANDOVER.md` §4), the machine you are on
  is not a reliable verifier. CI runs on Linux x86_64 and is the same everywhere.
- **Every gate must be runnable on a stock runner** with only Godot, Rust, and
  Python installed. No local-only tools, no paths that only exist here.
- **The committed config is the tool.** Warning levels, CI steps, and the test
  runner live in the repo. If a gate only works because of something on your
  machine, it is not a gate — it is what `foundation_audit.md` §1 describes.
- **Pull-request CI closes the loop the audit could not.** When you push from
  the PC, CI tells you whether the Rust half is green before you start work here.
  When you push from here, the same.

---

## 3a. What shipped on 2026-10-07

Recorded so the doc describes the end state rather than an intention.

**Live and green:** R1 (per-file parse gate), R2 (drift gate +
`warning_baseline.txt`), R5 (error-aware harness with per-phase sentinels and
declared-versus-executed counts), R6.1 (`run_all_checks.sh` discovers and runs
every suite), R6.2 (`linux.arm64` added), R7 (`CARGO_TARGET_DIR` documented),
R3 and R4 (Rust gates and `deny.toml` wired into CI), R8 (actions pinned).

**Tier 1 findings: 340 → 0** across all 23 first-party `.gd` files. The fixes
were not cosmetic. Three were real defects:

- `game_screen.gd` appended `"q"` to any pawn move reaching rank 8 or 1, making
  underpromotion unreachable — a chess rule decided in GDScript. Now the core
  decides, and the client sends origin and destination.
- `game_screen.gd:83` did `seconds / 60` on an int for the clock. Right by
  accident of truncation; `floori` now.
- `piece_view.gd` carried an `@export_enum` list of piece types, a second source
  of truth beside `chess_core`'s. Removed; identity is a `String` that arrives
  over the bridge, which is what `board_build_order.md` argued for and
  `HANDOVER.md` §3 left open.

Two more changes came out of it:

- **`ChessCoreBridge`** (`src/game/bridge/chess_core_bridge.gd`) is a typed
  facade over the GDExtension node. A GDExtension class has no GDScript type, so
  every call to one was statically `Variant`, which is what produced 24 of
  `game_screen.gd`'s 32 findings. The untyped surface is now confined to one
  file, checked once.
- **`ChessBoardView.is_selecting_press()`** is one shared implementation of
  "is this a press that selects", used by the board, the pieces, and both modal
  backdrops. It was duplicated four times with the same `event.pressed` access
  the type checker refuses.

**Tier 2 not started:** ~820 `inferred_declaration` findings remain, at the
engine default. Deliberate, and staged as its own mechanical pass.

### The environment finding

The bridge cannot load on this Android device, and the reason is not the
project. Termux's `godot-headless` is a wrapper that runs the Linux glibc Godot
binary through Termux's glibc sysroot with `--library-path $PREFIX/glibc/lib`.
That sysroot ships `libdl.so.2` and no `libdl.so`. `dlopen` needs the
unversioned name, so every GDExtension `.so` fails; adding a `libdl.so` symlink
to the path instead makes the loader resolve `libc.so` (a linker script, not an
ELF) and fail with `invalid ELF header`. Verified both ways with a minimal probe
project.

`bridge_spike_test.gd` now distinguishes the three causes — extension missing,
library not built, host cannot `dlopen` — and **fails in all of them**, naming
which. That is deliberate: this suite exists because a missing core was once
reported as a pass, and swapping "always green" for "always red for an
environment reason" would trade one lie for another. CI on a stock Linux runner
is the authority for that gate.

Two consequences for this repo, both now fixed:

- `.godot/extension_list.cfg` is git-ignored along with the rest of `.godot/`,
  and it is the file that tells Godot which `.gdextension` files exist. Without
  it the extension is never considered — which looks exactly like a missing
  library entry. CI writes it explicitly.
- The core library has to be built before the Godot suites can verify anything.
  CI builds it; the README says how to do it locally.

## 4. R9: every gate proved red

The rule that matters most, because it is the one that was broken. Each gate was
made to fail on purpose, on a throwaway copy:

| Injection | Expected | Got |
| --- | --- | --- |
| Unused local in a new script | parse gate fails | exit 1 |
| Bad method call, `unsafe_method_access=1` | passes | exit 0 |
| Same call, `=2` | fails | exit 1 |
| `null.get_node()` injected mid-phase | sentinel + count both fire | `phase game_screen ran to completion` FAIL, 61 checks never executed |
| A `_check(` line deleted | declared/reached mismatch | `86 of 147 checks ran` |
| Expected count overstated by 2 | mismatch still caught | `86 of 149 checks ran` |
| `treat_warnings_as_errors` added back | drift gate names the dead key | exit 1, key named |
| `empty_file` removed from baseline | drift gate names the undecided key | exit 1, key named |
| Suite printing `SCRIPT ERROR` while exiting 0 | runner still fails | exit 1 |
| Full runner with any of the above | non-zero | exit 1, `RESULT: NOT CLEAN` |

## 5. What this costs, honestly

**What is done:** steps 1-4 and 6 of the staged plan. Tier 1 is at zero, every
gate has been proved red on purpose, and CI runs the lot on every push.

**What remains: Tier 2**, ~820 `inferred_declaration` findings at the engine
default. Mechanical, one file at a time, with the parse gate green throughout so
each step is provably neutral. It is not started, and nothing above is waiting
on it.

**Still open, from the foundation audit and not fixed here:**

- **Audit finding 3** — closed locally. Rust now exposes typed occupied-square
  facts; the move number comes from the signed log; and the out-of-v1 clock is
  static `MOCK` furniture with no local timer or seconds state.
- **Audit finding 4** — closed locally. The local spike still supports two roles,
  but no committed shared seeds remain; fresh and persisted role identities are
  derived per installation. This does not substitute for live transport proof.
- **Audit finding 5** — `protocol.rs` is now the live wire protocol
  (version-first handshake, postcard codec, `ProtocolError`), not a
  placeholder; the tests README has been corrected but the handover and
  `foundation_tightening.md` still describe `treat_warnings_as_errors` as a
  live setting.

**What I am not claiming.** That 1383 findings meant 1383 bugs. Tier 1 was ~317
and they were the class that produces real defects; three were. Tier 2 is
hygiene. And a green gate is not proof the board looks right — `HANDOVER.md` §6
is still the last word on that, and it still needs someone to look at a screen.

**What I would not do.** Escalate everything. 222 of the 1383 were
`return_value_discarded`, which fires on `connect()`. Including them would mean
a gate that is red for reasons nobody can act on — the exact condition under
which a team disables its gate. Strictness that cannot be acted on is not
strictness.
