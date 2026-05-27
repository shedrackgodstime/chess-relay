# Chess Relay Product Rebuild Plan

## Product Intent

Chess Relay is a professional 3D chess application in Rust with Bevy 0.18 for desktop and mobile.

This is not a prototype and not a hobby-grade codebase.

Every system should be:

- intentional
- testable
- modular
- visually coherent
- ready to support future networking without rewriting core game logic

## Product Definition

The application should deliver:

- a polished 3D chess experience
- full FIDE-compliant local play
- a deliberate UI outside the board, not placeholder menus
- smooth board interaction and camera control
- a clean architecture that separates chess rules from presentation

Networking is out of scope for now, but the architecture must remain ready for it.

## Non-Negotiables

- `src/` is the only production code path
- `src-old/` is reference material for behavior only
- `src-redundant/` is reference material for structural direction only
- the pure chess engine must not depend on Bevy
- UI code must not contain chess-rule logic
- no magic values for theme, spacing, colors, or screen composition
- code must be split by responsibility, not dumped into oversized files
- all major gameplay rules should be backed by tests

## Target Architecture

```text
src/
├── main.rs
├── app/
│   ├── mod.rs
│   ├── camera.rs
│   ├── lighting.rs
│   └── scene.rs
├── chess/
│   ├── mod.rs
│   ├── board.rs
│   ├── game.rs
│   ├── moves.rs
│   ├── notation.rs
│   ├── pieces.rs
│   └── state.rs
├── screens/
│   ├── mod.rs
│   ├── home/
│   ├── lobby/
│   ├── game/
│   └── settings/
├── theme/
│   ├── mod.rs
│   ├── palette.rs
│   ├── spacing.rs
│   ├── typography.rs
│   └── widgets.rs
└── ui/
    ├── mod.rs
    ├── components.rs
    └── overlays.rs
```

## Core Architectural Rules

### 1. Chess Engine First

The `chess/` module owns:

- board representation
- piece definitions
- move generation
- legality filtering
- check and mate detection
- castling, en passant, and promotion
- draw-state tracking
- future FEN import/export

It should be pure Rust and independently testable with `cargo test`.

### 2. Presentation Is a Consumer

The Bevy layer should consume engine state and render it.

It owns:

- 3D board scene
- piece visuals
- camera orbit and rotation
- square selection
- move highlights
- HUD and overlays
- navigation and screen flow

It should never become the source of truth for chess rules.

### 3. Input Must Stay Pluggable

Move requests should flow through a common input path so the app can later support:

- local hot-seat play
- AI play
- online multiplayer

The controller should validate and apply moves regardless of source.

### 4. Theme Must Be Centralized

The visual language must be intentional and reusable:

- colors in `theme/palette.rs`
- spacing in `theme/spacing.rs`
- typography in `theme/typography.rs`
- common buttons, panels, cards, and HUD surfaces in `theme/widgets.rs`

## Experience Goals

## Board and Camera

- board presented as a proper 3D scene, not a rough test plane
- orbit/rotation around board center with full 360 control
- stable camera behavior on desktop and mobile
- good default angle, lighting, depth, and material contrast
- clear square and move highlighting

## UI Shell

- home screen should feel product-grade
- local game flow should be immediate and clean
- game HUD should be minimal but strong
- promotion should use visual UI, not keyboard-only fallback
- layout should work across desktop and mobile aspect ratios

## Engineering Quality

- compile cleanly
- keep modules small and purposeful
- avoid duplicated rules across layers
- keep data flow obvious
- prefer explicit names over vague abstractions

## Source Guidance

### What To Reuse From `src-old`

Reuse logic ideas from:

- move behavior
- special rule handling
- turn flow
- promotion flow
- check/checkmate/stalemate behavior

Do not copy its file structure into production.

### What To Reuse From `src-redundant`

Reuse direction from:

- screen/plugin split
- engine vs presentation separation
- input abstraction
- theme module concept

Do not treat its board and UI implementation as final quality.

## Execution Plan

### Phase 1. Foundation

- create the real `src/` production structure
- restore a compilable application entry point
- set up app plugin, screen state, base cameras, and scene bootstrap
- define theme tokens and shared UI widgets

### Phase 2. Engine

- rebuild `chess/` as the single source of truth
- port and improve rule handling from the rough implementation
- add unit tests for:
  - move generation
  - legality filtering
  - castling
  - en passant
  - promotion
  - check, checkmate, stalemate
- fix known edge cases while rebuilding

### Phase 3. Game Scene

- build the 3D board scene properly
- load and place piece models cleanly
- add selection and legal move highlights
- add controller flow from click to validated move application
- synchronize rendered state from engine state

### Phase 4. Camera and Interaction

- add orbit camera with 360 rotation
- support zoom and angle constraints where needed
- ensure mobile-safe interaction behavior
- make interaction feel stable and intentional

### Phase 5. Product UI

- rebuild home screen with stronger composition
- build clean lobby and settings placeholders
- build game HUD for turn, check state, result state, and promotion
- unify navigation and visual tone across all screens

### Phase 6. Rule Completion

- add draw conditions:
  - 50-move rule
  - threefold repetition
  - insufficient material
- add FEN import/export support
- prepare state and interfaces for clocks and future networking

## Immediate Working Order

1. Create a compilable `src/` baseline with app, theme, screens, and chess module boundaries.
2. Move chess logic into a pure engine and get tests passing.
3. Rebuild the game screen around that engine.
4. Add proper 360 camera control.
5. Upgrade the outer UI and overlays.

## Definition of Done For This Rebuild Direction

We are on the right track when:

- the project builds from `src/`
- the chess engine is pure and tested
- the 3D board is controlled by engine state, not ad hoc entities
- the camera can rotate cleanly around the board
- promotion and game state are handled through UI, not debug shortcuts
- the codebase reads like a deliberate product architecture

## Current Contradiction To Resolve

`docs/CHESS_RELAY_OBJECTIVE.md` currently describes a chase game, which conflicts with the actual project direction.

Until corrected, this document, `AGENTS.md`, `project-structure.md`, and `chess-rules.md` should be treated as the working source of truth for the product.
