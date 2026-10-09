# Full codebase audit — 2026-10-09

This audit records the current worktree after reviewing the project source,
architecture and standards documents, `godot/docs/`, `ref/`, Rust, Godot, the
bridge, protocol, persistence, lifecycle paths, and available verification
commands.

The worktree was already dirty before this audit. This audit added no code
changes and does not treat a passing local suite as proof of live multiplayer
integration.

## Audit authority

The review was checked against:

- `docs/standards/definition-of-done.md`
- `docs/architecture/application_core.md`
- `docs/standards/rust-standards.md`
- `docs/standards/cross-layer-correctness.md`
- `godot/docs/architecture/multiplayer_ui_lifecycle.md`
- `godot/docs/architecture/game_setup.md`
- `godot/docs/HANDOVER.md`
- `ref/chess-relay/` lobby, game, HUD, protocol, and result behavior

The reference project was used as a behavioral reference, not as authority
over the current Rust application contract.

## Verification performed

| Check | Result |
| --- | --- |
| Godot parse and warning drift | Passed; 25 scripts checked |
| Godot scenario suite | Passed; 50 checks |
| Godot UI smoke suite | Passed; 151/151 checks |
| Rust locked tests | Passed; 86 passed, 2 ignored |
| Rust integration tests | Passed |
| Rust Clippy | Passed with `-D warnings` |
| Rust formatting | Passed |
| Rust documentation | Passed with `RUSTDOCFLAGS='-D warnings'` |
| `cargo deny check` | Passed; duplicate versions remain warnings |
| `cargo audit` | Passed with two accepted unmaintained transitive warnings |
| `git diff --check` | Passed |

The two `cargo audit` warnings are:

- `RUSTSEC-2023-0089`, `atomic-polyfill 1.0.3`
- `RUSTSEC-2024-0436`, `paste 1.0.15`

They are transitive dependencies currently accepted explicitly in
`rust/deny.toml`; they are not security-vulnerability failures.

## Findings summary

| ID | Severity | Status | Finding |
| --- | --- | --- | --- |
| `AUDIT-STARTUP-001` | High | Confirmed | Network startup blocks the Godot scene thread |
| `AUDIT-RESUME-001` | High | Confirmed | Network application restart does not restore the saved session |
| `AUDIT-INVITE-RECONNECT-001` | High | Confirmed | Recent-peer invitation reconnect uses the wrong handshake mode |
| `AUDIT-REMATCH-001` | High | Confirmed | Rematch is not restricted to terminal sessions |
| `AUDIT-PRESENCE-001` | Medium | Confirmed | Ordinary disconnect does not update recent-peer presence to offline |
| `AUDIT-AUTH-001` | Medium | Confirmed | Readiness and setup messages trust claimed peer fields |
| `AUDIT-TIME-001` | Medium | Confirmed | Time controls remain selectable although time is not implemented |
| `AUDIT-FEN-001` | Medium | Confirmed | Godot still parses FEN metadata for en-passant presentation |
| `AUDIT-DOC-001` | Medium | Confirmed | Current standards and closure documents contain stale claims |
| `AUDIT-LIVE-001` | Shipping gate | Unavailable | Independent desktop, relay, Android, and live-loss evidence is missing |

## Detailed findings

### `AUDIT-STARTUP-001` — Network startup blocks the Godot scene thread

Status: `Confirmed`

Location:

- `rust/src/bridge.rs:546`
- `rust/src/bridge.rs:630`
- `rust/src/bridge.rs:672`
- `rust/src/bridge.rs:718`
- `rust/src/bridge.rs:2015-2031`
- `rust/src/bridge.rs:575-577`

Expected:

- Godot-facing calls return promptly.
- Endpoint binding, relay readiness, and rendezvous publication happen on a
  worker/runtime path.
- The UI receives explicit connecting, ready, or failed events.

Actual:

- `host_game`, `join_game`, `start_presence`, and `invite_peer` call
  `start_network()` synchronously from `#[func]` methods.
- `start_network()` calls `runtime.block_on(endpoint.wait_online(...))` with a
  ten-second timeout.
- `host_game()` then calls `publisher.block_on(publish_once(...))` before
  returning the generated code.

Impact:

- Desktop hosting can appear slow or frozen.
- Android can fail or appear unable to host while the main thread is blocked.
- The observed “could not start hosting” and slow desktop behavior are
  consistent with this source path.

Required protection:

- Move endpoint startup and publication behind a generation-owned worker.
- Return a typed pending result immediately.
- Emit success/failure snapshots through the existing bridge event queue.
- Add a test proving the Godot-facing call does not wait for relay readiness.

### `AUDIT-RESUME-001` — Network application restart does not restore the saved session

Status: `Confirmed`

Location:

- `rust/src/bridge.rs:603-651`
- `rust/src/bridge.rs:2015-2056`

Expected:

- A persisted installation identity remains stable.
- Rejoining after an application restart loads the local signed move log and
  resumes the network session.

Actual:

- `join_game()` loads the identity seed but does not load a saved move log.
- `start_network()` unconditionally creates `App::with_local(secret)`.
- The network path therefore starts with an empty application session after a
  process restart.

Impact:

- Identity persistence works independently, but session persistence does not.
- The v1 requirement “resume after disconnect or restart” is only partially
  implemented.

Required protection:

- Define the network save path and load policy explicitly.
- Restore and validate the local log before dialing or after authenticated
  handshake, depending on the chosen contract.
- Add a restart test using two application instances and a persisted log.

### `AUDIT-INVITE-RECONNECT-001` — Recent-peer invitation reconnect uses the wrong handshake mode

Status: `Confirmed`

Location:

- `rust/src/bridge.rs:2157-2159`
- `rust/src/bridge.rs:2173-2276`
- `rust/src/bridge.rs:2457-2466`

Expected:

- After a recent-peer invitation is accepted, the connection becomes a normal
  game session.
- A later transport reconnect follows the game resume handshake.

Actual:

- The host presence endpoint always runs `AcceptMode::Invite`.
- After accepting the invitation, the host enters `drive_session`, but when
  the connection ends, `accept_task` loops back to `drive_incoming_invite`.
- The reconnecting guest enters `drive_session` and sends game-session
  messages such as `Resume`.
- The host invite path expects another `InviteRequest` and rejects the game
  resume sequence.

Impact:

- Recent-peer/Morgan invitations can work once and then fail to reconnect.
- This is separate from short-code host/join reconnect behavior.

Required protection:

- Promote an accepted invitation to a persistent game-session accept mode, or
  route reconnects through a session registry keyed by authenticated peer.
- Add an integration test covering invite, accepted game, disconnect, and
  resume.

### `AUDIT-REMATCH-001` — Rematch is not restricted to terminal sessions

Status: `Confirmed`

Location:

- `rust/src/bridge.rs:780-805`
- `rust/src/bridge.rs:2940-2978`

Expected:

- Rematch is available only after checkmate, resignation, draw, or another
  terminal result.
- Accepting a rematch cannot reset an active game.

Actual:

- `request_rematch()` checks only whether a network exists.
- `Msg::RematchRequest` stores a pending request without checking the session
  state.
- Accepting the request calls `reset_for_rematch()` immediately.

Impact:

- A stale UI event or remote request can reset a live match.
- The rematch contract is not fully enforced by the Rust authority.

Required protection:

- Require `SessionState::Finished` before sending, accepting, or processing a
  rematch request.
- Reject duplicate, simultaneous, and non-terminal rematch attempts.
- Add a regression test proving an active game cannot be reset.

### `AUDIT-PRESENCE-001` — Ordinary disconnect does not update presence to offline

Status: `Confirmed`

Location:

- `rust/src/bridge.rs:2493-2535`
- `rust/src/bridge.rs:1556-1565`

Expected:

- A recent peer with a live connection is shown online.
- When that live connection closes, the row transitions to offline or unknown.
- The timestamp remains available as historical information.

Actual:

- `NetNote::Disconnected` updates network lifecycle to `lost` but does not
  update the peer's `PeerPresence`.
- `PeerPresence::Offline` is emitted for failed outgoing invitation dials, not
  for ordinary connection loss.

Impact:

- The recent-peer list can continue displaying an online indicator after the
  peer has disconnected.
- Presence becomes stale until another invite attempt or a later connection.

Required protection:

- Associate the disconnected note with the authenticated remote peer.
- Emit one offline transition per active connection generation.
- Test connected → disconnected → offline behavior.

### `AUDIT-AUTH-001` — Readiness and setup messages trust claimed peer fields

Status: `Confirmed`

Location:

- `rust/src/bridge.rs:3074-3100`
- `rust/src/bridge.rs:3152-3175`

Expected:

- Wire messages are authenticated by transport identity and validated against
  the session role before mutating session state.
- A guest cannot claim to be the host or alter host-owned setup.

Actual:

- `Msg::Ready { peer }` passes the claimed `peer` directly into
  `Command::NotePeerReady`.
- The code does not first require `peer == remote_peer`.
- `Msg::Setup` is accepted without checking `host_role`; it only validates the
  variant string.

Impact:

- A malformed or hostile peer can mark the wrong participant ready.
- Setup authority is enforced in the UI path but not strictly at the protocol
  boundary.

Required protection:

- Bind every peer-bearing wire field to the authenticated transport peer.
- Reject guest-originated setup updates.
- Add malformed-role and forged-readiness tests.

### `AUDIT-TIME-001` — Time controls remain selectable without implementation

Status: `Confirmed`

Location:

- `godot/src/ui/screens/game_setup/game_setup_screen.gd:67-74`
- `godot/src/ui/screens/game_setup/game_setup_screen.gd:203-210`
- `godot/src/ui/screens/game_setup/game_setup_screen.gd:265-274`

Expected:

- A selectable setting affects the authoritative match, or is explicitly
  labeled as preview/mock and cannot be mistaken for a real rule.

Actual:

- The setup screen offers multiple time controls and custom values.
- The values are synchronized as lobby metadata.
- Rust starts a standard untimed game and the clock is intentionally static
  mock furniture.

Impact:

- Players can reasonably believe they selected a time control that has no
  effect.
- This violates the project rule against phantom features.

Required protection:

- Hide time controls for v1, or label them as preview-only and disable the
  misleading start contract.

### `AUDIT-FEN-001` — Godot still parses FEN metadata

Status: `Confirmed`

Location:

- `godot/src/ui/screens/game/game_screen.gd:410-421`

Expected:

- Rust exposes presentation facts needed by Godot through a typed bridge
  snapshot.
- Godot does not parse rule-bearing FEN fields.

Actual:

- Piece rendering and occupancy now use Rust-owned `position_pieces()` facts.
- `_capture_squares()` still splits FEN and reads field 4 to identify the
  en-passant square.

Impact:

- The main duplication was removed, but the cross-layer authority rule is not
  completely enforced.

Required protection:

- Add en-passant state to the Rust-owned position snapshot or expose a typed
  `en_passant_square()` bridge query.
- Remove the remaining FEN field parsing from Godot.

### `AUDIT-DOC-001` — Current documentation contains stale claims

Status: `Confirmed`

Location:

- `docs/plans/implementation-closure-plan.md:294-298`
- `docs/standards/quality-gates.md:526-528`

Expected:

- Current standards and active plans describe the current worktree.
- Historical audits are clearly separated from active status.

Actual:

- The closure plan still says the supported Godot runner exits `139`, although
  the current runner passes.
- The quality-gates document still says `protocol.rs` is an empty placeholder,
  although it contains the active wire protocol.

Impact:

- Contributors and agents can make decisions from false evidence.
- The documentation itself becomes another inconsistent source of truth.

Required protection:

- Mark the obsolete sections historical or update them with current evidence.
- Keep the active closure ledger as the sole current status source.

### `AUDIT-LIVE-001` — Live integration evidence is unavailable

Status: `Unavailable`, not closed

Missing evidence:

- Two independent desktop installations through short-code join.
- Relay and direct-path behavior.
- Setup synchronization on two real clients.
- Move exchange after both sides enter the game.
- Authenticated leave and ordinary disconnect behavior.
- Reconnect and signed-log resume after network loss.
- Recent-peer invitation acceptance and reconnect.
- Checkmate, rematch, and decline on two clients.
- Android host, join, identity reset, reconnect, and rematch behavior.

The local Rust memory tests and Godot headless tests do not provide this
evidence. Under `docs/standards/definition-of-done.md`, these findings cannot
be marked `Verified`, `Protected`, or done until the required environments are
available.

## Reference comparison

The review of `ref/chess-relay` confirms these useful behavioral expectations:

- The create-game surface prioritizes the invitation code and explicit waiting
  state.
- The game screen renders from the authoritative game position rather than
  letting views mutate board state independently.
- Terminal results disable further moves and expose a dedicated result state.
- Menu actions differ between active and terminal games.
- The reference protocol treats malformed or mismatched messages as invalid and
  separates transport from game state.

The current project has adopted several of these patterns, but the live Rust
bridge remains the actual multiplayer contract. The reference does not prove
the current Iroh implementation.

## Audit conclusion

The local implementation is testable and the available local gates pass, but
the audit is not closed. There are 9 confirmed implementation/documentation
findings and 1 unavailable shipping verification gate.

The next implementation order should be:

1. Move network startup and rendezvous publication off the Godot thread.
2. Define and implement network-session persistence/resume after restart.
3. Unify accepted recent-peer invitations with the normal reconnect session
   path.
4. Enforce terminal-state and authenticated-peer checks in Rust.
5. Correct presence transitions and remove remaining FEN parsing.
6. Remove or clearly mark unused time controls.
7. Reconcile active documentation.
8. Run two-process desktop and Android verification.

