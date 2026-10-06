//! Move generation: pseudo-legal expansion plus legality filtering.
//!
//! [`pseudo_legal_moves`] expands piece movement ignoring self-check;
//! [`legal_moves`] keeps only moves leaving the mover's king safe, which
//! also resolves pins and the en-passant double-vacate edge case.
//! [`apply_move`] advances a position; [`perft`] counts leaf nodes as a
//! diagnostic cross-checked against oracle vectors.
//!
//! Castling requires rights, empty transit, and unattacked king path
//! (including the king's current square). King captures are never
//! generated. Generation order is deterministic: squares ascending,
//! then piece movement order.
//!
//! Oracles: prototype `ref/chess-relay/chess/rules.gd` (pseudo/legal
//! split, castling transit, ep pin fix) and `ref/shakmaty` perft vectors.
//!
//! # Examples
//!
//! ```
//! use chess_relay_core::chess_core::{Board, Color, legal_moves};
//!
//! let board = Board::startpos();
//! assert_eq!(legal_moves(&board, Color::White).len(), 20);
//! # Ok::<(), chess_relay_core::chess_core::IllegalMove>(())
//! ```

use super::board::{Board, CastlingRights};
use super::types::{Color, Move, Piece, Role, Square};

/// Knight jump offsets in (file, rank).
const KNIGHT_STEPS: [(i8, i8); 8] = [
    (1, 2),
    (2, 1),
    (2, -1),
    (1, -2),
    (-1, -2),
    (-2, -1),
    (-2, 1),
    (-1, 2),
];

/// King step offsets in (file, rank).
const KING_STEPS: [(i8, i8); 8] = [
    (1, 1),
    (1, 0),
    (1, -1),
    (0, 1),
    (0, -1),
    (-1, 1),
    (-1, 0),
    (-1, -1),
];

/// Diagonal ray directions in (file, rank).
const DIAGONALS: [(i8, i8); 4] = [(1, 1), (1, -1), (-1, 1), (-1, -1)];

/// Orthogonal ray directions in (file, rank).
const STRAIGHTS: [(i8, i8); 4] = [(1, 0), (-1, 0), (0, 1), (0, -1)];

/// Promotion targets in generation order.
const PROMOTIONS: [Role; 4] = [Role::Queen, Role::Rook, Role::Bishop, Role::Knight];

/// Steps one square, returning `None` past the edge.
fn step(from: Square, df: i8, dr: i8) -> Option<Square> {
    let file = from.file() as i8 + df;
    let rank = from.rank() as i8 + dr;
    if (0..8).contains(&file) && (0..8).contains(&rank) {
        Square::from_xy(file as u8, rank as u8).ok()
    } else {
        None
    }
}

/// Whether `square` is attacked by any piece of colour `by`.
#[must_use]
pub fn is_attacked(board: &Board, square: Square, by: Color) -> bool {
    pawn_attacks(board, square, by)
        || jumps_attack(board, square, by, &KNIGHT_STEPS, Role::Knight)
        || jumps_attack(board, square, by, &KING_STEPS, Role::King)
        || rays_attack(board, square, by, &DIAGONALS, &[Role::Bishop, Role::Queen])
        || rays_attack(board, square, by, &STRAIGHTS, &[Role::Rook, Role::Queen])
}

/// Whether `side`'s king is currently attacked.
#[must_use]
pub fn is_in_check(board: &Board, side: Color) -> bool {
    find_king(board, side).is_some_and(|king| is_attacked(board, king, side.opposite()))
}

fn pawn_attacks(board: &Board, square: Square, by: Color) -> bool {
    // A pawn of colour `by` attacks `square` from one rank behind it.
    let behind: i8 = match by {
        Color::White => -1,
        Color::Black => 1,
    };
    [(-1, behind), (1, behind)]
        .into_iter()
        .filter_map(|(df, dr)| step(square, df, dr))
        .any(|from| board.piece_at(from) == Some(Piece::new(by, Role::Pawn)))
}

fn jumps_attack(board: &Board, square: Square, by: Color, steps: &[(i8, i8)], role: Role) -> bool {
    steps
        .iter()
        .filter_map(|&(df, dr)| step(square, df, dr))
        .any(|from| board.piece_at(from) == Some(Piece::new(by, role)))
}

fn rays_attack(
    board: &Board,
    square: Square,
    by: Color,
    directions: &[(i8, i8)],
    roles: &[Role],
) -> bool {
    directions.iter().any(|&(df, dr)| {
        let mut cursor = step(square, df, dr);
        while let Some(sq) = cursor {
            match board.piece_at(sq) {
                None => cursor = step(sq, df, dr),
                Some(piece) => {
                    return piece.color == by && roles.contains(&piece.role);
                }
            }
        }
        false
    })
}

fn find_king(board: &Board, side: Color) -> Option<Square> {
    (0..64)
        .filter_map(|index| Square::try_new(index).ok())
        .find(|&sq| board.piece_at(sq) == Some(Piece::new(side, Role::King)))
}

/// Pseudo-legal moves for `side`, ignoring self-check.
///
/// King captures are excluded. Castling appears only when `side` is the
/// side to move. Kingless setup boards generate movement without the
/// self-check filter applied later (see [`legal_moves`]).
#[must_use]
pub fn pseudo_legal_moves(board: &Board, side: Color) -> Vec<Move> {
    let mut moves = Vec::new();
    for index in 0..64 {
        // Index range is valid by construction.
        let from = Square::try_new(index).expect("square index is valid");
        if board.piece_at(from).map(|piece| piece.color) != Some(side) {
            continue;
        }
        // Occupant checked above; cannot be missing.
        let piece = board.piece_at(from).expect("square holds own piece");
        match piece.role {
            Role::Pawn => push_pawn(board, from, side, &mut moves),
            Role::Knight => push_jumps(board, from, side, &KNIGHT_STEPS, &mut moves),
            Role::King => {
                push_jumps(board, from, side, &KING_STEPS, &mut moves);
                if side == board.side_to_move() {
                    push_castles(board, from, side, &mut moves);
                }
            }
            Role::Bishop => push_rays(board, from, side, &DIAGONALS, &mut moves),
            Role::Rook => push_rays(board, from, side, &STRAIGHTS, &mut moves),
            Role::Queen => {
                push_rays(board, from, side, &DIAGONALS, &mut moves);
                push_rays(board, from, side, &STRAIGHTS, &mut moves);
            }
        }
    }
    moves
}

/// Legal moves for `side`: pseudo-legal minus self-exposure.
///
/// Boards without a king of `side` (setup only) skip the filter.
#[must_use]
pub fn legal_moves(board: &Board, side: Color) -> Vec<Move> {
    if find_king(board, side).is_none() {
        return pseudo_legal_moves(board, side);
    }
    pseudo_legal_moves(board, side)
        .into_iter()
        .filter(|mv| {
            let next = apply_move(board, mv);
            !is_in_check(&next, side)
        })
        .collect()
}

/// Advances `board` by `mv`, returning the new position.
///
/// Updates en passant, castling rights, clocks, and turn. Assumes a
/// generated move; deeper legality is the caller's concern.
///
/// # Panics
///
/// Panics when `from` holds no piece (caller contract violation).
#[must_use]
pub fn apply_move(board: &Board, mv: &Move) -> Board {
    let mut next = *board;
    let piece = next
        .piece_at(mv.from)
        .expect("applied move departs from an occupied square");
    let is_pawn = piece.role == Role::Pawn;
    let is_capture = next.piece_at(mv.to).is_some();

    // En-passant capture removes the pawn beside the departure rank.
    if is_pawn && Some(mv.to) == board.en_passant() && !is_capture {
        // Departure rank and file are valid by construction.
        let victim = Square::from_xy(mv.to.file(), mv.from.rank())
            .expect("en-passant victim coordinates are valid");
        next.squares[victim.index() as usize] = None;
    }
    next.squares[mv.from.index() as usize] = None;

    // Castling also moves the rook.
    if piece.role == Role::King && mv.from.file().abs_diff(mv.to.file()) == 2 {
        let rank = mv.from.rank();
        let (rook_from_file, rook_to_file) = if mv.to.file() == 6 { (7, 5) } else { (0, 3) };
        // Corner coordinates are valid by construction.
        let rook_from =
            Square::from_xy(rook_from_file, rank).expect("castling rook coordinates are valid");
        let rook_to =
            Square::from_xy(rook_to_file, rank).expect("castling rook coordinates are valid");
        next.squares[rook_to.index() as usize] = next.squares[rook_from.index() as usize].take();
    }

    let placed = match mv.promotion {
        Some(role) => Piece::new(piece.color, role),
        None => piece,
    };
    next.squares[mv.to.index() as usize] = Some(placed);

    update_castling(&mut next, &piece, mv);
    next.en_passant = double_push_target(&piece, mv);
    next.halfmove_clock = if is_pawn || is_capture {
        0
    } else {
        board.halfmove_clock() + 1
    };
    if board.side_to_move() == Color::Black {
        next.fullmove_number = board.fullmove_number() + 1;
    }
    next.side_to_move = board.side_to_move().opposite();
    next
}

/// Counts leaf nodes below `board` at `depth` (diagnostic).
///
/// `perft(board, 1)` equals the legal move count. Vectors must agree
/// with the prototype and shakmaty before rules are called done.
#[must_use]
pub fn perft(board: &Board, depth: u32) -> u64 {
    if depth == 0 {
        return 1;
    }
    legal_moves(board, board.side_to_move())
        .iter()
        .map(|mv| perft(&apply_move(board, mv), depth - 1))
        .sum()
}

fn push_pawn(board: &Board, from: Square, side: Color, moves: &mut Vec<Move>) {
    let (forward, start_rank, promo_rank): (i8, u8, u8) = match side {
        Color::White => (1, 1, 7),
        Color::Black => (-1, 6, 0),
    };
    if let Some(one) = step(from, 0, forward)
        && board.piece_at(one).is_none()
    {
        push_pawn_move(moves, from, one, promo_rank);
        if from.rank() == start_rank
            && let Some(two) = step(one, 0, forward)
            && board.piece_at(two).is_none()
        {
            moves.push(Move {
                from,
                to: two,
                promotion: None,
            });
        }
    }

    for df in [-1, 1] {
        if let Some(to) = step(from, df, forward) {
            let victim = board.piece_at(to);
            let is_en_passant = Some(to) == board.en_passant() && victim.is_none();
            if victim.is_some_and(|piece| piece.color != side && piece.role != Role::King)
                || is_en_passant
            {
                push_pawn_move(moves, from, to, promo_rank);
            }
        }
    }
}

fn push_pawn_move(moves: &mut Vec<Move>, from: Square, to: Square, promo_rank: u8) {
    if to.rank() == promo_rank {
        for &role in &PROMOTIONS {
            moves.push(Move {
                from,
                to,
                promotion: Some(role),
            });
        }
    } else {
        moves.push(Move {
            from,
            to,
            promotion: None,
        });
    }
}

fn push_jumps(board: &Board, from: Square, side: Color, steps: &[(i8, i8)], moves: &mut Vec<Move>) {
    for to in steps.iter().filter_map(|&(df, dr)| step(from, df, dr)) {
        match board.piece_at(to) {
            None => moves.push(Move {
                from,
                to,
                promotion: None,
            }),
            Some(piece) if piece.color != side && piece.role != Role::King => {
                moves.push(Move {
                    from,
                    to,
                    promotion: None,
                });
            }
            Some(_) => {}
        }
    }
}

fn push_rays(
    board: &Board,
    from: Square,
    side: Color,
    directions: &[(i8, i8)],
    moves: &mut Vec<Move>,
) {
    for &(df, dr) in directions {
        let mut cursor = step(from, df, dr);
        while let Some(to) = cursor {
            match board.piece_at(to) {
                None => {
                    moves.push(Move {
                        from,
                        to,
                        promotion: None,
                    });
                    cursor = step(to, df, dr);
                }
                Some(piece) if piece.color != side && piece.role != Role::King => {
                    moves.push(Move {
                        from,
                        to,
                        promotion: None,
                    });
                    break;
                }
                Some(_) => break,
            }
        }
    }
}

fn push_castles(board: &Board, king: Square, side: Color, moves: &mut Vec<Move>) {
    let (home_rank, kingside, queenside) = match side {
        Color::White => (
            0,
            CastlingRights::WHITE_KINGSIDE,
            CastlingRights::WHITE_QUEENSIDE,
        ),
        Color::Black => (
            7,
            CastlingRights::BLACK_KINGSIDE,
            CastlingRights::BLACK_QUEENSIDE,
        ),
    };
    if king.rank() != home_rank || king.file() != 4 {
        return;
    }
    let enemy = side.opposite();
    // Home-rank coordinates are valid by construction.
    let at = |file: u8| Square::from_xy(file, home_rank).expect("home-rank square is valid");
    if board.castling().has(kingside)
        && board.piece_at(at(5)).is_none()
        && board.piece_at(at(6)).is_none()
        && ![4, 5, 6]
            .iter()
            .any(|&file| is_attacked(board, at(file), enemy))
    {
        moves.push(Move {
            from: king,
            to: at(6),
            promotion: None,
        });
    }
    if board.castling().has(queenside)
        && board.piece_at(at(1)).is_none()
        && board.piece_at(at(2)).is_none()
        && board.piece_at(at(3)).is_none()
        && ![4, 3, 2]
            .iter()
            .any(|&file| is_attacked(board, at(file), enemy))
    {
        moves.push(Move {
            from: king,
            to: at(2),
            promotion: None,
        });
    }
}

fn update_castling(next: &mut Board, piece: &Piece, mv: &Move) {
    // King moves vacate both rights; rook traffic on home corners
    // vacates the matching right (departure or capture square).
    if piece.role == Role::King {
        match piece.color {
            Color::White => {
                next.castling.remove(CastlingRights::WHITE_KINGSIDE);
                next.castling.remove(CastlingRights::WHITE_QUEENSIDE);
            }
            Color::Black => {
                next.castling.remove(CastlingRights::BLACK_KINGSIDE);
                next.castling.remove(CastlingRights::BLACK_QUEENSIDE);
            }
        }
    }
    for (square, flag) in [
        (
            Square::try_new(0).expect("corner index is valid"),
            CastlingRights::WHITE_QUEENSIDE,
        ),
        (
            Square::try_new(7).expect("corner index is valid"),
            CastlingRights::WHITE_KINGSIDE,
        ),
        (
            Square::try_new(56).expect("corner index is valid"),
            CastlingRights::BLACK_QUEENSIDE,
        ),
        (
            Square::try_new(63).expect("corner index is valid"),
            CastlingRights::BLACK_KINGSIDE,
        ),
    ] {
        if mv.from == square || mv.to == square {
            next.castling.remove(flag);
        }
    }
}

fn double_push_target(piece: &Piece, mv: &Move) -> Option<Square> {
    if piece.role == Role::Pawn
        && mv.from.file() == mv.to.file()
        && mv.from.rank().abs_diff(mv.to.rank()) == 2
    {
        let mid = (mv.from.rank() + mv.to.rank()) / 2;
        // Mid-rank between two valid pawn ranks is valid.
        return Square::from_xy(mv.from.file(), mid).ok();
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sq(name: &str) -> Square {
        name.parse().unwrap()
    }

    #[test]
    fn startpos_has_twenty_legal_moves() {
        let board = Board::startpos();
        assert_eq!(legal_moves(&board, Color::White).len(), 20);
        assert!(!legal_moves(&board, Color::Black).is_empty());
    }

    #[test]
    fn perft_startpos_matches_oracles() {
        let board = Board::startpos();
        assert_eq!(perft(&board, 1), 20);
        assert_eq!(perft(&board, 2), 400);
        assert_eq!(perft(&board, 3), 8_902);
        assert_eq!(perft(&board, 4), 197_281);
    }

    #[test]
    #[ignore = "slow: 4.8M nodes; run explicitly with -- --ignored"]
    fn perft_startpos_depth_five() {
        assert_eq!(perft(&Board::startpos(), 5), 4_865_609);
    }

    #[test]
    fn perft_kiwipete_matches_oracles() {
        let board: Board = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
            .parse()
            .unwrap();
        assert_eq!(perft(&board, 1), 48);
        assert_eq!(perft(&board, 2), 2_039);
        assert_eq!(perft(&board, 3), 97_862);
    }

    #[test]
    fn perft_endgame_position_matches_oracles() {
        let board: Board = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1".parse().unwrap();
        assert_eq!(perft(&board, 1), 14);
        assert_eq!(perft(&board, 2), 191);
        assert_eq!(perft(&board, 3), 2_812);
        assert_eq!(perft(&board, 4), 43_238);
    }

    #[test]
    fn perft_promotion_heavy_position_matches_oracles() {
        // Firewall position: promotions and rook captures galore.
        let board: Board = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1"
            .parse()
            .unwrap();
        assert_eq!(perft(&board, 1), 6);
        assert_eq!(perft(&board, 2), 264);
        assert_eq!(perft(&board, 3), 9_467);
    }

    #[test]
    fn perft_pin_heavy_position_matches_oracles() {
        let board: Board = "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8"
            .parse()
            .unwrap();
        assert_eq!(perft(&board, 1), 44);
        assert_eq!(perft(&board, 2), 1_486);
        assert_eq!(perft(&board, 3), 62_379);
    }

    #[test]
    fn apply_tracks_rights_en_passant_and_clocks() {
        let start = Board::startpos();
        // Double push sets the target and advances counters.
        let e4: Move = "e2e4".parse().unwrap();
        let after = apply_move(&start, &e4);
        assert_eq!(after.en_passant(), Some(sq("e3")));
        assert_eq!(after.side_to_move(), Color::Black);
        assert_eq!(after.halfmove_clock(), 0);
        assert_eq!(after.fullmove_number(), 1);
        // A quiet knight move ticks the clock and the move number.
        let nf6: Move = "g8f6".parse().unwrap();
        let next = apply_move(&after, &nf6);
        assert_eq!(next.en_passant(), None);
        assert_eq!(next.halfmove_clock(), 1);
        assert_eq!(next.fullmove_number(), 2);

        // King move vacates both rights for the side.
        let open: Board = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1".parse().unwrap();
        let stepped = apply_move(&open, &"e1e2".parse().unwrap());
        assert!(!stepped.castling().is_empty());
        assert!(!stepped.castling().has(CastlingRights::WHITE_KINGSIDE));
        assert!(!stepped.castling().has(CastlingRights::WHITE_QUEENSIDE));
        assert!(stepped.castling().has(CastlingRights::BLACK_KINGSIDE));

        // Capturing a home-corner rook clears that right.
        let loot: Board = "r3k2r/8/8/8/8/8/R7/R3K2R w KQkq - 0 1".parse().unwrap();
        let taken = apply_move(&loot, &"a2a8".parse().unwrap());
        assert!(!taken.castling().has(CastlingRights::BLACK_QUEENSIDE));
        assert!(taken.castling().has(CastlingRights::BLACK_KINGSIDE));
    }

    #[test]
    fn pinned_piece_cannot_expose_king() {
        // Black rook pins the e-pawn to the white king; a bishop tempts
        // it off the file.
        let board: Board = "4k3/8/8/8/4r3/3b4/4P3/4K3 w - - 0 1".parse().unwrap();
        assert!(!is_in_check(&board, Color::White));
        let pawn_moves: Vec<Move> = legal_moves(&board, Color::White)
            .into_iter()
            .filter(|mv| mv.from == sq("e2"))
            .collect();
        // Only e2-e3 survives: e2-e4 is blocked, exd3 drops the pin.
        assert_eq!(pawn_moves.len(), 1);
        assert_eq!(pawn_moves[0].to, sq("e3"));
    }

    #[test]
    fn en_passant_pin_forbids_the_capture() {
        // Rank 5 opens king-to-rook if both pawns leave via ep.
        let board: Board = "4k3/8/8/K2Pp2r/8/8/8/8 w - e6 0 1".parse().unwrap();
        let moves = legal_moves(&board, Color::White);
        assert!(
            !moves
                .iter()
                .any(|mv| mv.from == sq("d5") && mv.to == sq("e6"))
        );
        assert!(
            moves
                .iter()
                .any(|mv| mv.from == sq("d5") && mv.to == sq("d6"))
        );
    }

    #[test]
    fn en_passant_capture_applies() {
        let board: Board = "rnbqkbnr/1pp1pppp/p7/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3"
            .parse()
            .unwrap();
        let capture = Move::new(sq("e5"), sq("d6"), None).unwrap();
        assert!(legal_moves(&board, Color::White).contains(&capture));
        let next = apply_move(&board, &capture);
        assert_eq!(
            next.piece_at(sq("d6")),
            Some(Piece::new(Color::White, Role::Pawn))
        );
        assert_eq!(next.piece_at(sq("d5")), None);
        assert_eq!(next.en_passant(), None);
    }

    #[test]
    fn castling_needs_path_and_safety() {
        // Black rook on e8 checks the white king: no castling either way.
        let board: Board = "4rk2/8/8/8/8/8/5PPP/R3K2R w KQkq - 0 1".parse().unwrap();
        assert!(is_in_check(&board, Color::White));
        let castles: Vec<Move> = legal_moves(&board, Color::White)
            .into_iter()
            .filter(|mv| mv.from == sq("e1") && mv.from.file().abs_diff(mv.to.file()) == 2)
            .collect();
        assert!(castles.is_empty());
    }

    #[test]
    fn kings_are_never_captured() {
        let board: Board = "7k/8/8/8/8/8/8/K6R w - - 0 1".parse().unwrap();
        for mv in legal_moves(&board, Color::White) {
            assert_ne!(
                board.piece_at(mv.to),
                Some(Piece::new(Color::Black, Role::King))
            );
        }
    }
}
