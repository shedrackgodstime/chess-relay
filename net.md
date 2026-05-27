# Chess Relay — Networking Plan

## Architecture

P2P via libp2p, no central server. Each player maintains their own
`GameState` locally. Only moves are sent over the wire (deterministic).

## Wire Protocol

Each message is a JSON-serialized `ChessMove`:

```json
{"from_file":4,"from_rank":1,"to_file":4,"to_rank":3,"promotion":null}
```

## Changes Required

### 1. Add serde + serde_json to Cargo.toml
Derive `Serialize, Deserialize` on `ChessMove`, `PieceType`, `PieceColor`.

### 2. New module: `src/net/`
- `mod.rs` — libp2p setup, connection management
- `transport.rs` — message encoding/decoding
- `resource.rs` — `NetworkingState` resource (`Disconnected` / `Hosting` / `Connected`)

### 3. Lobby screen (`src/screens/lobby/`)
Replace stub with:
- "Host Game" button → opens libp2p listener, shows peer ID
- "Join Game" → type or paste peer ID to connect
- Connection status indicator

### 4. Game screen changes (`src/screens/game/mod.rs`)
- When `OpponentKind::Online`: block local clicks on opponent's turn
- `receive_network_move` system: deserialize incoming move → `apply_move` to `CurrentGame`
- `send_network_move` system: after local move, serialize → send
- Wait-for-opponent indicator in HUD
