use bevy::prelude::*;

use crate::chess::{PieceColor, all_legal_moves};
use crate::screens::game::CurrentGame;
use crate::screens::game::input::PendingMoves;

/// Resource tracking AI state.
#[derive(Resource)]
pub struct AiInput {
    pub ai_color: PieceColor,
    timer: Timer,
}

impl AiInput {
    pub fn new(ai_color: PieceColor) -> Self {
        AiInput {
            ai_color,
            timer: Timer::from_seconds(1.0, TimerMode::Once),
        }
    }
}

/// Simple AI: picks the first legal move after a short delay.
pub fn ai_input_system(
    ai: Option<ResMut<AiInput>>,
    time: Res<Time>,
    current_game: Option<Res<CurrentGame>>,
    mut pending: ResMut<PendingMoves>,
) {
    let Some(mut ai) = ai else { return };
    let Some(current_game) = current_game else {
        return;
    };

    if current_game.0.turn != ai.ai_color {
        return;
    }

    ai.timer.tick(time.delta());
    if !ai.timer.just_finished() {
        return;
    }

    let moves = all_legal_moves(
        &current_game.0.board,
        current_game.0.turn,
        &current_game.0.castling,
        current_game.0.en_passant,
    );
    if let Some(mv) = moves.into_iter().next() {
        pending.0.push(mv);
    }

    ai.timer.reset();
}
