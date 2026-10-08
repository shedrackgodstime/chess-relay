//! Stateful local-engine facade for future callers.

use super::{
    Adaptation, Difficulty, DifficultyController, EngineProfile, GameRecord, Personality,
    SearchControl, SearchResult, search_with_limits, search_with_seed,
};
use crate::chess_core::Board;

/// Stateful, deterministic AI configuration.
///
/// This is intentionally independent from the bridge. It owns only local
/// playing policy and can later be called from a worker task or thread.
#[derive(Clone, Debug)]
pub struct LocalAiEngine {
    controller: DifficultyController,
    personality: Personality,
    seed: u64,
    moves_searched: u64,
}

impl LocalAiEngine {
    /// Creates an engine with fixed or adaptive difficulty.
    #[must_use]
    pub const fn new(
        difficulty: Difficulty,
        adaptation: Adaptation,
        personality: Personality,
        seed: u64,
    ) -> Self {
        Self {
            controller: DifficultyController::new(difficulty, adaptation),
            personality,
            seed,
            moves_searched: 0,
        }
    }

    /// Current difficulty used for the next move.
    #[must_use]
    pub const fn difficulty(&self) -> Difficulty {
        self.controller.difficulty()
    }

    /// Current evaluation personality.
    #[must_use]
    pub const fn personality(&self) -> Personality {
        self.personality
    }

    /// Changes style without changing strength.
    pub const fn set_personality(&mut self, personality: Personality) {
        self.personality = personality;
    }

    /// Searches one move and advances the deterministic seed.
    #[must_use]
    pub fn choose_move(&mut self, board: &Board) -> SearchResult {
        let mut profile: EngineProfile = self.difficulty().profile();
        profile.personality = self.personality;
        let result = search_with_seed(board, profile, self.seed);
        self.seed = self.seed.wrapping_add(1);
        self.moves_searched = self.moves_searched.saturating_add(result.nodes);
        result
    }

    /// Searches one move with a caller-owned cancellation handle.
    #[must_use]
    pub fn choose_move_with_control(
        &mut self,
        board: &Board,
        control: &SearchControl,
    ) -> SearchResult {
        let mut profile: EngineProfile = self.difficulty().profile();
        profile.personality = self.personality;
        let result = search_with_limits(
            board,
            super::SearchLimits {
                max_time: profile.max_time,
                max_nodes: profile.max_nodes,
                max_depth: profile.max_depth,
            },
            profile.personality,
            profile.randomness,
            profile.quiescence,
            self.seed,
            Some(control),
        );
        self.seed = self.seed.wrapping_add(1);
        self.moves_searched = self.moves_searched.saturating_add(result.nodes);
        result
    }

    /// Records a completed game for adaptive difficulty.
    pub fn record_game(&mut self, record: GameRecord) {
        self.controller.record(record);
    }

    /// Total nodes searched by this engine instance.
    #[must_use]
    pub const fn nodes_searched(&self) -> u64 {
        self.moves_searched
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::chess_core::legal_moves;

    #[test]
    fn facade_returns_a_legal_move() {
        let mut engine = LocalAiEngine::new(
            Difficulty::Beginner,
            Adaptation::Fixed,
            Personality::Balanced,
            7,
        );
        let board = Board::startpos();
        let result = engine.choose_move(&board);
        assert!(legal_moves(&board, board.side_to_move()).contains(&result.best_move.unwrap()));
        assert!(engine.nodes_searched() > 0);
    }

    #[test]
    fn facade_is_reproducible_for_the_same_seed() {
        let board = Board::startpos();
        let mut first = LocalAiEngine::new(
            Difficulty::Easy,
            Adaptation::Fixed,
            Personality::Balanced,
            99,
        );
        let mut second = first.clone();
        assert_eq!(first.choose_move(&board), second.choose_move(&board));
    }

    #[test]
    fn adaptive_facade_changes_only_after_three_results() {
        let mut engine = LocalAiEngine::new(
            Difficulty::Normal,
            Adaptation::RecentResults,
            Personality::Solid,
            1,
        );
        for _ in 0..3 {
            engine.record_game(GameRecord {
                human_won: true,
                drawn: false,
            });
        }
        assert_eq!(engine.difficulty(), Difficulty::Hard);
    }
}
