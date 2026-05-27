#![allow(clippy::manual_range_contains)]

use crate::chess::board::*;
use crate::chess::pieces::*;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Move {
    pub from_file: u8,
    pub from_rank: u8,
    pub to_file: u8,
    pub to_rank: u8,
    pub promotion: Option<PieceType>,
}

impl Move {
    pub fn new(from: (u8, u8), to: (u8, u8)) -> Self {
        Move {
            from_file: from.0,
            from_rank: from.1,
            to_file: to.0,
            to_rank: to.1,
            promotion: None,
        }
    }

    pub fn with_promotion(from: (u8, u8), to: (u8, u8), pt: PieceType) -> Self {
        Move {
            from_file: from.0,
            from_rank: from.1,
            to_file: to.0,
            to_rank: to.1,
            promotion: Some(pt),
        }
    }
}

/// Generate pseudo-legal moves for a piece at (file, rank).
/// These ignore pins, check, and castling-through-check rules.
pub fn pseudo_legal_moves(
    board: &Board,
    file: u8,
    rank: u8,
    en_passant: Option<(u8, u8)>,
) -> Vec<Move> {
    let piece = match board.get(file, rank) {
        Some(p) => p,
        None => return vec![],
    };

    match piece.piece_type {
        PieceType::Pawn => pawn_moves(board, file, rank, piece.color, en_passant),
        PieceType::Knight => knight_moves(board, file, rank, piece.color),
        PieceType::King => king_moves(board, file, rank, piece.color),
        PieceType::Bishop => slide_moves(
            board,
            file,
            rank,
            piece.color,
            &[(1, 1), (1, -1), (-1, 1), (-1, -1)],
        ),
        PieceType::Rook => slide_moves(
            board,
            file,
            rank,
            piece.color,
            &[(1, 0), (-1, 0), (0, 1), (0, -1)],
        ),
        PieceType::Queen => {
            let mut moves = slide_moves(
                board,
                file,
                rank,
                piece.color,
                &[(1, 1), (1, -1), (-1, 1), (-1, -1)],
            );
            moves.extend(slide_moves(
                board,
                file,
                rank,
                piece.color,
                &[(1, 0), (-1, 0), (0, 1), (0, -1)],
            ));
            moves
        }
    }
}

fn is_empty_or_enemy(board: &Board, file: u8, rank: u8, color: PieceColor) -> bool {
    Board::in_bounds(file, rank) && board.get(file, rank).is_none_or(|p| p.color != color)
}

fn is_enemy(board: &Board, file: u8, rank: u8, color: PieceColor) -> bool {
    Board::in_bounds(file, rank) && board.get(file, rank).is_some_and(|p| p.color != color)
}

fn is_empty(board: &Board, file: u8, rank: u8) -> bool {
    Board::in_bounds(file, rank) && board.get(file, rank).is_none()
}

fn pawn_moves(
    board: &Board,
    file: u8,
    rank: u8,
    color: PieceColor,
    en_passant: Option<(u8, u8)>,
) -> Vec<Move> {
    let mut moves = Vec::new();
    let dir: i8 = if color == PieceColor::White { 1 } else { -1 };
    let start_rank: u8 = if color == PieceColor::White { 1 } else { 6 };
    let promote_rank: u8 = if color == PieceColor::White { 7 } else { 0 };

    let new_rank = (rank as i8 + dir) as u8;

    // Forward one
    if is_empty(board, file, new_rank) {
        if new_rank == promote_rank {
            for pt in &[
                PieceType::Queen,
                PieceType::Rook,
                PieceType::Bishop,
                PieceType::Knight,
            ] {
                moves.push(Move::with_promotion((file, rank), (file, new_rank), *pt));
            }
        } else {
            moves.push(Move::new((file, rank), (file, new_rank)));
        }

        // Forward two from start
        if rank == start_rank {
            let new_rank2 = (rank as i8 + 2 * dir) as u8;
            if is_empty(board, file, new_rank2) {
                moves.push(Move::new((file, rank), (file, new_rank2)));
            }
        }
    }

    // Captures
    for df in &[-1i8, 1i8] {
        let new_file = (file as i8 + df) as u8;
        if !Board::in_bounds(new_file, new_rank) {
            continue;
        }
        if is_enemy(board, new_file, new_rank, color) {
            if new_rank == promote_rank {
                for pt in &[
                    PieceType::Queen,
                    PieceType::Rook,
                    PieceType::Bishop,
                    PieceType::Knight,
                ] {
                    moves.push(Move::with_promotion(
                        (file, rank),
                        (new_file, new_rank),
                        *pt,
                    ));
                }
            } else {
                moves.push(Move::new((file, rank), (new_file, new_rank)));
            }
        }
        // En passant
        if let Some((ep_file, ep_rank)) = en_passant
            && new_file == ep_file
            && new_rank == ep_rank
        {
            moves.push(Move::new((file, rank), (new_file, new_rank)));
        }
    }

    moves
}

fn knight_moves(board: &Board, file: u8, rank: u8, color: PieceColor) -> Vec<Move> {
    let offsets = [
        (2, 1),
        (2, -1),
        (-2, 1),
        (-2, -1),
        (1, 2),
        (1, -2),
        (-1, 2),
        (-1, -2),
    ];
    let mut moves = Vec::new();
    for (df, dr) in offsets {
        let nf = file as i8 + df;
        let nr = rank as i8 + dr;
        if (0..8).contains(&nf) && (0..8).contains(&nr) {
            let (nf, nr) = (nf as u8, nr as u8);
            if is_empty_or_enemy(board, nf, nr, color) {
                moves.push(Move::new((file, rank), (nf, nr)));
            }
        }
    }
    moves
}

fn king_moves(board: &Board, file: u8, rank: u8, color: PieceColor) -> Vec<Move> {
    let offsets = [
        (1, 0),
        (-1, 0),
        (0, 1),
        (0, -1),
        (1, 1),
        (1, -1),
        (-1, 1),
        (-1, -1),
    ];
    let mut moves = Vec::new();
    for (df, dr) in offsets {
        let nf = file as i8 + df;
        let nr = rank as i8 + dr;
        if (0..8).contains(&nf) && (0..8).contains(&nr) {
            let (nf, nr) = (nf as u8, nr as u8);
            if is_empty_or_enemy(board, nf, nr, color) {
                moves.push(Move::new((file, rank), (nf, nr)));
            }
        }
    }
    // Castling moves are added by the legal_moves function, not here
    moves
}

fn slide_moves(
    board: &Board,
    file: u8,
    rank: u8,
    color: PieceColor,
    directions: &[(i8, i8)],
) -> Vec<Move> {
    let mut moves = Vec::new();
    for (df, dr) in directions {
        let mut nf = file as i8 + df;
        let mut nr = rank as i8 + dr;
        while nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
            let (uf, ur) = (nf as u8, nr as u8);
            if let Some(p) = board.get(uf, ur) {
                if p.color != color {
                    moves.push(Move::new((file, rank), (uf, ur)));
                }
                break;
            }
            moves.push(Move::new((file, rank), (uf, ur)));
            nf += df;
            nr += dr;
        }
    }
    moves
}

/// Check if any enemy piece attacks (file, rank).
pub fn is_attacked(board: &Board, file: u8, rank: u8, by: PieceColor) -> bool {
    // Check knight attacks
    let knight_offsets = [
        (2, 1),
        (2, -1),
        (-2, 1),
        (-2, -1),
        (1, 2),
        (1, -2),
        (-1, 2),
        (-1, -2),
    ];
    for (df, dr) in knight_offsets {
        let nf = file as i8 + df;
        let nr = rank as i8 + dr;
        if (0..8).contains(&nf)
            && (0..8).contains(&nr)
            && let Some(p) = board.get(nf as u8, nr as u8)
            && p.color == by
            && p.piece_type == PieceType::Knight
        {
            return true;
        }
    }

    // Check diagonal slides (bishop/queen)
    let diagonals = [(1, 1), (1, -1), (-1, 1), (-1, -1)];
    for (df, dr) in diagonals {
        let mut nf = file as i8 + df;
        let mut nr = rank as i8 + dr;
        while (0..8).contains(&nf) && (0..8).contains(&nr) {
            if let Some(p) = board.get(nf as u8, nr as u8) {
                if p.color == by
                    && (p.piece_type == PieceType::Bishop || p.piece_type == PieceType::Queen)
                {
                    return true;
                }
                break;
            }
            nf += df;
            nr += dr;
        }
    }

    // Check orthogonal slides (rook/queen)
    let straights = [(1, 0), (-1, 0), (0, 1), (0, -1)];
    for (df, dr) in straights {
        let mut nf = file as i8 + df;
        let mut nr = rank as i8 + dr;
        while (0..8).contains(&nf) && (0..8).contains(&nr) {
            if let Some(p) = board.get(nf as u8, nr as u8) {
                if p.color == by
                    && (p.piece_type == PieceType::Rook || p.piece_type == PieceType::Queen)
                {
                    return true;
                }
                break;
            }
            nf += df;
            nr += dr;
        }
    }

    // Check king attacks (adjacent squares)
    let king_offsets = [
        (1, 0),
        (-1, 0),
        (0, 1),
        (0, -1),
        (1, 1),
        (1, -1),
        (-1, 1),
        (-1, -1),
    ];
    for (df, dr) in king_offsets {
        let nf = file as i8 + df;
        let nr = rank as i8 + dr;
        if (0..8).contains(&nf)
            && (0..8).contains(&nr)
            && let Some(p) = board.get(nf as u8, nr as u8)
            && p.color == by
            && p.piece_type == PieceType::King
        {
            return true;
        }
    }

    // Check pawn attacks
    let pawn_dir: i8 = if by == PieceColor::White { 1 } else { -1 };
    for df in &[-1i8, 1i8] {
        let nf = file as i8 + df;
        let nr = rank as i8 + pawn_dir;
        if (0..8).contains(&nf)
            && (0..8).contains(&nr)
            && let Some(p) = board.get(nf as u8, nr as u8)
            && p.color == by
            && p.piece_type == PieceType::Pawn
        {
            return true;
        }
    }

    false
}

/// Generate all legal moves for a piece at (file, rank).
pub fn legal_moves(
    board: &Board,
    file: u8,
    rank: u8,
    castling: &CastlingRights,
    en_passant: Option<(u8, u8)>,
) -> Vec<Move> {
    let pseudo = pseudo_legal_moves(board, file, rank, en_passant);
    let piece = match board.get(file, rank) {
        Some(p) => p,
        None => return vec![],
    };

    let mut legal = Vec::new();
    for mv in pseudo {
        let mut sim = board.clone();
        apply_move_inner(&mut sim, &mv, en_passant);

        // After making the move, our king must not be in check
        if let Some((kf, kr)) = sim.find_king(piece.color)
            && !is_attacked(&sim, kf, kr, piece.color.opponent())
        {
            legal.push(mv);
        }
    }

    // Castling
    if piece.piece_type == PieceType::King {
        let (file, rank) = (file, rank);
        // Only add castling if still at starting position (ruling out moves that moved king and back)
        if (piece.color == PieceColor::White && rank == 0 && file == 4)
            || (piece.color == PieceColor::Black && rank == 7 && file == 4)
        {
            let opponent = piece.color.opponent();

            // Kingside
            if can_castle_kingside(board, castling, piece.color, opponent) {
                legal.push(Move::new((file, rank), (6, rank)));
            }

            // Queenside
            if can_castle_queenside(board, castling, piece.color, opponent) {
                legal.push(Move::new((file, rank), (2, rank)));
            }
        }
    }

    legal
}

fn can_castle_kingside(
    board: &Board,
    rights: &CastlingRights,
    color: PieceColor,
    opponent: PieceColor,
) -> bool {
    match color {
        PieceColor::White => {
            if !rights.white_kingside {
                return false;
            }
            let rook_ready = board.get(7, 0).is_some_and(|piece| {
                piece.color == PieceColor::White && piece.piece_type == PieceType::Rook
            });
            rook_ready
                && board.get(5, 0).is_none()
                && board.get(6, 0).is_none()
                && !is_attacked(board, 4, 0, opponent)
                && !is_attacked(board, 5, 0, opponent)
                && !is_attacked(board, 6, 0, opponent)
        }
        PieceColor::Black => {
            if !rights.black_kingside {
                return false;
            }
            let rook_ready = board.get(7, 7).is_some_and(|piece| {
                piece.color == PieceColor::Black && piece.piece_type == PieceType::Rook
            });
            rook_ready
                && board.get(5, 7).is_none()
                && board.get(6, 7).is_none()
                && !is_attacked(board, 4, 7, opponent)
                && !is_attacked(board, 5, 7, opponent)
                && !is_attacked(board, 6, 7, opponent)
        }
    }
}

fn can_castle_queenside(
    board: &Board,
    rights: &CastlingRights,
    color: PieceColor,
    opponent: PieceColor,
) -> bool {
    match color {
        PieceColor::White => {
            if !rights.white_queenside {
                return false;
            }
            let rook_ready = board.get(0, 0).is_some_and(|piece| {
                piece.color == PieceColor::White && piece.piece_type == PieceType::Rook
            });
            rook_ready
                && board.get(1, 0).is_none()
                && board.get(2, 0).is_none()
                && board.get(3, 0).is_none()
                && !is_attacked(board, 4, 0, opponent)
                && !is_attacked(board, 3, 0, opponent)
                && !is_attacked(board, 2, 0, opponent)
        }
        PieceColor::Black => {
            if !rights.black_queenside {
                return false;
            }
            let rook_ready = board.get(0, 7).is_some_and(|piece| {
                piece.color == PieceColor::Black && piece.piece_type == PieceType::Rook
            });
            rook_ready
                && board.get(1, 7).is_none()
                && board.get(2, 7).is_none()
                && board.get(3, 7).is_none()
                && !is_attacked(board, 4, 7, opponent)
                && !is_attacked(board, 3, 7, opponent)
                && !is_attacked(board, 2, 7, opponent)
        }
    }
}

/// Apply a move to a board (no validation, used for simulation).
fn apply_move_inner(board: &mut Board, mv: &Move, en_passant: Option<(u8, u8)>) {
    let piece = match board.remove(mv.from_file, mv.from_rank) {
        Some(p) => p,
        None => return,
    };

    // En passant capture
    if piece.piece_type == PieceType::Pawn
        && mv.to_file != mv.from_file
        && board.get(mv.to_file, mv.to_rank).is_none()
        && let Some((ep_file, ep_rank)) = en_passant
        && mv.to_file == ep_file
        && mv.to_rank == ep_rank
    {
        board.remove(mv.to_file, mv.from_rank);
    }

    // Promotion
    if let Some(pt) = mv.promotion {
        board.set(
            mv.to_file,
            mv.to_rank,
            Some(Piece {
                color: piece.color,
                piece_type: pt,
            }),
        );
    } else {
        board.set(mv.to_file, mv.to_rank, Some(piece));
    }

    // Castling rook movement
    let is_king = piece.piece_type == PieceType::King;
    if is_king {
        let diff = mv.to_file as i8 - mv.from_file as i8;
        if diff == 2 {
            // Kingside
            if mv.to_rank == 0 {
                if let Some(rook) = board.remove(7, 0) {
                    board.set(5, 0, Some(rook));
                }
            } else {
                if let Some(rook) = board.remove(7, 7) {
                    board.set(5, 7, Some(rook));
                }
            }
        } else if diff == -2 {
            // Queenside
            if mv.to_rank == 0 {
                if let Some(rook) = board.remove(0, 0) {
                    board.set(3, 0, Some(rook));
                }
            } else {
                if let Some(rook) = board.remove(0, 7) {
                    board.set(3, 7, Some(rook));
                }
            }
        }
    }
}

/// Apply a move to a board (public, called from GameState).
pub fn apply_move_inner_public(board: &mut Board, mv: &Move, en_passant: Option<(u8, u8)>) {
    apply_move_inner(board, mv, en_passant);
}

/// Generate all legal moves for the current player.
pub fn all_legal_moves(
    board: &Board,
    turn: PieceColor,
    castling: &CastlingRights,
    en_passant: Option<(u8, u8)>,
) -> Vec<Move> {
    let mut moves = Vec::new();
    for (file, rank, piece) in board.iter() {
        if piece.color == turn {
            moves.extend(legal_moves(board, file, rank, castling, en_passant));
        }
    }
    moves
}

/// Check if the given player's king is in check.
pub fn is_player_in_check(board: &Board, color: PieceColor) -> bool {
    board
        .find_king(color)
        .is_some_and(|(kf, kr)| is_attacked(board, kf, kr, color.opponent()))
}
