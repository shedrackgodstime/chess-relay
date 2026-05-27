//! High-level game status values derived from the current position.

use super::PieceColor;

/// Describes the current game outcome or tactical state.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum GameStatus {
    /// The side to move is not in check and the game can continue.
    InProgress,
    /// The side to move is currently in check.
    Check(PieceColor),
    /// The side to move is checkmated and `winner` has won the game.
    Checkmate { winner: PieceColor },
    /// The side to move has no legal moves but is not in check.
    Stalemate,
    /// Neither side has made progress for 50 full moves.
    FiftyMoveDraw,
    /// The same position has occurred three times.
    ThreefoldRepetitionDraw,
    /// There are insufficient pieces remaining to deliver checkmate.
    InsufficientMaterialDraw,
}
