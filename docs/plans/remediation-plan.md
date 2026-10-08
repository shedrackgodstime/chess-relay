# Remediation Plan: Game Setup, Network Lifecycle, and Preventing Divergence

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
Phase 1: Wire Protocol & Application Fixes (Non-UI Core)
  ├── 1.1 Accept remote lifecycle entries in `app.rs` (`Resign`, `DrawOffer`, `DrawAccept`, `Abort`)
  ├── 1.2 Unbind `resign()` and `offer_draw()` from turn ownership in `bridge.rs`
  └── 1.3 Fix self-answering draw dialog in `game_screen.gd`
  └── Gate 1: Automated tests proving remote resign/draw/abort ingest cleanly without disconnects.

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
  ├── 3.3 Expose pkarr 6-character short codes in `bridge.rs` and `MultiplayerHubScreen`
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
* **Test:** Update `godot/tests/game_scenarios_test.gd` to verify the recipient sees the draw dialog.

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
* Expose `host_game_with_code()` returning 6-character short codes via `transport_rendezvous.rs`.
* Allow joining via 6-character code in `MultiplayerHubScreen`.

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
