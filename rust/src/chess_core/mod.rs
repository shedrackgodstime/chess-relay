//! Pure chess domain: board, moves, legality, results.
//!
//! Must not depend on Godot, Iroh, networking, or UI.
//! Deterministic and testable on its own.
//!
//! Behaviour oracles: `ref/chess-relay/chess/` (our GDScript prototype)
//! and `ref/shakmaty` (independent cross-check). Nothing is copied from
//! either; perft vectors must agree with both (see plan Phase 1).

pub(crate) mod board;
pub(crate) mod types;

#[doc(inline)]
pub use board::{Board, CastlingRights};
#[doc(inline)]
pub use types::{Color, IllegalMove, Move, Piece, Role, Square};
