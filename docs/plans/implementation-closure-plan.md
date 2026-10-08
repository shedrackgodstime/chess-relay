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

- Rust: complete suite passed outside the restricted socket sandbox: 83 unit
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

Current evidence: `host_game()` generates and publishes a six-character code;
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

Status: `Implemented` for removing fabricated rows; authoritative data source
remains open — `RECENT-001`.

Current evidence: `MultiplayerHubScreen._populate_mock_players()` inserts four
hardcoded rows; `MockMultiplayerService` fabricates invites, incoming players,
and readiness.

- Decide and document the real meaning of “recent”: local completed/joined
  sessions, discovered peers, or both. They are different data sets.
- Put the chosen data behind a Rust-owned query/persistence contract.
- Render an honest loading, empty, unavailable, or populated state.
- Remove hardcoded recent/player names from production flow. The separate mock
  invite/readiness flows remain explicitly open until their backend contract is
  implemented; they must not be presented as real network state.
- Until the source exists, render an explicit empty state instead of pretending
  that the feature is populated.
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
- Keep the transport-connected, session-created, ready, and game-started
  transitions distinct in the Godot screen flow; transport connection opens
  setup, host starts the session, guest marks its assigned side ready, and only
  `game_started` opens the board.

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

Status: `Not run`.

- Add regression tests for every confirmed finding and every boundary invariant.
- Run Rust, Godot, bridge, and integration gates independently and together.
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
| `RECENT-001` | Recent/player list is hardcoded/mock data in production UI | Confirmed | Real query/persistence source + empty/error tests |
| `LIFECYCLE-001` | Bridge/transport/session lifecycle has competing implicit states | Implemented | State transition wiring + stale-generation tests; two-process UI integration still open |
| `AUTHORITY-001` | Godot and Rust retain overlapping state representations | Observed | Authority matrix + removal of duplicate mutable state |

## Session handoff rule

At the end of every work session, update this plan with:

- files changed;
- findings moved and the evidence for each move;
- checks actually run and their result;
- checks unavailable or externally blocked;
- the next smallest closure action.

No session may end with a broad “done” statement while this ledger contains a
`Confirmed`, `Assigned`, or `Implemented` finding.
