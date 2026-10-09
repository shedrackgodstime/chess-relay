# Remediation Plan: Game Setup, Network Lifecycle, and Preventing Divergence

> Historical audit plan. The active execution order and current evidence live
> in [`implementation-closure-plan.md`](implementation-closure-plan.md). Items
> below are retained for provenance and must not be read as current status
> without checking that ledger.

**Date:** 2026-10-08  
**Status:** Approved  
**Authority:** [`docs/architecture/application_core.md`](../architecture/application_core.md), [`docs/audits/game_setup_and_network_audit.md`](../audits/game_setup_and_network_audit.md), [`godot/docs/HANDOVER.md`](../../godot/docs/HANDOVER.md).

---

## 1. Why Did Divergence Happen? (Root Cause Analysis)

Before fixing the code, we must understand why previous agents diverged so that we do not repeat the failure:

1. **The "Green Suite Fallacy":**  
   Agents ran `cargo test` and `godot/tests/run_all_checks.sh`. Seeing all green, they assumed the architecture was sound. But the tests only proved that *a scripted headless CLI game could exchange moves*, not that the UI lifecycle, user intent, or host authority were preserved.
2. **Copying Test Harnesses into Core/Bridge:**  
   When moving from the Phase 4 CLI spike to Godot integration, an agent copied the automated, scripted CLI test (`chess_relay.rs`) directly into `bridge.rs` as `handshake()`. It solved the immediate task ("make two nodes talk in a test") while bypassing the user interaction model.
3. **Cascading Band-Aids (Compensating Hacks):**  
   When an agent noticed that the game was already started in Rust when opening Godot, instead of fixing the lifecycle in Rust, they hacked Godot: *"Let's just hide the choices in GameSetup, call them 'theater controls', and add an 'Enter game' button."* One architectural shortcut cascaded into three UI hacks.
4. **No Gate Proved User Intent:**  
   No test asserted that the Host could choose Black. No test asserted that a remote `Resign` could cross the network. Because the gates didn't test those contracts, agents improvised without guardrails.

---

## 2. The 3 Non-Negotiable Guardrails (Preventing Future Divergence)

Every subsequent contributor or agent must adhere to these three rules:

### Guardrail 1: The Invariant Law
* **Rule:** Every change must preserve the boundaries in [`docs/architecture/application_core.md`](../architecture/application_core.md).
* **Invariants:**
  1. **Rust owns correctness; Godot owns presentation.** Godot never invents rules; Rust never invents UI intent.
  2. **The host creates the session and sets configuration/sides.** Hardcoding `white: me, black: guest` in Rust is strictly forbidden.
  3. **Transport is an adapter.** Iroh exists solely below the transport trait.
  4. **Game state and connection state are separate state machines.** Connecting transport does *not* start a match.

### Guardrail 2: Red-First Quality Gates
* **Rule:** Before fixing any defect, **write a test that proves the failure (red)**.
* Never declare a bug fixed without demonstrating the failing test passing green.
* Never commit a change if existing gates or new negative gates fail.

### Guardrail 3: Atomic, Phased Execution
* Do not attempt monolithic refactors across Godot and Rust simultaneously.
* Execute one phase at a time, verify with CI gates (`make check`), and commit before proceeding.

---

## 3. Phased Execution Roadmap

```text
Phase 1: Wire Protocol & Application Fixes (Non-UI Core) [COMPLETED]
  ├── [x] 1.1 Accept remote lifecycle entries in `app.rs` (`Resign`, `DrawOffer`, `DrawAccept`, `Abort`)
  ├── [x] 1.2 Unbind `resign()` and `offer_draw()` from turn ownership in `bridge.rs`
  └── [x] 1.3 Fix self-answering draw dialog in `game_screen.gd`
  └── Gate 1: Automated tests proving remote resign/draw/abort ingest cleanly without disconnects. [PASSED]

Phase 2: Lifecycle & Handshake Decoupling (Restoring Setup Authority)
  ├── 2.1 Decouple Iroh link-up (`peer_connected`) from session creation (`StartGame`)
  ├── 2.2 Route `peer_connected` to open `GameSetupScreen` (not `game_started`)
  ├── 2.3 Remove "theater controls" hiding in `game_setup_screen.gd`; restore White/Black/Random picker
  ├── 2.4 Make `StartGame` host-driven with chosen sides; exchange `Msg::Hello { genesis }`
  ├── 2.5 Make readiness user-driven (`Command::SetReady` on "Ready" button press)
  ├── 2.6 Advance to `GameScreen` only on `Event::GameStarted` (both players ready)
  └── 2.7 Fix network session leak on leaving setup in `app_root.gd`
  └── Gate 2: End-to-end test verifying host side selection, user ready toggles, and clean leave.

Phase 3: Structural Deconstruction & Transport Modernization
  ├── 3.1 Extract Tokio runtime and network tasks from `bridge.rs` into a dedicated `network` service
  ├── 3.2 Upgrade `transport_iroh.rs` from per-message uni-streams to persistent framed streams
  ├── 3.3 Expose pkarr 8-character short codes in `bridge.rs` and `MultiplayerHubScreen`
  └── 3.4 Resolve phantom UI controls (remove/wire real clock controls, clarify Chess960)
  └── Gate 3: `make check` all green, CI workflows pass.
```

---

## Phase 1: Wire Protocol & Application Core Fixes

**Objective:** Ensure active networked games never crash when a player resigns, offers a draw, accepts a draw, or aborts.

### Task 1.1: Support Lifecycle Entries in `app.ingest_remote()`
* **File:** [`rust/src/app.rs`](../../rust/src/app.rs)
* **Action:**
  - In `ingest_remote(&mut self, entry: &LogEntry)`:
    Replace the check that rejects non-move entries (`let LogPayload::Move { mv } = entry.payload else { ... }`).
  - Validate and ingest `LogPayload::Resign`, `LogPayload::DrawOffer`, `LogPayload::DrawAccept`, and `LogPayload::Abort`.
  - Pass the entry into `session.receive(entry)`.
  - Map resulting session finish/events to [`Event::GameEnded`](../../rust/src/app.rs#L243), [`Event::DrawOffered`](../../rust/src/app.rs#L229), [`Event::DrawAnswered`](../../rust/src/app.rs#L236).
* **Test:** Add integration tests in `rust/tests/app.rs`:
  - `remote_resign_ingests_and_ends_game`
  - `remote_draw_offer_and_accept_ingests`
  - `remote_abort_ingests`

### Task 1.2: Unbind Resignation & Draw Offers from Turn Ownership
* **File:** [`rust/src/bridge.rs`](../../rust/src/bridge.rs)
* **Action:**
  - In `resign(&mut self)` and `offer_draw(&mut self)`:
    Change target peer from `turn_peer(&core)` to `core.me`.
  - Ensure a player can resign unilaterally when it is the opponent's turn.
* **Test:** Add tests in `rust/tests/session.rs` and `rust/tests/app.rs` asserting that `Command::Resign { peer: me }` succeeds on the opponent's turn.

### Task 1.3: Fix Draw Offer UI Dialog
* **File:** [`godot/src/ui/screens/game/game_screen.gd`](../../godot/src/ui/screens/game/game_screen.gd)
* **Action:**
  - Remove the immediate confirmation dialog in `_offer_draw()`. When offering a draw, inform the user with a header message (`"Draw offer sent · waiting for opponent"`).
  - In `_on_core_draw_offered(by, seq)`:
    Check if `by != _bridge.my_side()`. If received from the opponent, display the `ConfirmationDialog` with "Accept" / "Decline" buttons.
  - Wire confirmation to `_bridge.answer_draw(true)` and cancellation to `_bridge.answer_draw(false)`.
### Status: Completed (Green)
* `Session::receive` and `replay_game` in [`rust/src/session/mod.rs`](../../rust/src/session/mod.rs) now validate and ingest all lifecycle log payloads (`Resign`, `DrawOffer`, `DrawAccept`, `Abort`).
* `App::ingest_remote` in [`rust/src/app.rs`](../../rust/src/app.rs) routes all lifecycle entries to `outbox` events (`GameEnded`, `DrawOffered`, `DrawAnswered`).
* `on_msg` in [`rust/src/bridge.rs`](../../rust/src/bridge.rs) supports `Ingest::Applied` so unagreed lifecycle entries do not sever the connection.
* `resign`, `offer_draw`, `answer_draw`, and new `abort` in [`rust/src/bridge.rs`](../../rust/src/bridge.rs) use `core.me` when networked/AI, enabling out-of-turn resignation/draw offers.
* Exposed `my_peer` and `side_of_peer` in [`bridge.rs`](../../rust/src/bridge.rs) and [`chess_core_bridge.gd`](../../godot/src/game/bridge/chess_core_bridge.gd).
* In [`game_screen.gd`](../../godot/src/ui/screens/game/game_screen.gd), the draw offer dialog is routed to the receiving opponent rather than self-answering.
* All unit tests, doc-tests, integration tests, and Godot test suites are 100% green.

---

## Phase 2: Lifecycle & Handshake Decoupling

**Objective:** Restore Game Setup as an authoritative match configuration screen and fix the lifecycle inversion.

### Task 2.1: Decouple Transport Link-up from Session Creation
* **File:** [`rust/src/bridge.rs`](../../rust/src/bridge.rs)
* **Action:**
  - When `accept()` or `connect()` succeeds in `accept_task` / `join_task`, emit `NetNote::Connected(remote_peer.to_string())`.
  - Do **not** call `Command::StartGame` or `handshake()` inside the link task.
  - Hold the open connection in `NetState` ready to transmit session messages.

### Task 2.2: Route `peer_connected` to Open Game Setup
* **File:** [`godot/src/ui/app/app_root.gd`](../../godot/src/ui/app/app_root.gd), [`godot/src/ui/screens/multiplayer_hub/multiplayer_hub_screen.gd`](../../godot/src/ui/screens/multiplayer_hub/multiplayer_hub_screen.gd)
* **Action:**
  - In `MultiplayerHubScreen`, transition to `GameSetupScreen` on `peer_connected` instead of waiting for `game_started`.
  - Both Host and Guest land on `GameSetupScreen` in the `SettingUp` state.

### Task 2.3: Restore Host Authority on Game Setup Screen
* **File:** [`godot/src/ui/screens/game_setup/game_setup_screen.gd`](../../godot/src/ui/screens/game_setup/game_setup_screen.gd)
* **Action:**
  - Remove `_apply_net_lobby()` hiding choices.
  - For the **Host**: Show the "Choose Color" choice group (White / Black / Random).
  - For the **Guest**: Display color as "Assigned by host" until genesis arrives.
  - Replace the "Enter game" button with the standard "Ready" toggle.

### Task 2.4: Host-Driven Session Creation
* **Action:**
  - When Host clicks "Ready" on `GameSetupScreen`, the host issues `start_network_game(side)`.
  - Bridge executes `Command::StartGame { white, black }` based on host's chosen color.
  - Host transmits `Msg::Hello { version, genesis }` over the connection.
  - Guest receives `Hello`, calls `Command::JoinGame`, and co-signs genesis.
  - Guest sends `Msg::Agreed { seq: 0, sig }`.
  - Both participant cards update with the authoritative colors from genesis.

### Task 2.5: User-Driven Readiness & Game Start
* **Action:**
  - Host and Guest send `Msg::Ready` only when their respective users click "Ready".
  - When both sides are ready, the Rust core session emits `Event::GameStarted`.
  - `app_root.gd` receives `game_started` and transitions both screens to `GameScreen`.

### Task 2.6: Fix Network Session Leak on Leaving Setup
* **File:** [`godot/src/ui/app/app_root.gd`](../../godot/src/ui/app/app_root.gd)
* **Action:**
  - In `_on_game_setup_leave_requested(is_peer_setup)`:
    Ensure `_leave_network()` is called whenever leaving a peer setup session.

---

## Phase 3: Structural Deconstruction & Transport Modernization

**Objective:** Clean architecture, modularity, and transport reliability.

### Task 3.1: Decompose `bridge.rs`
* Extract Tokio runtime, connection loops, and packet pumps into `rust/src/network/`.
* `bridge.rs` becomes a thin node conforming to Section 8 of `application_core.md`.

### Task 3.2: Modernize Iroh Framing
* Replace opening a uni-stream per message with persistent framing over bidirectional QUIC streams.

### Task 3.3: Expose pkarr Short Codes
* Expose `host_game_with_code()` returning 8-character short codes via `transport_rendezvous.rs`.
* Allow joining via 8-character code in `MultiplayerHubScreen`.

### Task 3.4: Resolve UI Furniture
* Remove or implement real time controls.
* Remove or clarify Chess960 option.
* Replace fabricated clock with proper timekeeper architecture when clock slice is prioritized.

---

## 4. Verification & Quality Gates

Every phase must pass:
1. `cargo fmt --manifest-path rust/Cargo.toml -- --check`
2. `cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings`
3. `cargo test --manifest-path rust/Cargo.toml`
4. `RUSTDOCFLAGS="-D warnings" cargo doc --manifest-path rust/Cargo.toml --no-deps`
5. `GODOT_BIN=godot bash godot/tests/run_all_checks.sh`

### 4a. Gate corrections, 2026-10-08

Two fixes to this list, both found by checking the commands against the code
rather than assuming they cover it.

**`cargo fmt` flag is wrong above.** `cargo fmt -- --check` passes `--check` to
rustfmt, but the canonical form is `cargo fmt --check` (rustfmt takes the flag
directly through cargo). Both happen to work; keep the plain one so it matches
CI, which runs `cargo fmt --check`.

**Add `--locked` to test, clippy, and doc.** Without it, CI silently accepts a
`Cargo.lock` update, which is how a breaking dependency arrives in a commit that
looks small. `Cargo.lock` has already grown by 274 lines in this period.

### 4b. The Godot gate cannot run on a device without the import step

**This is the one that matters, and it is a defect in the gate rather than in
the code.** `godot/tests/run_all_checks.sh` parses every `.gd` individually, and
`promotion_picker.gd` does:

```gdscript
const PREVIEW_QUEEN_WHITE: Texture2D = preload("res://assets/chess/pieces/preview_queen_white.png")
```

That preload resolves through `.godot/imported/*.ctex`, and `.godot/` is
git-ignored. On a clone where the import has not run, all eight previews fail to
load and the file fails to parse:

```
SCRIPT ERROR: Parse Error: Could not preload resource file
              "res://assets/chess/pieces/preview_queen_white.png".
```

Confirmed by extracting `HEAD` into a clean directory: the PNG sources are
committed (8 of them, with `.import` sidecars), no `.ctex` exists, and
`--check-only` fails.

**Two consequences, and only the first is obvious:**

1. **On this device, `--import` aborts** with `free(): invalid size` — the known
   binary fault in `HANDOVER.md` §4. So the import can never be made to run here
   and the promotion picker can never parse here. That is environmental.
2. **CI does not run `--import` either.** `.github/workflows/gates.yml` only
   *restores* a cache of `godot/.godot/imported`. On a cache hit the `.ctex`
   files are there; on a cold cache they are not, and the parse gate fails for a
   reason that has nothing to do with the code under review.

**Fix, before Phase 1:** add an import step to the `godot-checks` job, before the
gates run, and make it authoritative rather than allowed to fail:

```yaml
- name: Import project assets
  run: |
    godot --headless --path godot --import || true
    test -f godot/.godot/imported/preview_queen_white.png-*.ctex
```

The `|| true` is because `--import` exits noisily even on success on some
builds. The `test -f` after it is what makes the step real: it fails when the
import did not happen, which is exactly the case a cache miss produces.

**A gate that only passes when a cache is warm is a gate that will fail for
someone on their first push and read as their mistake.** Same family as the
"expected versus executed check" problem, and worth the same suspicion.

### 4c. Verification commands this environment cannot run

`cargo test` on Android shared storage is a 40-minute build that cannot be run
interactively. The Rust gates above are therefore verified by CI only, and any
claim about them should say so. The Godot gates run in seconds and are verified
directly.

---

## 5. Review of the remediation plan itself

Independent check of the plan and of
[`game_setup_and_network_audit.md`](../audits/game_setup_and_network_audit.md)
against the code as of `0a4218b`. The audit is accurate and unusually specific;
these are confirmations, corrections, and additions.

### 5a. Every finding verified still present

Checked against the tree, not the audit's line numbers:

| ID | Still present? | Where |
| --- | --- | --- |
| F-01 lifecycle inversion | **Yes** | `bridge.rs:1263` still `StartGame { white: me, black: guest }` inside the link task; `game_setup_screen.gd:113` still `_apply_net_lobby()` with `_play_button.text = "Enter game"` |
| F-02 remote lifecycle | **Yes** | `app.rs:619` still `let LogPayload::Move { mv } = entry.payload else { ... }` |
| F-03 turn-bound resign | **Yes** | `bridge.rs:578` and `:591` both still `turn_peer(&core)` |
| F-04 self-answering draw | **Yes** | `game_screen.gd:546` still opens the dialog on the offerer's own screen; `:488` still only sets a header string |
| F-05 monolithic bridge | **Yes, worse** | 1,885 lines, and now also owns local AI, pkarr, and file storage |
| F-06 setup leak | **Yes** | `app_root.gd:258-262` unchanged; no `_leave_network()` |
| F-07 no resume | **Yes** | `bridge.rs:1639` still discards `Msg::Hello` / `Tip` / `Fen` |
| F-08 uni stream per msg | **Yes** | `transport_iroh.rs:135-147` unchanged |
| F-09 phantom features | **Yes, extended** | see 5c |

### 5b. F-08 is confirmed by the RFC — cite it

The audit asserts an ordering hazard without authority. RFC 9000 §2 says it
directly:

> QUIC does not provide any means of ensuring ordering between bytes on different
> streams.

and §4 (stream priority) notes QUIC "relies on receiving priority information
from the application" to decide delivery order between streams.

So the hazard is not a suspicion, it is the specification's stated behaviour.
The relevant consequence for this project is sharper than the audit puts it: log
entries carry sequence numbers and are hash-linked, so an out-of-order entry
fails validation and **stops the game** (`application_core.md` §Disconnects).
One uni-stream-per-message is therefore not merely wasteful overhead — under
loss it can end a match. The plan puts this in Phase 1 as "persistent framing";
it deserves to be *first* in Phase 1, ahead of the resign/draw work, because it is
the only finding here that can end a live game by accident rather than by player
action.

Counter-consideration worth stating: QUIC's own stream-reordering behavior is
invisible if the receiver never reorders. The receiving side should therefore
buffer and sort by `seq` regardless of what the transport does, rather than
trusting arrival order. That is defence in depth, and it also makes the F-07
resume path easier to build later.

### 5c. F-09 has grown since the audit was written

The audit lists five phantom features. Since then:

- **Chess960** remains in the setup UI with 0% core support. Still true.
- **Time controls** remain and are still discarded. Still true.
- **Fabricated clock** still present in `game_screen.gd`.
- **Discovery toggles** still write a local label only.
- **Short invite codes** — the audit says `host_game()` returns raw tickets.
  **This is now partly fixed.** `transport_rendezvous.rs` exists (217 lines) and
  `bridge.rs` exposes a short-code path; commit `8a25602` is titled "Short-code
  rendezvous via pkarr wormhole pattern". Needs a read to confirm how much of
  F-09's fifth item is closed.

Four of the five remain a control that is visible, interactive, and discarded.
None of them crash. They are the exact shape the handover's fourth law warns
about — a `PLAY` button with nothing connected to it — repeated four times on one
screen.

Worth a gate. The cheapest version: a test that asserts every `ChoiceGroup`
option and every toggle on `game_setup_screen.tscn` is read by something. That is
checkable headless and would have caught four of the five.

### 5d. The committed seeds are now worse, not better

`bridge.rs:31-32` still holds `LOCAL_SEED = [1u8; 32]` and
`SPIKE_PEER_SEED = [2u8; 32]`. The handover names this as "the worst thing still
in the repository".

Since the audit, `SPIKE_PEER_SEED` acquired a **third** use at `bridge.rs:263`,
where it signs the AI's moves:

```rust
let ai_key = SigningKey::from_bytes(&SPIKE_PEER_SEED);
```

So one hardcoded secret now stands in for the local player, the remote player,
*and* the computer opponent. The security argument is unchanged and still
weak-for-a-spike, but the blast radius grew: a game against the AI is signed by a
key that is in the git history, and a key used for two different roles should
not be used for a third. **Give the AI its own seed, or better, a real per-install
identity.** This belongs in Phase 1 and is smaller than anything else in it.

### 5e. 20 temporary diagnostic prints are committed

`grep -rn TEMP-DIAG rust/src godot/src` returns 20 lines: `NET-TRACE` prints in
`bridge.rs` (14) and `app_root.gd` (6), including a `_trace_screen()` helper
added purely for them.

Two problems. First, they are `eprintln!`/`print` on the render thread, so they
run in the shipped build. Second, **no gate catches them**, which is the part
that repeats the pattern: the HANDOVER's fifth law is about debug scaffolding
outliving the session, and nothing enforces it.

Cheapest gate that works: `grep -rE 'TEMP-DIAG|NET-TRACE|DBG ' godot/src rust/src`
must return nothing, in `run_all_checks.sh` and in CI. A debug print with no gate
is a print that stays.

### 5f. Phase ordering — one correction

The plan's Phase 1 is resign/draw/abort (application-level), and transport
framing is Phase 3. **Move framing to the front of Phase 1**, per 5b: it is the
one defect here that can destroy a live game by accident rather than by player
action, and it is cheap.

The plan's own ordering is otherwise sound — unblocking remote lifecycle before
rearchitecting the handshake is right, because Phases 1 and 2 are independent and
Phase 2's e2e test will exercise Phase 1 anyway.

### 5g. Two things the plan does not mention

**The `--expected-checks` count is now correct, and that fix has a consequence
worth recording.** `run_all_checks.sh` changed from `grep -c '_check('` to
`grep -cE '^\s*_check\('` because the helper definition itself contains `_check(`.
Measured deltas: `ai_bridge_test.gd` 7→6, `bridge_spike_test.gd` 14→13,
`game_scenarios_test.gd` 43→42, `ui_smoke_test.gd` 149→147. That is a genuine
correction of an over-count, and it is the kind of fix that quietly makes a
gate weaker if done carelessly — here it is right, and the old count would have
been unachievable by any suite. Worth a note so nobody "fixes" it back.

Also added: a 300s `timeout` per suite, and exit code 124 handled. Good — a
hung suite now fails loudly instead of stalling CI.

**`make check` exists and Guardrail 3 is correct.** There is a `Makefile` at the
repository root (added with `51b00d9`), and its `check` target runs the five
commands above. Two things in it are still worth fixing, and they are the same
two from §4a: `cargo fmt -- --check` should be `cargo fmt --check`, and none of
the cargo invocations pass `--locked`.

Its `run` target also encodes something useful that the gates do not:
`godot/bin/libchess_relay_core.so` is a real file target depending on the Rust
sources, so a stale `.so` cannot be exported to a device. The header comment
says exactly why — *"a stale .so can never reach the device again"* — which is a
good instinct that the Godot gate does not share. Worth extending: the Godot
suite currently loads whatever `.so` is present and does not check whether it
matches the sources.

---

## 6. Two more audits, reviewed

### 6a. `chess-differential.md` is strong; its one known divergence is a rules bug

The differential run against shakmaty is the most valuable verification in the
project's history: 1500 games, 507,485 plies, zero mismatches, comparing FEN,
full legal move sets, check flag, mate/stalemate, insufficient material,
halfmove clock, and threefold timing after *every ply*. Fifty thousand more
agreements than anything else here. The three self-authored test vectors that
turned out to be illegal positions, where the engines were right and the vectors
were wrong, is exactly the kind of thing that makes the result trustworthy.

**But the one documented divergence is not a simplification. It is a FIDE error,
and calling it casual understates it.**

`game.rs` declares two knights versus a bare king a draw. The audit's own words
are accurate — *"a helpmate exists"* — and that is precisely the FIDE test.
Article 5.2(b) / 9.6 draw a position when neither player can checkmate *"by any
series of legal moves"*, not by any forced line. A position where mate is
**possible** is not dead.

Every source agrees, and they agree for the same reason:

> Two knights against a bare king cannot force mate. Everybody knows that...
> **But watch what happens if the defender helps.** [...] Because that mate
> exists, two knights are not insufficient material. The rules ask whether a mate
> is possible by any series of legal moves, not whether you can force one against
> a defender who is trying.

The consequence is concrete. FIDE 6.9: run out of time and you **lose**,
unless the opponent cannot mate you by any possible sequence. With two knights,
mate is possible, so a flag fall in that ending is a loss. Our engine returns
`Draw`. A player who reaches KNNK with the opponent on the clock wins on time
under FIDE and is handed a draw by our engine.

**This is out of scope for this remediation plan** — it is a chess-core rules
change, not a lifecycle or network fix, and it needs its own red test and its own
perft-adjacent vector. It belongs in `rust-core-plan.md` as a Phase 1 amendment.

The comment in `game.rs:10` says the simplification *"matches the GDScript
prototype"*. That is the wrong reason to keep a rules bug. `rust-standards.md`
says the prototype and shakmaty are **oracles to agree with**, and here they
disagree with each other, so agreement is not available as a justification.
shakmaty plays on; shakmaty is the independent one.

Suggested, so it is a decision rather than a shrug: remove the two-knight rule,
and record in `chess-differential.md` that the divergence closed with shakmaty.
The rule is `game.rs:223-227` (a `matches!` on exactly two knights against an
empty side) and the test that pins it is `game.rs:309`. Both would go.

**One caveat before anyone does it.** Insufficient material is also used for
flag-fall adjudication in most engines, and this codebase has no clock, so the
6.9 case does not arise yet. Which means fixing this changes nothing a player can
observe *today*, and it would be easy to defer indefinitely on that basis. It
should be fixed anyway, before a clock lands and inherits the bug: a time control
added on top of this would award draws where FIDE says wins.

### 6b. `ai-integration-divergence.md` is right, and its guardrail is missing

That audit found the AI losing a legal capture because a tap on the destination
piece hit the piece surface before the board surface, and the multiplayer
ownership guard returned "Waiting for opponent" before routing to
`SubmitMove`. The diagnosis is correct: each layer is individually right and the
gesture is still discarded between rendering and command submission.

It lists seven risks. One of them is now worth turning into a gate, and the audit
itself names the missing evidence: *"bridge integration can appear healthy while
the real `GameScreen` event path is not exercised."*

**That is still true.** `game_scenarios_test.gd` (43 checks) is new and substantial,
but the AI capture regression was found and fixed *by hand*, and the class of bug
is "the surface that answers the tap is not the surface you expected." No gate
asserts event ordering between the piece surface and the board surface.

Cheap gate: one scenario where the capture destination is **occupied**, tapping
that piece routes to `SubmitMove` in AI mode, and the same gesture in multiplayer
mode is refused. Both halves, because the bug only appears when the two modes
diverge — which is why the fix could pass locally and fail for the AI.

---

## 7. What to do first, concretely

Not the plan's order. The plan's order is right for the architectural work; this
is the order that keeps the gates honest while that happens.

**Read first:** [`player_visible_defects.md`](../audits/player_visible_defects.md),
written the same day from player reports on real hardware. It confirms all nine
findings above as still present, extends F-03 into the client, extends F-06 to
the in-game leave path, and names four things this plan does not cover — a
string-typed `setup_kind` compared in two files, a guard flag that cannot fail, a
fixed `custom_minimum_size` that leaves empty cards once the lifecycle inversion
hides their contents, and the gates whose absence let all of it ship.

1. **Add the `--import` step to CI** (§4b). Without it the Godot gate fails on a
   cold cache for a reason unrelated to the change, which teaches people to
   ignore the gate.
2. **Give the AI its own signing key** (§5d). Smallest real defect in the repo.
3. **Add the no-debug-prints gate** (§5e). Twenty lines of script, removes twenty
   lines of committed noise, and stops it recurring.
4. **Move transport framing to the front of Phase 1** (§5b, §5f).
5. **Commit `.godot/extension_list.cfg` or document the step** — it is required,
   git-ignored, and its absence is indistinguishable from a missing library
   entry. Already documented in `HANDOVER.md` §4; make CI do it automatically,
   which it does.
6. **Then Phase 1 proper**: remote lifecycle ingest, turn-bound resign/draw.
7. **Add the phantom-control gate** (§5c) before Phase 2, so the setup screen
   cannot grow a fifth one while it is being rebuilt.

Steps 1-3 are an afternoon, none of them touch architecture, and all three make
the remaining work verifiable. Steps 4-7 are the plan.

One thing deliberately left out of this list: the two-knights draw (§6a). It is a
real rules bug and it should be fixed, but it is chess-core work, it needs its own
red test, and mixing it into a lifecycle-and-network remediation would be the
"monolithic refactor across Godot and Rust simultaneously" Guardrail 3 forbids.
Amend `rust-core-plan.md` and do it as its own change.
