//! Deterministic stress checks for engine legality and resource limits.

use super::{SearchLimits, search_with_limits};
use crate::chess_core::{Color, Game, Outcome, legal_moves};
use std::time::Duration;

/// Summary from a deterministic legal-game stress run.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct StressReport {
    /// Number of games attempted.
    pub games: u32,
    /// Number of positions checked by the engine.
    pub positions: u32,
    /// Number of games that reached a rules outcome.
    pub completed_games: u32,
    /// Number of illegal moves returned by the engine.
    pub illegal_engine_moves: u32,
}

/// Walks deterministic legal games and verifies every returned engine move.
///
/// This intentionally uses a small budget so it is suitable for CI and mobile
/// regression checks, not as a strength benchmark.
#[must_use]
pub fn stress_legal_games(game_count: u32, max_plies: u16, seed: u64) -> StressReport {
    let mut report = StressReport {
        games: game_count,
        ..StressReport::default()
    };
    let limits = SearchLimits {
        max_time: Duration::from_millis(100),
        max_nodes: 256,
        max_depth: 2,
    };

    for game_index in 0..game_count {
        let mut game = Game::from_startpos();
        let mut random = seed
            .wrapping_add(u64::from(game_index))
            .wrapping_mul(0x9e37_79b9_7f4a_7c15);
        let mut reached_outcome = false;

        for _ in 0..max_plies {
            if game.outcome() != Outcome::Ongoing {
                reached_outcome = true;
                break;
            }
            let legal = legal_moves(game.board(), game.board().side_to_move());
            if legal.is_empty() {
                reached_outcome = true;
                break;
            }
            let result = search_with_limits(
                game.board(),
                limits,
                super::Personality::Balanced,
                0.0,
                true,
                random,
                None,
            );
            report.positions = report.positions.saturating_add(1);
            let Some(engine_move) = result.best_move else {
                report.illegal_engine_moves = report.illegal_engine_moves.saturating_add(1);
                break;
            };
            if !legal.contains(&engine_move) {
                report.illegal_engine_moves = report.illegal_engine_moves.saturating_add(1);
                break;
            }
            game.play(&engine_move)
                .expect("verified engine move must be playable");

            // Advance the position with a deterministic legal reply. This
            // explores more branches than repeatedly asking the AI to play
            // both sides while keeping the stress run inexpensive.
            if game.outcome() == Outcome::Ongoing {
                let replies = legal_moves(game.board(), Color::Black);
                if !replies.is_empty() && game.board().side_to_move() == Color::Black {
                    random = next_random(random);
                    let reply = replies[(random as usize) % replies.len()];
                    game.play(&reply)
                        .expect("legal stress reply must be playable");
                }
            }
            random = next_random(random);
        }
        if game.outcome() != Outcome::Ongoing || reached_outcome {
            report.completed_games = report.completed_games.saturating_add(1);
        }
    }
    report
}

fn next_random(mut value: u64) -> u64 {
    if value == 0 {
        value = 0xa076_1d64_78bd_642f;
    }
    value ^= value >> 12;
    value ^= value << 25;
    value ^= value >> 27;
    value.wrapping_mul(0x2545_f491_4f6c_dd1d)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn random_legal_stress_returns_only_legal_moves() {
        let report = stress_legal_games(4, 20, 1234);
        assert_eq!(report.illegal_engine_moves, 0);
        assert_eq!(report.games, 4);
        assert!(report.positions >= 4);
    }
}
