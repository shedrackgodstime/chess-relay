//! Small deterministic tools for validating and tuning the local engine.

use super::{
    Adaptation, Difficulty, EngineProfile, LocalAiEngine, Personality, SearchResult, search,
};
use crate::chess_core::{Board, Game, IllegalMove, Outcome};
use std::time::Instant;

/// A position with a move that should be preferred by the engine.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct TacticalCase {
    /// Human-readable case name.
    pub name: &'static str,
    /// Starting FEN.
    pub fen: &'static str,
    /// Expected UCI move.
    pub expected_move: &'static str,
}

/// Small tactical suite used during engine development.
pub const TACTICAL_CASES: &[TacticalCase] = &[
    TacticalCase {
        name: "free queen",
        fen: "4k3/8/8/8/3q4/2B5/8/4K3 w - - 0 1",
        expected_move: "c3d4",
    },
    TacticalCase {
        name: "mate in one",
        fen: "7k/5Q2/6K1/8/8/8/8/8 w - - 0 1",
        expected_move: "f7e8",
    },
    TacticalCase {
        name: "promote safely",
        fen: "7k/4P3/8/8/8/8/8/4K3 w - - 0 1",
        expected_move: "e7e8q",
    },
];

/// Result for one tactical position.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TacticalResult {
    /// Case name.
    pub name: &'static str,
    /// Expected move.
    pub expected_move: &'static str,
    /// Move returned by the engine, if any.
    pub actual_move: Option<String>,
    /// Search metadata.
    pub search: SearchResult,
}

/// Runs the built-in tactical suite with one fixed profile.
#[must_use]
pub fn run_tactical_suite(profile: EngineProfile) -> Vec<TacticalResult> {
    TACTICAL_CASES
        .iter()
        .map(|case| {
            let board = Board::from_fen(case.fen).expect("calibration FEN must be valid");
            let result = search(&board, profile);
            TacticalResult {
                name: case.name,
                expected_move: case.expected_move,
                actual_move: result.best_move.map(|mv| mv.to_string()),
                search: result,
            }
        })
        .collect()
}

/// Search benchmark summary for one position.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct BenchmarkResult {
    /// Search result.
    pub search: SearchResult,
    /// Wall-clock duration in microseconds.
    pub elapsed_micros: u128,
    /// Approximate search throughput.
    pub nodes_per_second: f64,
}

/// Benchmarks one FEN with the supplied search profile.
pub fn benchmark(fen: &str, profile: EngineProfile) -> Result<BenchmarkResult, IllegalMove> {
    let board = Board::from_fen(fen)?;
    let started = Instant::now();
    let result = search(&board, profile);
    let elapsed = started.elapsed();
    let elapsed_micros = elapsed.as_micros();
    let nodes_per_second = if elapsed.as_secs_f64() > 0.0 {
        result.nodes as f64 / elapsed.as_secs_f64()
    } else {
        0.0
    };
    Ok(BenchmarkResult {
        search: result,
        elapsed_micros,
        nodes_per_second,
    })
}

/// Result of a bounded engine-vs-engine match.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SelfPlayResult {
    /// Rules outcome after the final move or at the ply limit.
    pub outcome: Outcome,
    /// Number of plies played.
    pub plies: u16,
    /// Total nodes searched by both engines.
    pub nodes: u64,
}

/// Runs a bounded deterministic self-play game from the standard position.
pub fn self_play(
    white_difficulty: Difficulty,
    black_difficulty: Difficulty,
    max_plies: u16,
    seed: u64,
) -> SelfPlayResult {
    let mut game = Game::from_startpos();
    let mut white = LocalAiEngine::new(
        white_difficulty,
        Adaptation::Fixed,
        Personality::Balanced,
        seed,
    );
    let mut black = LocalAiEngine::new(
        black_difficulty,
        Adaptation::Fixed,
        Personality::Balanced,
        seed.wrapping_add(1),
    );
    let mut plies = 0;

    while plies < max_plies && game.outcome() == Outcome::Ongoing {
        let result = if game.board().side_to_move() == crate::chess_core::Color::White {
            white.choose_move(game.board())
        } else {
            black.choose_move(game.board())
        };
        let Some(mv) = result.best_move else {
            break;
        };
        game.play(&mv).expect("engine must return a legal move");
        plies += 1;
    }

    SelfPlayResult {
        outcome: game.outcome(),
        plies,
        nodes: white
            .nodes_searched()
            .saturating_add(black.nodes_searched()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tactical_suite_has_expected_moves() {
        let results = run_tactical_suite(Difficulty::Normal.profile());
        assert!(
            results
                .iter()
                .all(|result| { result.actual_move.as_deref() == Some(result.expected_move) }),
            "{results:?}"
        );
    }

    #[test]
    fn benchmark_reports_nodes() {
        let result = benchmark(Board::STARTPOS_FEN, Difficulty::Beginner.profile()).unwrap();
        assert!(result.search.best_move.is_some());
        assert!(result.search.nodes > 0);
    }

    #[test]
    fn self_play_stays_legal_and_bounded() {
        let result = self_play(Difficulty::Beginner, Difficulty::Beginner, 12, 42);
        assert!(result.plies <= 12);
        assert!(result.nodes > 0);
    }
}
