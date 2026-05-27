//! Move generation, attack detection, and move application helpers.

#![allow(clippy::manual_range_contains)]

use super::{Board, CastlingRights, Piece, PieceColor, PieceType};

/// A fully specified move between two squares, with optional promotion.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct ChessMove {
    /// Origin file.
    pub from_file: u8,
    /// Origin rank.
    pub from_rank: u8,
    /// Destination file.
    pub to_file: u8,
    /// Destination rank.
    pub to_rank: u8,
    /// Promotion choice for pawn promotions.
    pub promotion: Option<PieceType>,
}

impl ChessMove {
    /// Creates a non-promotion move from one square to another.
    #[must_use]
    pub fn new(from: (u8, u8), to: (u8, u8)) -> Self {
        Self {
            from_file: from.0,
            from_rank: from.1,
            to_file: to.0,
            to_rank: to.1,
            promotion: None,
        }
    }

    /// Creates a promotion move with the chosen promotion piece.
    #[must_use]
    pub fn with_promotion(from: (u8, u8), to: (u8, u8), piece_type: PieceType) -> Self {
        Self {
            from_file: from.0,
            from_rank: from.1,
            to_file: to.0,
            to_rank: to.1,
            promotion: Some(piece_type),
        }
    }
}

/// Generates pseudo-legal moves for the piece on `(file, rank)`.
#[must_use]
pub fn pseudo_legal_moves(
    board: &Board,
    file: u8,
    rank: u8,
    en_passant: Option<(u8, u8)>,
) -> Vec<ChessMove> {
    let piece = match board.get(file, rank) {
        Some(piece) => piece,
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
    Board::in_bounds(file, rank)
        && board
            .get(file, rank)
            .is_none_or(|piece| piece.color != color)
}

fn is_enemy(board: &Board, file: u8, rank: u8, color: PieceColor) -> bool {
    Board::in_bounds(file, rank)
        && board
            .get(file, rank)
            .is_some_and(|piece| piece.color != color)
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
) -> Vec<ChessMove> {
    let mut moves = Vec::new();
    let direction: i8 = if color == PieceColor::White { 1 } else { -1 };
    let start_rank = if color == PieceColor::White { 1 } else { 6 };
    let promotion_rank = if color == PieceColor::White { 7 } else { 0 };
    let next_rank = (rank as i8 + direction) as u8;

    if is_empty(board, file, next_rank) {
        if next_rank == promotion_rank {
            for piece_type in [
                PieceType::Queen,
                PieceType::Rook,
                PieceType::Bishop,
                PieceType::Knight,
            ] {
                moves.push(ChessMove::with_promotion(
                    (file, rank),
                    (file, next_rank),
                    piece_type,
                ));
            }
        } else {
            moves.push(ChessMove::new((file, rank), (file, next_rank)));
        }

        if rank == start_rank {
            let jump_rank = (rank as i8 + 2 * direction) as u8;
            if is_empty(board, file, jump_rank) {
                moves.push(ChessMove::new((file, rank), (file, jump_rank)));
            }
        }
    }

    for file_delta in [-1i8, 1i8] {
        let next_file = (file as i8 + file_delta) as u8;
        if !Board::in_bounds(next_file, next_rank) {
            continue;
        }

        if is_enemy(board, next_file, next_rank, color) {
            if next_rank == promotion_rank {
                for piece_type in [
                    PieceType::Queen,
                    PieceType::Rook,
                    PieceType::Bishop,
                    PieceType::Knight,
                ] {
                    moves.push(ChessMove::with_promotion(
                        (file, rank),
                        (next_file, next_rank),
                        piece_type,
                    ));
                }
            } else {
                moves.push(ChessMove::new((file, rank), (next_file, next_rank)));
            }
        }

        if let Some((en_passant_file, en_passant_rank)) = en_passant
            && next_file == en_passant_file
            && next_rank == en_passant_rank
        {
            moves.push(ChessMove::new((file, rank), (next_file, next_rank)));
        }
    }

    moves
}

fn knight_moves(board: &Board, file: u8, rank: u8, color: PieceColor) -> Vec<ChessMove> {
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

    for (file_delta, rank_delta) in offsets {
        let next_file = file as i8 + file_delta;
        let next_rank = rank as i8 + rank_delta;
        if (0..8).contains(&next_file) && (0..8).contains(&next_rank) {
            let next_file = next_file as u8;
            let next_rank = next_rank as u8;
            if is_empty_or_enemy(board, next_file, next_rank, color) {
                moves.push(ChessMove::new((file, rank), (next_file, next_rank)));
            }
        }
    }

    moves
}

fn king_moves(board: &Board, file: u8, rank: u8, color: PieceColor) -> Vec<ChessMove> {
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

    for (file_delta, rank_delta) in offsets {
        let next_file = file as i8 + file_delta;
        let next_rank = rank as i8 + rank_delta;
        if (0..8).contains(&next_file) && (0..8).contains(&next_rank) {
            let next_file = next_file as u8;
            let next_rank = next_rank as u8;
            if is_empty_or_enemy(board, next_file, next_rank, color) {
                moves.push(ChessMove::new((file, rank), (next_file, next_rank)));
            }
        }
    }

    moves
}

fn slide_moves(
    board: &Board,
    file: u8,
    rank: u8,
    color: PieceColor,
    directions: &[(i8, i8)],
) -> Vec<ChessMove> {
    let mut moves = Vec::new();

    for (file_delta, rank_delta) in directions {
        let mut next_file = file as i8 + file_delta;
        let mut next_rank = rank as i8 + rank_delta;

        while (0..8).contains(&next_file) && (0..8).contains(&next_rank) {
            let target_file = next_file as u8;
            let target_rank = next_rank as u8;
            if let Some(piece) = board.get(target_file, target_rank) {
                if piece.color != color {
                    moves.push(ChessMove::new((file, rank), (target_file, target_rank)));
                }
                break;
            }

            moves.push(ChessMove::new((file, rank), (target_file, target_rank)));
            next_file += file_delta;
            next_rank += rank_delta;
        }
    }

    moves
}

/// Returns `true` when `(file, rank)` is attacked by the given side.
#[must_use]
pub fn is_attacked(board: &Board, file: u8, rank: u8, by: PieceColor) -> bool {
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
    for (file_delta, rank_delta) in knight_offsets {
        let next_file = file as i8 + file_delta;
        let next_rank = rank as i8 + rank_delta;
        if (0..8).contains(&next_file)
            && (0..8).contains(&next_rank)
            && let Some(piece) = board.get(next_file as u8, next_rank as u8)
            && piece.color == by
            && piece.piece_type == PieceType::Knight
        {
            return true;
        }
    }

    for (file_delta, rank_delta) in [(1, 1), (1, -1), (-1, 1), (-1, -1)] {
        let mut next_file = file as i8 + file_delta;
        let mut next_rank = rank as i8 + rank_delta;
        while (0..8).contains(&next_file) && (0..8).contains(&next_rank) {
            if let Some(piece) = board.get(next_file as u8, next_rank as u8) {
                if piece.color == by
                    && (piece.piece_type == PieceType::Bishop
                        || piece.piece_type == PieceType::Queen)
                {
                    return true;
                }
                break;
            }
            next_file += file_delta;
            next_rank += rank_delta;
        }
    }

    for (file_delta, rank_delta) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
        let mut next_file = file as i8 + file_delta;
        let mut next_rank = rank as i8 + rank_delta;
        while (0..8).contains(&next_file) && (0..8).contains(&next_rank) {
            if let Some(piece) = board.get(next_file as u8, next_rank as u8) {
                if piece.color == by
                    && (piece.piece_type == PieceType::Rook || piece.piece_type == PieceType::Queen)
                {
                    return true;
                }
                break;
            }
            next_file += file_delta;
            next_rank += rank_delta;
        }
    }

    for (file_delta, rank_delta) in [
        (1, 0),
        (-1, 0),
        (0, 1),
        (0, -1),
        (1, 1),
        (1, -1),
        (-1, 1),
        (-1, -1),
    ] {
        let next_file = file as i8 + file_delta;
        let next_rank = rank as i8 + rank_delta;
        if (0..8).contains(&next_file)
            && (0..8).contains(&next_rank)
            && let Some(piece) = board.get(next_file as u8, next_rank as u8)
            && piece.color == by
            && piece.piece_type == PieceType::King
        {
            return true;
        }
    }

    let pawn_rank_delta = if by == PieceColor::White { 1 } else { -1 };
    for file_delta in [-1i8, 1i8] {
        let next_file = file as i8 + file_delta;
        let next_rank = rank as i8 + pawn_rank_delta;
        if (0..8).contains(&next_file)
            && (0..8).contains(&next_rank)
            && let Some(piece) = board.get(next_file as u8, next_rank as u8)
            && piece.color == by
            && piece.piece_type == PieceType::Pawn
        {
            return true;
        }
    }

    false
}

/// Generates fully legal moves for the piece on `(file, rank)`.
#[must_use]
pub fn legal_moves(
    board: &Board,
    file: u8,
    rank: u8,
    castling: &CastlingRights,
    en_passant: Option<(u8, u8)>,
) -> Vec<ChessMove> {
    let pseudo = pseudo_legal_moves(board, file, rank, en_passant);
    let piece = match board.get(file, rank) {
        Some(piece) => piece,
        None => return vec![],
    };

    let mut legal = Vec::new();
    for chess_move in pseudo {
        let mut simulated = board.clone();
        let simulated_en_passant = if piece.piece_type == PieceType::Pawn
            && chess_move.from_file != chess_move.to_file
            && board.get(chess_move.to_file, chess_move.to_rank).is_none()
        {
            en_passant
        } else {
            None
        };
        apply_move_inner(&mut simulated, &chess_move, simulated_en_passant);

        if let Some((king_file, king_rank)) = simulated.find_king(piece.color)
            && !is_attacked(&simulated, king_file, king_rank, piece.color.opponent())
        {
            legal.push(chess_move);
        }
    }

    if piece.piece_type == PieceType::King
        && ((piece.color == PieceColor::White && rank == 0 && file == 4)
            || (piece.color == PieceColor::Black && rank == 7 && file == 4))
    {
        let opponent = piece.color.opponent();
        if can_castle_kingside(board, castling, piece.color, opponent) {
            legal.push(ChessMove::new((file, rank), (6, rank)));
        }
        if can_castle_queenside(board, castling, piece.color, opponent) {
            legal.push(ChessMove::new((file, rank), (2, rank)));
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

fn apply_move_inner(board: &mut Board, chess_move: &ChessMove, en_passant: Option<(u8, u8)>) {
    let piece = match board.remove(chess_move.from_file, chess_move.from_rank) {
        Some(piece) => piece,
        None => return,
    };

    if piece.piece_type == PieceType::Pawn
        && chess_move.to_file != chess_move.from_file
        && board.get(chess_move.to_file, chess_move.to_rank).is_none()
        && let Some((en_passant_file, en_passant_rank)) = en_passant
        && chess_move.to_file == en_passant_file
        && chess_move.to_rank == en_passant_rank
    {
        let _ = board.remove(chess_move.to_file, chess_move.from_rank);
    }

    if let Some(piece_type) = chess_move.promotion {
        let _ = board.set(
            chess_move.to_file,
            chess_move.to_rank,
            Some(Piece {
                color: piece.color,
                piece_type,
            }),
        );
    } else {
        let _ = board.set(chess_move.to_file, chess_move.to_rank, Some(piece));
    }

    if piece.piece_type == PieceType::King {
        let delta = chess_move.to_file as i8 - chess_move.from_file as i8;
        if delta == 2 {
            if chess_move.to_rank == 0 {
                if let Some(rook) = board.remove(7, 0) {
                    let _ = board.set(5, 0, Some(rook));
                }
            } else if let Some(rook) = board.remove(7, 7) {
                let _ = board.set(5, 7, Some(rook));
            }
        } else if delta == -2 {
            if chess_move.to_rank == 0 {
                if let Some(rook) = board.remove(0, 0) {
                    let _ = board.set(3, 0, Some(rook));
                }
            } else if let Some(rook) = board.remove(0, 7) {
                let _ = board.set(3, 7, Some(rook));
            }
        }
    }
}

/// Applies a move to a board using the supplied en passant context.
pub fn apply_move_inner_public(
    board: &mut Board,
    chess_move: &ChessMove,
    en_passant: Option<(u8, u8)>,
) {
    apply_move_inner(board, chess_move, en_passant);
}

/// Returns every legal move for the given side in the current position.
#[must_use]
pub fn all_legal_moves(
    board: &Board,
    turn: PieceColor,
    castling: &CastlingRights,
    en_passant: Option<(u8, u8)>,
) -> Vec<ChessMove> {
    let mut moves = Vec::new();
    for (file, rank, piece) in board.iter() {
        if piece.color == turn {
            moves.extend(legal_moves(board, file, rank, castling, en_passant));
        }
    }

    moves
}

/// Returns `true` when the given side's king is currently in check.
#[must_use]
pub fn is_player_in_check(board: &Board, color: PieceColor) -> bool {
    board
        .find_king(color)
        .is_some_and(|(file, rank)| is_attacked(board, file, rank, color.opponent()))
}
