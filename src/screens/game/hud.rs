//! Heads-up display and overlay controls for the game screen.

use bevy::prelude::*;

use crate::chess::{GameStatus, PieceType};
use crate::screens::Screen;
use crate::screens::game::{
    CurrentGame, GameOverData, GameOverOverlay, GameSceneRoot, GameScreenEntity,
    HighlightedSquares, OpponentBadgeModel, OpponentKind, PendingPromotion, PendingSquareClick,
    ROTATION_STEP_RADIANS, RematchButton, SelectedSquare,
};
use crate::theme::{palette, typography, widgets};
use crate::ui::rasterize::rasterize_svg;

/// Marker for the "Back Home" navigation button.
#[derive(Component)]
pub(crate) struct BackButton;

/// Marker for the scene rotation button.
#[derive(Component)]
pub(super) struct RotateButton;

/// Displays captured pieces for one side in the HUD panel.
#[derive(Component)]
pub(super) struct CapturedDisplay {
    side: crate::chess::PieceColor,
}

/// Marker for the pawn-promotion overlay root entity.
#[derive(Component)]
pub(super) struct PromotionOverlay;

/// A clickable promotion choice button within the promotion overlay.
#[derive(Component)]
pub(super) struct PromotionButton {
    piece_type: PieceType,
}

/// Pre-rasterized UI icons used throughout the game screen HUD.
#[derive(Resource)]
pub(super) struct HudIcons {
    home: Handle<Image>,
    rotate: Handle<Image>,
    checkmate: Handle<Image>,
    stalemate: Handle<Image>,
    turn_white: Handle<Image>,
    turn_black: Handle<Image>,
}

impl FromWorld for HudIcons {
    fn from_world(world: &mut World) -> Self {
        let mut images = world.resource_mut::<Assets<Image>>();

        Self {
            home: images.add(rasterize_svg(include_str!(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/assets/ui/icons/home.svg"
            )))),
            rotate: images.add(rasterize_svg(include_str!(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/assets/ui/icons/rotate.svg"
            )))),
            checkmate: images.add(rasterize_svg(include_str!(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/assets/ui/icons/checkmate.svg"
            )))),
            stalemate: images.add(rasterize_svg(include_str!(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/assets/ui/icons/stalemate.svg"
            )))),
            turn_white: images.add(rasterize_svg(include_str!(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/assets/ui/icons/turn-white.svg"
            )))),
            turn_black: images.add(rasterize_svg(include_str!(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/assets/ui/icons/turn-black.svg"
            )))),
        }
    }
}

/// Marker for the turn-indicator icon (swaps between white/black).
#[derive(Component)]
pub(super) struct TurnIndicator;

const CAPTURE_VALUE_ORDER: &[crate::chess::PieceType] = &[
    crate::chess::PieceType::Queen,
    crate::chess::PieceType::Rook,
    crate::chess::PieceType::Bishop,
    crate::chess::PieceType::Knight,
    crate::chess::PieceType::Pawn,
];

pub(super) fn spawn_hud(commands: &mut Commands, icons: &HudIcons, opponent: &OpponentBadgeModel) {
    commands
        .spawn((
            Node {
                width: Val::Percent(100.0),
                height: Val::Percent(100.0),
                position_type: PositionType::Absolute,
                justify_content: JustifyContent::SpaceBetween,
                align_items: AlignItems::Stretch,
                padding: UiRect::all(Val::Px(18.0)),
                ..default()
            },
            BackgroundColor(Color::NONE),
            GameScreenEntity,
        ))
        .with_children(|parent| {
            parent
                .spawn((
                    Node {
                        width: Val::Percent(100.0),
                        justify_content: JustifyContent::SpaceBetween,
                        align_items: AlignItems::FlexStart,
                        ..default()
                    },
                    BackgroundColor(Color::NONE),
                ))
                .with_children(|parent| {
                    parent
                        .spawn((
                            Node {
                                flex_direction: FlexDirection::Column,
                                row_gap: Val::Px(4.0),
                                padding: UiRect::all(Val::Px(8.0)),
                                border_radius: BorderRadius::all(Val::Px(8.0)),
                                min_width: Val::Px(40.0),
                                ..default()
                            },
                            BackgroundColor(Color::srgba(0.05, 0.06, 0.08, 0.6)),
                        ))
                        .with_children(|parent| {
                            parent
                                .spawn((
                                    Node {
                                        column_gap: Val::Px(6.0),
                                        align_items: AlignItems::Center,
                                        ..default()
                                    },
                                    BackgroundColor(Color::NONE),
                                ))
                                .with_children(|parent| {
                                    parent.spawn((
                                        Text::new("Taken"),
                                        TextFont {
                                            font_size: 11.0,
                                            ..default()
                                        },
                                        TextColor(palette::TEXT_MUTED),
                                    ));
                                    parent.spawn((
                                        Node {
                                            width: Val::Px(10.0),
                                            height: Val::Px(10.0),
                                            ..default()
                                        },
                                        ImageNode::new(icons.turn_white.clone()),
                                        TurnIndicator,
                                    ));
                                });
                            parent.spawn((
                                Text::new(""),
                                TextFont {
                                    font_size: 15.0,
                                    ..default()
                                },
                                TextColor(palette::TEXT_PRIMARY),
                                CapturedDisplay {
                                    side: crate::chess::PieceColor::White,
                                },
                            ));
                            parent.spawn((
                                Text::new(""),
                                TextFont {
                                    font_size: 15.0,
                                    ..default()
                                },
                                TextColor(palette::TEXT_MUTED),
                                CapturedDisplay {
                                    side: crate::chess::PieceColor::Black,
                                },
                            ));
                        });

                    parent
                        .spawn(Node {
                            flex_direction: FlexDirection::Column,
                            align_items: AlignItems::FlexEnd,
                            row_gap: Val::Px(8.0),
                            ..default()
                        })
                        .with_children(|parent| {
                            parent.spawn(opponent_badge_node()).with_children(|parent| {
                                spawn_opponent_badge_contents(parent, opponent)
                            });
                        });
                });

            parent
                .spawn((
                    Node {
                        width: Val::Percent(100.0),
                        justify_content: JustifyContent::Center,
                        align_items: AlignItems::FlexEnd,
                        padding: UiRect::bottom(Val::Px(4.0)),
                        ..default()
                    },
                    BackgroundColor(Color::NONE),
                ))
                .with_children(|parent| {
                    parent
                        .spawn(bottom_control_strip())
                        .with_children(|parent| {
                            let back = icon_button(parent, icons.home.clone());
                            parent.commands().entity(back).insert(BackButton);

                            let rotate = icon_button(parent, icons.rotate.clone());
                            parent.commands().entity(rotate).insert(RotateButton);
                        });
                });
        });
}

pub(super) fn sync_promotion_overlay(
    mut commands: Commands,
    pending_promotion: Res<PendingPromotion>,
    overlays: Query<Entity, With<PromotionOverlay>>,
) {
    if !pending_promotion.is_changed() {
        return;
    }

    for entity in overlays.iter() {
        commands
            .entity(entity)
            .despawn_related::<Children>()
            .despawn();
    }

    if pending_promotion.0.is_none() {
        return;
    }

    commands
        .spawn((
            Node {
                width: Val::Percent(100.0),
                height: Val::Percent(100.0),
                position_type: PositionType::Absolute,
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                padding: UiRect::all(Val::Px(24.0)),
                ..default()
            },
            BackgroundColor(Color::srgba(0.02, 0.03, 0.04, 0.58)),
            PromotionOverlay,
            GameScreenEntity,
        ))
        .with_children(|parent| {
            parent
                .spawn(widgets::panel_node(420.0))
                .with_children(|parent| {
                    parent.spawn(section_label("Promotion"));
                    parent.spawn((
                        Text::new("Promote Pawn"),
                        TextFont {
                            font_size: 30.0,
                            ..default()
                        },
                        TextColor(palette::TEXT_PRIMARY),
                    ));
                    parent.spawn((
                        Text::new("The move is paused until you choose the finishing piece."),
                        TextFont {
                            font_size: typography::BODY_SMALL,
                            ..default()
                        },
                        TextColor(palette::TEXT_MUTED),
                    ));

                    parent
                        .spawn(Node {
                            width: Val::Percent(100.0),
                            display: Display::Grid,
                            grid_template_columns: RepeatedGridTrack::flex(2, 1.0),
                            column_gap: Val::Px(12.0),
                            row_gap: Val::Px(12.0),
                            ..default()
                        })
                        .with_children(|parent| {
                            for piece_type in [
                                PieceType::Queen,
                                PieceType::Rook,
                                PieceType::Bishop,
                                PieceType::Knight,
                            ] {
                                let button = widgets::button(
                                    parent,
                                    piece_type_label(piece_type),
                                    widgets::ButtonKind::Secondary,
                                );
                                parent
                                    .commands()
                                    .entity(button)
                                    .insert(PromotionButton { piece_type });
                            }
                        });
                });
        });
}

pub(super) fn handle_navigation_action(
    mut next_screen: ResMut<NextState<Screen>>,
    buttons: Query<&Interaction, (Changed<Interaction>, With<BackButton>)>,
) {
    for interaction in buttons.iter() {
        if *interaction == Interaction::Pressed {
            next_screen.set(Screen::Home);
        }
    }
}

pub(super) fn handle_rotation_actions(
    rotate_buttons: Query<&Interaction, (Changed<Interaction>, With<RotateButton>)>,
    mut scene_root: Query<&mut Transform, With<GameSceneRoot>>,
) {
    for interaction in rotate_buttons.iter() {
        if *interaction == Interaction::Pressed
            && let Ok(mut transform) = scene_root.single_mut()
        {
            transform.rotate_y(ROTATION_STEP_RADIANS);
        }
    }
}

#[allow(clippy::too_many_arguments)]
pub(super) fn handle_promotion_actions(
    mut commands: Commands,
    mut current_game: ResMut<CurrentGame>,
    mut selected_square: ResMut<SelectedSquare>,
    mut highlighted_squares: ResMut<HighlightedSquares>,
    mut pending_click: ResMut<PendingSquareClick>,
    mut pending_promotion: ResMut<PendingPromotion>,
    promotion_buttons: Query<(&Interaction, &PromotionButton), Changed<Interaction>>,
    overlays: Query<Entity, With<PromotionOverlay>>,
) {
    let Some(choices) = pending_promotion.0.as_ref() else {
        return;
    };

    let mut chosen_move = None;
    for (interaction, button) in promotion_buttons.iter() {
        if *interaction != Interaction::Pressed {
            continue;
        }

        chosen_move = choices
            .moves
            .iter()
            .find(|chess_move| chess_move.promotion == Some(button.piece_type))
            .copied();
        break;
    }

    let Some(chosen_move) = chosen_move else {
        return;
    };

    current_game.0.apply_move(&chosen_move);
    selected_square.0 = None;
    highlighted_squares.0.clear();
    pending_click.0 = None;
    pending_promotion.0 = None;

    for entity in overlays.iter() {
        commands
            .entity(entity)
            .despawn_related::<Children>()
            .despawn();
    }
}

fn section_label(value: &str) -> (Text, TextFont, TextColor) {
    (
        Text::new(value),
        TextFont {
            font_size: typography::EYEBROW,
            ..default()
        },
        TextColor(palette::ACCENT),
    )
}

fn icon_button(parent: &mut ChildSpawnerCommands, icon: Handle<Image>) -> Entity {
    parent
        .spawn((
            Node {
                width: Val::Px(56.0),
                height: Val::Px(56.0),
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                border: UiRect::all(Val::Px(1.0)),
                border_radius: BorderRadius::all(Val::Px(18.0)),
                ..default()
            },
            Button,
            BackgroundColor(Color::srgba(0.06, 0.07, 0.09, 0.82)),
            BorderColor::all(Color::srgba(0.72, 0.60, 0.39, 0.30)),
        ))
        .with_child(image_icon_node(icon, 22.0))
        .id()
}

fn image_icon_node(icon: Handle<Image>, size: f32) -> (Node, ImageNode) {
    (
        Node {
            width: Val::Px(size),
            height: Val::Px(size),
            ..default()
        },
        ImageNode::new(icon),
    )
}

fn spawn_opponent_badge_contents(parent: &mut ChildSpawnerCommands, opponent: &OpponentBadgeModel) {
    let initials = opponent_initials(&opponent.display_name);
    let (mode_label, indicator_color) = opponent_mode_presentation(opponent);

    parent
        .spawn(opponent_avatar_node(opponent))
        .with_children(|parent| {
            parent.spawn((
                Text::new(initials),
                TextFont {
                    font_size: 14.0,
                    ..default()
                },
                TextColor(palette::TEXT_PRIMARY),
            ));
        });

    parent
        .spawn((
            Node {
                flex_direction: FlexDirection::Column,
                row_gap: Val::Px(2.0),
                align_items: AlignItems::FlexStart,
                ..default()
            },
            BackgroundColor(Color::NONE),
        ))
        .with_children(|parent| {
            parent.spawn((
                Text::new(opponent.display_name.clone()),
                TextFont {
                    font_size: 13.0,
                    ..default()
                },
                TextColor(palette::TEXT_PRIMARY),
            ));

            parent
                .spawn((
                    Node {
                        column_gap: Val::Px(6.0),
                        align_items: AlignItems::Center,
                        ..default()
                    },
                    BackgroundColor(Color::NONE),
                ))
                .with_children(|parent| {
                    parent.spawn((
                        Node {
                            width: Val::Px(7.0),
                            height: Val::Px(7.0),
                            border_radius: BorderRadius::all(Val::Percent(50.0)),
                            ..default()
                        },
                        BackgroundColor(indicator_color),
                    ));
                    parent.spawn((
                        Text::new(mode_label),
                        TextFont {
                            font_size: 11.0,
                            ..default()
                        },
                        TextColor(palette::TEXT_MUTED),
                    ));
                });
        });
}

fn opponent_badge_node() -> (Node, BackgroundColor, BorderColor) {
    (
        Node {
            padding: UiRect::axes(Val::Px(10.0), Val::Px(8.0)),
            column_gap: Val::Px(10.0),
            justify_content: JustifyContent::Center,
            align_items: AlignItems::Center,
            border: UiRect::all(Val::Px(1.0)),
            border_radius: BorderRadius::all(Val::Px(18.0)),
            ..default()
        },
        BackgroundColor(Color::srgba(0.06, 0.07, 0.09, 0.76)),
        BorderColor::all(Color::srgba(0.72, 0.60, 0.39, 0.22)),
    )
}

fn opponent_avatar_node(opponent: &OpponentBadgeModel) -> (Node, BackgroundColor) {
    (
        Node {
            width: Val::Px(34.0),
            height: Val::Px(34.0),
            justify_content: JustifyContent::Center,
            align_items: AlignItems::Center,
            border_radius: BorderRadius::all(Val::Percent(50.0)),
            ..default()
        },
        BackgroundColor(opponent_avatar_color(opponent.kind)),
    )
}

fn bottom_control_strip() -> (Node, BackgroundColor, BorderColor) {
    (
        Node {
            padding: UiRect::all(Val::Px(8.0)),
            column_gap: Val::Px(10.0),
            justify_content: JustifyContent::Center,
            align_items: AlignItems::Center,
            border: UiRect::all(Val::Px(1.0)),
            border_radius: BorderRadius::all(Val::Px(24.0)),
            ..default()
        },
        BackgroundColor(Color::srgba(0.05, 0.06, 0.08, 0.72)),
        BorderColor::all(Color::srgba(0.72, 0.60, 0.39, 0.20)),
    )
}

fn piece_type_label(piece_type: PieceType) -> &'static str {
    match piece_type {
        PieceType::Queen => "Queen",
        PieceType::Rook => "Rook",
        PieceType::Bishop => "Bishop",
        PieceType::Knight => "Knight",
        PieceType::King => "King",
        PieceType::Pawn => "Pawn",
    }
}

fn opponent_initials(name: &str) -> String {
    let mut initials = String::new();
    for segment in name.split_whitespace().take(2) {
        if let Some(ch) = segment.chars().next() {
            initials.push(ch.to_ascii_uppercase());
        }
    }

    if initials.is_empty() {
        "OP".to_string()
    } else {
        initials
    }
}

fn opponent_mode_presentation(opponent: &OpponentBadgeModel) -> (&'static str, Color) {
    match opponent.kind {
        OpponentKind::Online if opponent.online => ("ONLINE", Color::srgb(0.24, 0.85, 0.47)),
        OpponentKind::Online => ("CONNECTING", Color::srgb(0.92, 0.71, 0.24)),
        OpponentKind::SameDevice => ("SAME DEVICE", Color::srgb(0.86, 0.63, 0.31)),
        OpponentKind::Computer => ("COMPUTER", Color::srgb(0.42, 0.70, 0.95)),
    }
}

fn opponent_avatar_color(kind: OpponentKind) -> Color {
    match kind {
        OpponentKind::Online => Color::srgb(0.20, 0.27, 0.35),
        OpponentKind::SameDevice => Color::srgb(0.31, 0.24, 0.18),
        OpponentKind::Computer => Color::srgb(0.17, 0.22, 0.30),
    }
}

pub(super) fn sync_game_over_overlay(
    mut commands: Commands,
    game_over: Res<GameOverData>,
    icons: Res<HudIcons>,
    overlays: Query<Entity, With<GameOverOverlay>>,
) {
    if !game_over.is_changed() {
        return;
    }

    for entity in overlays.iter() {
        commands
            .entity(entity)
            .despawn_related::<Children>()
            .despawn();
    }

    let Some(status) = game_over.0 else {
        return;
    };

    let (icon, title) = match status {
        GameStatus::Checkmate { .. } => (icons.checkmate.clone(), "Checkmate!"),
        GameStatus::Stalemate
        | GameStatus::FiftyMoveDraw
        | GameStatus::ThreefoldRepetitionDraw
        | GameStatus::InsufficientMaterialDraw => (icons.stalemate.clone(), "Draw!"),
        _ => return,
    };
    let message = match status {
        GameStatus::Checkmate { winner } => format!("{} wins!", winner),
        GameStatus::Stalemate => "Stalemate — no legal moves.".to_string(),
        GameStatus::FiftyMoveDraw => "Draw — 50-move rule.".to_string(),
        GameStatus::ThreefoldRepetitionDraw => "Draw — threefold repetition.".to_string(),
        GameStatus::InsufficientMaterialDraw => "Draw — insufficient material.".to_string(),
        _ => return,
    };

    commands
        .spawn((
            Node {
                width: Val::Percent(100.0),
                height: Val::Percent(100.0),
                position_type: PositionType::Absolute,
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                padding: UiRect::all(Val::Px(24.0)),
                ..default()
            },
            BackgroundColor(Color::srgba(0.02, 0.03, 0.04, 0.65)),
            GameOverOverlay,
            GameScreenEntity,
        ))
        .with_children(|parent| {
            parent
                .spawn(widgets::panel_node(400.0))
                .with_children(|parent| {
                    parent.spawn((
                        Node {
                            width: Val::Px(48.0),
                            height: Val::Px(48.0),
                            margin: UiRect::bottom(Val::Px(8.0)),
                            ..default()
                        },
                        ImageNode::new(icon),
                    ));

                    parent.spawn((
                        Text::new(title),
                        TextFont {
                            font_size: 36.0,
                            ..default()
                        },
                        TextColor(palette::TEXT_PRIMARY),
                    ));

                    parent.spawn((
                        Text::new(message),
                        TextFont {
                            font_size: typography::BODY_MEDIUM,
                            ..default()
                        },
                        TextColor(palette::TEXT_MUTED),
                    ));

                    let rematch = widgets::button(parent, "Rematch", widgets::ButtonKind::Primary);
                    parent.commands().entity(rematch).insert(RematchButton);

                    let home = widgets::button(parent, "Back Home", widgets::ButtonKind::Ghost);
                    parent.commands().entity(home).insert(BackButton);
                });
        });
}

#[allow(clippy::too_many_arguments)]
pub(super) fn handle_game_over_actions(
    mut commands: Commands,
    mut game_over: ResMut<GameOverData>,
    mut current_game: ResMut<CurrentGame>,
    mut selected_square: ResMut<SelectedSquare>,
    mut highlighted_squares: ResMut<HighlightedSquares>,
    mut pending_promotion: ResMut<PendingPromotion>,
    mut pending_click: ResMut<PendingSquareClick>,
    overlays: Query<Entity, With<GameOverOverlay>>,
    rematch_buttons: Query<&Interaction, (Changed<Interaction>, With<RematchButton>)>,
    back_buttons: Query<&Interaction, (Changed<Interaction>, With<BackButton>)>,
    mut next_screen: ResMut<NextState<Screen>>,
) {
    let mut go_home = false;
    let mut rematch = false;

    for interaction in rematch_buttons.iter() {
        if *interaction == Interaction::Pressed {
            rematch = true;
        }
    }

    for interaction in back_buttons.iter() {
        if *interaction == Interaction::Pressed {
            go_home = true;
        }
    }

    if go_home {
        next_screen.set(Screen::Home);
        return;
    }

    if rematch {
        *current_game = CurrentGame(crate::chess::GameState::new());
        selected_square.0 = None;
        highlighted_squares.0.clear();
        pending_promotion.0 = None;
        pending_click.0 = None;
        game_over.0 = None;

        for entity in overlays.iter() {
            commands
                .entity(entity)
                .despawn_related::<Children>()
                .despawn();
        }
    }
}

fn piece_label(piece_type: crate::chess::PieceType) -> &'static str {
    match piece_type {
        crate::chess::PieceType::King => "K",
        crate::chess::PieceType::Queen => "Q",
        crate::chess::PieceType::Rook => "R",
        crate::chess::PieceType::Bishop => "B",
        crate::chess::PieceType::Knight => "N",
        crate::chess::PieceType::Pawn => "P",
    }
}

pub(super) fn update_captured_display(
    current_game: Res<CurrentGame>,
    mut texts: Query<(&CapturedDisplay, &mut Text)>,
) {
    if !current_game.is_changed() {
        return;
    }

    let captured = &current_game.0.captured;

    for (display, mut text) in texts.iter_mut() {
        let side_pieces: Vec<&crate::chess::Piece> = captured
            .iter()
            .filter(|p| p.color == display.side)
            .collect();

        let display_text = if side_pieces.is_empty() {
            String::new()
        } else {
            let mut parts: Vec<String> = vec![];
            for pt in CAPTURE_VALUE_ORDER {
                let count = side_pieces.iter().filter(|p| p.piece_type == *pt).count() as u32;
                if count > 0 {
                    let label = piece_label(*pt);
                    if count > 1 {
                        parts.push(format!("{label}{count}"));
                    } else {
                        parts.push(label.to_string());
                    }
                }
            }
            parts.join(" ")
        };

        *text = Text::new(display_text);
    }
}

pub(super) fn update_turn_indicator(
    current_game: Res<CurrentGame>,
    icons: Res<HudIcons>,
    mut indicators: Query<&mut ImageNode, With<TurnIndicator>>,
) {
    if !current_game.is_changed() {
        return;
    }

    let Ok(mut image) = indicators.single_mut() else {
        return;
    };

    image.image = match current_game.0.turn {
        crate::chess::PieceColor::White => icons.turn_white.clone(),
        crate::chess::PieceColor::Black => icons.turn_black.clone(),
    };
}
