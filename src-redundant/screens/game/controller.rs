use bevy::prelude::*;

use crate::chess::is_player_in_check;
use crate::screens::game::CurrentGame;
use crate::screens::game::input::PendingMoves;

/// Drains PendingMoves, validates legality, applies to GameState.
pub fn controller_system(
    mut pending: ResMut<PendingMoves>,
    current_game: Option<ResMut<CurrentGame>>,
    mut check_warning: ResMut<CheckWarning>,
) {
    let Some(mut current_game) = current_game else {
        return;
    };

    for mv in pending.0.drain(..) {
        let legal = current_game.0.all_legal_moves();
        if !legal.contains(&mv) {
            continue;
        }

        current_game.0.apply_move(&mv);

        check_warning.0 = is_player_in_check(&current_game.0.board, current_game.0.turn);
    }
}

/// Simple flag so HUD can show a check indicator.
#[derive(Resource, Default, Debug)]
pub struct CheckWarning(pub bool);
