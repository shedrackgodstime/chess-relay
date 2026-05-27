use crate::chess::pieces::*;

#[derive(Clone, Debug)]
pub struct Board {
    squares: [[Option<Piece>; 8]; 8],
}

impl Board {
    /// Standard starting position.
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

        Board { squares }
    }

    /// Create an empty board.
    #[allow(dead_code)]
    pub fn empty() -> Self {
        Board {
            squares: [[None; 8]; 8],
        }
    }

    /// Get piece at (file, rank). file=a(0)..h(7), rank=1(0)..8(7).
    pub fn get(&self, file: u8, rank: u8) -> Option<Piece> {
        if file > 7 || rank > 7 {
            return None;
        }
        self.squares[rank as usize][file as usize]
    }

    /// Set piece at (file, rank).
    pub fn set(&mut self, file: u8, rank: u8, piece: Option<Piece>) {
        if file <= 7 && rank <= 7 {
            self.squares[rank as usize][file as usize] = piece;
        }
    }

    /// Remove and return piece at (file, rank).
    pub fn remove(&mut self, file: u8, rank: u8) -> Option<Piece> {
        let piece = self.get(file, rank);
        self.set(file, rank, None);
        piece
    }

    /// Find the king of the given color.
    pub fn find_king(&self, color: PieceColor) -> Option<(u8, u8)> {
        for rank in 0..8 {
            for file in 0..8 {
                if let Some(p) = self.get(file, rank)
                    && p.color == color
                    && p.piece_type == PieceType::King
                {
                    return Some((file, rank));
                }
            }
        }
        None
    }

    /// Iterate over all occupied squares.
    pub fn iter(&self) -> impl Iterator<Item = (u8, u8, &Piece)> + '_ {
        self.squares.iter().enumerate().flat_map(|(rank, row)| {
            row.iter()
                .enumerate()
                .filter_map(move |(file, opt)| opt.as_ref().map(|p| (file as u8, rank as u8, p)))
        })
    }

    /// Check if file/rank is on the board.
    pub fn in_bounds(file: u8, rank: u8) -> bool {
        file < 8 && rank < 8
    }
}
