//! Piece, side, and castling-rights primitives for the chess engine.

use std::fmt;

/// Identifies which side a piece belongs to.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum PieceColor {
    #[default]
    White,
    Black,
}

impl fmt::Display for PieceColor {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::White => write!(f, "White"),
            Self::Black => write!(f, "Black"),
        }
    }
}

impl PieceColor {
    /// Returns the opposing side.
    #[must_use]
    pub fn opponent(self) -> Self {
        match self {
            Self::White => Self::Black,
            Self::Black => Self::White,
        }
    }
}

/// Identifies the kind of chess piece.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum PieceType {
    King,
    Queen,
    Bishop,
    Knight,
    Rook,
    Pawn,
}

impl fmt::Display for PieceType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::King => write!(f, "K"),
            Self::Queen => write!(f, "Q"),
            Self::Bishop => write!(f, "B"),
            Self::Knight => write!(f, "N"),
            Self::Rook => write!(f, "R"),
            Self::Pawn => write!(f, "P"),
        }
    }
}

/// A placed chess piece with a side and kind.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Piece {
    /// The owning side.
    pub color: PieceColor,
    /// The piece kind.
    pub piece_type: PieceType,
}

/// Castling availability for both sides and flanks.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct CastlingRights {
    /// `true` when White may still castle kingside.
    pub white_kingside: bool,
    /// `true` when White may still castle queenside.
    pub white_queenside: bool,
    /// `true` when Black may still castle kingside.
    pub black_kingside: bool,
    /// `true` when Black may still castle queenside.
    pub black_queenside: bool,
}

impl Default for CastlingRights {
    fn default() -> Self {
        Self {
            white_kingside: true,
            white_queenside: true,
            black_kingside: true,
            black_queenside: true,
        }
    }
}
