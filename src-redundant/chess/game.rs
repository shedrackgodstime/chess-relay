use crate::chess::board::*;
use crate::chess::moves::*;
use crate::chess::pieces::*;

#[derive(Clone, Debug)]
pub struct GameState {
    pub board: Board,
    pub turn: PieceColor,
    pub castling: CastlingRights,
    pub en_passant: Option<(u8, u8)>,
    pub halfmove_clock: u8,
    pub fullmove_number: u32,
    pub last_move: Option<Move>,
}

impl GameState {
    pub fn new() -> Self {
        GameState {
            board: Board::new(),
            turn: PieceColor::White,
            castling: CastlingRights::default(),
            en_passant: None,
            halfmove_clock: 0,
            fullmove_number: 1,
            last_move: None,
        }
    }

    /// Get legal moves for the piece at (file, rank).
    #[allow(dead_code)]
    pub fn legal_moves_for(&self, file: u8, rank: u8) -> Vec<Move> {
        legal_moves(&self.board, file, rank, &self.castling, self.en_passant)
    }

    /// All legal moves for the current player.
    pub fn all_legal_moves(&self) -> Vec<Move> {
        all_legal_moves(&self.board, self.turn, &self.castling, self.en_passant)
    }

    /// Whether the current player has any legal move.
    #[allow(dead_code)]
    pub fn has_any_legal_move(&self) -> bool {
        !self.all_legal_moves().is_empty()
    }

    /// Whether the current player is in check.
    #[allow(dead_code)]
    pub fn is_check(&self) -> bool {
        is_player_in_check(&self.board, self.turn)
    }

    /// Whether the current player is in checkmate.
    #[allow(dead_code)]
    pub fn is_checkmate(&self) -> bool {
        self.is_check() && !self.has_any_legal_move()
    }

    /// Whether the current player is in stalemate.
    #[allow(dead_code)]
    pub fn is_stalemate(&self) -> bool {
        !self.is_check() && !self.has_any_legal_move()
    }

    /// Apply a move, updating all state.
    pub fn apply_move(&mut self, mv: &Move) {
        let moving_piece = self.board.get(mv.from_file, mv.from_rank);
        let captured = self.board.get(mv.to_file, mv.to_rank);

        // En passant capture
        let mut ep_captured = None;
        if let Some(piece) = moving_piece
            && piece.piece_type == PieceType::Pawn
            && mv.to_file != mv.from_file
            && captured.is_none()
            && let Some((ep_file, _)) = self.en_passant
            && mv.to_file == ep_file
        {
            ep_captured = self.board.remove(mv.to_file, mv.from_rank);
        }

        // Execute move
        apply_move_inner_public(&mut self.board, mv, self.en_passant);

        // Update castling rights
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
                PieceType::Rook => match (mv.from_file, mv.from_rank) {
                    (0, 0) => self.castling.white_queenside = false,
                    (7, 0) => self.castling.white_kingside = false,
                    (0, 7) => self.castling.black_queenside = false,
                    (7, 7) => self.castling.black_kingside = false,
                    _ => {}
                },
                _ => {}
            }
        }

        // Rook captured
        match (mv.to_file, mv.to_rank) {
            (0, 0) => self.castling.white_queenside = false,
            (7, 0) => self.castling.white_kingside = false,
            (0, 7) => self.castling.black_queenside = false,
            (7, 7) => self.castling.black_kingside = false,
            _ => {}
        }

        // En passant target
        self.en_passant = moving_piece.and_then(|p| {
            if p.piece_type == PieceType::Pawn && mv.to_rank.abs_diff(mv.from_rank) == 2 {
                let ep_rank = (mv.from_rank + mv.to_rank) / 2;
                Some((mv.from_file, ep_rank))
            } else {
                None
            }
        });

        // Halfmove clock
        let is_capture = captured.is_some() || ep_captured.is_some();
        let is_pawn_move = moving_piece.is_some_and(|p| p.piece_type == PieceType::Pawn);
        if is_capture || is_pawn_move {
            self.halfmove_clock = 0;
        } else {
            self.halfmove_clock += 1;
        }

        // Fullmove number
        if self.turn == PieceColor::Black {
            self.fullmove_number += 1;
        }

        // Switch turn
        self.turn = self.turn.opponent();
        self.last_move = Some(*mv);
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
        }
    }

    fn place(state: &mut GameState, file: u8, rank: u8, pt: PieceType, color: PieceColor) {
        state.board.set(
            file,
            rank,
            Some(Piece {
                color,
                piece_type: pt,
            }),
        );
    }

    mod board_tests {
        use crate::chess::board::*;
        use crate::chess::pieces::*;

        #[test]
        fn starting_position_has_32_pieces() {
            let board = Board::new();
            assert_eq!(board.iter().count(), 32);
        }

        #[test]
        fn starting_position_white_back_rank() {
            let board = Board::new();
            assert_eq!(board.get(0, 0).unwrap().piece_type, PieceType::Rook);
            assert_eq!(board.get(1, 0).unwrap().piece_type, PieceType::Knight);
            assert_eq!(board.get(2, 0).unwrap().piece_type, PieceType::Bishop);
            assert_eq!(board.get(3, 0).unwrap().piece_type, PieceType::Queen);
            assert_eq!(board.get(4, 0).unwrap().piece_type, PieceType::King);
            assert_eq!(board.get(5, 0).unwrap().piece_type, PieceType::Bishop);
            assert_eq!(board.get(6, 0).unwrap().piece_type, PieceType::Knight);
            assert_eq!(board.get(7, 0).unwrap().piece_type, PieceType::Rook);
        }

        #[test]
        fn find_king_returns_correct_position() {
            let board = Board::new();
            assert_eq!(board.find_king(PieceColor::White), Some((4, 0)));
            assert_eq!(board.find_king(PieceColor::Black), Some((4, 7)));
        }

        #[test]
        fn remove_and_set_work() {
            let mut board = Board::empty();
            board.set(
                3,
                4,
                Some(Piece {
                    color: PieceColor::White,
                    piece_type: PieceType::Queen,
                }),
            );
            assert!(board.get(3, 4).is_some());
            assert_eq!(board.remove(3, 4).unwrap().piece_type, PieceType::Queen);
            assert!(board.get(3, 4).is_none());
        }
    }

    mod move_tests {
        use crate::chess::board::*;
        use crate::chess::moves::*;
        use crate::chess::pieces::*;

        fn board_with(positions: &[(u8, u8, PieceType, PieceColor)]) -> Board {
            let mut board = Board::empty();
            for &(f, r, pt, c) in positions {
                board.set(
                    f,
                    r,
                    Some(Piece {
                        color: c,
                        piece_type: pt,
                    }),
                );
            }
            board
        }

        #[test]
        fn knight_moves_from_center() {
            let board = board_with(&[(3, 3, PieceType::Knight, PieceColor::White)]);
            let moves = pseudo_legal_moves(&board, 3, 3, None);
            assert_eq!(moves.len(), 8);
        }

        #[test]
        fn knight_moves_from_corner() {
            let board = board_with(&[(0, 0, PieceType::Knight, PieceColor::White)]);
            let moves = pseudo_legal_moves(&board, 0, 0, None);
            assert_eq!(moves.len(), 2);
        }

        #[test]
        fn pawn_double_advance_from_start() {
            let board = board_with(&[(4, 1, PieceType::Pawn, PieceColor::White)]);
            let moves = pseudo_legal_moves(&board, 4, 1, None);
            assert!(moves.iter().any(|m| m.to_file == 4 && m.to_rank == 3));
            assert!(moves.iter().any(|m| m.to_file == 4 && m.to_rank == 2));
        }

        #[test]
        fn pawn_capture_diagonal() {
            let board = board_with(&[
                (4, 4, PieceType::Pawn, PieceColor::White),
                (3, 5, PieceType::Pawn, PieceColor::Black),
                (5, 5, PieceType::Pawn, PieceColor::Black),
            ]);
            let moves = pseudo_legal_moves(&board, 4, 4, None);
            assert!(moves.iter().any(|m| m.to_file == 3 && m.to_rank == 5));
            assert!(moves.iter().any(|m| m.to_file == 5 && m.to_rank == 5));
        }

        #[test]
        fn pawn_promotion_generates_four_choices() {
            let board = board_with(&[(4, 6, PieceType::Pawn, PieceColor::White)]);
            let moves = pseudo_legal_moves(&board, 4, 6, None);
            assert_eq!(moves.len(), 4);
            for mv in &moves {
                assert!(mv.promotion.is_some());
            }
        }

        #[test]
        fn en_passant_captures_correct_square() {
            let board = board_with(&[
                (4, 4, PieceType::Pawn, PieceColor::White),
                (3, 4, PieceType::Pawn, PieceColor::Black),
            ]);
            // En passant target behind the black pawn
            let moves = pseudo_legal_moves(&board, 4, 4, Some((3, 5)));
            assert!(moves.iter().any(|m| m.to_file == 3 && m.to_rank == 5));
        }

        #[test]
        fn rook_slides_orthogonally() {
            let board = board_with(&[(3, 3, PieceType::Rook, PieceColor::White)]);
            let moves = pseudo_legal_moves(&board, 3, 3, None);
            // 7 up, 7 down, 7 left-ish, 7 right-ish = up to 14
            assert!(moves.len() >= 13);
        }

        #[test]
        fn bishop_slides_diagonally() {
            let board = board_with(&[(3, 3, PieceType::Bishop, PieceColor::White)]);
            let moves = pseudo_legal_moves(&board, 3, 3, None);
            assert!(moves.len() >= 10);
        }

        #[test]
        fn queen_slides_everywhere() {
            let board = board_with(&[(3, 3, PieceType::Queen, PieceColor::White)]);
            let moves = pseudo_legal_moves(&board, 3, 3, None);
            assert!(moves.len() >= 23);
        }

        #[test]
        fn king_moves_one_square() {
            let board = board_with(&[(3, 3, PieceType::King, PieceColor::White)]);
            let moves = pseudo_legal_moves(&board, 3, 3, None);
            assert_eq!(moves.len(), 8);
        }

        #[test]
        fn is_attacked_detects_knight() {
            let board = board_with(&[
                (4, 4, PieceType::King, PieceColor::White),
                (6, 5, PieceType::Knight, PieceColor::Black),
            ]);
            assert!(is_attacked(&board, 4, 4, PieceColor::Black));
        }

        #[test]
        fn is_attacked_detects_rook() {
            let board = board_with(&[
                (4, 4, PieceType::King, PieceColor::White),
                (4, 7, PieceType::Rook, PieceColor::Black),
            ]);
            assert!(is_attacked(&board, 4, 4, PieceColor::Black));
        }

        #[test]
        fn is_attacked_detects_bishop() {
            let board = board_with(&[
                (4, 4, PieceType::King, PieceColor::White),
                (7, 7, PieceType::Bishop, PieceColor::Black),
            ]);
            assert!(is_attacked(&board, 4, 4, PieceColor::Black));
        }

        #[test]
        fn is_attacked_detects_queen() {
            let board = board_with(&[
                (4, 4, PieceType::King, PieceColor::White),
                (4, 0, PieceType::Queen, PieceColor::Black),
            ]);
            assert!(is_attacked(&board, 4, 4, PieceColor::Black));
        }

        #[test]
        fn is_attacked_detects_pawn() {
            let board = board_with(&[
                (4, 4, PieceType::King, PieceColor::White),
                (3, 3, PieceType::Pawn, PieceColor::Black),
            ]);
            assert!(is_attacked(&board, 4, 4, PieceColor::Black));
        }

        #[test]
        fn is_attached_detects_king() {
            let board = board_with(&[
                (4, 4, PieceType::King, PieceColor::White),
                (5, 5, PieceType::King, PieceColor::Black),
            ]);
            assert!(is_attacked(&board, 4, 4, PieceColor::Black));
        }
    }

    mod game_state_tests {
        use super::{empty_state, place};
        use crate::chess::game::*;
        use crate::chess::moves::is_player_in_check;

        #[test]
        fn initial_state_turn_is_white() {
            let state = GameState::new();
            assert_eq!(state.turn, PieceColor::White);
        }

        #[test]
        fn apply_pawn_double_advance_sets_en_passant() {
            let mut state = GameState::new();
            let mv = Move::new((4, 1), (4, 3)); // e2 → e4
            state.apply_move(&mv);
            assert_eq!(state.en_passant, Some((4, 2)));
            assert_eq!(state.turn, PieceColor::Black);
        }

        #[test]
        fn apply_simple_move_switches_turn() {
            let mut state = GameState::new();
            let mv = Move::new((4, 1), (4, 2)); // e2 → e3
            state.apply_move(&mv);
            assert_eq!(state.turn, PieceColor::Black);
            assert_eq!(state.halfmove_clock, 0);
        }

        #[test]
        fn is_checkmate_false_on_initial_position() {
            let state = GameState::new();
            assert!(!state.is_checkmate());
            assert!(!state.is_stalemate());
        }

        #[test]
        fn simple_checkmate() {
            // Black king cornered by white queen + king
            let mut state = empty_state();
            place(&mut state, 0, 7, PieceType::King, PieceColor::Black);
            place(&mut state, 1, 7, PieceType::Queen, PieceColor::White);
            place(&mut state, 1, 6, PieceType::King, PieceColor::White);
            state.turn = PieceColor::Black;

            // Black king on a8 (0,7), white queen on b8 (1,7) checks
            // King can't capture queen (white king on b7 defends)
            // King can't move to b7 (white king), b8 (queen), a7 (white king attacks from b6)
            assert!(state.is_checkmate());
        }

        #[test]
        fn castling_moves_generated_for_white() {
            let mut state = empty_state();
            place(&mut state, 4, 0, PieceType::King, PieceColor::White);
            place(&mut state, 7, 0, PieceType::Rook, PieceColor::White);
            state.castling.white_kingside = true;

            let moves = state.all_legal_moves();
            assert!(
                moves.iter().any(|m| m.from_file == 4
                    && m.from_rank == 0
                    && m.to_file == 6
                    && m.to_rank == 0)
            );
        }

        #[test]
        fn castling_requires_rook_on_home_square() {
            let mut state = empty_state();
            place(&mut state, 4, 0, PieceType::King, PieceColor::White);
            state.castling.white_kingside = true;

            let moves = state.all_legal_moves();
            assert!(!moves.iter().any(|m| {
                m.from_file == 4 && m.from_rank == 0 && m.to_file == 6 && m.to_rank == 0
            }));
        }

        #[test]
        fn castling_move_updates_rook_position() {
            let mut state = empty_state();
            place(&mut state, 4, 0, PieceType::King, PieceColor::White);
            place(&mut state, 7, 0, PieceType::Rook, PieceColor::White);
            state.castling.white_kingside = true;
            state.turn = PieceColor::White;

            let mv = Move::new((4, 0), (6, 0));
            state.apply_move(&mv);
            assert_eq!(state.board.get(5, 0).unwrap().piece_type, PieceType::Rook);
            assert!(state.board.get(7, 0).is_none());
        }

        #[test]
        fn cannot_castle_through_check() {
            let mut state = empty_state();
            place(&mut state, 4, 0, PieceType::King, PieceColor::White);
            place(&mut state, 7, 0, PieceType::Rook, PieceColor::White);
            place(&mut state, 5, 3, PieceType::Rook, PieceColor::Black);
            state.castling.white_kingside = true;

            let moves = state.all_legal_moves();
            assert!(!moves.iter().any(|m| m.from_file == 4 && m.to_file == 6));
        }

        #[test]
        fn en_passant_captures_pawn() {
            let mut state = empty_state();
            place(&mut state, 4, 4, PieceType::Pawn, PieceColor::White);
            place(&mut state, 3, 4, PieceType::Pawn, PieceColor::Black);
            state.en_passant = Some((3, 5));
            state.turn = PieceColor::White;

            let mv = Move::new((4, 4), (3, 5));
            state.apply_move(&mv);
            assert!(state.board.get(3, 4).is_none());
            assert_eq!(state.board.get(3, 5).unwrap().piece_type, PieceType::Pawn);
        }

        #[test]
        fn promotion_replace_pawn_with_queen() {
            let mut state = empty_state();
            place(&mut state, 4, 6, PieceType::Pawn, PieceColor::White);
            state.turn = PieceColor::White;

            let mv = Move::with_promotion((4, 6), (4, 7), PieceType::Queen);
            state.apply_move(&mv);
            assert_eq!(state.board.get(4, 7).unwrap().piece_type, PieceType::Queen);
        }

        #[test]
        fn fifty_move_count_increments() {
            let mut state = GameState::new();
            // Move a knight back and forth
            state.apply_move(&Move::new((1, 0), (2, 2)));
            state.apply_move(&Move::new((6, 7), (5, 5)));
            state.apply_move(&Move::new((2, 2), (1, 0)));
            state.apply_move(&Move::new((5, 5), (6, 7)));
            // 4 non-pawn, non-capture moves
            assert_eq!(state.halfmove_clock, 4);
        }

        #[test]
        fn pawn_move_resets_halfmove_clock() {
            let mut state = GameState::new();
            state.apply_move(&Move::new((1, 0), (2, 2)));
            state.apply_move(&Move::new((6, 7), (5, 5)));
            // Halfmove clock = 2 (two knight moves)
            state.apply_move(&Move::new((4, 1), (4, 3)));
            // Pawn move resets to 0
            assert_eq!(state.halfmove_clock, 0);
        }

        #[test]
        fn capture_resets_halfmove_clock() {
            let mut state = GameState::new();
            state.apply_move(&Move::new((4, 1), (4, 3)));
            state.apply_move(&Move::new((3, 6), (3, 4)));
            // e4 d5
            state.apply_move(&Move::new((4, 3), (3, 4)));
            // exd5 — capture, clock reset
            assert_eq!(state.halfmove_clock, 0);
        }

        #[test]
        fn all_legal_moves_in_starting_position() {
            let state = GameState::new();
            let moves = state.all_legal_moves();
            // White has 20 legal moves in starting position
            assert_eq!(moves.len(), 20);
        }

        #[test]
        fn bishop_checks_king() {
            let mut state = empty_state();
            place(&mut state, 4, 0, PieceType::King, PieceColor::White);
            place(&mut state, 0, 4, PieceType::Bishop, PieceColor::Black);
            // Bishop at a5 attacks king at e1 along diagonal
            assert!(is_player_in_check(&state.board, PieceColor::White));
        }

        #[test]
        fn piece_can_block_check() {
            let mut state = empty_state();
            place(&mut state, 4, 0, PieceType::King, PieceColor::White);
            place(&mut state, 4, 7, PieceType::Rook, PieceColor::Black);
            place(&mut state, 4, 5, PieceType::Queen, PieceColor::White);
            state.turn = PieceColor::White;

            // Rook checks king along e-file, queen can block at e3 (4,2)
            let moves = state.all_legal_moves();
            assert!(moves.iter().any(|m| m.to_file == 4 && m.to_rank == 2));
        }

        #[test]
        fn pinned_pawn_cannot_capture() {
            let mut state = empty_state();
            place(&mut state, 4, 1, PieceType::King, PieceColor::White);
            place(&mut state, 4, 2, PieceType::Pawn, PieceColor::White);
            place(&mut state, 4, 7, PieceType::Rook, PieceColor::Black);
            place(&mut state, 5, 2, PieceType::Queen, PieceColor::Black);
            state.turn = PieceColor::White;

            // Pawn at e3 (4,2) is pinned by rook on e8 (4,7) against king at e2 (4,1)
            // Pawn would like to capture queen on f3 (5,2), but that exposes king
            let moves = legal_moves(&state.board, 4, 2, &state.castling, None);
            assert!(!moves.iter().any(|m| m.to_file == 5 && m.to_rank == 2));
        }
    }
}
