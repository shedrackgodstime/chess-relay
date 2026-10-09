# Implementation and Closure Plan

This is the active execution plan for taking Chess Relay from the current
checkpoint to a verified, predictable implementation.

It supersedes historical `DONE` labels in older phase plans until each claim is
re-verified under [Definition of Done](../standards/definition-of-done.md).
Those labels describe what a previous session believed; they are not evidence
that the current tree is protected.

## Objective

Remove contradictory implementations and false sources of truth across Rust,
Godot, the bridge, transport identity, joining, and recent-game/player data.
Then enforce the resulting contracts with tests and gates.

The target is not “a passing demo.” The target is one authoritative model whose
observable behavior remains deterministic through startup, navigation, retries,
disconnects, reconnects, persistence, and stale asynchronous work.

## Current execution order

This is the active order for the next sessions. It is deliberately narrower
than the historical phase numbering: the next item must close or clearly split
the scope currently being changed before broader cleanup begins.

### 1. Close the postgame/rematch boundary

Priority: highest; current scope.

- Diagnose the `ui_smoke_test.gd` exit `139`; the supported Godot runner is not
  green until its process exits successfully.
- Add Rust memory-transport coverage for rematch request, accept, decline,
  duplicate request, stale ID, send failure, and both peers' fresh setup
  generation.
- Add bridge/UI coverage for checkmate, draw, resignation, authenticated leave,
  unrecovered disconnect, rematch offer, and rematch decline.
- Verify the terminal barrier: no move, promotion, draw, or clock interaction
  after terminal state; review remains available; rematch is offered only when
  the authenticated peer session still permits it.

Exit condition: the postgame/rematch ledger entries are protected by local
regression tests, the supported Godot runner exits zero, and no local result
depends on timing or a second screen winning an event race. Live two-process
evidence remains a separate shipping gate.

### 2. Clean stale documentation and reconcile the contract

Priority: immediately after the current scope is protected.

- Update `godot/docs/HANDOVER.md` so it no longer presents removed mock/live
  behavior as the current implementation.
- Mark historical audit and remediation statements as historical, or update
  them with current evidence; do not leave contradictory “done” claims.
- Reconcile the active architecture documents with the postgame/rematch
  contract, current recent-peer/invite behavior, and actual verification state.
- Re-read `ref/chess-relay` result/menu behavior and preserve explicit citations
  for behavior adopted from it; do not imply the reference supplied rematch.

Exit condition: a contributor reading the handover, standards, active plan, and
relevant reference notes gets one consistent current contract and one explicit
list of unverified behavior.

### 3. Repair enforcement infrastructure

Priority: after documentation agrees with the code, before broader refactors.

- Repair `rust/deny.toml` for the installed `cargo-deny` schema and run the
  supply-chain gate.
- Record the `cargo audit` unmaintained-crate warnings and decide whether to
  replace, accept with rationale, or isolate those dependencies.
- Ensure the supported combined Godot runner and Rust commands use the exact
  locked/documented commands from the standards.
- Add regression checks for stale-generation, duplicate-event, and shutdown
  behavior required by the cross-layer standard.

Exit condition: all repository gates are executable, their failure modes are
known, and the closure ledger distinguishes passed, failed, and unavailable
checks without manual interpretation.

### 4. Remove remaining authority violations

Priority: broader correctness cleanup.

- Remove or explicitly label the out-of-v1 fabricated clock; it must not look
  authoritative while Rust owns no clock.
- Remove GDScript FEN parsing/piece tables or replace them with a documented
  Rust-owned render snapshot contract.
- Reduce local lifecycle booleans and string role values where a typed bridge
  snapshot/state can replace them without creating another mirror.
- Keep Godot limited to intent, rendering, navigation, and temporary visual
  interaction state.

Exit condition: each remaining mutable value has a named authority and every
  UI fact can be traced to a bridge snapshot/event or an explicitly local view
  concern.

### 5. Remove spike identity and finish live integration verification

Priority: shipping readiness.

- Replace or isolate committed spike identities in every path that could be
  mistaken for real peer identity, including AI/test paths.
- Run two independent desktop installations through code join, setup
  synchronization, move exchange, leave, reconnect, checkmate, and rematch.
- Repeat the applicable flow on Android, including identity reset/install
  behavior and signed export.
- Record relay/direct-path and failure-mode results separately; do not collapse
  them into one “connection works” claim.

Exit condition: bridge/integration findings have real two-process evidence and
the remaining ledger contains no `Confirmed`, `Assigned`, or unverified
shipping-critical finding.

## Rules for this execution

1. No implementation begins from an assumption. Trace the current code and
   verify the intended behavior against `docs/architecture/`, `godot/docs/`,
   `docs/standards/`, and the applicable material in `ref/`.
2. No historical `DONE` label closes a finding. Only current evidence can move
   a finding to `Verified` and `Protected`.
3. No compatibility wrapper is added merely to preserve an incoherent API.
   Breaking changes are allowed when they remove duplicate authority or a
   misleading contract.
4. Every mutable field must have one owner. Every mirror must be explicitly
   named as an observation/snapshot/cache.
5. Every asynchronous operation receives a generation/correlation identity and
   has an explicit cancellation and stale-result policy.
6. A mock may exist only behind a test seam or an explicitly labelled preview
   mode. Production UI must not present invented people, sessions, readiness,
   or network state as real data.
7. Cargo failures caused by unrelated concurrent work are recorded as external
   verification blockers, not silently treated as code findings and not treated
   as completion.

## Execution phases

### Phase 0 — Baseline and inventory

Status: `Verified` for the available local gates; live rendezvous remains a
separate integration check.

- Checkpoint current work before refactoring. Done in commit `3f8e8f2`, pushed
  to `origin/main`.
- Map every authority, mirror, command, query, event, signal, worker, and
  persistence path.
- Reconcile code with architecture, handover, standards, audits, plans, and
  `ref/`. Mark stale documentation instead of trusting it.
- Create a finding ledger with stable IDs and exact evidence.

Exit condition: no major subsystem is described as understood without a traced
source path and a stated owner.

Baseline evidence from 2026-10-08:

- Rust: complete suite passed outside the restricted socket sandbox: 84 unit
  tests, 26 integration tests, 21 doctests; 2 intentionally ignored tests.
- Godot: complete suite passed with a writable `user://`: 26 scripts parsed,
  warning drift passed, resume persistence passed, and the UI suite reported
  exactly `156 of 156` checks.
- The earlier Rust and Godot failures were environment-specific: the sandbox
  blocked Iroh UDP binding and Godot user-data writes. They are retained in the
  session record as evidence, not as code findings.

### Phase 1 — Contract reset and bridge disentangling

Status: `Observed`.

- Freeze the real command/query/event contract in Rust.
- Separate Godot translation from application orchestration, transport,
  rendezvous, persistence, and AI worker code.
- Replace strings, booleans, and implicit timing with typed lifecycle states,
  generations, revisions, and explicit results.
- Remove dead handshake paths, spike-only behavior, temporary diagnostics, and
  APIs whose names claim stronger guarantees than they provide.

Exit condition: each bridge operation has one owner, one direction, one result
contract, and one testable failure policy.

### Phase 2 — Persistent identity and endpoint authority

Status: `Implemented`; end-to-end restart verification remains open —
`IDENTITY-001`.

Current evidence: `host_game()` and `join_game()` load the same persisted
installation seed and `start_network()` binds the endpoint from it. The Rust
unit test proves seed reuse and endpoint/session identity equality; a full
application restart test is still required.

- Load or create one installation identity through one Rust-owned persistence
  path.
- Derive the session signing identity and Iroh endpoint identity from the same
  persisted key material when that is the contract.
- Bind one endpoint per live application/network owner; do not regenerate its
  identity on every screen or retry.
- Make identity rotation explicit, deliberate, and observable.
- Add tests proving restart stability, endpoint-ID/peer-ID equality, and
  generation-safe replacement of a retired endpoint.

Exit condition: restarting the app preserves identity; starting a new match
does not silently create a new identity; deliberate reset is the only rotation.

### Phase 3 — Real join-code contract

Status: `Implemented`; live rendezvous verification remains open — `JOIN-001`.

Current evidence: `host_game()` deterministically derives and publishes an
eight-character code from the persistent endpoint identity;
the Godot host card displays/copies that code; join input sends the code to the
Rust resolver. Offline shape and bridge tests pass. A live relay round trip is
still intentionally separate and is not claimed here.

- Make host creation return a typed invitation containing the short code and
  any private/internal dial information required by the owner.
- Publish and retire the invitation through the endpoint owner, with explicit
  TTL, cancellation, and failure states.
- Make join input accept the documented short-code format; keep raw tickets
  only as an intentional diagnostic/fallback contract if still needed.
- Ensure the displayed value, copied value, join field, backend resolver, and
  tests all describe the same invitation type.
- Add offline contract tests and a separately labelled live rendezvous test.

Exit condition: a host displays the generated code, a guest enters that code,
the backend resolves it, and both sides report distinct resolution, transport,
handshake, and session outcomes.

### Phase 4 — Remove invented recent/discovery state

Status: `Verified`; final protection is the store/bridge/UI regression gate —
`RECENT-001`.

Current evidence: Rust now owns a bounded, persisted recent-peer index written
only after successful network connection and exposed through the typed bridge.
Godot renders those peer IDs newest-first and distinguishes empty from
unavailable. The former `MockMultiplayerService` has been removed from the
production tree; local setup-preview behavior is exercised directly by tests
and is not wired into `AppRoot`.

Verification evidence: `RecentPeerStore` persistence/deduplication tests pass;
the rebuilt GDExtension exposes the query/status methods; and the full Godot
gate passes with the hub loading its empty recent-peer state through the bridge.

- “Recent” means local peers observed through successful network connections;
  it is not a current-presence or discovery claim.
- Put the chosen data behind a Rust-owned query/persistence contract.
- Render an honest loading, empty, unavailable, or populated state.
- Remove hardcoded recent/player names from production flow. Invite and
  incoming-player controls remain unavailable until their backend contract is
  implemented; they must not be presented as real network state.
- Refresh the index after the bridge reports a successful peer connection.
- Add persistence and empty/error/reload tests.

Exit condition: every displayed row has a real source, stable identity, defined
freshness, and an explicit unavailable/empty behavior.

### Phase 5 — Lifecycle and connection determinism

Status: `Implemented` in the bridge/UI path; end-to-end two-process coverage
remains open — `LIFECYCLE-001`.

- Separate transport, handshake, session, and presentation states.
- Subscribe before starting producers, or provide snapshot/replay semantics.
- Make disconnect, timeout, protocol failure, cancellation, and retry distinct.
- Retire workers/endpoints atomically; stale generations cannot publish facts.
- Make startup, shutdown, screen re-entry, and repeated start/stop idempotent.
- Verify the session cannot remain live-looking after its driver dies.
- Attach GameScreen observers before owned startup and synchronize borrowed
  screens from the authoritative snapshot after attachment.
- Treat a configured new match as an explicit fresh start; a finished save is
  stale for resume-for-play and is purged before the replacement session.
- Keep the transport-connected, session-created, ready, and game-started
  transitions distinct in the Godot screen flow; transport connection opens
  setup, the host owns live setup and the single Start action, the guest
  observes and auto-acknowledges, and the peer-loaded barrier opens the board.

Exit condition: event order, revision, generation, and terminal-state behavior
are covered by integration tests rather than inferred from timing.

### Phase 6 — Godot authority cleanup

Status: `Observed`.

- Make the typed bridge facade the only Godot access path.
- Remove client-side rule/state duplication: FEN parsing, piece identity tables,
  fake clocks, local lifecycle flags, and UI transitions that imply backend facts.
- Render from authoritative snapshots/events; do not advance state from
  animation completion or scene entry.
- Make all screens tolerate re-entry, delayed events, duplicate events, and
  backend failure.

Exit condition: Godot owns presentation and intent only, and every displayed
network/session fact can be traced to a current core observation.

### Phase 7 — Enforcement and closure

Status: `Blocked by confirmed local gate failure`; Rust gates pass, but the
supported Godot UI runner exits `139`, and two-process/device verification is
still open.

- Add regression tests for every confirmed finding and every boundary invariant.
- Run Rust, Godot, bridge, and integration gates independently and together;
  do not call the combined gate green when a suite process exits abnormally.
- Check test counts and failure exit codes; reject skipped/unexecuted suites.
- Update architecture and standards only when the implemented contract changes.
- Move each finding through `Implemented`, `Verified`, and `Protected`; leave
  blocked work explicitly open.

Exit condition: no confirmed finding lacks a protection mechanism, and the final
report distinguishes verified behavior from unavailable evidence.

## Current finding ledger

| ID | Finding | Status | First closure proof |
| --- | --- | --- | --- |
| `IDENTITY-001` | Network endpoint/session identity regenerates per network start | Implemented | Persistent-identity restart test + endpoint/peer equality; app restart still open |
| `JOIN-001` | Short-code implementation is not the displayed/used host contract | Implemented | Host-code → resolver contract and UI wiring; live rendezvous still open |
| `RECENT-001` | Recent/player list is hardcoded/mock data in production UI | Implemented | Rust owns version-2 recent-peer records with stable identity, latest authenticated endpoint ticket, last successful-contact timestamp, and bridge-exposed presence; Godot renders the Rust query |
| `INVITE-001` | Morgan incoming/listed-player invite UI has no live backend event contract | Implemented | Authenticated `InviteRequest`/`InviteResponse` messages, bridge signals, persistent-ticket dial, and Morgan accept/decline routing are implemented; two-process verification remains open |
| `PRESENCE-001` | Recent-peer history is not online presence | Implemented | Presence is a separate Rust-owned live observation (`online`/`offline`/`unknown`); history and ticket retention do not infer it |
| `TRANSPORT-READY-001` | Host ticket can be generated before Iroh endpoint readiness settles | Implemented | `start_network()` now performs a bounded ten-second `IrohEndpoint::wait_online()` before ticket generation; direct paths remain allowed after timeout. Full Rust suite passes |
| `DISCOVERY-001` | Discovery controls claim backend state while only changing a local label | Verified | Discovery dialog removed from production; hub explicitly displays unavailable and directs users to invite codes |
| `LABEL-001` | Game screen hardcodes an opponent name instead of observing the peer identity | Verified | Networked GameScreen receives the bridge-owned peer label; neutral fallback is used when no label exists |
| `SETUP-001` | Network setup hides shared controls and allows host board entry before guest readiness | Implemented | `LobbyHello` plus durable host `Setup` snapshots; guest is observer-only and auto-acknowledges the host start; both sides advance only through the shared readiness/game-start path |
| `LIFECYCLE-001` | Bridge/transport/session lifecycle has competing implicit states | Implemented | State transition wiring, startup-order protection, snapshot synchronization, and stale-generation tests; two-process UI integration still open |
| `SAVE-001` | New games can be hijacked by persisted or finished sessions | Verified | Explicit fresh-start contract, finished-save rejection/purge in both resume paths, and Godot AI regression; user-facing Resume action remains a separate product surface |
| `AUTHORITY-001` | Godot and Rust retain overlapping state representations | Protected locally | Clock is explicit mock-only; typed Rust piece snapshots replace GDScript FEN decoding |
| `DISCONNECT-001` | A peer disconnect left the remaining game board interactive | Implemented | GameScreen now stops clock, closes promotion, clears move affordances, rejects board/promotion/draw input, and retains the last authoritative position; Godot suite passes |
| `DISCONNECT-002` | Hub invite flow could remain stranded after peer disconnect | Implemented | Morgan outgoing/incoming flows now route disconnects to an explicit failure/ended state with recovery; Godot suite passes |
| `LEAVE-001` | Lobby/setup leave is indistinguishable from transport failure | Implemented | Retiring a network sends authenticated `Msg::Leave` with bounded acknowledgement; Rust suppresses reconnect, and Godot receives a distinct `peer_left` result |
| `POSTGAME-001` | Terminal game events had no dedicated presentation or consistent interaction barrier | Implemented | Checkmate/draw/resignation, opponent leave, and unrecovered connection loss now stop interaction and present distinct result cards; menu actions change after terminal state |
| `REMATCH-001` | Finished network games had no authoritative rematch contract | Implemented | Authenticated rematch request/response messages reset both peers through a fresh setup generation; accept/decline is bridged to the postgame UI |
| `GATE-UI-001` | Supported Godot runner exited 139 during AppRoot teardown | Protected | `AppRoot._exit_tree()` retires the bridge; full runner passes 25 scripts and 151/151 UI assertions |
| `REMATCH-VERIFY-001` | Rematch exchange lacked dedicated regression coverage | Protected locally | Memory transport covers request, accept, decline, duplicate, stale-ID rejection, reset, and both fresh generations; live two-process verification remains open |
| `SUPPLY-CHAIN-001` | Cargo deny policy is not executable with the current config schema | Protected locally | `cargo deny check` passes with explicit licenses and documented transitive advisory exceptions |
| `DOC-DRIFT-001` | Handover and remediation documents contained stale historical implementation claims | Implemented, locally reconciled | Handover and historical audit headers now point to the active closure ledger; remaining live gaps are explicit |

## Session handoff rule

At the end of every work session, update this plan with:

- files changed;
- findings moved and the evidence for each move;
- checks actually run and their result;
- checks unavailable or externally blocked;
- the next smallest closure action.

No session may end with a broad “done” statement while this ledger contains a
`Confirmed`, `Assigned`, or `Implemented` finding.

## Latest session handoff — 2026-10-09

Changed the Rust recent-peer record/query, authenticated invite protocol,
explicit leave protocol, presence signals, endpoint readiness path, Godot
bridge facade, Morgan hub flow, invite host/guest setup roles, terminal
game-over presentation, and authenticated rematch flow. This session also
closed the local authority/policy findings: mock-only clocks, typed Rust-owned
piece snapshots, per-installation spike role derivation, and executable
`cargo-deny` policy.

Verification completed:

- `cargo fmt`, `cargo test --locked --all-targets`: 86 unit tests passed, 2 ignored;
  app/integration suites also passed (23 tests).
- `cargo clippy --all-targets -- -D warnings`: passed.
- `RUSTDOCFLAGS='-D warnings' cargo doc --locked --no-deps`: passed.
- `cargo deny check` from `rust/`: passed; duplicate dependency versions are
  warnings, and the two transitive unmaintained advisories are explicit policy
  exceptions.
- Godot parse/warning-drift passed; all 25 scripts and 151 UI assertions ran,
  including the game-over-card checks and typed piece rendering, and the
  supported runner exited zero.
- `git diff --check`: passed.

Still unavailable here: two independent running installations exercising the
full Iroh invite/accept/rematch flow over the relay/direct-path matrix, and
Android on-glass verification. Those are not inferred from local
memory-transport or Godot assertions.
