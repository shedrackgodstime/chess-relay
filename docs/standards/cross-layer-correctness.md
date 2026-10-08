# Cross-Layer Correctness Standard

Binding standard for Rust, Godot, and the boundary between them.

This document turns the project's architecture into rules that can be reviewed,
tested, and enforced. It is intentionally strict: a UI that looks correct is
not evidence that the underlying state is correct.

The standard is informed by Microsoft's [Pragmatic Rust
Guidelines](https://microsoft.github.io/rust-guidelines/agents/all.txt),
especially its rules on strong types, errors, panics, FFI translation,
structured logging, mockable I/O, integration tests, and static verification.
The existing [Rust standard](rust-standards.md) remains authoritative for
Rust-specific API and crate rules.

## The governing law

Every piece of state has exactly one authority. Every other copy is an
explicitly labelled observation.

Rust owns chess rules, session lifecycle, move history, application state,
protocol decisions, and transport state. Godot owns presentation, input,
animation, navigation, and temporary interaction state. The bridge translates
commands, queries, snapshots, and events; it owns no domain truth.

Network uncertainty cannot be removed. Ambiguous ownership, stale results,
silent fallback, event loss, and race-dependent presentation can be removed.

## Non-negotiable rules

### 1. One authority per state

- The owner is named in the architecture and in the type/module that stores it.
- A mirror must be called a snapshot, view model, cache, or observation; never
  `state` when it is not authoritative.
- Godot must not calculate legal moves, infer whose turn it is, advance clocks,
  decide game completion, or reconstruct session lifecycle.
- If a value can be derived from an authoritative snapshot, do not maintain a
  second mutable copy of it.
- A UI control is not proof that an action is legal. The core accepts or rejects
  the command and the UI renders the resulting fact.

### 2. State machines are explicit

- Use enums or tagged types for lifecycle state. Do not encode a state machine
  with unrelated booleans, nullable fields, magic strings, or combinations of
  flags that permit impossible states.
- Game state and connection state are independent state machines. A game may be
  `Playing` while the connection is `Reconnecting`; a finished game may be
  `Disconnected`.
- Every transition has a documented source state, triggering command/event,
  destination state, and rejected cases.
- Terminal states are durable. After `Finished`, `Aborted`, or `Failed`, later
  moves and stale network events are rejected or ignored deterministically.
- No transition is performed by UI animation, signal order, or object lifetime.

### 3. Commands, facts, and queries stay separate

- A command expresses intent (`SubmitMove`, `OfferDraw`, `Reconnect`). It does
  not contain UI instructions.
- An event reports a fact that already happened (`MoveApplied`, `PeerDisconnected`,
  `GameEnded`). It does not ask the UI to make a decision.
- A query reads an authoritative snapshot without changing it.
- Command handling is atomic: validate, mutate the owner, and publish the
  resulting facts as one logical operation. Never publish an event for a
  mutation that may still be rolled back.
- Every rejected command returns a typed, inspectable error. No silent no-op,
  implicit retry, or fallback to a fresh session.

### 4. Event delivery is deterministic

- Subscribers are connected before a producer is started.
- Startup must expose a snapshot or replay mechanism; correctness must not
  depend on a subscriber winning a race against the first event.
- Events have a defined ordering and, for session events, a monotonically
  increasing revision/sequence number.
- A late subscriber synchronizes from a snapshot/replay boundary before it
  renders live events.
- Handlers are idempotent or reject duplicate/out-of-order revisions. No
  handler assumes that an event is delivered exactly once unless the contract
  explicitly guarantees it.
- Events from a retired connection/session generation are ignored and logged as
  stale; they cannot mutate current state.
- The bridge drains external events on the Godot thread. Rust worker threads
  never call Godot APIs.

### 5. Connection lifecycle is explicit

- Separate transport state (`Disconnected`, `Connecting`, `Connected`,
  `Reconnecting`, `Failed`) from session state (`Created`, `Ready`, `Playing`,
  `Finished`, etc.).
- `Connected` means only that the transport is available. It does not mean that
  protocol negotiation, identity, session restoration, or readiness completed.
- A peer is not announced as ready until the handshake and required session
  initialization have succeeded.
- Every connection attempt has an identity/generation. Completion, timeout,
  failure, and disconnect events must carry or resolve against that generation.
- Retiring an attempt cancels its work, closes its resources, and makes its
  later results harmless. Retiring is idempotent.
- A dead worker must not leave a live-looking session, endpoint, or command
  path behind.
- Retry is an explicit state transition with bounded policy and observable
  reason. It is never an accidental consequence of a dropped task.
- Disconnect, protocol failure, timeout, and user cancellation remain distinct
  facts even if they share a UI destination.

### 6. Startup and shutdown are symmetric

- Construction allocates inert objects only. Starting work is explicit.
- Startup order is: create owner, attach observers, initialize snapshot, then
  start workers/transport.
- Shutdown order is: stop accepting commands, cancel workers, drain or discard
  only according to the documented policy, close transport, then release the
  owner.
- Start and stop are safe to call more than once and produce no duplicate
  workers, signals, subscriptions, or connections.
- A screen leaving the tree cannot silently destroy application state that is
  meant to survive navigation. Ownership and lifetime must be named.

## Rust rules

The full Rust rules are in [rust-standards.md](rust-standards.md). These rules
are the cross-layer minimum:

- Use strong types for IDs, revisions, generations, squares, players, sides,
  lifecycle states, and protocol versions. Do not pass unvalidated strings or
  bare integers when a domain type can enforce the invariant.
- Return `Result` for invalid input, I/O, protocol errors, disconnects, and
  expected lifecycle rejection. Do not use `unwrap`/`expect` on network,
  storage, or Godot-provided input.
- Panic only for an internal invariant that proves a programming bug. The panic
  message must identify the invariant and relevant values. Never use panic as a
  control-flow protocol.
- Keep unsafe code isolated to the FFI necessity, with a local safety proof.
  There is no unsafe code in chess/session/contract logic.
- Keep core logic independent of Godot and Iroh. Translate at the boundary;
  do not leak dependency types through public core APIs.
- Prefer immutable snapshots and explicit ownership over shared mutable global
  state. No mutable statics for session, connection, or UI state.
- Use structured logs with stable fields such as `session_id`, `peer_id`,
  `attempt_id`, `generation`, `revision`, `event`, and `reason`. Production
  code does not use `println!` for diagnostics.
- Make transport, storage, clocks, and task scheduling injectable or mockable.
  Tests must be able to force delay, duplicate delivery, reordering, timeout,
  disconnect, malformed input, and worker failure.
- Integration tests assert observable contracts, not implementation details.
  Every lifecycle transition and bridge protocol rule needs at least one test
  for success, rejection, and stale/duplicate input where applicable.
- Public types implement `Debug`; user-facing values implement `Display`.
  Public fallible APIs document errors and panics.

## Godot rules

- Godot is a client of the application core, never a second application core.
- GDScript must not contain chess legality, session authority, network retry
  policy, authoritative clocks, move-log mutation, or protocol interpretation.
- Use typed GDScript. Treat unsafe property/method access, unsafe casts,
  incompatible branch types, integer division in state calculations, and
  untyped declarations in new code as defects.
- Use enums and typed records for UI state. Avoid booleans such as
  `is_connected`, `is_ready`, and `has_game` when they represent one lifecycle
  machine.
- Screens render from a bridge snapshot and subsequent events. They do not
  assume that entering the scene means the backend is ready.
- Connect signals before calling `start()`, and make each connection explicit
  and idempotent. A signal emitted before a listener is attached is a bridge
  contract failure, not a UI timing issue.
- Handlers must tolerate repeated refreshes, duplicate events, scene re-entry,
  and delayed events. Do not use animation completion as a state transition.
- UI failure states must be driven by typed backend facts. Do not turn every
  failure into `Disconnected`, and do not silently show a new empty game after
  restore failure.
- Godot tests must exercise real user-visible interactions and inject delayed,
  failed, duplicated, and out-of-order backend responses. A test that only
  checks that a node exists is not a connection or state test.
- No Rust worker, callback, or thread may touch a Godot object directly. All
  cross-thread data is queued and applied on the Godot thread.

## Bridge and protocol rules

- The bridge exposes a small, versioned contract of commands, queries,
  snapshots, events, and typed errors.
- Cross-boundary payloads contain portable data only: IDs, enums represented by
  a documented stable form, numbers with documented units, strings, arrays, and
  maps with documented keys. Never expose Rust ownership, pointers, internal
  handles, or dependency types to GDScript.
- Each event schema documents required fields, units, ordering, revision, and
  whether it is replayable or terminal.
- Snapshot and event semantics must agree: a snapshot declares the revision it
  represents, and events advance it. The UI must never combine fields from
  unrelated revisions.
- Protocol versions are explicit in the first handshake message. Unknown
  versions and unknown required fields fail clearly; they do not fall back to a
  guessed interpretation.
- Serialization/deserialization is a translation layer. It does not decide
  chess legality, session permissions, or connection policy.
- One bridge instance owns one core handle and one event-consumer path per
  application session. Multiple screens must share that owner instead of
  starting competing bridge sessions.
- Command submission returns an acceptance/rejection result or a documented
  asynchronous correlation ID. It must never imply success merely because a
  command was queued.
- Correlation IDs, session IDs, attempt generations, and revisions are never
  fabricated by Godot. The authority creates them and the bridge preserves
  them.

## Enforcement gates

Every change touching Rust, Godot, or the bridge must satisfy the applicable
gates below. Cargo failures caused by unrelated work in another agent do not
change these rules, but they must be reported separately from audit findings.

- Rust: `fmt`, Clippy with warnings denied, locked tests, documentation
  warnings denied, and integration tests, as defined by
  [quality-gates.md](quality-gates.md).
- Godot: per-file parse checks, the committed warning-key policy, and the full
  headless suite. No test runner may report success when a test failed to run.
- Boundary: contract tests for startup ordering, snapshot/revision alignment,
  duplicate/out-of-order events, stale generations, terminal-state rejection,
  disconnect/reconnect, and worker shutdown.
- Review: every new mutable field must name its owner; every new event must
  state ordering/replay/terminal semantics; every retry must state its
  cancellation and generation policy.
- Documentation: update this standard or the architecture contract when an
  ownership, lifecycle, event, or payload rule changes. Code and docs must not
  describe different authorities.

## Contributor checklist

Before opening a change, answer these questions in the review description:

- What is the authoritative owner of every new state value?
- What are the valid states and transitions, including rejection and terminal
  cases?
- Can startup, retry, disconnect, scene re-entry, duplicate delivery, or stale
  completion change the result?
- What snapshot/revision does the UI render, and how does it resynchronize?
- Which failures are user input errors, transport errors, protocol errors, and
  internal bugs?
- What test proves the failure path and the race/stale path?
- Does the bridge expose only documented portable data?

If any answer is “the UI will probably…” or “the event should arrive first,” the
contract is underspecified and the change is not ready.
