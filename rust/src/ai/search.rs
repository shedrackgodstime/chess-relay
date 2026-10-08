//! Small classical search engine built on the existing chess core.

use super::{EngineProfile, Personality};
use crate::chess_core::{Board, Move, Piece, Role, apply_move, is_in_check, legal_moves};
use std::collections::HashMap;
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};
use std::time::Instant;

const MATE_SCORE: i32 = 30_000;
const INF: i32 = MATE_SCORE + 1_000;
const MAX_TABLE_ENTRIES: usize = 16_384;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum TableBound {
    Exact,
    Lower,
    Upper,
}

#[derive(Clone, Copy, Debug)]
struct TableEntry {
    depth: u8,
    score: i32,
    bound: TableBound,
}

/// Result of one bounded engine search.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SearchResult {
    /// Selected legal move, if the position has a legal move.
    pub best_move: Option<Move>,
    /// Evaluation from the side to move's perspective, in centipawn-like units.
    pub score: i32,
    /// Deepest fully completed iteration.
    pub depth: u8,
    /// Number of searched nodes.
    pub nodes: u64,
}

/// Explicit limits for one search invocation.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SearchLimits {
    /// Soft wall-clock budget.
    pub max_time: std::time::Duration,
    /// Hard node budget.
    pub max_nodes: u64,
    /// Maximum iterative-deepening depth.
    pub max_depth: u8,
}

/// Cooperative cancellation handle for a search running elsewhere.
#[derive(Clone, Debug, Default)]
pub struct SearchControl {
    cancelled: Arc<AtomicBool>,
}

impl SearchControl {
    /// Creates a fresh active control handle.
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Requests that the search stop at its next checkpoint.
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Relaxed);
    }

    /// Whether cancellation has been requested.
    #[must_use]
    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::Relaxed)
    }
}

/// Searches a position using iterative deepening and a soft time limit.
#[must_use]
pub fn search(board: &Board, profile: EngineProfile) -> SearchResult {
    search_with_seed(board, profile, 0)
}

/// Searches a position and uses `seed` only when the profile permits a
/// near-best move. The same seed and position always produce the same move.
#[must_use]
pub fn search_with_seed(board: &Board, profile: EngineProfile, seed: u64) -> SearchResult {
    let limits = SearchLimits {
        max_time: profile.max_time,
        max_nodes: profile.max_nodes,
        max_depth: profile.max_depth,
    };
    search_with_limits(
        board,
        limits,
        profile.personality,
        profile.randomness,
        profile.quiescence,
        seed,
        None,
    )
}

/// Searches with explicit limits and optional cooperative cancellation.
#[must_use]
pub fn search_with_limits(
    board: &Board,
    limits: SearchLimits,
    personality: Personality,
    randomness: f32,
    quiescence: bool,
    seed: u64,
    control: Option<&SearchControl>,
) -> SearchResult {
    let started = Instant::now();
    let deadline = started
        .checked_add(limits.max_time)
        .unwrap_or_else(Instant::now);
    let mut context = SearchContext {
        deadline,
        nodes: 0,
        max_nodes: limits.max_nodes,
        quiescence,
        personality,
        table: HashMap::new(),
        history: [[0; 64]; 64],
        killers: [None; 64],
        control: control.map(|handle| handle.cancelled.clone()),
    };

    let moves = legal_moves(board, board.side_to_move());
    let Some(fallback) = moves.first().copied() else {
        return SearchResult {
            best_move: None,
            score: terminal_score(board, 0),
            depth: 0,
            nodes: 0,
        };
    };

    let mut result = SearchResult {
        best_move: Some(fallback),
        score: evaluate(board, personality),
        depth: 0,
        nodes: 0,
    };

    for depth in 1..=limits.max_depth {
        let mut best = None;
        let mut best_score = -INF;
        let mut candidates = Vec::new();
        let mut completed = true;

        for mv in ordered_moves(board, legal_moves(board, board.side_to_move()), &context, 0) {
            let next = apply_move(board, &mv);
            let score = match negamax(&next, depth.saturating_sub(1), -INF, INF, 1, &mut context) {
                Ok(score) => -score,
                Err(()) => {
                    completed = false;
                    break;
                }
            };
            if score > best_score {
                best_score = score;
                best = Some(mv);
            }
            candidates.push((mv, score));
        }

        if !completed {
            break;
        }
        if let Some(best_move) = best {
            result.best_move = Some(select_move(
                candidates,
                best_move,
                randomness,
                seed.wrapping_add(u64::from(depth)),
            ));
            result.score = best_score;
            result.depth = depth;
        }
    }
    result.nodes = context.nodes;
    result
}

struct SearchContext {
    deadline: Instant,
    nodes: u64,
    quiescence: bool,
    personality: Personality,
    max_nodes: u64,
    table: HashMap<Board, TableEntry>,
    history: [[i32; 64]; 64],
    killers: [Option<Move>; 64],
    control: Option<Arc<AtomicBool>>,
}

fn negamax(
    board: &Board,
    depth: u8,
    mut alpha: i32,
    beta: i32,
    ply: u8,
    context: &mut SearchContext,
) -> Result<i32, ()> {
    touch(context)?;
    let original_alpha = alpha;
    if let Some(entry) = context.table.get(board).copied()
        && entry.depth >= depth
        && entry.bound == TableBound::Exact
    {
        return Ok(entry.score);
    }
    let moves = legal_moves(board, board.side_to_move());
    if moves.is_empty() {
        return Ok(terminal_score(board, ply));
    }
    if depth == 0 {
        return if context.quiescence {
            quiescence(board, alpha, beta, 0, context)
        } else {
            Ok(evaluate(board, context.personality))
        };
    }

    let mut best = -INF;
    let mut cutoff = false;
    for mv in ordered_moves(board, moves, context, ply) {
        let next = apply_move(board, &mv);
        let score = -negamax(&next, depth - 1, -beta, -alpha, ply + 1, context)?;
        best = best.max(score);
        alpha = alpha.max(score);
        if alpha >= beta {
            if !is_capture(board, &mv) && !mv.is_promotion() {
                record_cutoff(context, mv, depth, ply);
            }
            cutoff = true;
            break;
        }
    }
    if context.table.len() >= MAX_TABLE_ENTRIES {
        context.table.clear();
    }
    let bound = if best <= original_alpha {
        TableBound::Upper
    } else if cutoff || best >= beta {
        TableBound::Lower
    } else {
        TableBound::Exact
    };
    context.table.insert(
        *board,
        TableEntry {
            depth,
            score: best,
            bound,
        },
    );
    Ok(best)
}

fn quiescence(
    board: &Board,
    mut alpha: i32,
    beta: i32,
    ply: u8,
    context: &mut SearchContext,
) -> Result<i32, ()> {
    touch(context)?;
    let in_check = is_in_check(board, board.side_to_move());
    let stand_pat = evaluate(board, context.personality);
    if ply >= 5 {
        return Ok(stand_pat);
    }
    if !in_check && stand_pat >= beta {
        return Ok(stand_pat);
    }
    let mut best = if in_check {
        -INF
    } else {
        alpha = alpha.max(stand_pat);
        stand_pat
    };

    for mv in ordered_moves(
        board,
        legal_moves(board, board.side_to_move()),
        context,
        ply,
    ) {
        let next = apply_move(board, &mv);
        if !in_check && !is_capture(board, &mv) && !mv.is_promotion() {
            continue;
        }
        let score = -quiescence(&next, -beta, -alpha, ply + 1, context)?;
        if score >= beta {
            return Ok(score);
        }
        alpha = alpha.max(score);
        best = best.max(score);
    }
    Ok(best.max(alpha))
}

fn ordered_moves(
    board: &Board,
    mut moves: Vec<Move>,
    context: &SearchContext,
    ply: u8,
) -> Vec<Move> {
    moves.sort_by_key(|mv| {
        let attacker = board
            .piece_at(mv.from)
            .map_or(0, |piece| piece_value(piece.role));
        let capture = board
            .piece_at(mv.to)
            .map_or(0, |piece| piece_value(piece.role));
        let promotion = mv.promotion.map_or(0, piece_value);
        let killer = context
            .killers
            .get(ply as usize)
            .is_some_and(|killer| *killer == Some(*mv));
        let history = context.history[mv.from.index() as usize][mv.to.index() as usize];
        -(capture * 10 - attacker + promotion * 10_000 + i32::from(killer) * 5_000 + history)
    });
    moves
}

fn record_cutoff(context: &mut SearchContext, mv: Move, depth: u8, ply: u8) {
    let from = mv.from.index() as usize;
    let to = mv.to.index() as usize;
    let bonus = i32::from(depth).saturating_mul(i32::from(depth));
    context.history[from][to] = (context.history[from][to] + bonus).min(10_000);
    if let Some(slot) = context.killers.get_mut(ply as usize)
        && *slot != Some(mv)
    {
        *slot = Some(mv);
    }
}

fn is_capture(board: &Board, mv: &Move) -> bool {
    board.piece_at(mv.to).is_some()
        || (board
            .piece_at(mv.from)
            .is_some_and(|piece| piece.role == Role::Pawn)
            && board.en_passant() == Some(mv.to)
            && board.piece_at(mv.to).is_none())
}

fn evaluate(board: &Board, personality: Personality) -> i32 {
    let mut white_score = 0;
    let mut black_score = 0;
    let mut white_pawns = [0_u8; 8];
    let mut black_pawns = [0_u8; 8];
    let mut white_bishops = 0;
    let mut black_bishops = 0;
    for index in 0..64 {
        let square = crate::chess_core::Square::try_new(index).expect("valid square index");
        if let Some(piece) = board.piece_at(square) {
            let value = piece_value(piece.role)
                + positional_bonus(piece, square, personality)
                + advancement_bonus(piece, square, personality)
                + passed_pawn_bonus(board, piece, square, personality);
            match piece.color {
                crate::chess_core::Color::White => white_score += value,
                crate::chess_core::Color::Black => black_score += value,
            }
            match (piece.color, piece.role) {
                (crate::chess_core::Color::White, Role::Pawn) => {
                    white_pawns[square.file() as usize] += 1
                }
                (crate::chess_core::Color::Black, Role::Pawn) => {
                    black_pawns[square.file() as usize] += 1
                }
                (crate::chess_core::Color::White, Role::Bishop) => white_bishops += 1,
                (crate::chess_core::Color::Black, Role::Bishop) => black_bishops += 1,
                _ => {}
            }
        }
    }
    white_score += structure_bonus(&white_pawns, white_bishops, personality);
    black_score += structure_bonus(&black_pawns, black_bishops, personality);
    let white_perspective = white_score - black_score;
    if board.side_to_move() == crate::chess_core::Color::White {
        white_perspective
    } else {
        -white_perspective
    }
}

fn positional_bonus(
    piece: Piece,
    square: crate::chess_core::Square,
    personality: Personality,
) -> i32 {
    let center = 3
        - (square.file() as i32 - 3)
            .abs()
            .max((square.rank() as i32 - 3).abs());
    let style = match personality {
        Personality::Aggressive => 2,
        Personality::Solid => 0,
        Personality::Tactical => 2,
        Personality::Endgame => 1,
        Personality::Balanced => 1,
    };
    match piece.role {
        Role::Pawn => center.max(0),
        Role::Knight | Role::Bishop => center.max(0) * (1 + style),
        Role::King if personality == Personality::Endgame => center.max(0) * 3,
        _ => 0,
    }
}

fn advancement_bonus(
    piece: Piece,
    square: crate::chess_core::Square,
    personality: Personality,
) -> i32 {
    if piece.role != Role::Pawn {
        return 0;
    }
    let rank_from_start = match piece.color {
        crate::chess_core::Color::White => square.rank(),
        crate::chess_core::Color::Black => 7 - square.rank(),
    };
    let multiplier = match personality {
        Personality::Aggressive | Personality::Endgame => 3,
        _ => 1,
    };
    i32::from(rank_from_start) * multiplier
}

fn passed_pawn_bonus(
    board: &Board,
    piece: Piece,
    square: crate::chess_core::Square,
    personality: Personality,
) -> i32 {
    if piece.role != Role::Pawn || !is_passed_pawn(board, piece, square) {
        return 0;
    }
    let rank_from_start = match piece.color {
        crate::chess_core::Color::White => square.rank(),
        crate::chess_core::Color::Black => 7 - square.rank(),
    };
    let multiplier = match personality {
        Personality::Aggressive | Personality::Endgame => 10,
        Personality::Solid => 7,
        _ => 8,
    };
    i32::from(rank_from_start + 1) * multiplier
}

fn is_passed_pawn(board: &Board, piece: Piece, square: crate::chess_core::Square) -> bool {
    let enemy = piece.color.opposite();
    let direction: i8 = match piece.color {
        crate::chess_core::Color::White => 1,
        crate::chess_core::Color::Black => -1,
    };
    let mut rank = square.rank() as i8 + direction;
    while (0..8).contains(&rank) {
        for file in square.file().saturating_sub(1)..=(square.file() + 1).min(7) {
            let checked = crate::chess_core::Square::from_xy(file, rank as u8)
                .expect("passed-pawn square is valid");
            if board.piece_at(checked) == Some(Piece::new(enemy, Role::Pawn)) {
                return false;
            }
        }
        rank += direction;
    }
    true
}

fn structure_bonus(pawns: &[u8; 8], bishops: u8, personality: Personality) -> i32 {
    let doubled_penalty = match personality {
        Personality::Solid => 12,
        _ => 8,
    };
    let doubled = pawns
        .iter()
        .map(|&count| count.saturating_sub(1) as i32)
        .sum::<i32>();
    let bishop_pair = if bishops >= 2 { 25 } else { 0 };
    bishop_pair - doubled * doubled_penalty
}

fn select_move(mut candidates: Vec<(Move, i32)>, best: Move, randomness: f32, seed: u64) -> Move {
    if randomness <= 0.0 {
        return best;
    }
    candidates.sort_by_key(|right| std::cmp::Reverse(right.1));
    let best_score = candidates.first().map_or(i32::MIN, |candidate| candidate.1);
    candidates.retain(|candidate| candidate.1 >= best_score - 180);
    if candidates.len() <= 1 || random_unit(seed) >= randomness {
        return best;
    }
    candidates[(random_u64(seed) as usize) % candidates.len()].0
}

fn random_u64(mut value: u64) -> u64 {
    if value == 0 {
        value = 0x9e37_79b9_7f4a_7c15;
    }
    value ^= value >> 12;
    value ^= value << 25;
    value ^= value >> 27;
    value.wrapping_mul(0x2545_f491_4f6c_dd1d)
}

fn random_unit(seed: u64) -> f32 {
    (random_u64(seed) as f64 / u64::MAX as f64) as f32
}

const fn piece_value(role: Role) -> i32 {
    match role {
        Role::Pawn => 100,
        Role::Knight => 320,
        Role::Bishop => 330,
        Role::Rook => 500,
        Role::Queen => 900,
        Role::King => 0,
    }
}

fn terminal_score(board: &Board, ply: u8) -> i32 {
    if is_in_check(board, board.side_to_move()) {
        -MATE_SCORE + i32::from(ply)
    } else {
        0
    }
}

fn touch(context: &mut SearchContext) -> Result<(), ()> {
    context.nodes = context.nodes.saturating_add(1);
    if context.nodes >= context.max_nodes {
        return Err(());
    }
    if context
        .control
        .as_ref()
        .is_some_and(|flag| flag.load(Ordering::Relaxed))
    {
        return Err(());
    }
    if context.nodes & 0x3ff == 0 && Instant::now() >= context.deadline {
        return Err(());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::Difficulty;

    #[test]
    fn finds_a_legal_opening_move() {
        let board = Board::startpos();
        let result = search(&board, Difficulty::Beginner.profile());
        assert!(result.best_move.is_some());
        assert!(legal_moves(&board, board.side_to_move()).contains(&result.best_move.unwrap()));
        assert!(result.nodes > 0);
    }

    #[test]
    fn prefers_free_queen_capture() {
        let board = Board::from_fen("4k3/8/8/8/3q4/2B5/8/4K3 w - - 0 1").unwrap();
        let result = search(&board, Difficulty::Normal.profile());
        assert_eq!(result.best_move.unwrap().to_string(), "c3d4");
    }

    #[test]
    fn finished_position_has_no_move() {
        let board = Board::from_fen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1").unwrap();
        assert_eq!(search(&board, Difficulty::Easy.profile()).best_move, None);
    }

    #[test]
    fn avoids_stopping_quiescence_on_check() {
        let board = Board::from_fen("7k/8/8/8/8/2B5/1Q6/4K3 b - - 0 1").unwrap();
        let result = search(&board, Difficulty::Normal.profile());
        assert!(result.best_move.is_some());
        assert!(legal_moves(&board, board.side_to_move()).contains(&result.best_move.unwrap()));
    }

    #[test]
    fn takes_mate_in_one() {
        let board = Board::from_fen("7k/5Q2/6K1/8/8/8/8/8 w - - 0 1").unwrap();
        let result = search(&board, Difficulty::Normal.profile());
        let next = apply_move(&board, &result.best_move.unwrap());
        assert!(is_in_check(&next, crate::chess_core::Color::Black));
        assert!(legal_moves(&next, crate::chess_core::Color::Black).is_empty());
    }

    #[test]
    fn promotes_when_given_a_free_pawn() {
        let board = Board::from_fen("7k/4P3/8/8/8/8/8/4K3 w - - 0 1").unwrap();
        let result = search(&board, Difficulty::Easy.profile());
        assert!(result.best_move.unwrap().is_promotion());
    }

    #[test]
    fn respects_node_budget() {
        let profile = Difficulty::Expert.profile();
        let result = search_with_limits(
            &Board::startpos(),
            SearchLimits {
                max_time: std::time::Duration::from_secs(10),
                max_nodes: 32,
                max_depth: profile.max_depth,
            },
            profile.personality,
            profile.randomness,
            profile.quiescence,
            1,
            None,
        );
        assert!(result.nodes <= 32);
        assert!(result.best_move.is_some());
    }

    #[test]
    fn respects_cooperative_cancellation() {
        let profile = Difficulty::Expert.profile();
        let control = SearchControl::new();
        control.cancel();
        let result = search_with_limits(
            &Board::startpos(),
            SearchLimits {
                max_time: std::time::Duration::from_secs(10),
                max_nodes: profile.max_nodes,
                max_depth: profile.max_depth,
            },
            profile.personality,
            profile.randomness,
            profile.quiescence,
            1,
            Some(&control),
        );
        assert!(result.best_move.is_some());
        assert!(result.depth == 0);
    }

    #[test]
    fn values_a_farther_advanced_passed_pawn() {
        let earlier = Board::from_fen("4k3/8/4P3/8/8/8/8/4K3 w - - 0 1").unwrap();
        let later = Board::from_fen("4k3/8/8/4P3/8/8/8/4K3 w - - 0 1").unwrap();
        assert!(evaluate(&earlier, Personality::Endgame) > evaluate(&later, Personality::Endgame));
    }
}
