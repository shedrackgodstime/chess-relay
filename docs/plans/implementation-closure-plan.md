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

Status: `Implemented`; baseline verification has failures.

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

- Rust: 81 passed, 1 failed, 2 ignored. The failing test is
  `bridge::tests::retire_completes_with_pending_accept`; its Iroh bind is
  unavailable in this environment.
- Godot: parsing and warning drift pass, but the full run is not clean: resume
  persistence has four failures and the runner reports `156 of 147 checks ran`.
- Godot verification is available through `/home/kristency/.local/bin/godot`,
  but its log directory reports a separate `user://logs` write failure.

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

Status: `Implemented`; integration verification remains open — `IDENTITY-001`.

Current evidence: `start_network()` generates a new random seed every time and
calls `bind_with_seed(seed)`. The persisted identity used by
`start_resumable()` is not used by network host/join.

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

Status: `Confirmed` — `JOIN-001`.

Current evidence: `transport_rendezvous.rs` implements code resolution, but
`bridge.rs::host_game()` returns a raw ticket and the Godot UI labels/copies it
as a ticket. The UI does not receive a generated short code.

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

Status: `Observed`; informed by `docs/audits/connection-and-source-of-truth-audit.md`.

- Separate transport, handshake, session, and presentation states.
- Subscribe before starting producers, or provide snapshot/replay semantics.
- Make disconnect, timeout, protocol failure, cancellation, and retry distinct.
- Retire workers/endpoints atomically; stale generations cannot publish facts.
- Make startup, shutdown, screen re-entry, and repeated start/stop idempotent.
- Verify the session cannot remain live-looking after its driver dies.

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
| `IDENTITY-001` | Network endpoint/session identity regenerates per network start | Implemented | Persistent-identity restart test + endpoint/peer equality |
| `JOIN-001` | Short-code implementation is not the displayed/used host contract | Confirmed | Host-code → resolve-code → join integration test |
| `RECENT-001` | Recent/player list is hardcoded/mock data in production UI | Confirmed | Real query/persistence source + empty/error tests |
| `LIFECYCLE-001` | Bridge/transport/session lifecycle has competing implicit states | Observed | State transition table + stale-generation integration tests |
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
