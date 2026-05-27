//! Game-state transitions built on top of the pure board and move logic.

use super::{
    Board, CastlingRights, ChessMove, GameStatus, Piece, PieceColor, PieceType, all_legal_moves,
    apply_move_inner_public, is_player_in_check, legal_moves,
};

/// Stores the full mutable state of a chess game.
#[derive(Clone, Debug)]
pub struct GameState {
    /// The 8×8 board with all currently placed pieces.
    pub board: Board,
    /// Which side is to move next.
    pub turn: PieceColor,
    /// Castling availability for both sides.
    pub castling: CastlingRights,
    /// En passant capture target square, if any.
    pub en_passant: Option<(u8, u8)>,
    /// Halfmove clock for the 50-move rule.
    pub halfmove_clock: u8,
    /// Full-move counter (starts at 1, increments after Black moves).
    pub fullmove_number: u32,
    /// The most recent move played, for UI highlighting.
    pub last_move: Option<ChessMove>,
    /// Pieces captured so far during the game.
    pub captured: Vec<Piece>,
    position_history: Vec<u64>,
}

impl GameState {
    /// Creates a new game in the standard starting position.
    #[must_use]
    pub fn new() -> Self {
        let mut state = Self {
            board: Board::new(),
            turn: PieceColor::White,
            castling: CastlingRights::default(),
            en_passant: None,
            halfmove_clock: 0,
            fullmove_number: 1,
            last_move: None,
            captured: Vec::new(),
            position_history: Vec::new(),
        };
        state.position_history.push(state.position_key());
        state
    }

    /// Returns all legal moves for the piece at the given square.
    #[must_use]
    pub fn legal_moves_for(&self, file: u8, rank: u8) -> Vec<ChessMove> {
        legal_moves(&self.board, file, rank, &self.castling, self.en_passant)
    }

    /// Returns every legal move for the current side to move.
    #[must_use]
    pub fn all_legal_moves(&self) -> Vec<ChessMove> {
        all_legal_moves(&self.board, self.turn, &self.castling, self.en_passant)
    }

    /// Returns `true` when the current side has at least one legal move.
    #[must_use]
    pub fn has_any_legal_move(&self) -> bool {
        !self.all_legal_moves().is_empty()
    }

    /// Returns `true` when the current side's king is in check.
    #[must_use]
    pub fn is_check(&self) -> bool {
        is_player_in_check(&self.board, self.turn)
    }

    /// Returns `true` when the current side is in checkmate.
    #[must_use]
    pub fn is_checkmate(&self) -> bool {
        self.is_check() && !self.has_any_legal_move()
    }

    /// Returns `true` when the current side is stalemated.
    #[must_use]
    pub fn is_stalemate(&self) -> bool {
        !self.is_check() && !self.has_any_legal_move()
    }

    #[must_use]
    fn position_key(&self) -> u64 {
        let mut hash: u64 = 0;
        for (file, rank, piece) in self.board.iter() {
            let idx = rank as u64 * 8 + file as u64;
            let piece_val: u64 = match piece.piece_type {
                PieceType::Pawn => 1,
                PieceType::Knight => 2,
                PieceType::Bishop => 3,
                PieceType::Rook => 4,
                PieceType::Queen => 5,
                PieceType::King => 6,
            };
            let color_val: u64 = if piece.color == PieceColor::Black {
                1
            } else {
                0
            };
            hash ^= idx
                .wrapping_mul(13)
                .wrapping_add(piece_val.wrapping_mul(37) + color_val.wrapping_mul(71));
        }
        if self.castling.white_kingside {
            hash ^= 1 << 16;
        }
        if self.castling.white_queenside {
            hash ^= 1 << 17;
        }
        if self.castling.black_kingside {
            hash ^= 1 << 18;
        }
        if self.castling.black_queenside {
            hash ^= 1 << 19;
        }
        if let Some((f, r)) = self.en_passant {
            hash ^= (f as u64) << 20;
            hash ^= (r as u64) << 24;
        }
        hash ^= if self.turn == PieceColor::White {
            1 << 28
        } else {
            0
        };
        hash
    }

    /// Returns `true` when the halfmove clock exceeds 100.
    #[must_use]
    pub fn is_fifty_move_draw(&self) -> bool {
        self.halfmove_clock >= 100
    }

    /// Returns `true` when the same position has occurred three times.
    #[must_use]
    pub fn is_threefold_repetition(&self) -> bool {
        if self.position_history.len() < 4 {
            return false;
        }
        let last = self.position_history.last().copied().unwrap_or(0);
        let mut count = 0u32;
        for &key in self.position_history.iter().rev() {
            if key == last {
                count += 1;
                if count >= 3 {
                    return true;
                }
            }
        }
        false
    }

    /// Returns `true` when neither side can force checkmate.
    #[must_use]
    pub fn is_insufficient_material(&self) -> bool {
        let pieces: Vec<Piece> = self.board.iter().map(|(_, _, p)| p).collect();
        if pieces.len() <= 2 {
            return true;
        }
        let non_kings: Vec<&Piece> = pieces
            .iter()
            .filter(|p| p.piece_type != PieceType::King)
            .collect();
        if non_kings.len() == 1 {
            let pt = non_kings[0].piece_type;
            if matches!(pt, PieceType::Bishop | PieceType::Knight) {
                return true;
            }
        }
        if non_kings.len() == 2 {
            let bishops: Vec<&&Piece> = non_kings
                .iter()
                .filter(|p| p.piece_type == PieceType::Bishop)
                .collect();
            if bishops.len() == 2 {
                let mut squares: Vec<(u8, u8)> = vec![];
                for (f, r, piece) in self.board.iter() {
                    if piece.piece_type == PieceType::Bishop {
                        squares.push((f, r));
                    }
                }
                if squares.len() == 2
                    && (squares[0].0 + squares[0].1) % 2 == (squares[1].0 + squares[1].1) % 2
                {
                    return true;
                }
            }
            let knights: Vec<&&Piece> = non_kings
                .iter()
                .filter(|p| p.piece_type == PieceType::Knight)
                .collect();
            if knights.len() == 2 {
                return true;
            }
        }
        false
    }

    /// Evaluates the current position and returns the game status.
    pub fn status(&self) -> GameStatus {
        if self.is_checkmate() {
            return GameStatus::Checkmate {
                winner: self.turn.opponent(),
            };
        }
        if self.is_stalemate() {
            return GameStatus::Stalemate;
        }
        if self.is_fifty_move_draw() {
            return GameStatus::FiftyMoveDraw;
        }
        if self.is_threefold_repetition() {
            return GameStatus::ThreefoldRepetitionDraw;
        }
        if self.is_insufficient_material() {
            return GameStatus::InsufficientMaterialDraw;
        }
        if self.is_check() {
            return GameStatus::Check(self.turn);
        }
        GameStatus::InProgress
    }

    /// Applies a legal chess move and advances the game state.
    pub fn apply_move(&mut self, chess_move: &ChessMove) {
        let moving_piece = self.board.get(chess_move.from_file, chess_move.from_rank);
        let captured_piece = self.board.get(chess_move.to_file, chess_move.to_rank);

        let mut en_passant_capture = None;
        if let Some(piece) = moving_piece
            && piece.piece_type == PieceType::Pawn
            && chess_move.to_file != chess_move.from_file
            && captured_piece.is_none()
            && let Some((en_passant_file, _)) = self.en_passant
            && chess_move.to_file == en_passant_file
        {
            en_passant_capture = self.board.remove(chess_move.to_file, chess_move.from_rank);
        }

        apply_move_inner_public(&mut self.board, chess_move, self.en_passant);

        if let Some(piece) = moving_piece {
            match piece.piece_type {
                PieceType::King => match piece.color {
                    PieceColor::White => {
                        self.castling.white_kingside = false;
                        self.castling.white_queenside = false;
                    }
                    PieceColor::Black => {
                        self.castling.black_kingside = false;
                        self.castling.black_queenside = false;
                    }
                },
                PieceType::Rook => match (chess_move.from_file, chess_move.from_rank) {
                    (0, 0) => self.castling.white_queenside = false,
                    (7, 0) => self.castling.white_kingside = false,
                    (0, 7) => self.castling.black_queenside = false,
                    (7, 7) => self.castling.black_kingside = false,
                    _ => {}
                },
                _ => {}
            }
        }

        match (chess_move.to_file, chess_move.to_rank) {
            (0, 0) => self.castling.white_queenside = false,
            (7, 0) => self.castling.white_kingside = false,
            (0, 7) => self.castling.black_queenside = false,
            (7, 7) => self.castling.black_kingside = false,
            _ => {}
        }

        self.en_passant = moving_piece.and_then(|piece| {
            if piece.piece_type == PieceType::Pawn
                && chess_move.to_rank.abs_diff(chess_move.from_rank) == 2
            {
                Some((
                    chess_move.from_file,
                    (chess_move.from_rank + chess_move.to_rank) / 2,
                ))
            } else {
                None
            }
        });

        if let Some(piece) = captured_piece {
            self.captured.push(piece);
        }
        if let Some(piece) = en_passant_capture {
            self.captured.push(piece);
        }

        let is_capture = captured_piece.is_some() || en_passant_capture.is_some();
        let is_pawn_move = moving_piece.is_some_and(|piece| piece.piece_type == PieceType::Pawn);
        if is_capture || is_pawn_move {
            self.halfmove_clock = 0;
        } else {
            self.halfmove_clock += 1;
        }

        if self.turn == PieceColor::Black {
            self.fullmove_number += 1;
        }

        self.turn = self.turn.opponent();
        self.last_move = Some(*chess_move);
        self.position_history.push(self.position_key());
    }
}

impl Default for GameState {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn empty_state() -> GameState {
        GameState {
            board: Board::empty(),
            turn: PieceColor::White,
            castling: CastlingRights {
                white_kingside: false,
                white_queenside: false,
                black_kingside: false,
                black_queenside: false,
            },
            en_passant: None,
            halfmove_clock: 0,
            fullmove_number: 1,
            last_move: None,
            captured: Vec::new(),
            position_history: Vec::new(),
        }
    }

    fn place(state: &mut GameState, file: u8, rank: u8, piece_type: PieceType, color: PieceColor) {
        let _ = state
            .board
            .set(file, rank, Some(Piece { color, piece_type }));
    }

    #[test]
    fn starting_position_has_32_pieces() {
        let board = Board::new();
        assert_eq!(board.iter().count(), 32);
    }

    #[test]
    fn starting_position_white_has_20_legal_moves() {
        let state = GameState::new();
        assert_eq!(state.all_legal_moves().len(), 20);
    }

    #[test]
    fn pawn_double_advance_sets_en_passant_target() {
        let mut state = GameState::new();
        state.apply_move(&ChessMove::new((4, 1), (4, 3)));
        assert_eq!(state.en_passant, Some((4, 2)));
        assert_eq!(state.turn, PieceColor::Black);
    }

    #[test]
    fn castling_move_repositions_rook() {
        let mut state = empty_state();
        place(&mut state, 4, 0, PieceType::King, PieceColor::White);
        place(&mut state, 7, 0, PieceType::Rook, PieceColor::White);
        state.castling.white_kingside = true;

        state.apply_move(&ChessMove::new((4, 0), (6, 0)));
        assert_eq!(state.board.get(5, 0).unwrap().piece_type, PieceType::Rook);
        assert!(state.board.get(7, 0).is_none());
    }

    #[test]
    fn en_passant_capture_removes_pawn() {
        let mut state = empty_state();
        place(&mut state, 4, 4, PieceType::Pawn, PieceColor::White);
        place(&mut state, 3, 4, PieceType::Pawn, PieceColor::Black);
        state.en_passant = Some((3, 5));

        state.apply_move(&ChessMove::new((4, 4), (3, 5)));
        assert!(state.board.get(3, 4).is_none());
        assert_eq!(state.board.get(3, 5).unwrap().piece_type, PieceType::Pawn);
    }

    #[test]
    fn promotion_replaces_pawn() {
        let mut state = empty_state();
        place(&mut state, 4, 6, PieceType::Pawn, PieceColor::White);

        state.apply_move(&ChessMove::with_promotion((4, 6), (4, 7), PieceType::Queen));
        assert_eq!(state.board.get(4, 7).unwrap().piece_type, PieceType::Queen);
    }

    #[test]
    fn detects_checkmate() {
        let mut state = empty_state();
        place(&mut state, 0, 7, PieceType::King, PieceColor::Black);
        place(&mut state, 1, 7, PieceType::Queen, PieceColor::White);
        place(&mut state, 1, 6, PieceType::King, PieceColor::White);
        state.turn = PieceColor::Black;

        assert!(state.is_checkmate());
        assert_eq!(
            state.status(),
            GameStatus::Checkmate {
                winner: PieceColor::White
            }
        );
    }

    #[test]
    fn pinned_pawn_cannot_move_off_file() {
        let mut state = empty_state();
        place(&mut state, 4, 1, PieceType::King, PieceColor::White);
        place(&mut state, 4, 2, PieceType::Pawn, PieceColor::White);
        place(&mut state, 4, 7, PieceType::Rook, PieceColor::Black);
        place(&mut state, 5, 3, PieceType::Queen, PieceColor::Black);

        let moves = state.legal_moves_for(4, 2);
        assert!(!moves.iter().any(|chess_move| chess_move.to_file == 5));
    }
}
