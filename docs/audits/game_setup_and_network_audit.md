# Comprehensive Architectural Audit: Game Setup, Iroh, and Application Core

**Date:** 2026-10-08  
**Scope:** `godot/src/ui/screens/game_setup/`, `godot/src/ui/app/app_root.gd`, `godot/src/ui/screens/multiplayer_hub/`, `godot/src/ui/screens/game/`, `rust/src/bridge.rs`, `rust/src/transport_iroh.rs`, `rust/src/transport.rs`, `rust/src/transport_rendezvous.rs`, `rust/src/protocol.rs`, `rust/src/app.rs`, and `rust/src/session/`.  
**Authority:** [`docs/architecture/application_core.md`](../architecture/application_core.md), [`godot/docs/HANDOVER.md`](../../godot/docs/HANDOVER.md), [`docs/standards/rust-standards.md`](../standards/rust-standards.md), and official Godot documentation in `ref/godot-docs/`.

---

## Executive Summary

While all automated tests currently pass (`cargo test` and `godot/tests/run_all_checks.sh`), this audit confirms that **the current Game Setup UI and Iroh network integration fundamentally violate the architecture specified in [`application_core.md`](../architecture/application_core.md)**.

A quick-and-dirty CLI integration test script from Phase 4 was copied wholesale into the GDExtension bridge ([`rust/src/bridge.rs`](../../rust/src/bridge.rs)). Because that script automatically starts matches and forces player readiness without user interaction, the Godot frontend was forced to implement awkward workarounds:
- The UI lifecycle was inverted: the multiplayer hub advances to the "Setup" screen *only after* the game has already started.
- All controls on the Game Setup screen were disabled and hidden as "theater controls," demoting the setup screen to a passive pass-through lobby.
- Remote lifecycle operations (draw offers, draw answers, resignations, aborts) fail at the network boundary and crash active sessions.
- Draw offers in GDScript prompt the player offering the draw to accept their own offer, while the opponent receives no action prompt.
- The GDExtension bridge grew into a 1,886-line monolith combining Godot node APIs, Tokio runtime management, QUIC socket handling, pkarr DNS rendezvous, session driving, AI worker threading, and file I/O.

---

## Index of Findings

| ID | Finding | Severity | Layer |
| :--- | :--- | :--- | :--- |
| **F-01** | [The Lifecycle Inversion: Handshake vs Game Setup](#f-01-the-lifecycle-inversion-handshake-vs-game-setup) | **Critical** | Bridge / Godot UI |
| **F-02** | [Remote Lifecycle Entries Crash Network Sessions](#f-02-remote-lifecycle-entries-crash-network-sessions) | **Critical** | Protocol / Application |
| **F-03** | [Resignations and Draw Offers Bound to Turn Ownership](#f-03-resignations-and-draw-offers-bound-to-turn-ownership) | **High** | Bridge / Session |
| **F-04** | [Self-Answering Draw Offers in Game Screen UI](#f-04-self-answering-draw-offers-in-game-screen-ui) | **High** | Godot UI |
| **F-05** | [Monolithic Bridge Violates Dependency Isolation](#f-05-monolithic-bridge-violates-dependency-isolation) | **High** | Bridge Architecture |
| **F-06** | [Network Session Leak When Leaving Game Setup](#f-06-network-session-leak-when-leaving-game-setup) | **Medium-High** | Godot App Root |
| **F-07** | [Reconnect and Resume Path in Bridge](#f-07-reconnect-and-resume-path-in-bridge) | **Implemented; hardware verification pending** | Bridge / Transport |
| **F-08** | [One Unidirectional QUIC Stream per Message Hazard](#f-08-one-unidirectional-quic-stream-per-message-hazard) | **Medium** | Iroh Transport |
| **F-09** | [Phantom Features and Disconnected Controls](#f-09-phantom-features-and-disconnected-controls) | **Medium** | Godot UI / Core |
| **F-10** | [Inefficient Scene Teardown and GDScript FEN Parsing](#f-10-inefficient-scene-teardown-and-gdscript-fen-parsing) | **Low-Medium** | Game Screen |

---

## Detailed Audit Findings

### F-01: The Lifecycle Inversion: Handshake vs Game Setup
**Severity: Critical**  
**Locations:**
- [`rust/src/bridge.rs#L1262-L1358`](../../rust/src/bridge.rs#L1262-L1358)
- [`godot/src/ui/app/app_root.gd#L191-L222`](../../godot/src/ui/app/app_root.gd#L191-L222)
- [`godot/src/ui/screens/game_setup/game_setup_screen.gd#L84-L128`](../../godot/src/ui/screens/game_setup/game_setup_screen.gd#L84-L128)

#### Rule Broken
[`application_core.md`](../architecture/application_core.md#L115-L127) specifies:
```text
Created -> SettingUp -> Ready -> Playing -> Finished
```
> *"The **host** is the peer that created the session. That role means two things: it sets the configuration and sides, and it would be the timekeeper if a clock is ever added."*  
> *"Commands are intent: `StartGame`, `SetReady`, `SubmitMove`, `Resign`, `OfferDraw`..."*  
> *"Separate state machines: Game state and connection state are independent. Don't merge them."*

#### Evidence
1. In `bridge.rs`, as soon as two peers connect over QUIC, `accept_task` and `join_task` execute `handshake()`:
   ```rust
   // Host side automatically creates the game without Godot intent:
   apply(core, Command::StartGame { white: me, black: guest });
   ```
   The host is hardcoded as White; the guest is hardcoded as Black.
2. The guest receives `Hello` and automatically issues `Command::JoinGame` and `Command::SetReady`.
3. The host receives guest readiness and automatically issues `Command::NotePeerReady` and `Command::SetReady`.
4. Both sides transition the session to `SessionState::Playing` (`Event::GameStarted`) inside the network task *before Godot is even aware that a player joined*.
5. In `app_root.gd`, `_on_net_game_started` routes to `opponent_connected`, advancing the Multiplayer Hub to `GameSetupScreen`:
   ```gdscript
   ## The hub advances to setup on `game_started`: the handshake (ready +
   ## genesis agreement both ways) must complete first...
   ```
6. In `game_setup_screen.gd`, because the game is already live and sides are already committed:
   ```gdscript
   func _apply_net_lobby() -> void:
       _side_choice.hide()
       _time_choice.hide()
       _variant_choice.hide()
       _custom_time_controls.hide()
       _play_button.text = "Enter game"
       _ready_label.text = "Connected · game is live · enter when ready"
   ```

#### Impact
The host is stripped of its authority to choose sides (White/Black/Random) or configure the session. The Game Setup screen is reduced to a hollow shell ("theater controls") where players are forced into an "Enter game" button for a match that already started underneath. Mock multiplayer and live P2P multiplayer have completely diverged lifecycles.

---

### F-02: Remote Lifecycle Entries Crash Network Sessions
**Severity: Critical**  
**Locations:**
- [`rust/src/app.rs#L618-L623`](../../rust/src/app.rs#L618-L623)
- [`rust/src/bridge.rs#L1577-L1605`](../../rust/src/bridge.rs#L1577-L1605)

#### Rule Broken
[`application_core.md`](../architecture/application_core.md#L149-L152):
> *"Draw offers (and later, rematch) are a request/answer exchange in the protocol: one side sends an offer, the other answers. They are session actions, not chess rules."*

#### Evidence
1. In `app.rs`, `ingest_remote` is guarded by:
   ```rust
   pub fn ingest_remote(&mut self, entry: &LogEntry) -> Result<(), AppError> {
       let LogPayload::Move { mv } = entry.payload else {
           return Err(AppError::bad_command(
               "remote lifecycle sync arrives with protocol".to_string(),
           ));
       };
   ```
2. When a player resigns, offers a draw, accepts a draw, or aborts, `flush_unsent` sends `Msg::Entry(entry)` with `LogPayload::Resign`, `LogPayload::DrawOffer`, etc.
3. When the remote peer receives this entry, `on_msg` calls `app.ingest_remote(&entry)`.
4. `ingest_remote` fails immediately with `"remote lifecycle sync arrives with protocol"`.
5. `bridge.rs` converts this to `Ingest::Reject(reason)`, emits `NetNote::Error`, and returns `Err(())`.
6. Returning `Err(())` causes `drive_session` to abort and terminate the connection loop.

#### Impact
Any attempt to resign, offer a draw, accept a draw, or abort over the network causes the opponent's bridge to error out and sever the QUIC connection. Clean match termination over P2P is currently impossible.

---

### F-03: Resignations and Draw Offers Bound to Turn Ownership
**Severity: High**  
**Locations:**
- [`rust/src/bridge.rs#L573-L601`](../../rust/src/bridge.rs#L573-L601)

#### Rule Broken
Rules of chess and [`application_core.md`](../architecture/application_core.md#L87-L89):
> *"Commands are intent: `StartGame`, `SetReady`, `SubmitMove`, `Resign`, `OfferDraw`, `AnswerDraw`, `Abort`."*  
> Resignation is a unilateral declaration of surrender by a player at any time.

#### Evidence
In `bridge.rs`:
```rust
#[func]
fn resign(&mut self) -> bool {
    let command = {
        let core = self.lock();
        match turn_peer(&core) {
            Some(peer) => Command::Resign { peer },
            None => return false,
        }
    };
    self.run_command(command)
}
```
`offer_draw` follows the exact same pattern:
```rust
#[func]
fn offer_draw(&mut self) -> bool {
    let peer = {
        let core = self.lock();
        match turn_peer(&core) {
            Some(peer) => peer,
            None => return false,
        }
    };
...
```

#### Impact
A player cannot resign or offer a draw unless it is currently their turn. If a player attempts to resign while waiting for their opponent to move, `turn_peer(&core)` returns the *opponent's* identity. In a networked session, this triggers `AppError::not_local()` (since this node does not hold the opponent's signing key), completely blocking resignation.

---

### F-04: Self-Answering Draw Offers in Game Screen UI
**Severity: High**  
**Locations:**
- [`godot/src/ui/screens/game/game_screen.gd#L540-L563`](../../godot/src/ui/screens/game/game_screen.gd#L540-L563)
- [`godot/src/ui/screens/game/game_screen.gd#L487-L489`](../../godot/src/ui/screens/game/game_screen.gd#L487-L489)

#### Rule Broken
UI interaction design and [`application_core.md`](../architecture/application_core.md#L149-L152):
> *"Draw offers are a request/answer exchange in the protocol: one side sends an offer, the other answers."*

#### Evidence
1. In `game_screen.gd`:
   ```gdscript
   func _offer_draw() -> void:
       ...
       if not _bridge.offer_draw():
           return
       var answer := ConfirmationDialog.new()
       answer.title = "Draw offered"
       answer.dialog_text = "The side to move offers a draw. Accept?"
       answer.confirmed.connect(func() -> void:
           _bridge.answer_draw(true)
           answer.queue_free()
       )
   ```
2. When a player clicks "Offer draw," the game opens a modal dialog on the **offerer's own screen**, asking them if they accept their own draw offer.
3. Meanwhile, when the opponent receives the `draw_offered` signal, `_on_core_draw_offered` only executes:
   ```gdscript
   func _on_core_draw_offered(by: String, seq: int) -> void:
       _header.set_center_text("Draw offered · awaiting answer")
   ```
   The recipient is given no dialog, button, or mechanism to accept or decline.

#### Impact
Draw offer UX is fundamentally broken: the sender answers their own offer, while the receiver cannot interact with it.

---

### F-05: Monolithic Bridge Violates Dependency Isolation
**Severity: High**  
**Locations:**
- [`rust/src/bridge.rs`](../../rust/src/bridge.rs) (1,886 lines)

#### Rule Broken
[`application_core.md`](../architecture/application_core.md#L232-L272):
> *"Godot scene tree is single-threaded... One `GodotClass` node, the bridge, owns the core handle (command sender and event receiver)... Avoid one giant GameManager that mixes chess, UI, voice, discovery, Iroh and storage."*

#### Evidence
`bridge.rs` acts as a monolithic catch-all module containing:
1. GDExtension bindings for Godot.
2. An embedded multi-threaded Tokio runtime (`tokio::runtime::Runtime`).
3. QUIC network management and Iroh endpoint lifecycle (`IrohEndpoint`).
4. pkarr DNS rendezvous publishing and resolution (`resolve_ticket`).
5. Asynchronous network accept and dial tasks.
6. Custom wire handshake and timeout coordination.
7. Network session event loop and message stream processing.
8. Background OS threads for local AI evaluation (`LocalAiEngine`).
9. File persistence for identity seeds and binary move logs (`FileStore`).
10. Committed spike keys (`LOCAL_SEED` and `SPIKE_PEER_SEED`).
11. Blocking calls (`net.runtime.block_on`) executed directly on Godot's render thread during setup and teardown.

#### Impact
The GDExtension bridge cannot be unit tested without Godot; the network session driver cannot be tested without GDExtension; blocking runtime calls risk frame hitching on mobile devices; architectural separation of concerns is completely compromised.

---

### F-06: Network Session Leak When Leaving Game Setup
**Severity: Medium-High**  
**Locations:**
- [`godot/src/ui/app/app_root.gd#L258-L263`](../../godot/src/ui/app/app_root.gd#L258-L263)

#### Rule Broken
[`godot/docs/architecture/multiplayer_ui_lifecycle.md`](../../godot/docs/architecture/multiplayer_ui_lifecycle.md#L9-L12):
> *"Keep this separation when backend work begins: the backend should report events and receive user intent through the app layer."*  
> Leaving a session must cleanly tear down network resources.

#### Evidence
In `app_root.gd`:
```gdscript
func _on_game_setup_leave_requested(is_peer_setup: bool) -> void:
    if is_peer_setup:
        _on_p2p_requested()
    else:
        _show_home_screen()
```
`_leave_network()` is called when leaving the Multiplayer Hub or leaving the Game Screen, but is **omitted entirely** when leaving Game Setup.

#### Impact
If a player opens the "Leave game" dialog in `GameSetupScreen` and confirms, the active Iroh endpoint, background accept/dial tasks, and session driver remain alive in memory. Navigating back into the hub leaves orphaned network links running in the background.

---

### F-07: Reconnect and Resume Path in Bridge
**Status: fixed in the current implementation; device verification remains required**
**Locations:**
- [`rust/src/bridge.rs#L1639`](../../rust/src/bridge.rs#L1639)
- [`rust/src/bridge.rs#L1491-L1522`](../../rust/src/bridge.rs#L1491-L1522)

#### Rule Broken
[`application_core.md`](../architecture/application_core.md#L141-L148):
> *"With no clock, a disconnect just pauses the game. On reconnect, peers compare logs, replay any moves the other side is missing, and continue. If either side's log fails validation, the game stops with an error."*

#### Evidence and current contract
The network driver now keeps the Rust session and endpoint alive after a
transport loss. Hosts re-enter accept, guests redial the same persistent
endpoint ticket for a bounded retry window, and the bridge emits
`network_reconnecting` while the header is `DEGRADED`.

After a new link is established, both sides exchange `Msg::Resume` containing
the signed log. Existing entries must have the same hash; only a contiguous
suffix may be ingested and replayed. Invalid hashes or gaps terminate the
attempt with a visible network error. The local session remains authoritative;
the UI never invents a replacement position.

#### Impact
Transient packet loss no longer immediately terminates the game. Recovery is
silent at the session layer and visible only through the header's degraded and
recovered states. A peer that does not return before the retry bound, or whose
signed log fails validation, remains a terminal disconnect for v1.

---

### F-08: One Unidirectional QUIC Stream per Message Hazard
**Severity: Medium**  
**Locations:**
- [`rust/src/transport_iroh.rs#L134-L169`](../../rust/src/transport_iroh.rs#L134-L169)

#### Rule Broken
QUIC stream multiplexing and framing best practices.

#### Evidence
In `IrohConnection`:
```rust
async fn send(&mut self, msg: &Msg) -> Result<(), TransportError> {
    let frame = encode_frame(msg);
    let mut send = self.connection.open_uni().await...;
    send.write_all(&frame).await...;
    send.finish().map_err(...)?;
    Ok(())
}
```
Every individual message opens a new unidirectional QUIC stream, writes 4 bytes of length plus body, and finishes the stream.

#### Impact
QUIC guarantees in-order delivery *within* a stream, but streams are scheduled and delivered independently. Under packet loss, later streams can be accepted and read before earlier streams arrive. If move entries arrive out of sequence, log validation fails. Additionally, opening and closing QUIC streams for small 20-byte control messages introduces unnecessary transport overhead.

---

### F-09: Phantom Features and Disconnected Controls
**Severity: Medium**  
**Locations:**
- [`godot/src/ui/screens/game_setup/game_setup_screen.tscn`](../../godot/src/ui/screens/game_setup/game_setup_screen.tscn)
- [`godot/src/ui/screens/game/game_screen.gd#L29-L33`](../../godot/src/ui/screens/game/game_screen.gd#L29-L33)
- [`godot/src/ui/screens/multiplayer_hub/multiplayer_hub_screen.gd#L61-L63`](../../godot/src/ui/screens/multiplayer_hub/multiplayer_hub_screen.gd#L61-L63)

#### Rule Broken
[`godot/docs/HANDOVER.md`](../../godot/docs/HANDOVER.md#L150-L156):
> *"The clock is fabricated... application_core.md puts clocks out of v1... Leaving it looking real is the worst of the three."*

#### Evidence
1. **Chess960:** `VariantChoice` presents "Standard" and "Chess960". The Rust `chess_core` move generator and board parser have 0% support for Chess960.
2. **Time Controls:** `TimeChoice` offers presets ("1\|0", "3\|2", "5\|3", "Custom"). When starting a game, this selection is discarded.
3. **Fabricated Clocks:** In `game_screen.gd`, clocks remain hardcoded to `_white_seconds := 600` and decremented by a local Godot timer without core synchronization. This remains open; the opponent-name fabrication has been removed separately.
4. **Discovery Preferences:** The former toggles in `DiscoverySettingsDialog` ("Nearby", "Online") only updated a local text label and connected to no background service or persistence. They have been removed; the hub now reports discovery unavailable and directs users to invite codes.
5. **Short Invite Codes:** `transport_rendezvous.rs` implements pkarr ticket publishing and resolution, but `bridge.rs` `host_game()` only returns raw, long Iroh tickets. Short-code generation is not exposed to the UI.

#### Impact
The UI presents controls that promise non-existent functionality, creating a misleading user experience and technical debt.

---

### F-10: Inefficient Scene Teardown and GDScript FEN Parsing
**Severity: Low-Medium**  
**Locations:**
- [`godot/src/ui/screens/game/game_screen.gd#L178-L228`](../../godot/src/ui/screens/game/game_screen.gd#L178-L228)
- [`godot/src/ui/screens/game/game_screen.gd#L367-L413`](../../godot/src/ui/screens/game/game_screen.gd#L367-L413)

#### Rule Broken
[`godot/docs/HANDOVER.md`](../../godot/docs/HANDOVER.md#L274-L285):
> *"The core's FEN is still parsed in GDScript... That is a second reader of the position, in the client, beside `chess_core`."*

#### Evidence
1. On every move applied, `_rebuild_position()` removes and frees all 32 piece scenes in the 3D world, then instantiates 32 new piece scenes and reassigns their materials and transforms.
2. `game_screen.gd` parses FEN placement strings, active sides, castling rights, and en-passant squares in GDScript to calculate capture markers and castling markers.

#### Impact
Unnecessary CPU allocations on every move (limiting piece animation possibilities) and violation of the single-source-of-truth principle by re-parsing FEN in client script.

---

## Remediation Roadmap

```
Phase 1: Wire Protocol & Application Fixes
├── Extend `ingest_remote` in `app.rs` to handle Resign, DrawOffer, DrawAccept, Abort
├── Unbind `resign()` and `offer_draw()` from turn ownership in `bridge.rs`
└── Implement persistent bidirectional framing in `transport_iroh.rs`

Phase 2: Lifecycle & Handshake Decoupling
├── Split transport connection (`Connected`) from session creation (`StartGame`)
├── Restore host match configuration on GameSetupScreen (Color, Time, Rules)
├── Require explicit `SetReady` commands from players before starting game
└── Clean up network resources on `leave_setup` in `app_root.gd`

Phase 3: UI Correction & Polish
├── Fix draw offer dialog in `game_screen.gd` (dialog on receiver, not sender)
├── Expose pkarr short codes in `bridge.rs` and MultiplayerHubScreen
├── Either hide or implement real time controls / remove fabricated clocks
└── Decompose `bridge.rs` into modular network, AI, and storage services
```

---

## Follow-up from player reports

A player-visible audit was produced from device reports on 2026-10-08:
[`player_visible_defects.md`](player_visible_defects.md). It confirms every
finding above as still present, and adds detail or new findings:

- **F-01** confirmed as the cause of "setup cards show titles only" — with an
  additional layout defect this document does not cover (fixed
  `custom_minimum_size` leaves empty cards once the contents are hidden).
- **F-03** extended beyond the bridge: the same turn-ownership assumption is
  load-bearing in `game_screen.gd` in two places, so it affects captures and
  draw offers, not just the two `#[func]`s named above.
- **F-06** extended to the in-game leave path, which produces no
  opponent-visible event.
- Four findings not in this document: a string-typed `setup_kind` compared in two
  files, a guard flag that cannot fail, and two proposed gates whose absence is
  the root cause of this class of defect shipping.
