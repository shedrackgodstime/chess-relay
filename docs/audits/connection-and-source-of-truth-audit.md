# Connection lifecycle and source-of-truth audit

**Date:** 2026-10-08  
**Scope:** Rust bridge/network lifecycle and Godot connection/game-state integration  
**Method:** source trace after the a17e1ba pull; no Cargo results used as evidence

## Executive finding

The connection path has more than one state machine, but no single durable
connection state is exposed to the client. Transport state, session state,
bridge state, and Godot presentation state can therefore describe different
realities at the same time.

The existing audits document the broad architectural problems. This audit
records the concrete paths that make the behavior appear unpredictable:

- a dead transport leaves a locally playable-looking session alive;
- transport-connected is reported before the session handshake is complete;
- setup controls were local-only, so the two setup screens could disagree;
- startup events can be emitted before the Godot screen subscribes;
- restored draw-offer state is not reconstructed in the bridge;
- Godot shadow state is not always initialized from Rust state;
- failed connection attempts do not consistently retire the bridge.

## State ownership as implemented

| State or fact | Intended owner | Current representations |
| --- | --- | --- |
| Chess position and turn | Rust chess/session core | Session, Game, App queries, Godot FEN/turn reads |
| Session lifecycle | Rust session | SessionState, App, bridge app |
| Transport lifecycle | Rust bridge/network task | NetState, net_generation, task lifetime, transient NetNote signals |
| Draw offer | Rust session | Session.open_offer; also bridge CoreState.offer_by |
| Connection presentation | Godot | peer_connected, peer_disconnected, _net_game_active, hub flow flags |
| Game completion presentation | Godot observation | Rust GameEnded; Godot _finished |
| Active side for the clock strip | Rust turn query | Godot _active_clock_side |
| Selection and legal-target display | Godot interaction cache | _selected_piece_square, _legal_targets, marker nodes |

The intended direction is Rust authority with Godot observation. In practice,
some observations become gates for later behavior and therefore act as second
authorities.

## Findings

### C-SOT-01 — Dead transport leaves a live-looking session

**Status:** partially covered by the existing F-07 network audit; the concrete
state split below is new.  
**Severity:** High

When drive_session() exits because the connection closes, it emits a
peer_disconnected note and returns. It does not clear CoreState.net, change the
application/session state, or expose a durable disconnected status.

Evidence: [bridge.rs:1541](../../rust/src/bridge.rs:1541).

After the driver exits:

- Godot receives a one-shot disconnect signal;
- CoreState.app still contains the session;
- fen(), turn(), and legal-move queries still work;
- local submit_move() can still mutate the session;
- flush_to_peer() can send to a driver that no longer consumes commands,
  while ignoring the send result.

The UI can therefore say “Opponent disconnected” while the application still
behaves as though the game is playable.

### C-SOT-02 — peer_connected precedes session readiness

**Status:** the recent network audit documents the broad handshake issue; this
signal-level distinction is recorded here.  
**Severity:** Medium

Both network roles emit NetNote::Connected before handshake completion:

- host: [bridge.rs:1336](../../rust/src/bridge.rs:1336);
- guest: [bridge.rs:1457](../../rust/src/bridge.rs:1457).

At those points, readiness, genesis agreement, and the final Ready exchange
can still fail. The project consequently has at least two distinct states:

    transport connected
    session established and playable

The UI now waits for game_started before advancing, but the bridge signal name
and the state it represents remain easy to confuse.

### C-SOT-03 — Startup events can be lost before screen subscription

**Status:** implemented and protected for owned startup and borrowed snapshot
re-entry.
**Severity:** High

`GameScreen` now attaches its bridge signals before calling `start_resumable()`
or `start_ai()`. It also reads a current FEN, turn, move number, and terminal
session snapshot after wiring, so a borrowed network bridge remains correct
when `game_started` happened before the screen was instantiated.

Protection: the Godot full suite passes with the rebuilt extension, including
resume persistence and the bridge-backed game screen checks.

### C-SOT-04 — Restored draw offers are not reconstructed at the bridge boundary

**Status:** new.  
**Severity:** Medium

Session::resume() reconstructs Session.open_offer, but App::restore() only emits
GameStarted or GameEnded. It does not emit a DrawOffered fact for a restored
open offer.

The bridge keeps a separate CoreState.offer_by, populated when a DrawOffered
event is emitted:

- bridge mirror: [bridge.rs:809](../../rust/src/bridge.rs:809);
- answer path: [bridge.rs:614](../../rust/src/bridge.rs:614).

After restoring a session with an unanswered draw offer:

- Session knows the offer exists;
- CoreState.offer_by is empty;
- the bridge cannot answer the offer in hotseat/local mode.

This is a direct source-of-truth split between the session and bridge layers.

### C-SOT-05 — Godot shadow state is not initialized from authoritative state

**Status:** the foundation audit documents the general duplication; these
specific initialization gaps are new.  
**Severity:** Medium

GameScreen keeps presentation state that can affect behavior:

- _finished starts false and changes only after game_ended;
- _active_clock_side starts as "white";
- _active_clock_side is synchronized after move_applied, but not in
  _on_core_game_started();
- the clock values are local counters rather than core state.

Evidence: [game_screen.gd:28](../../godot/src/ui/screens/game/game_screen.gd:28),
[game_screen.gd:154](../../godot/src/ui/screens/game/game_screen.gd:154), and
[game_screen.gd:425](../../godot/src/ui/screens/game/game_screen.gd:425).

This can produce a screen whose board was rebuilt from the current FEN but
whose input lock, active-side styling, or clock strip describes an earlier
state.

### C-SOT-06 — Failed connection attempts do not consistently retire the bridge

**Status:** fixed for setup-to-lobby and failed hub/setup attempts; retain as a
regression check for all future network screen transitions.  
**Severity:** Medium

When the bridge reports a network error, AppRoot routes the message to the hub
or setup screen:

[app_root.gd:223](../../godot/src/ui/app/app_root.gd:223).

Those callbacks update presentation state, but failure handling must also retire
the bridge. The setup screen previously returned to a new multiplayer hub
without calling `_leave_network()`, so the old endpoint and driver remained
owned by `AppRoot` while the UI presented a fresh lobby. The transition now
retires the borrowed bridge before creating the replacement hub; the peer sees
the existing `peer_disconnected` path and the lobby displays “Opponent
disconnected.” Network errors now also retire the bridge after the visible
failure is rendered, so retry cannot inherit the failed runtime.

## Event and state transitions currently in play

    host_game/join_game
          |
          v
    endpoint bound, NetState stored
          |
          v
    transport link established
          |
          +--> peer_connected / peer_linked
          |
          v
    handshake and genesis agreement
          |
          +--> network_error or peer_disconnected
          |
          v
    game_started / setup advances
          |
          v
    drive_session
          |
          +--> move/events continue
          |
          +--> driver exits, transient disconnect signal only

The missing durable transition is the right-hand branch: the connection is no
longer usable, but NetState and the session remain available to local calls.

### C-SOT-07 — Setup choices were local-only

**Status:** fixed for v1 lobby behavior; game-rule enforcement remains a
separate follow-up because the current session core still starts standard chess
only.

The setup screen previously let each peer render its own time and variant
selection. Those values never crossed the wire, while side assignment lived in
the Rust genesis. The connection now begins with `LobbyHello`; the host may
send repeated `Setup` snapshots while changing the lobby. The snapshot is also
stored in the Rust bridge so a screen created after the signal still reads the
same state. The guest is a read-only observer: it has no Ready action and
automatically acknowledges the host's single start action. Both peers enter the
session only after that host commit and the normal genesis/readiness exchange.
Unsupported variants are rejected at the wire boundary; the UI exposes only
the core-supported Standard variant. Time-control choices are synchronized as
preview metadata because the clock is explicitly out of v1 and has no Rust
authority yet.

This is the v1 multiplayer contract:

    LobbyHello -> live host Setup snapshots -> host Start
        -> Hello(genesis) -> Ready exchange -> host Started -> GameStarted

No client may invent a setup value, declare itself ready independently, or
advance to the game screen from transport connection alone.

## What is already documented elsewhere

- F-01 covers the network lifecycle inversion and the hollow setup screen.
- F-03 covers turn-bound network actions.
- F-06 covers network/setup ownership and teardown leaks.
- F-07 covers missing reconnect/resume behavior.
- F-08 covers one-uni-stream-per-message ordering risk.
- F-09 covers fabricated clocks and disconnected controls.
- The foundation audit covers Godot retaining shadow copies of core state.

This document adds the concrete event-ordering and state-reconstruction paths
that those broader findings do not spell out.

## Audit conclusion

The main problem is not that one signal is named incorrectly or that one UI
flag is stale. The system lacks one durable, queryable connection/session
snapshot that all layers observe.

Until that exists, the following facts can disagree:

    transport alive       != session playable
    bridge exists         != connection alive
    game_started emitted  != game screen subscribed
    session open offer    != bridge offer_by populated
    current Rust turn     != Godot active-side cache
    peer disconnected     != local session stopped

These mismatches should be treated as the source map for the upcoming
connection-unpredictability investigation.
