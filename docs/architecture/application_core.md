# Application Core

Chess Relay has a Rust application core that owns everything that must stay correct regardless of what draws the board or moves the bytes: chess rules, sessions, the move log, and the contract clients talk to.

Godot is the main client. It renders and takes input. It is not the authority on anything.

The same application core should work unchanged with other clients and adapters: AI players, MCP agents, a CLI, tests, and remote peers. Iroh is the P2P transport, and nothing in the chess or session logic should know it exists.

```text
 Godot      AI      MCP      CLI
   \         |       |       /
    +--------+-------+------+
                  |
                  v
          Application API
        (commands / queries / events)
                  |
     +------------+-------------+
     |            |             |
   Game        Presence    Communication
     |         (later)      (voice, later)
  Session
     |
Chess Core
```

Remote peers don't call the Application API directly. They arrive through the network path:

```text
Remote peer <-> Iroh <-> Transport <-> Protocol <-> Application API
```

### Terms

- **Application core:** the whole Rust side: application API, session, move log, chess core, protocol, and supporting pieces.
- **Chess core:** only the pure chess domain inside it.

An unqualified "the core" is ambiguous, so use one of these two names.

This doc defines who owns what and how the pieces talk. It does not define a file layout. Start with a few modules and split only when a real boundary forces it.

---

## v1 scope

**In:**

- Chess core with full rules
- Session lifecycle
- Application contract (commands, queries, events)
- Two peers playing over Iroh
- Signed move log, with resume after disconnect or restart
- Draw offers, resignation, abort
- Godot bridge
- Desktop and mobile from the start; mobile is a hard requirement, not a later port. Android is the first mobile target. iOS is verified afterward, by someone with a Mac and an iOS device

**Out, but planned for:**

- Voice (see [Voice](#voice-planned))
- Presence and nearby discovery
- Signals (rematch, reactions)
- Clock (see [Clock](#clock-reserved))

**Out, and not planned:**

- Cheating and engine-assistance prevention
- Takebacks

---

## Principles

**Rust owns correctness.** Move legality, game state, session lifecycle, results, and the move log live in Rust. Godot never keeps its own authoritative copy.

**Godot owns presentation.** Rendering, input, animation, UI state. It sends intent in and gets facts back. It never touches Rust domain objects directly.

**The caller doesn't matter.** A move from a mouse click, an AI, an MCP agent, a CLI, or a remote peer is the same `SubmitMove` command. Chess core can't tell the difference.

**Transport is an adapter.** Local games, AI games and tests work with no network. Iroh only appears once a peer is on the other end.

---

## The contract

Clients talk to the core through three things.

- **Commands** are intent: `StartGame`, `SetReady`, `SubmitMove`, `Resign`, `OfferDraw`, `AnswerDraw`, `Abort`.
- **Queries** read state without changing it: `GetGameState`, `GetSessionState`, `GetMoveLog`.
- **Events** are facts that already happened: `GameStarted`, `MoveApplied`, `MoveRejected`, `ReadyChanged`, `GameEnded`, `PeerDisconnected`, `PeerReconnected`.

These names are examples, not a final API.

Commands and events never contain UI instructions. A command is `SubmitMove`, not `OpenPromotionMenu`. An event is `PeerDisconnected`, not `ShowDisconnectPopup`. What to show is Godot's call.

The application core's shape is a plain function:

```text
handle(command) -> Result<Vec<Event>, Error>
```

Local play calls this directly and gets events back immediately. Events that originate outside the frame loop (a remote move, a disconnect) arrive through a channel. See [Godot integration](#godot-integration).

---

## Core components

### Chess core

The innermost layer. It knows chess and nothing else.

It owns the board, pieces, moves, legal move generation, validation, check, checkmate, stalemate, castling, en passant, promotion, draw rules, the result, and the position history those rules need.

It must not know about Godot, Iroh, networking, AI, MCP, databases, or anything UI. It is deterministic and testable on its own.

### Session

A chess position isn't a match. The session wraps a game with participants and roles, configuration, readiness, lifecycle, what each side may do right now, and the final result.

```text
Created -> SettingUp -> Ready -> Playing -> Finished
```

On a move, the session checks the move is allowed right now, asks chess core whether it's legal, appends it to the move log, and emits `MoveApplied` or `MoveRejected`.

The **host** is the peer that created the session. That role means two things: it sets the configuration and sides, and it would be the timekeeper if a clock is ever added. It has no special power over moves.

### Move log

Both peers run the same deterministic core and validate every move themselves. Agreement is recorded in a signed, hash-linked log.

- The first entry fixes the session: protocol version, configuration, both peer IDs, and which side each plays.
- Each move entry holds the move, the hash of the previous entry, and the mover's signature (their Iroh key).
- The opponent validates the move with the core and co-signs it. A move is **agreed** once both signatures are on it.

This gives us a tamper-evident history that both peers hold identically, which also makes reconnects, resuming, replays, and PGN export cheap.

**Ownership:** chess core owns the position and history that chess rules need (repetition, fifty-move rule, and so on). Session owns the move log: the signed, agreed match record used for sync, resume, and replay. They are different data structures and may overlap in content.

What it can't do is settle a disagreement. With two peers there is no majority, so the log can detect that the peers disagree, not decide who is right. For chess moves that's fine, because the core is deterministic and a disagreement means a bug or a bad peer, and the game stops. It is also exactly why the clock can't be solved by signatures (see below).

### Disconnects and resuming

With no clock, a disconnect just pauses the game. On reconnect, peers compare logs, replay any moves the other side is missing, and continue. If either side's log fails validation, the game stops with an error.

Without a clock, the only ways to end a game early are resign, abort, and an agreed draw. A peer that never comes back leaves the game unfinished, which is acceptable for v1.

If a game must survive an app restart, each peer saves the move log to a local file and loads it on resume. That's the only storage v1 needs, and it sits behind a small interface, never inside chess core.

### Offers

Draw offers (and later, rematch) are a request/answer exchange in the protocol: one side sends an offer, the other answers. They are session actions, not chess rules. Takebacks are out of v1.

### Protocol and transport

Protocol is the boundary between application commands and events and their wire representation. For networked communication it sits between the application and transport, in both directions. It is not another application subsystem. It covers what crosses a process or device boundary: log entries, offers, handshake, versions. It never decides whether a move is legal.

```text
wire message -> protocol type -> application command -> domain operation
```

Keeping those steps separate means wire format choices don't leak into the chess domain, and protocol versions can change without touching the engine.

Pick a serialization early (serde with a compact binary format) and put a **protocol version in the very first message**, so the format can change later.

Transport moves data between endpoints and exposes only what higher layers need: connections, reliable delivery, connection lifecycle, errors. Iroh sits underneath. Direct connections, relay fallback, encryption and endpoint identity are Iroh details that stay below the transport boundary.

Game messages get their own ALPN on the Iroh endpoint. Voice will get another, on the same endpoint.

Don't design the transport abstraction up front. Pull it out of the first working Iroh connection.

### Identity and joining

Iroh's endpoint identity is the peer identity. v1 identity is a local keypair that signs log entries. Player-facing identity (names, accounts) waits until a feature needs it — and one now does: terminal results must name the winner for the player, so the bridge owns a persisted local display-name profile with a deterministic identity-derived fallback, and terminal facts carry actor/winner/loser by peer ID for Godot to render.

Joining works without a server: the host creates a session and shares something that lets the guest reach the host's endpoint. The goal is a short human-readable code. Open question: Iroh tickets are long, so a short code needs some way to resolve to an endpoint without a central server. Until that's solved, the fallback is sharing the Iroh ticket directly.

---

## Clock (reserved)

Not in v1. The design only reserves room for it:

- The host is the timekeeper and the only authority on timeout.
- Time is not part of the signed move log's validity. Moves are valid without it.
- The session and protocol should be able to carry time-control config and clock snapshots later without a breaking change.

Why signatures don't solve it: they prove who played what and in what order, not when, and neither peer has a trusted clock. Someone has to keep time, and that's the host. Lag compensation and disconnect handling during a timed game get designed when the clock does.

---

## Voice (planned)

Not in v1, but it is a real component and not a nice-to-have. Iroh already supports it: iroh-roq carries RTP over QUIC, and the callme demo exchanges Opus audio between iroh peers. iroh-live (Media over QUIC) is another route, but it's experimental. Both are early, so evaluate them before committing.

- Voice runs on the same Iroh endpoint with its own ALPN, separate from game messages.
- **Rust owns the whole voice subsystem:** capture, encode, decode, playback, and voice state. Godot only receives state (muted, speaking, connected) and renders it. This is a platform decision, not just a boundary one: Rust now owns native audio integration on every platform we ship. The audio backend is an implementation detail of the subsystem and can be swapped. Mobile is a target, so verify the audio backend on real Android and iOS devices (permissions, audio routing, background behavior) before starting voice work.
- Voice state is independent of game state and connection state. A player can be mid-game with voice muted or disconnected.
- Commands like `SetMicrophoneMuted` and events like `MicrophoneStateChanged` go through the same application contract.

---

## State ownership

| State | Owner |
|---|---|
| Chess position and rules | chess core |
| Match / session lifecycle, move log | session |
| Application transitions | application |
| Network connection | transport |
| Voice state (later) | communication |
| Presentation | Godot |

### Authority vs observation

A client can observe state without owning it. Godot may hold a rendered copy of the board, a cached player list, or the current microphone state. Those are observations used for presentation.

The authoritative state stays in the subsystem that owns it. A client changes it only by issuing a command through the application API.

### Separate state machines

Game state and connection state are independent. Don't merge them.

```text
Game:        Created | SettingUp | Ready | Playing | Finished
Connection:  Disconnected | Connecting | Connected | Reconnecting
```

`Playing` + `Reconnecting` is valid. `Finished` + `Disconnected` is valid. Voice and presence get their own state the same way once they exist.

---

## Godot integration

Godot's scene tree is single-threaded. Rust threads (tokio, Iroh) must never call Godot APIs directly. The integration uses gdext and one rule: Rust pushes events into a channel, and a Godot node drains it each frame and emits signals.

```text
Godot  --- #[func] call ---> Bridge --- Command ---> core thread
Godot  <--- signal --------- Bridge <--- Event ----- core thread
                        (drained in process())
```

- One `GodotClass` node, the bridge, owns the core handle (command sender and event receiver).
- Godot calls `#[func]` methods on it. Each one becomes a `Command`.
- In `process()`, the bridge drains the event channel with `try_recv()` and emits signals. GDScript connects to them and renders.
- Events cross as simple data: a kind plus a `Dictionary` payload, or typed signals for hot events like `move_applied`. No Rust structs handed to Godot.
- Drain events into a `Vec` before emitting. A GDScript handler that calls back into the bridge while it holds `&mut self` will panic on the borrow.
- Start the core from an explicit `start()` call, not from `init`.

Pin the API level in `Cargo.toml` (`api-4-7` for Godot 4.7). The API version must be less than or equal to the Godot version it runs in.

**Mobile risk:** the official gdext project (github.com/godot-rust/gdext) lists Android and iOS support as experimental, with documentation and tooling still lacking. Since mobile is required, this is the biggest platform risk in the plan, so it gets its own spike before we build on the bridge (Android first, then iOS). Some forks of gdext show old READMEs claiming no mobile support at all; ignore those and use the official repo.

If the spike fails, only the bridge changes. The application core is client-agnostic, so another client can sit on the same contract.

---

## Dependency rules

Dependencies point inward, toward the stable parts.

```text
chess core -> Godot    NO
chess core -> Iroh     NO
chess core -> AI/MCP   NO
Godot      -> Iroh     NO
Godot      -> chess core / session internals   NO
```

Godot, AI, MCP and the CLI only talk to the application API.

Avoid one giant `GameManager` that mixes chess, UI, voice, discovery, Iroh and storage. Equally, don't stuff everything into `chess_core` just because it's the first module.

---

## Errors

Each error belongs to the layer that understands it.

- `IllegalMove`: chess core
- `GameNotReady`: session
- `LogMismatch`: session / move log
- `PeerUnavailable`: transport
- `InvalidProtocolMessage`: protocol

No universal error type. Convert at the application boundary when a client needs it.

---

## Testing

Test each layer without the ones around it.

- **Chess core:** positions, moves, rules, results, draws. Fully deterministic.
- **Session and move log:** lifecycle, readiness, roles, allowed actions, signing and validation, log comparison and replay after a gap.
- **Application:** command in, state change, event out.
- **Transport:** connect, disconnect, reconnect, delivery. Iroh behavior is tested separately from chess rules.

---

## Build order

Follow dependencies, with one early exception: prove the network path before building on top of it.

1. **Chess core.** Full rules, tested. No Iroh, no Godot, no AI.
2. **Session and move log.** Participants, lifecycle, readiness, signed log, wired to chess core.
3. **Application contract.** Commands, queries, events, errors, and `handle()`.
4. **Iroh spike.** Two peers, one session, moves sent over Iroh, co-signed and applied on both sides, including a disconnect and a log resume. This is where we find out whether the contract and session model survive a real network. Fix the contract here, before more code depends on it. Settle the joining code question here too.
5. **Mobile spike.** A minimal gdext bridge running on a real Android device: call into chess core, get an event back as a signal. Then an Iroh connection from the phone to a desktop. This is a gate. If it fails, we find out before building on it, and we choose a different bridge or client. Once Android passes, hand the same spike to someone with a Mac and an iOS device to verify iOS; don't let the iOS result block Android work, but do get it before v1 is called done.
6. **Godot integration.** The bridge, replacing mock game behavior with real application state.
7. **Protocol and transport cleanup.** Pull the abstractions out of the spikes, now that real requirements exist.
8. **Local persistence.** Save and resume the move log.
9. **After v1, as features need them:** voice, presence and discovery, signals, clock, AI and MCP clients, richer identity.

---

## Later

Each of these arrives as a new capability or adapter around the contract, not by growing `chess_core`.

- **Voice, signals, presence and nearby discovery.** "Nearby" means whatever the discovery mechanism finds (e.g. a local network), not geographic distance.
- **Clock.** See [Clock](#clock-reserved).
- **AI and MCP:** clients of the same contract, never alternative chess implementations.
- **Spectators, replays, rooms, matchmaking, chat.**

