---
name: chess-relay-skills
description: >
  Strict coding guidelines for the Chess Relay project — a multiplayer 3D chess
  game in Rust (Bevy 0.18) implementing all FIDE rules for desktop & mobile.
  Invoke with /chess.
license: MIT
metadata:
  author: chess-relay
  version: "1.0.0"
---

# Chess Relay — Coding Standards

Non-negotiable rules for every change made to this codebase. Violations must be
caught before any commit reaches review.

---

## 0. Zero Tolerance Rules

These are absolute. Any violation must be immediately rejected, no exceptions.

- **0.1.** No `unwrap()`, `expect()`, `todo!()`, `unreachable!()`, `dbg!()`,
  `eprintln!()`, or `println!()` in production code ever. Period. Use `?`,
  proper error handling, or `unreachable!` only in test code with a comment
  explaining why it is truly unreachable.
- **0.2.** No `unsafe` blocks. If you genuinely need one, seek review. Every
  `unsafe` must have a `// SAFETY:` proof attached. The proof must be correct.
- **0.3.** No dead code. No commented-out code. No `#[allow(dead_code)]`
  without a documented reason and an outstanding issue tracking removal.
- **0.4.** No unwrap-on-query patterns. Every `Query::single()`,
  `ResMut::unwrap()`, `Commands::entity()`, etc. must handle the error case.
- **0.5.** No stringly-typed APIs. Use enums, newtypes, or typed structs.
- **0.6.** No ambiguous or single-letter variable names except for the
  conventional `f`/`r` for file/rank in chess logic, and loop counters in
  trivial 3-line scopes.
- **0.7.** Every exported public item (`pub` API visible outside its defining
  module tree) must have a doc comment (`///`). Every module must have a
  module doc (`//!`). Crate-private implementation markers and private struct
  fields do not require rustdoc, but the surrounding module must remain clear
  and intentionally named.
- **0.8.** Every function must return a meaningful type. No `()` return on
  functions that can fail — use `Result`. No returning `Vec` when a reference
  suffices.

---

## 1. Architecture Rules

### 1.1 Module Boundaries (Strict)

The project has four layers. They may only depend in one direction:

```
src/main.rs  →  src/lib.rs  →  screens/  →  chess/  +  theme/  +  ui/
                src/app/     ←  screens/
```

- **`src/chess/`** — Pure chess logic. Absolutely no Bevy imports. No I/O. No
  rendering. No random. Must be testable with `cargo test --lib` without a
  headless runner. All types must implement `Clone`, `Debug`, `PartialEq`.
- **`src/app/`** — Bevy plugin setup, camera, lighting, window config. Cannot
  depend on `screens/`, `chess/`, `theme/`, or `ui/`.
- **`src/screens/`** — Bevy state-driven screen plugins (`Screen` state
  machine). Each screen is one directory. Screens may depend on `chess/`,
  `theme/`, `ui/`, and `app/` (only `MainCamera3d`). Screens must NOT depend
  on each other.
- **`src/theme/`** — Pure constants and widget factories. No `chess/` or
  `screens/` imports. Plugin is minimal (global interaction systems only).
- **`src/ui/`** — Reusable marker components shared across screens. No logic.

### 1.2 State Management

- Use Bevy `State` (`Screen` enum) for navigation. Do NOT use stacked states
  or custom state machines.
- Use Bevy `Resource` for game state (`CurrentGame(GameState)`). Exactly one
  instance, created on `OnEnter(Screen::Game)`, removed on
  `OnExit(Screen::Game)`.
- Use Bevy `Event` for one-shot signals. Use `ResMut` for accumulative state.
- Never store `Entity` IDs in resources unless paired with a despawn observer.
  Prefer marker components + `Query` filters.

### 1.3 Plugin Structure

Every plugin must follow this exact template:

```rust
pub struct FooPlugin;

impl Plugin for FooPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(OnEnter(Screen::Foo), spawn_foo)
            .add_systems(OnExit(Screen::Foo), despawn_foo)
            .add_systems(Update, handle_foo.run_if(in_state(Screen::Foo)));
    }
}
```

- `spawn_*` creates the screen root and inserts all entities/resources.
- `despawn_*` tears down every entity with the screen's marker component.
- `handle_*` contains the update logic.
- Never mix spawning/despawning with update logic in the same system.

---

## 2. Chess Engine Rules

### 2.1 Coordinate Convention

**THIS IS CRITICAL AND NON-NEGOTIABLE. WRONG COORDINATES CRASH THE GAME.**

- `file`: horizontal axis, 0–7 (a–h). First index in arrays.
- `rank`: vertical axis, 0–7 (1–8). Second index in arrays.
- All board access: `board.get(file, rank)` → `squares[rank][file]`.
- Algebraic notation: `char::from(b'a' + file)`, `char::from(b'1' + rank)`.
- Vector directions: `x` = file delta, `z` = rank delta, `y` = up.
- In 3D space: `x = file - 3.5`, `z = rank - 3.5`.

When in doubt, draw an 8×8 grid on paper and trace the operation.

### 2.2 Move Generation Rules

- `pseudo_legal_moves` generates moves ignoring check. `legal_moves` filters
  by simulation. Never skip the simulation step.
- En passant target is `Option<(file, rank)>`. Store on double pawn advance.
- Castling rights are tracked as four booleans on `CastlingRights`. Both king
  and rook movement must update the corresponding rights.
- Promotion generates exactly four moves (Q/R/B/N). Never add King or Pawn to
  promotion choices.
- `is_attacked` checks all six piece types (pawn, knight, bishop, rook, queen,
  king). Every attack check must verify `piece.color == by`. Do NOT shortcut
  king attacks through sliding logic.

### 2.3 Game State Transitions

```
apply_move:
  1. Clone board (handled by caller in legal_moves; actual pass by apply_move)
  2. Execute move on board
  3. Update en_passant target (previous target consumed, new set only on double advance)
  4. Update castling rights (king move = both lost, rook move/capture = that side lost)
  5. Update halfmove clock (reset on capture or pawn move)
  6. Update fullmove number (increment after Black's turn)
  7. Switch turn
  8. Record last_move (for UI highlighting)

status:
  checkmate  →  checkmate with winner = opponent of current turn
  stalemate  →  draw by stalemate
  check      →  check (current turn is in check)
  otherwise  →  in progress
```

### 2.4 Validation Every Move

Every `apply_move` must guarantee:
- Move is in `all_legal_moves` (caller responsibility, enforced through UI).
- En passant capture removes the correct pawn (`to_file, from_rank`).
- Castling moves the rook to the correct square (`5, rank` for kingside,
  `3, rank` for queenside).
- Promotion replaces the pawn with the chosen piece type.

---

## 3. Bevy Patterns

### 3.1 Commands and Entity Management

- **Always despawn children first**: `despawn_related::<Children>().despawn()`.
  Bevy 0.18 does NOT cascade despawns automatically.
- **Never store raw `Entity` IDs** in components that are also being despawned.
  Use marker components + queries.
- **Never use `.commands().entity(id).despawn()` inside a system that also
  queries for that entity.** Use deferred commands.
- **Spawning patterns**: Use `parent.with_children(|parent| { ... })` for
  hierarchical scenes. Use `commands.spawn(...)` for flat UI roots.

### 3.2 Query Patterns

- **Always handle "not found"**: `Query::single_mut()` returns `Result`.
  Pattern:
  ```rust
  let Ok(transform) = query.single_mut() else { return; };
  ```
- **Filter aggressively**: Use `With<Component>`, `Without<Component>`, and
  `Changed<Component>` to minimise iteration.
- **Never mutate `Transform` in a query that also reads it** — use `&mut`.
- **Prefer `Ref<T>` over `Res<T>`** when you need `is_changed()` on a
  resource.

### 3.3 Materials and Assets

- Pre-create materials in `spawn_*` using `ResMut<Assets<StandardMaterial>>`.
  Store handles in component bundles (`SquareMaterialSet`).
- Swap materials by replacing the handle on `MeshMaterial3d<StandardMaterial>`.
  Do NOT re-create meshes to change colour.
- GLB piece paths use the format
  `"models/chess_kit/pieces.glb#Mesh*/Primitive0"`. These are fragile — if you
  regenerate the GLB, verify every path.
- King and Knight glTF scenes have *two* meshes. All others have one.

### 3.4 Picking and Input

- The project does NOT use `bevy_picking` for pieces. Piece selection uses a
  manual ray-AABB intersection path (`ray_aabb_hit_distance`) against
  piece-local hit volumes derived from the rendered mesh bounds and combined at
  the piece-root level.
- Square clicks use a ray-plane intersection against the board plane.
- When a piece is already selected, legal target squares take precedence over
  piece-body hits so move resolution remains deterministic in crowded
  positions.
- `PendingSquareClick` acts as a one-frame buffer to decouple click detection
  from game logic. Always consume it via `.take()`.
- Ignore clicks while `PendingPromotion` is active.

### 3.5 Camera and Layout

- Two cameras: 3D camera (order 0), 2D UI camera (order 1, with
  `IsDefaultUiCamera`).
- Layout mode switches between desktop and mobile based on `width > height`.
- Never hardcode camera positions in game screen code. Use `GameSceneRoot`
  rotation for board orientation changes.

---

## 4. Coding Standards

### 4.1 Style (Enforced by `rustfmt`)

- Edition 2024. Run `cargo fmt --all --check` before every commit.
- Line width: 100 (default).
- Use `let-else`, `let-chains`, `let &&` syntax. Prefer `is_none_or` and
  `is_some_and` over manual pattern matching on `Option`.
- Derive macros in this order: `#[derive(Clone, Copy, PartialEq, Eq, Debug)]`.
  Add `Default` at the end if applicable, `Hash` only if needed.

### 4.2 Naming

| Category | Convention | Example |
|----------|-----------|---------|
| Types, traits, enums | `UpperCamelCase` | `GameState`, `PieceType` |
| Enum variants | `UpperCamelCase` | `Checkmate { winner }` |
| Functions, methods | `snake_case` | `apply_move`, `legal_moves_for` |
| Module names | `snake_case` | `chess`, `game` (module) |
| Constants, statics | `SCREAMING_SNAKE_CASE` | `BOARD_HALF_SPAN` |
| File/rank vars | Single letter `f`, `r` | `f`, `r` in loops |
| All others | Full words, no abbreviations | `file`, `rank`, `piece_type` |

- Getters: no `get_` prefix. `board.get(file, rank)` is the only exception
  (matches array indexing convention).
- Boolean methods: `is_` / `has_` / `can_` prefix. E.g. `is_check()`,
  `has_any_legal_move()`.
- Conversion methods: `as_` for free refs, `to_` for expensive, `into_` for
  ownership transfer.

### 4.3 Error Handling

- This project uses `anyhow` at the application level. Main returns
  `anyhow::Result<()>`.
- Core chess functions that can fail return `Option<T>` or `bool`, never
  `Result` (the chess engine has no fallible operations — every position is
  valid).
- Bevy systems never return `Result`. Handle errors inline with early returns.

### 4.4 Imports

- Group: `std` → external crates → `bevy` → `crate`.
- Single line per import group, no blank lines within.
- Use `use crate::module::{Type, function}`. Avoid `use crate::module::*` in
  production code. `use super::*` is allowed only in `#[cfg(test)] mod tests`.

### 4.5 Validation Command

Run **all four** before every commit:

```bash
cargo fmt --all --check
cargo check --workspace
cargo clippy --all-targets --all-features -- -D warnings
cargo test
```

If any fails, fix it. No exceptions. If clippy is too aggressive on a
specific line, add `#[allow(clippy::lint_name)]` with a one-line comment
explaining why.

---

## 5. Testing Rules

### 5.1 Coverage Requirements

- Every `pub fn` in `src/chess/` must have at least one test.
- Every edge case in move generation must be tested: en passant, castling
  (both sides, blocked, attacked through), promotion (each piece), pins,
  discovered checks, double check, stalemate.
- Standard starting position: exactly 20 legal moves for White.

### 5.2 Test Structure

```rust
#[cfg(test)]
mod tests {
    use super::*;

    fn empty_state() -> GameState { /* helper */ }
    fn place(state: &mut GameState, file: u8, rank: u8, piece_type: PieceType, color: PieceColor) {
        state.board.set(file, rank, Some(Piece { color, piece_type }));
    }

    #[test]
    fn descriptive_name_of_what_is_being_tested() {
        // Arrange
        // Act
        // Assert
    }
}
```

- Use `empty_state()` + `place()` for custom board setups.
- Never use `Board::new()` in tests that need specific positions.
- Test names must describe the scenario: `pinned_pawn_cannot_move_off_file`.

---

## 6. Anti-Patterns Watchlist

These patterns have been found and fixed before. Do not reintroduce them.

| Anti-pattern | Why it's wrong | Correct approach |
|---|---|---|
| `x`/`y` for file/rank in 3D space | `x=file, z=rank, y=up`. Using `y` for rank creates coordinate bugs | Use `file`/`rank` in logic, `x`/`z` in 3D transforms |
| Hardcoded castling rook positions | King at e1/e8, rooks at a1/h1/a8/h8. Must use `(file, rank)` matching | Use `(7, rank)` for kingside rook, `(0, rank)` for queenside |
| `en_passant` passed to `is_attacked` for non-pawn moves | En passant target only matters for pawn captures | Pass `None` when simulating non-pawn moves |
| Using `bevy_picking` for pieces | Picking doesn't work well with GLB children | Manual ray-AABB per piece type |
| Storing `Entity` in resources | Entity IDs become dangling after `despawn_related()` | Marker components + queries |
| `#[allow(dead_code)]` without tracking | Dead code accumulates silently | Remove it or file an issue |

---

## 7. Dependency Discipline

- `Cargo.toml` uses edition 2024. Bevy 0.18.1 with explicit feature selection.
- No dependency added without a documented reason in the commit message.
- No dependency added that duplicates functionality (e.g. no `serde` unless
  FEN serialization requires it — currently there is no `serde`).
- Prefer Bevy's built-in types over external crates. If Bevy has it, use it.
