//! Minimax search with alpha-beta pruning for AI move selection.

use super::super::{Board, ChessMove, GameState, PieceColor};
use super::eval::{evaluate, piece_value};

const MATE_SCORE: i32 = 20_000;
const MAX_DEPTH: u8 = 3;

/// Selects the best legal move for the side whose turn it is.
pub(crate) fn find_best_move(state: &GameState) -> Option<ChessMove> {
    let moves = order_moves(state.all_legal_moves(), &state.board);
    if moves.is_empty() {
        return None;
    }

    let mut best_move = None;
    let mut best_score = i32::MIN;

    for chess_move in moves {
        let mut child = state.clone();
        child.apply_move(&chess_move);
        let score = -negamax(&child, MAX_DEPTH - 1, i32::MIN + 1, i32::MAX - 1);
        if score > best_score {
            best_score = score;
            best_move = Some(chess_move);
        }
    }

    best_move
}

/// Returns moves ordered with captures first (sorted by victim value descending).
fn order_moves(moves: Vec<ChessMove>, board: &Board) -> Vec<ChessMove> {
    let mut moves = moves;
    moves.sort_by(|a, b| {
        let a_score = board
            .get(a.to_file, a.to_rank)
            .map_or(0, |p| piece_value(p.piece_type));
        let b_score = board
            .get(b.to_file, b.to_rank)
            .map_or(0, |p| piece_value(p.piece_type));
        b_score.cmp(&a_score)
    });
    moves
}

/// Negamax evaluation with alpha-beta pruning.
fn negamax(state: &GameState, depth: u8, mut alpha: i32, beta: i32) -> i32 {
    if depth == 0 {
        let eval = evaluate(&state.board);
        return if state.turn == PieceColor::White {
            eval
        } else {
            -eval
        };
    }

    let moves = order_moves(state.all_legal_moves(), &state.board);
    if moves.is_empty() {
        if state.is_check() {
            return -MATE_SCORE;
        }
        return 0;
    }

    for chess_move in moves {
        let mut child = state.clone();
        child.apply_move(&chess_move);
        let score = -negamax(&child, depth - 1, -beta, -alpha);
        if score > alpha {
            alpha = score;
            if alpha >= beta {
                break;
            }
        }
    }
    alpha
}
