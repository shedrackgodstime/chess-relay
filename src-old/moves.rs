use bevy::prelude::Entity;

use crate::pieces::*;

#[derive(Clone)]
struct Occupant {
    entity: Entity,
    color: PieceColor,
    piece_type: PieceType,
}

type Board = [[Option<Occupant>; 8]; 8];

fn build_board(pieces: &[(Entity, PieceColor, PieceType, u8, u8)]) -> Board {
    let mut board: Board = core::array::from_fn(|_| core::array::from_fn(|_| None));
    for &(entity, color, piece_type, x, y) in pieces {
        board[x as usize][y as usize] = Some(Occupant { entity, color, piece_type });
    }
    board
}

fn on_board(x: u8, y: u8) -> bool {
    x < 8 && y < 8
}

fn add_if<P>(moves: &mut Vec<(u8, u8)>, x: u8, y: u8, board: &Board, _color: PieceColor, pred: P)
where
    P: Fn(&Occupant) -> bool,
{
    if on_board(x, y) {
        match &board[x as usize][y as usize] {
            None => moves.push((x, y)),
            Some(o) if pred(o) => moves.push((x, y)),
            _ => {}
        }
    }
}

fn push_line(
    moves: &mut Vec<(u8, u8)>,
    mut x: i8,
    mut y: i8,
    dx: i8,
    dy: i8,
    board: &Board,
    color: PieceColor,
) {
    loop {
        x += dx;
        y += dy;
        if !on_board(x as u8, y as u8) {
            break;
        }
        let ux = x as u8;
        let uy = y as u8;
        match &board[ux as usize][uy as usize] {
            None => moves.push((ux, uy)),
            Some(o) => {
                if o.color != color {
                    moves.push((ux, uy));
                }
                break;
            }
        }
    }
}

fn pseudo_legal_moves(
    piece_type: PieceType,
    color: PieceColor,
    x: u8,
    y: u8,
    board: &Board,
    castling_rights: &CastlingRights,
    en_passant_target: Option<(u8, u8)>,
) -> Vec<(u8, u8)> {
    let mut moves = Vec::with_capacity(28);
    let enemy = |o: &Occupant| o.color != color;

    match piece_type {
        PieceType::Pawn => {
            let (forward, start_rank) = match color {
                PieceColor::White => (1i8, 1),
                PieceColor::Black => (-1i8, 6),
            };
            let nx = x as i8 + forward;
            if on_board(nx as u8, y) && board[nx as usize][y as usize].is_none() {
                moves.push((nx as u8, y));
                if x == start_rank {
                    let nx2 = x as i8 + 2 * forward;
                    let n2 = nx2 as u8;
                    if on_board(n2, y) && board[n2 as usize][y as usize].is_none() {
                        moves.push((n2, y));
                    }
                }
            }
            for &dy in &[y.wrapping_sub(1), y.wrapping_add(1)] {
                if on_board(nx as u8, dy) {
                    let target = (nx as u8, dy);
                    let idx = target.0 as usize;
                    let idy = target.1 as usize;
                    if board[idx][idy].as_ref().is_some_and(|o| o.color != color) {
                        moves.push(target);
                    }
                    if en_passant_target == Some(target) {
                        moves.push(target);
                    }
                }
            }
        }
        PieceType::Knight => {
            for &(dx, dy) in &[(2, 1), (2, -1), (-2, 1), (-2, -1), (1, 2), (1, -2), (-1, 2), (-1, -2)] {
                let rx = x as i8 + dx;
                let ry = y as i8 + dy;
                if on_board(rx as u8, ry as u8) {
                    add_if(&mut moves, rx as u8, ry as u8, board, color, enemy);
                }
            }
        }
        PieceType::Bishop => {
            for &(dx, dy) in &[(1, 1), (1, -1), (-1, 1), (-1, -1)] {
                push_line(&mut moves, x as i8, y as i8, dx, dy, board, color);
            }
        }
        PieceType::Rook => {
            for &(dx, dy) in &[(1, 0), (-1, 0), (0, 1), (0, -1)] {
                push_line(&mut moves, x as i8, y as i8, dx, dy, board, color);
            }
        }
        PieceType::Queen => {
            for &(dx, dy) in &[(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)] {
                push_line(&mut moves, x as i8, y as i8, dx, dy, board, color);
            }
        }
        PieceType::King => {
            for &(dx, dy) in &[(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)] {
                let rx = x as i8 + dx;
                let ry = y as i8 + dy;
                if on_board(rx as u8, ry as u8) {
                    add_if(&mut moves, rx as u8, ry as u8, board, color, enemy);
                }
            }
            let home = match color {
                PieceColor::White => 0u8,
                PieceColor::Black => 7u8,
            };
            if x == home && y == 4 {
                if castling_rights.can_castle_kingside(color)
                    && board[home as usize][5].is_none()
                    && board[home as usize][6].is_none()
                {
                    moves.push((home, 6));
                }
                if castling_rights.can_castle_queenside(color)
                    && board[home as usize][1].is_none()
                    && board[home as usize][2].is_none()
                    && board[home as usize][3].is_none()
                {
                    moves.push((home, 2));
                }
            }
        }
    }

    moves
}

fn find_king(color: PieceColor, board: &Board) -> Option<(u8, u8)> {
    for (x, row) in board.iter().enumerate() {
        for (y, cell) in row.iter().enumerate() {
            if let Some(o) = cell {
                if o.piece_type == PieceType::King && o.color == color {
                    return Some((x as u8, y as u8));
                }
            }
        }
    }
    None
}

fn is_square_attacked_inner(
    attacking_color: PieceColor,
    x: u8,
    y: u8,
    board: &Board,
    castling_rights: &CastlingRights,
    en_passant_target: Option<(u8, u8)>,
) -> bool {
    for (sx, row) in board.iter().enumerate() {
        for (sy, cell) in row.iter().enumerate() {
            if let Some(o) = cell {
                if o.color != attacking_color {
                    continue;
                }
                let attacks = pseudo_legal_moves(
                    o.piece_type,
                    o.color,
                    sx as u8,
                    sy as u8,
                    board,
                    castling_rights,
                    en_passant_target,
                );
                if attacks.contains(&(x, y)) {
                    return true;
                }
            }
        }
    }
    false
}

pub fn is_player_in_check(
    color: PieceColor,
    pieces: &[(Entity, PieceColor, PieceType, u8, u8)],
) -> bool {
    let board = build_board(pieces);
    let rights = CastlingRights::default();
    let king_pos = match find_king(color, &board) {
        Some(kp) => kp,
        None => return false,
    };
    is_square_attacked_inner(color.opposite(), king_pos.0, king_pos.1, &board, &rights, None)
}

pub fn has_any_legal_move(
    color: PieceColor,
    pieces: &[(Entity, PieceColor, PieceType, u8, u8)],
    castling_rights: &CastlingRights,
    en_passant_target: Option<(u8, u8)>,
) -> bool {
    for &(entity, pc, _, _, _) in pieces {
        if pc == color && !legal_moves(entity, pieces, castling_rights, en_passant_target).is_empty() {
            return true;
        }
    }
    false
}

pub fn legal_moves(
    piece_entity: Entity,
    pieces: &[(Entity, PieceColor, PieceType, u8, u8)],
    castling_rights: &CastlingRights,
    en_passant_target: Option<(u8, u8)>,
) -> Vec<(u8, u8)> {
    let board = build_board(pieces);

    let (px, py, piece) = {
        let mut found = None;
        for (x, row) in board.iter().enumerate() {
            for (y, cell) in row.iter().enumerate() {
                if let Some(o) = cell {
                    if o.entity == piece_entity {
                        found = Some((x as u8, y as u8, o));
                    }
                }
            }
        }
        match found {
            Some(v) => v,
            None => return Vec::new(),
        }
    };

    let pseudo = pseudo_legal_moves(
        piece.piece_type,
        piece.color,
        px,
        py,
        &board,
        castling_rights,
        en_passant_target,
    );

    match piece.piece_type {
        PieceType::King => pseudo
            .into_iter()
            .filter(|&(tx, ty)| {
                let is_castle = ty == 2 || ty == 6;
                let mut sim = board.clone();
                sim[px as usize][py as usize] = None;
                sim[tx as usize][ty as usize] = None;
                if !is_castle {
                    !is_square_attacked_inner(
                        piece.color.opposite(), tx, ty, &sim, castling_rights, en_passant_target,
                    )
                } else {
                    let home = if piece.color == PieceColor::White { 0u8 } else { 7u8 };
                    if ty == 6 {
                        !is_square_attacked_inner(piece.color.opposite(), home, 4, &sim, castling_rights, en_passant_target)
                        && !is_square_attacked_inner(piece.color.opposite(), home, 5, &sim, castling_rights, en_passant_target)
                        && !is_square_attacked_inner(piece.color.opposite(), home, 6, &sim, castling_rights, en_passant_target)
                    } else {
                        !is_square_attacked_inner(piece.color.opposite(), home, 4, &sim, castling_rights, en_passant_target)
                        && !is_square_attacked_inner(piece.color.opposite(), home, 3, &sim, castling_rights, en_passant_target)
                        && !is_square_attacked_inner(piece.color.opposite(), home, 2, &sim, castling_rights, en_passant_target)
                    }
                }
            })
            .collect(),
        _ => pseudo
            .into_iter()
            .filter(|&(tx, ty)| {
                let mut sim = board.clone();
                sim[px as usize][py as usize] = None;
                sim[tx as usize][ty as usize] = None;
                sim[tx as usize][ty as usize] = Some(Occupant {
                    entity: piece_entity,
                    color: piece.color,
                    piece_type: piece.piece_type,
                });
                let king_pos = match find_king(piece.color, &sim) {
                    Some(kp) => kp,
                    None => return false,
                };
                !is_square_attacked_inner(
                    piece.color.opposite(), king_pos.0, king_pos.1,
                    &sim, castling_rights, en_passant_target,
                )
            })
            .collect(),
    }
}
