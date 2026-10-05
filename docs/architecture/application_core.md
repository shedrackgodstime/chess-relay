# Chess Relay application core

This document defines the boundary between the Godot client and the Rust
application core. It is a design contract for the next implementation phase;
it does not add transport, chess rules, or a Godot bridge yet.

## Boundary

```text
                         Chess Relay
                              │
                ┌─────────────┴─────────────┐
                │                           │
             Godot                         Rust
          Presentation                 Application core
                │                           │
       ┌────────┼────────┐         ┌────────┼────────┐
       │        │        │         │        │        │
      UI      Board    Input     Chess    Session  Network
                                  core     state     core
                                                     │
                                             Protocol + transport
                                                     │
                                                    Iroh
```

Godot owns presentation and user interaction. Rust owns facts that must remain
correct independently of the renderer, platform, or transport implementation.
The boundary is expressed as commands going into Rust and events coming out of
Rust.

```text
Godot action
    │ command
    ▼
Rust application core
    ├── validate
    ├── update state
    ├── persist or transmit when required
    └── emit an event
    │ event
    ▼
Godot presentation update
```

Godot must not duplicate chess legality, session authority, protocol encoding,
or timeout decisions. Rust must not know about Godot scene paths, controls,
theme variations, layout, or modal presentation.

## Responsibilities

### Godot

- Screen lifecycle and navigation.
- Reusable controls, themes, board rendering, animation, and accessibility.
- Capturing input and turning it into application commands.
- Rendering Rust state and events.
- Purely visual preferences and presentation-only state.

### Rust application core

#### `chess_core`

The deterministic rules model:

- Board and piece state.
- Legal move generation and validation.
- Check, checkmate, and stalemate.
- Castling, en passant, and promotion.
- Draw rules and game result.
- Move notation and replayable move history.

Godot renders the board. Rust decides whether a position and move are valid.

#### `session`

The match state machine and player/session facts:

```text
Waiting → Connected → SettingUp → Ready → Playing → Finished
                         │            │
                         └────────────┴── Paused/Reconnecting
```

It owns player identity within a match, assigned colors, game ID, current turn,
ready state, and session status. It does not decide how those states look.

#### `protocol`

Versioned messages shared by local session logic and transport:

```text
CreateGame       JoinGame          PlayerJoined       PlayerReady
GameStarted      Move              MoveAccepted       MoveRejected
DrawOffer        DrawResponse      Resign             Signal
VoiceNegotiation GameState         GameEnded
```

The protocol describes data and intent. It must not contain Godot UI concepts.

#### `transport`

The current Rust focus and the Iroh boundary:

- Endpoint and connection lifecycle.
- Direct connections, relay use, and discovery integration.
- Streams and datagrams.
- Reconnect and transport failure reporting.

The rest of Rust should depend on transport interfaces, not directly on Iroh,
so the transport implementation can change without rewriting chess or session
logic.

#### `identity`

Device-local identity and cryptographic material:

- Device identity and keypairs.
- Peer identity and trust information.
- Game/session identity.
- Authentication material required by the protocol.

Identity is local-device data in this product. It is not an account system.

#### `clock`

If time controls are implemented, Rust owns the authoritative clock:

- White and Black remaining time.
- Initial time and increment.
- Turn switching.
- Pause/resume rules.
- Timeout decisions.

Godot displays the clock and animates it; it does not decide when a player has
lost on time.

#### `storage`

Add this only when persistence requirements exist. Candidate data includes
device identity, saved games, replay history, peer information, and transport
or security settings. Godot may keep presentation-only preferences locally when
there is no correctness or security reason to move them into Rust.

#### AI

An engine or AI adapter can live in Rust later. The UI sends a request for a
move and receives a result; the UI does not contain the engine.

## Command and event contract

Commands express user or application intent:

```text
SubmitMove { from, to, promotion }
SetReady
OfferDraw
AnswerDraw { accepted }
Resign
CancelInvite
```

Events express a state change or result:

```text
MoveApplied { move, position, clocks }
MoveRejected { reason }
ReadyChanged { player, ready }
SessionStateChanged { state }
PeerDisconnected { reason }
GameEnded { result }
```

Commands are validated by Rust before state changes or network messages are
created. Godot renders events and may show a user-facing explanation for a
rejection; it does not reinterpret the rule decision.

Example:

```text
Godot  → SubmitMove(e2, e4)
Rust   → validate, update Board and Session, send protocol message
Rust   → MoveApplied
Godot  → animate e2 → e4 and refresh clocks/turn indicators
```

## Workspace growth

Do not create one crate for every named responsibility before the boundaries
need it. The current Rust package is an initial Godot/Iroh integration point.
Grow it around real dependency boundaries:

```text
rust/
├── Cargo.toml
└── crates/                 # introduce when a boundary is real
    ├── chess_core/
    ├── protocol/
    ├── session/
    └── transport/
```

`identity`, `clock`, `storage`, and an AI adapter become separate crates only
when their ownership, dependencies, or test surfaces justify that split. The
architecture is more important than the number of crates.

## Integration rules

1. Keep Godot-facing calls narrow and typed.
2. Prefer explicit command/event data over arbitrary cross-language calls.
3. Keep protocol types independent of Godot and Iroh.
4. Keep transport errors distinct from chess-rule rejections.
5. Make Rust core state deterministic and unit-testable without a running Godot
   window or network connection.
6. Keep UI-only mock services behind the same intent/event boundary until the
   real Rust service is ready.
7. Do not let a screen call transport internals directly.

## Current status

- Godot UI lifecycle and reusable components are the active development scope.
- Rust is initialized with a Godot-compatible library target and Iroh
  dependency, but the application-core modules are not implemented yet.
- The current Godot mock multiplayer service is a presentation fixture. It will
  be replaced or adapted behind the command/event boundary when Rust services
  are introduced.
- The board screen can be designed against this contract without implementing
  chess rules or transport in the UI pass.
