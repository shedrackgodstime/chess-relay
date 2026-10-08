//! Lightweight, deterministic AI contracts.
//!
//! This module deliberately does not know about Godot, networking, sessions,
//! or clocks. The first implementation can sit on top of `chess_core` without
//! introducing another chess representation or an external engine dependency.
//!
//! Search and move selection will be added behind these contracts. Keeping the
//! policy types here first lets the bridge and UI agree on difficulty without
//! coupling either one to the eventual search implementation.

use std::time::Duration;

mod calibration;
mod engine;
mod search;
mod verification;

pub use calibration::{
    BenchmarkResult, SelfPlayResult, TACTICAL_CASES, TacticalCase, TacticalResult, benchmark,
    run_tactical_suite, self_play,
};
pub use engine::LocalAiEngine;
pub use search::{
    SearchControl, SearchLimits, SearchResult, search, search_with_limits, search_with_seed,
};
pub use verification::{StressReport, stress_legal_games};

/// Lightweight evaluation bias that changes style without adding another
/// engine or model.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Personality {
    /// Balanced material and positional play.
    #[default]
    Balanced,
    /// Values activity, king attacks, and advanced pawns.
    Aggressive,
    /// Values king safety, material, and simplification.
    Solid,
    /// Values captures, development, and tactical activity.
    Tactical,
    /// Values king activity and passed pawns.
    Endgame,
}

/// Strength policy used by a local AI game.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Difficulty {
    /// Makes simple mistakes while remaining mostly coherent.
    Beginner,
    /// A forgiving but useful casual opponent.
    Easy,
    /// The default local opponent.
    #[default]
    Normal,
    /// Searches more deeply and makes fewer tactical errors.
    Hard,
    /// Uses the largest configured local search budget.
    Expert,
}

impl Difficulty {
    /// Stable search policy for this difficulty.
    #[must_use]
    pub const fn profile(self) -> EngineProfile {
        match self {
            Self::Beginner => EngineProfile {
                max_depth: 1,
                max_time: Duration::from_millis(40),
                max_nodes: 25_000,
                randomness: 0.35,
                quiescence: false,
                personality: Personality::Balanced,
            },
            Self::Easy => EngineProfile {
                max_depth: 2,
                max_time: Duration::from_millis(100),
                max_nodes: 75_000,
                randomness: 0.18,
                quiescence: true,
                personality: Personality::Balanced,
            },
            Self::Normal => EngineProfile {
                max_depth: 4,
                max_time: Duration::from_millis(250),
                max_nodes: 250_000,
                randomness: 0.06,
                quiescence: true,
                personality: Personality::Balanced,
            },
            Self::Hard => EngineProfile {
                max_depth: 6,
                max_time: Duration::from_millis(700),
                max_nodes: 750_000,
                randomness: 0.02,
                quiescence: true,
                personality: Personality::Solid,
            },
            Self::Expert => EngineProfile {
                max_depth: 8,
                max_time: Duration::from_millis(1_500),
                max_nodes: 2_000_000,
                randomness: 0.0,
                quiescence: true,
                personality: Personality::Tactical,
            },
        }
    }
}

/// Search budget and deliberate weakness controls.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct EngineProfile {
    /// Maximum principal search depth.
    pub max_depth: u8,
    /// Soft wall-clock budget for one move.
    pub max_time: Duration,
    /// Hard node budget for one move.
    pub max_nodes: u64,
    /// Probability of selecting a near-best candidate instead of the best one.
    /// This is bounded policy noise, not random legal-move selection.
    pub randomness: f32,
    /// Whether tactical captures/checks may extend the nominal search.
    pub quiescence: bool,
    /// Evaluation style used by the engine.
    pub personality: Personality,
}

/// Optional player-strength adjustment applied between games.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Adaptation {
    /// Use the selected difficulty unchanged.
    #[default]
    Fixed,
    /// Adjust one level at a time from recent game results.
    RecentResults,
}

/// Small persistent signal used by adaptive difficulty.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct GameRecord {
    /// Whether the human won.
    pub human_won: bool,
    /// Whether the game ended in a draw.
    pub drawn: bool,
}

/// Difficulty selector that changes only between games.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DifficultyController {
    selected: Difficulty,
    adaptation: Adaptation,
    recent_human_wins: u8,
    recent_human_losses: u8,
}

impl DifficultyController {
    /// Creates a fixed or adaptive difficulty controller.
    #[must_use]
    pub const fn new(selected: Difficulty, adaptation: Adaptation) -> Self {
        Self {
            selected,
            adaptation,
            recent_human_wins: 0,
            recent_human_losses: 0,
        }
    }

    /// Current difficulty used for the next game.
    #[must_use]
    pub const fn difficulty(self) -> Difficulty {
        self.selected
    }

    /// Records one completed game and, when enabled, adjusts conservatively.
    pub fn record(&mut self, record: GameRecord) {
        if self.adaptation == Adaptation::Fixed || record.drawn {
            return;
        }

        if record.human_won {
            self.recent_human_wins = self.recent_human_wins.saturating_add(1);
            self.recent_human_losses = 0;
            if self.recent_human_wins >= 3 {
                self.selected = step_up(self.selected);
                self.recent_human_wins = 0;
            }
        } else {
            self.recent_human_losses = self.recent_human_losses.saturating_add(1);
            self.recent_human_wins = 0;
            if self.recent_human_losses >= 3 {
                self.selected = step_down(self.selected);
                self.recent_human_losses = 0;
            }
        }
    }
}

const fn step_up(difficulty: Difficulty) -> Difficulty {
    match difficulty {
        Difficulty::Beginner => Difficulty::Easy,
        Difficulty::Easy => Difficulty::Normal,
        Difficulty::Normal => Difficulty::Hard,
        Difficulty::Hard | Difficulty::Expert => Difficulty::Expert,
    }
}

const fn step_down(difficulty: Difficulty) -> Difficulty {
    match difficulty {
        Difficulty::Beginner | Difficulty::Easy => Difficulty::Beginner,
        Difficulty::Normal => Difficulty::Easy,
        Difficulty::Hard => Difficulty::Normal,
        Difficulty::Expert => Difficulty::Hard,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fixed_difficulty_does_not_change() {
        let mut controller = DifficultyController::new(Difficulty::Normal, Adaptation::Fixed);
        for _ in 0..4 {
            controller.record(GameRecord {
                human_won: true,
                drawn: false,
            });
        }
        assert_eq!(controller.difficulty(), Difficulty::Normal);
    }

    #[test]
    fn adaptation_moves_one_level_after_three_results() {
        let mut controller =
            DifficultyController::new(Difficulty::Normal, Adaptation::RecentResults);
        for _ in 0..3 {
            controller.record(GameRecord {
                human_won: true,
                drawn: false,
            });
        }
        assert_eq!(controller.difficulty(), Difficulty::Hard);
    }

    #[test]
    fn draws_do_not_adjust_strength() {
        let mut controller =
            DifficultyController::new(Difficulty::Normal, Adaptation::RecentResults);
        for _ in 0..5 {
            controller.record(GameRecord {
                human_won: false,
                drawn: true,
            });
        }
        assert_eq!(controller.difficulty(), Difficulty::Normal);
    }
}
