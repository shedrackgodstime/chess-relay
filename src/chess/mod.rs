//! Pure chess engine types and rules for Chess Relay.

pub(crate) mod ai;
mod board;
mod game;
mod moves;
mod pieces;
mod state;

pub(crate) use board::Board;
pub(crate) use game::GameState;
pub(crate) use moves::{
    ChessMove, all_legal_moves, apply_move_inner_public, is_player_in_check, legal_moves,
};
pub(crate) use pieces::{CastlingRights, Piece, PieceColor, PieceType};
pub(crate) use state::GameStatus;
