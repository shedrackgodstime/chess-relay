//! Played game: position stream plus rules-based outcomes.
//!
//! A [`Game`] wraps a [`Board`] with repetition history and answers the
//! only question chess rules ask about a match: is it over, and how?
//! Resignation, abort, and agreed draws are session outcomes, not chess
//! rules, and live one layer up.
//!
//! Draw simplifications (documented, prototype-compatible): threefold is
//! automatic rather than claimed; fifty moves means 100 halfmoves without
//! pawn move or capture; two knights versus bare king is drawn. These
//! match `ref/chess-relay/chess/game.gd` and suit clock-less casual play.
//!
//! Repetition keys include the en-passant square only when an en-passant
//! capture is actually available, per FIDE sameness.
//!
//! # Examples
//!
//! ```
//! use chess_relay_core::chess_core::{Game, Outcome};
//!
//! let mut game = Game::from_startpos();
//! game.play(&"f2f3".parse()?)?;
//! game.play(&"e7e5".parse()?)?;
//! game.play(&"g2g4".parse()?)?;
//! let outcome = game.play(&"d8h4".parse()?)?; // Fool's mate.
//! assert!(matches!(outcome, Outcome::Checkmate { .. }));
//! # Ok::<(), chess_relay_core::chess_core::IllegalMove>(())
//! ```

use super::board::Board;
use super::movegen::{apply_move, is_in_check, legal_moves};
use super::types::{Color, IllegalMove, Move, Piece, Role, Square};
use std::collections::HashMap;

/// How a game ended, or that it continues.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Outcome {
    /// Play continues.
    Ongoing,
    /// Side to move is checkmated; `winner` delivered mate.
    Checkmate {
        /// Mating side.
        winner: Color,
    },
    /// Side to move has no legal move and is not in check.
    Stalemate,
    /// Drawn for a rules reason.
    Draw(DrawReason),
}

/// Why a game was drawn.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum DrawReason {
    /// 100 halfmoves without pawn move or capture.
    FiftyMove,
    /// Same position (FIDE sameness) appeared three times.
    Threefold,
    /// Neither side can possibly mate.
    InsufficientMaterial,
}

/// Position key for repetition (FIDE sameness).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
struct RepetitionKey {
    squares: [Option<Piece>; 64],
    side_to_move: Color,
    castling: super::board::CastlingRights,
    en_passant: Option<Square>,
}

/// Played game from a starting board to an outcome.
///
/// Owns the repetition table chess rules need. The signed match record
/// used for sync and replay belongs to the session layer, not here.
#[derive(Clone, Debug)]
pub struct Game {
    board: Board,
    counts: HashMap<RepetitionKey, u32>,
}

impl Game {
    /// Starts from `board`, registering its position once.
    #[must_use]
    pub fn new(board: Board) -> Self {
        let mut game = Self {
            board,
            counts: HashMap::new(),
        };
        game.register();
        game
    }

    /// Starts from the standard initial position.
    #[must_use]
    pub fn from_startpos() -> Self {
        Self::new(Board::startpos())
    }

    /// Current position.
    #[must_use]
    pub fn board(&self) -> &Board {
        &self.board
    }

    /// Legal moves for the side to move.
    #[must_use]
    pub fn legal_moves(&self) -> Vec<Move> {
        legal_moves(&self.board, self.board.side_to_move())
    }

    /// Current outcome without moving.
    #[must_use]
    pub fn outcome(&self) -> Outcome {
        decide(&self.board, &self.counts)
    }

    /// Plays `mv` for the side to move, returning the new outcome.
    ///
    /// # Errors
    ///
    /// Returns [`IllegalMove`] when the game is already over, or when
    /// `mv` is not legal in this position.
    pub fn play(&mut self, mv: &Move) -> Result<Outcome, IllegalMove> {
        if self.outcome() != Outcome::Ongoing {
            return Err(IllegalMove::not_legal("game is over".to_string()));
        }
        if !self.legal_moves().contains(mv) {
            return Err(IllegalMove::not_legal(format!("{mv}")));
        }
        self.board = apply_move(&self.board, mv);
        self.register();
        Ok(self.outcome())
    }

    fn register(&mut self) {
        let key = repetition_key(&self.board);
        *self.counts.entry(key).or_insert(0) += 1;
    }
}

fn repetition_key(board: &Board) -> RepetitionKey {
    // FIDE: positions differ on en passant only when a capture exists.
    let en_passant = board.en_passant().filter(|&ep| {
        legal_moves(board, board.side_to_move()).iter().any(|mv| {
            mv.to == ep
                && board
                    .piece_at(mv.from)
                    .is_some_and(|p| p.role == Role::Pawn)
        })
    });
    let mut squares = [None; 64];
    for index in 0..64 {
        // Index range is valid by construction.
        let sq = Square::try_new(index).expect("square index is valid");
        squares[index as usize] = board.piece_at(sq);
    }
    RepetitionKey {
        squares,
        side_to_move: board.side_to_move(),
        castling: board.castling(),
        en_passant,
    }
}

fn decide(board: &Board, counts: &HashMap<RepetitionKey, u32>) -> Outcome {
    if board.halfmove_clock() >= 100 {
        return Outcome::Draw(DrawReason::FiftyMove);
    }
    if counts.get(&repetition_key(board)).is_some_and(|&n| n >= 3) {
        return Outcome::Draw(DrawReason::Threefold);
    }
    if insufficient_material(board) {
        return Outcome::Draw(DrawReason::InsufficientMaterial);
    }
    let side = board.side_to_move();
    if legal_moves(board, side).is_empty() {
        if is_in_check(board, side) {
            return Outcome::Checkmate {
                winner: side.opposite(),
            };
        }
        return Outcome::Stalemate;
    }
    Outcome::Ongoing
}

/// Whether neither side can possibly mate (prototype-compatible set).
fn insufficient_material(board: &Board) -> bool {
    // Minors per side as (role, square-colour parity) pairs.
    let mut white: Vec<(Role, u8)> = Vec::new();
    let mut black: Vec<(Role, u8)> = Vec::new();
    for index in 0..64 {
        // Index range is valid by construction.
        let sq = Square::try_new(index).expect("square index is valid");
        match board.piece_at(sq) {
            None
            | Some(Piece {
                role: Role::King, ..
            }) => {}
            Some(Piece {
                role: Role::Pawn | Role::Rook | Role::Queen,
                ..
            }) => return false,
            Some(Piece { color, role }) => {
                let minor = (role, (sq.file() + sq.rank()) % 2);
                match color {
                    Color::White => white.push(minor),
                    Color::Black => black.push(minor),
                }
            }
        }
    }
    match (white.len(), black.len()) {
        (0, 0) => true,          // Bare kings.
        (1, 0) | (0, 1) => true, // Single minor versus bare king.
        _ => {
            let all = white.iter().chain(&black);
            if all.clone().all(|&(role, _)| role == Role::Bishop)
                && same_square_colour(white.iter().chain(&black).map(|&(_, c)| c))
            {
                return true; // Bishops locked on one square colour.
            }
            // Two knights on one side cannot force mate.
            matches!(
                (&white[..], &black[..]),
                ([(Role::Knight, _), (Role::Knight, _)], [])
                    | ([], [(Role::Knight, _), (Role::Knight, _)])
            )
        }
    }
}

fn same_square_colour(colours: impl Iterator<Item = u8>) -> bool {
    let mut colours = colours;
    match colours.next() {
        None => false,
        Some(first) => colours.all(|c| c == first),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn play_all(game: &mut Game, ucis: &[&str]) -> Outcome {
        let mut outcome = Outcome::Ongoing;
        for uci in ucis {
            let mv: Move = uci.parse().unwrap();
            outcome = game.play(&mv).unwrap();
        }
        outcome
    }

    #[test]
    fn scholars_mate_checkmates() {
        let mut game = Game::from_startpos();
        let outcome = play_all(
            &mut game,
            &["e2e4", "e7e5", "d1h5", "b8c6", "f1c4", "g8f6", "h5f7"],
        );
        assert_eq!(
            outcome,
            Outcome::Checkmate {
                winner: Color::White
            }
        );
    }

    #[test]
    fn stalemate_draws() {
        let game = Game::new("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1".parse().unwrap());
        assert_eq!(game.outcome(), Outcome::Stalemate);
    }

    #[test]
    fn fifty_moves_draw() {
        let mut game = Game::new("4k3/8/8/8/8/5N2/3n4/4K3 w - - 99 1".parse().unwrap());
        let outcome = game.play(&"e1e2".parse().unwrap()).unwrap();
        assert_eq!(outcome, Outcome::Draw(DrawReason::FiftyMove));
    }

    #[test]
    fn threefold_draws() {
        let mut game = Game::from_startpos();
        // Side to move is part of the key: the third P0 lands on ply 8.
        let outcome = play_all(
            &mut game,
            &[
                "g1f3", "g8f6", "f3g1", "f6g8", "g1f3", "g8f6", "f3g1", "f6g8",
            ],
        );
        assert_eq!(outcome, Outcome::Draw(DrawReason::Threefold));
        // Further play is refused; the position is untouched.
        let before = game.board().to_fen();
        assert!(
            game.play(&"g1f3".parse().unwrap())
                .unwrap_err()
                .is_not_legal()
        );
        assert_eq!(game.board().to_fen(), before);
    }

    #[test]
    fn dead_positions_draw() {
        for fen in [
            "4k3/8/8/8/8/8/8/4K3 w - - 0 1",    // Bare kings.
            "4k3/8/8/8/8/5N2/8/4K3 w - - 0 1",  // Single knight.
            "8/8/8/3b4/8/5B2/8/4K2k w - - 0 1", // Same-coloured bishops.
            "7k/8/8/8/8/5N1N/8/4K3 w - - 0 1",  // Two knights vs bare king.
        ] {
            let game = Game::new(fen.parse().unwrap());
            assert_eq!(
                game.outcome(),
                Outcome::Draw(DrawReason::InsufficientMaterial),
                "{fen}"
            );
        }
        let live = Game::new("4k3/8/8/8/8/5N2/3B4/4K3 w - - 0 1".parse().unwrap());
        assert_eq!(live.outcome(), Outcome::Ongoing);
    }

    #[test]
    fn illegal_play_rejected_without_state_change() {
        let mut game = Game::from_startpos();
        let before = game.board().to_fen();
        let err = game.play(&"e2e5".parse().unwrap()).unwrap_err();
        assert!(err.is_not_legal());
        assert!(!err.is_parse());
        assert_eq!(game.board().to_fen(), before);
    }
}
