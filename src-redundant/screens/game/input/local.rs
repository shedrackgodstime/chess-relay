use bevy::prelude::*;

use crate::chess::{PieceType, legal_moves};
use crate::screens::game::CurrentGame;
use crate::screens::game::input::{
    LocalSelection, PendingMoves, PendingPromotion, PendingSquareClick, PromotionRequest,
};

/// Deselect on right-click or press Escape.
/// Select a piece on left-click, then select destination to queue a move.
pub fn local_input_system(
    mut selection: ResMut<LocalSelection>,
    mut pending: ResMut<PendingMoves>,
    mut pending_promotion: ResMut<PendingPromotion>,
    mut pending_square_click: ResMut<PendingSquareClick>,
    current_game: Option<Res<CurrentGame>>,
    keys: Res<ButtonInput<KeyCode>>,
) {
    let Some(current_game) = current_game else {
        return;
    };
    let game_state = &current_game.0;

    if pending_promotion.0.is_some() {
        return;
    }

    if keys.just_pressed(KeyCode::Escape) {
        selection.selected_file = None;
        selection.selected_rank = None;
        return;
    }

    let Some((file, rank)) = pending_square_click.0.take() else {
        return;
    };

    // If nothing selected, try to select our piece
    if selection.selected_file.is_none() {
        if let Some(piece) = game_state.board.get(file, rank)
            && piece.color == game_state.turn
        {
            selection.selected_file = Some(file);
            selection.selected_rank = Some(rank);
        }
        return;
    }

    let Some(from_file) = selection.selected_file else {
        return;
    };
    let Some(from_rank) = selection.selected_rank else {
        return;
    };

    // If clicking on own piece, re-select
    if let Some(piece) = game_state.board.get(file, rank)
        && piece.color == game_state.turn
    {
        selection.selected_file = Some(file);
        selection.selected_rank = Some(rank);
        return;
    }

    // Try to move
    let legal = legal_moves(
        &game_state.board,
        from_file,
        from_rank,
        &game_state.castling,
        game_state.en_passant,
    );
    let chosen_move = legal
        .into_iter()
        .filter(|mv| mv.to_file == file && mv.to_rank == rank)
        .collect::<Vec<_>>();

    if chosen_move.len() > 1
        && chosen_move.iter().all(|mv| {
            matches!(
                mv.promotion,
                Some(PieceType::Queen | PieceType::Rook | PieceType::Bishop | PieceType::Knight)
            )
        })
    {
        pending_promotion.0 = Some(PromotionRequest {
            from_file,
            from_rank,
            to_file: file,
            to_rank: rank,
            choices: chosen_move.iter().filter_map(|mv| mv.promotion).collect(),
        });
        selection.selected_file = None;
        selection.selected_rank = None;
        return;
    }

    if let Some(mv) = chosen_move
        .into_iter()
        .max_by_key(|mv| matches!(mv.promotion, Some(PieceType::Queen)))
    {
        pending.0.push(mv);
        selection.selected_file = None;
        selection.selected_rank = None;
        return;
    }

    // Invalid destination — deselect
    selection.selected_file = None;
    selection.selected_rank = None;
}
