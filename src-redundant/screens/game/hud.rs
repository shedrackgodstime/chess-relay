use bevy::prelude::*;

use crate::chess::{Move, PieceType};
use crate::screens::game::CurrentGame;
use crate::screens::game::GameEntity;
use crate::screens::game::controller::CheckWarning;
use crate::screens::game::input::{PendingMoves, PendingPromotion};
use crate::theme::palette;
use crate::theme::widgets;

/// System that keeps the HUD text updated with turn and check status.
#[allow(clippy::type_complexity)]
pub fn update_hud(
    mut texts: ParamSet<(
        Query<(&mut Text, &TurnDisplay)>,
        Query<(&mut Text, &CheckDisplay)>,
        Query<(&mut Visibility, &PromotionOverlay)>,
    )>,
    current_game: Option<Res<CurrentGame>>,
    check_warning: Res<CheckWarning>,
    pending_promotion: Res<PendingPromotion>,
) {
    if let Ok((mut turn_style, _)) = texts.p0().single_mut()
        && let Some(state) = &current_game
    {
        turn_style.0 = format!("{}'s turn", state.0.turn);
    }

    if let Ok((mut check_style, _)) = texts.p1().single_mut() {
        if check_warning.0 {
            check_style.0 = "Check!".to_string();
        } else {
            check_style.0 = String::new();
        }
    }

    if let Ok((mut visibility, _)) = texts.p2().single_mut() {
        *visibility = if pending_promotion.0.is_some() {
            Visibility::Visible
        } else {
            Visibility::Hidden
        };
    }
}

/// Marker for the turn text.
#[derive(Component)]
pub struct TurnDisplay;

/// Marker for the check warning text.
#[derive(Component)]
pub struct CheckDisplay;

/// Marker for the promotion choice overlay.
#[derive(Component)]
pub struct PromotionOverlay;

#[derive(Component)]
pub struct PromotionButton {
    piece_type: PieceType,
}

/// Spawn the HUD overlay.
pub fn spawn_hud(mut commands: Commands) {
    commands
        .spawn((
            Node {
                width: Val::Percent(100.0),
                height: Val::Percent(100.0),
                position_type: PositionType::Absolute,
                justify_content: JustifyContent::SpaceBetween,
                padding: UiRect::all(Val::Px(16.0)),
                ..default()
            },
            BackgroundColor(Color::NONE),
            GameEntity,
        ))
        .with_children(|parent| {
            parent
                .spawn((
                    Node {
                        flex_direction: FlexDirection::Column,
                        row_gap: Val::Px(8.0),
                        ..default()
                    },
                    BackgroundColor(Color::NONE),
                ))
                .with_children(|parent| {
                    parent.spawn((
                        Text::new("White's turn"),
                        TextFont {
                            font_size: 20.0,
                            ..default()
                        },
                        TextColor(palette::TEXT_PRIMARY),
                        TurnDisplay,
                    ));
                    parent.spawn((
                        Text::new(String::new()),
                        TextFont {
                            font_size: 24.0,
                            ..default()
                        },
                        TextColor(palette::ACCENT),
                        CheckDisplay,
                    ));
                });

            parent
                .spawn((
                    Node {
                        width: Val::Px(280.0),
                        padding: UiRect::all(Val::Px(20.0)),
                        flex_direction: FlexDirection::Column,
                        align_items: AlignItems::Center,
                        row_gap: Val::Px(12.0),
                        border: UiRect::all(Val::Px(1.0)),
                        border_radius: BorderRadius::all(Val::Px(10.0)),
                        ..default()
                    },
                    BackgroundColor(palette::SURFACE),
                    BorderColor::all(palette::BORDER),
                    Visibility::Hidden,
                    PromotionOverlay,
                ))
                .with_children(|parent| {
                    parent.spawn((
                        Text::new("Choose Promotion"),
                        TextFont {
                            font_size: 22.0,
                            ..default()
                        },
                        TextColor(palette::TEXT_PRIMARY),
                    ));
                    parent.spawn((
                        Text::new("Select the piece for your pawn."),
                        TextFont {
                            font_size: 15.0,
                            ..default()
                        },
                        TextColor(palette::TEXT_MUTED),
                    ));
                    parent
                        .spawn((
                            Node {
                                width: Val::Percent(100.0),
                                flex_wrap: FlexWrap::Wrap,
                                justify_content: JustifyContent::Center,
                                column_gap: Val::Px(10.0),
                                row_gap: Val::Px(10.0),
                                ..default()
                            },
                            BackgroundColor(Color::NONE),
                        ))
                        .with_children(|parent| {
                            spawn_promotion_button(parent, PieceType::Queen, "Queen");
                            spawn_promotion_button(parent, PieceType::Rook, "Rook");
                            spawn_promotion_button(parent, PieceType::Bishop, "Bishop");
                            spawn_promotion_button(parent, PieceType::Knight, "Knight");
                        });
                });
        });
}

fn spawn_promotion_button(parent: &mut ChildSpawnerCommands, piece_type: PieceType, label: &str) {
    let button = widgets::secondary_button(parent, label);
    parent
        .commands()
        .entity(button)
        .insert(PromotionButton { piece_type });
}

type PromotionInteractionQuery<'w, 's> = Query<
    'w,
    's,
    (&'static Interaction, &'static PromotionButton),
    (Changed<Interaction>, With<Button>),
>;

pub fn handle_promotion_buttons(
    mut pending_moves: ResMut<PendingMoves>,
    mut pending_promotion: ResMut<PendingPromotion>,
    interactions: PromotionInteractionQuery,
) {
    let Some(request) = pending_promotion.0.as_ref() else {
        return;
    };

    let mut selected_piece = None;
    for (interaction, button) in interactions.iter() {
        if *interaction == Interaction::Pressed {
            selected_piece = Some(button.piece_type);
            break;
        }
    }

    let Some(piece_type) = selected_piece else {
        return;
    };
    if !request.choices.contains(&piece_type) {
        return;
    }

    pending_moves.0.push(Move::with_promotion(
        (request.from_file, request.from_rank),
        (request.to_file, request.to_rank),
        piece_type,
    ));
    pending_promotion.0 = None;
}
