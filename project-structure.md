# Chess Relay — Architecture & Design

## Project
Multiplayer 3D chess in **Rust + Bevy 0.18** for desktop & mobile.

## Screens

| Screen | Purpose |
|--------|---------|
| **Home** | Logo, Play Online, Local Game, Settings link |
| **Lobby** | Matchmaking / opponent list |
| **Game** | 3D board + HUD overlay |
| **Settings** | Preferences (future) |

Navigation: `Screen` enum drives state-based plugin activation.

---

## Visual Theme: **Dark Modern Chess**
- Canvas: deep charcoal `#121214`
- Accent: warm amber/gold `#D4A04A`
- Surface: rich dark gray `#1E1E24`
- Text: off-white `#F0EDE8`
- Secondary: muted rosewood `#6B3A3A`

---

## Project Structure

```
chess-relay/
├── assets/
│   ├── fonts/                  # TTF/OTF font files (future)
│   ├── models/chess_kit/       # GLB chess piece models
│   └── ui/                     # Icons, textures, backgrounds (future)
│
├── src/
│   ├── main.rs                 # App entry — plugins, 3D camera, light
│   │
│   ├── theme/                  # ★ Design system (single source of truth)
│   │   ├── mod.rs
│   │   ├── palette.rs          # All color tokens, no magic values
│   │   ├── typography.rs       # Font sizes, weights, families
│   │   └── widgets.rs          # Styled button/panel/card builders
│   │
│   ├── screens/                # ★ One plugin per page
│   │   ├── mod.rs              # Screen enum + state-driven plugin routing
│   │   ├── home/               # Home screen — logo, navigation buttons
│   │   ├── lobby/              # Lobby — matchmaking placeholder
│   │   ├── game/               # ★ Game screen — board, HUD, input
│   │   │   ├── mod.rs          # GamePlugin, CurrentGame, GameConfig
│   │   │   ├── controller.rs   # Core loop: validate moves → apply → update
│   │   │   ├── board.rs        # 3D checkerboard spawning
│   │   │   ├── hud.rs          # Turn indicator, check warning
│   │   │   ├── pieces.rs       # 3D piece spawning (GLB scene)
│   │   │   └── input/          # ★ Pluggable move producers
│   │   │       ├── mod.rs      # PendingMoves queue, GameInput enum
│   │   │       ├── local.rs    # Click-based hot-seat input
│   │   │       ├── ai.rs       # Computer opponent (stub: random)
│   │   │       └── network.rs  # Online input (stub)
│   │   └── settings/           # Settings placeholder
│   │
│   └── chess/                  # ★ Pure chess engine (zero Bevy deps)
│       ├── mod.rs              # Re-exports
│       ├── pieces.rs           # PieceColor, PieceType, Piece, CastlingRights
│       ├── board.rs            # 8×8 board, starting position, queries
│       ├── moves.rs            # Move generation, legality, check detection
│       └── game.rs             # GameState: apply_move, turn switching
│
├── Cargo.toml
└── project-structure.md
```

---

## Architecture Principles

| Principle | Rule |
|-----------|------|
| **Separation** | `chess/` has zero Bevy imports — testable with `cargo test`, reusable independently |
| **Single source** | Every color, font size, and spacing lives in `theme/` — never hardcoded |
| **Page isolation** | Each screen is its own `Plugin` — add/remove without touching others |
| **State-driven** | A `Screen` enum drives which plugins are active (Bevy state) |
| **Pluggable input** | `input/local.rs`, `ai.rs`, `network.rs` all push `PendingMoves` — `controller.rs` is input-agnostic |
| **No trash** | `src-old/` is discarded prototype, not referenced or copied |

### Input Architecture

```
[Local clicks]   ──→  pending.0.push(move)
[AI timer]       ──→  pending.0.push(move)         PendingMoves  ──→  controller_system
[Network socket] ──→  pending.0.push(move)           (Resource)        validates + applies
```

The `GameConfig` resource selects which `GameInput` variant is active at screen spawn. The `GameInput` enum (`Local / Ai / Network`) determines which resources (`AiInput`, `NetworkInput`) are inserted. Systems for each variant check `resource_exists` before running.

---

## Cargo.toml — Dependencies

See `Cargo.toml` for canonical feature list. Key features:
- `default-features = false` + minimal feature selection
- `bevy_pbr`, `bevy_gltf`, `bevy_ui`, `bevy_state`, `default_font`

---

## Home Page — Layout

```
┌──────────────────────────────────────┐
│                                      │
│            ♚ Chess Relay             │  ← Logo area
│           ───────────────            │  ← Gold divider
│                                      │
│        ┌────────────────────┐        │
│        │    Play Online      │        │  ← Primary button (filled amber)
│        └────────────────────┘        │
│                                      │
│        ┌────────────────────┐        │
│        │    Local Game       │        │  ← Secondary button (outlined)
│        └────────────────────┘        │
│                                      │
│            Settings                  │  ← Text link
│                                      │
│    v0.1.0 · Rust + Bevy             │  ← Footer
└──────────────────────────────────────┘
```

## Next Steps
1. Write chess engine unit tests (board, moves, game)
2. Fix typography.rs constants usage in widgets
3. Implement draw conditions (50-move rule, threefold repetition)
4. FEN export/import
5. Visual promotion UI (piece selection dialog)
6. Chess clock / turn timer
7. Networking (multiplayer)
