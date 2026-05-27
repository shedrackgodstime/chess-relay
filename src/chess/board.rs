//! Board storage and coordinate helpers for the chess engine.

use super::{Piece, PieceColor, PieceType};

/// Stores the 8x8 chess board using `(file, rank)` accessors.
#[derive(Clone, Debug)]
pub struct Board {
    squares: [[Option<Piece>; 8]; 8],
}

impl Board {
    /// Creates a new board in the standard chess starting position.
    #[must_use]
    pub fn new() -> Self {
        let mut squares = [[None; 8]; 8];

        let back_row = |color: PieceColor| -> [Option<Piece>; 8] {
            [
                Some(Piece {
                    color,
                    piece_type: PieceType::Rook,
                }),
                Some(Piece {
                    color,
                    piece_type: PieceType::Knight,
                }),
                Some(Piece {
                    color,
                    piece_type: PieceType::Bishop,
                }),
                Some(Piece {
                    color,
                    piece_type: PieceType::Queen,
                }),
                Some(Piece {
                    color,
                    piece_type: PieceType::King,
                }),
                Some(Piece {
                    color,
                    piece_type: PieceType::Bishop,
                }),
                Some(Piece {
                    color,
                    piece_type: PieceType::Knight,
                }),
                Some(Piece {
                    color,
                    piece_type: PieceType::Rook,
                }),
            ]
        };

        squares[0] = back_row(PieceColor::White);
        squares[1] = [Some(Piece {
            color: PieceColor::White,
            piece_type: PieceType::Pawn,
        }); 8];
        squares[6] = [Some(Piece {
            color: PieceColor::Black,
            piece_type: PieceType::Pawn,
        }); 8];
        squares[7] = back_row(PieceColor::Black);

        Self { squares }
    }

    /// Creates an empty board with no pieces.
    #[cfg(test)]
    #[must_use]
    pub fn empty() -> Self {
        Self {
            squares: [[None; 8]; 8],
        }
    }

    /// Returns the piece at the given `(file, rank)` if the square is in bounds.
    #[must_use]
    pub fn get(&self, file: u8, rank: u8) -> Option<Piece> {
        if !Self::in_bounds(file, rank) {
            return None;
        }

        self.squares[rank as usize][file as usize]
    }

    /// Sets the piece at the given `(file, rank)` when the square is in bounds.
    ///
    /// Returns the previous occupant of the square, or `None` if the square was
    /// empty or out of bounds.
    #[must_use]
    pub fn set(&mut self, file: u8, rank: u8, piece: Option<Piece>) -> Option<Piece> {
        if Self::in_bounds(file, rank) {
            let prev = self.squares[rank as usize][file as usize];
            self.squares[rank as usize][file as usize] = piece;
            prev
        } else {
            None
        }
    }

    /// Removes and returns the piece at the given `(file, rank)`.
    #[must_use]
    pub fn remove(&mut self, file: u8, rank: u8) -> Option<Piece> {
        self.set(file, rank, None)
    }

    /// Finds the king square for the given side.
    #[must_use]
    pub fn find_king(&self, color: PieceColor) -> Option<(u8, u8)> {
        for rank in 0..8 {
            for file in 0..8 {
                if let Some(piece) = self.get(file, rank)
                    && piece.color == color
                    && piece.piece_type == PieceType::King
                {
                    return Some((file, rank));
                }
            }
        }

        None
    }

    /// Iterates over every occupied square as `(file, rank, piece)`.
    pub fn iter(&self) -> impl Iterator<Item = (u8, u8, Piece)> + '_ {
        self.squares.iter().enumerate().flat_map(|(rank, row)| {
            row.iter()
                .enumerate()
                .filter_map(move |(file, piece)| piece.map(|piece| (file as u8, rank as u8, piece)))
        })
    }

    /// Returns `true` when the given coordinates are on the board.
    #[must_use]
    pub fn in_bounds(file: u8, rank: u8) -> bool {
        file < 8 && rank < 8
    }
}
