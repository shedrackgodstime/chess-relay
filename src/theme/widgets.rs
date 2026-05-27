//! Shared widget factories and button interaction styling.

use bevy::prelude::*;

use crate::theme::{palette, spacing, typography};

/// Visual variants for shared button widgets.
#[derive(Clone, Copy)]
pub(crate) enum ButtonKind {
    Primary,
    Secondary,
    Ghost,
}

/// Interaction palette used by the shared button styling system.
#[derive(Component)]
pub(crate) struct StyledButton {
    idle: Color,
    hover: Color,
    pressed: Color,
}

/// Returns the common root node used for full-screen layouts.
pub(crate) fn screen_root_node() -> Node {
    Node {
        width: Val::Percent(100.0),
        height: Val::Percent(100.0),
        justify_content: JustifyContent::Center,
        align_items: AlignItems::Center,
        padding: UiRect::all(Val::Px(spacing::LARGE)),
        ..default()
    }
}

/// Returns a panel node bundle for primary centered screens.
pub(crate) fn panel_node(width: f32) -> (Node, BackgroundColor, BorderColor) {
    (
        Node {
            width: Val::Px(width),
            max_width: Val::Percent(94.0),
            padding: UiRect::all(Val::Px(spacing::XLARGE)),
            flex_direction: FlexDirection::Column,
            row_gap: Val::Px(spacing::LARGE),
            border_radius: BorderRadius::all(Val::Px(28.0)),
            ..default()
        },
        BackgroundColor(palette::SURFACE),
        BorderColor::all(palette::BORDER),
    )
}

/// Returns display-sized text styling for large headings.
pub(crate) fn display_text(value: &str) -> (Text, TextFont, TextColor) {
    (
        Text::new(value),
        TextFont {
            font_size: typography::DISPLAY,
            ..default()
        },
        TextColor(palette::TEXT_PRIMARY),
    )
}

/// Returns body text styling for standard descriptive copy.
pub(crate) fn body_text(value: &str) -> (Text, TextFont, TextColor) {
    (
        Text::new(value),
        TextFont {
            font_size: typography::BODY_MEDIUM,
            ..default()
        },
        TextColor(palette::TEXT_MUTED),
    )
}

/// Spawns a shared styled button and returns the created entity.
pub(crate) fn button(parent: &mut ChildSpawnerCommands, label: &str, kind: ButtonKind) -> Entity {
    let palette = match kind {
        ButtonKind::Primary => StyledButton {
            idle: palette::ACCENT,
            hover: palette::ACCENT_HOVER,
            pressed: palette::ACCENT_HOVER.mix(&Color::BLACK, 0.18),
        },
        ButtonKind::Secondary => StyledButton {
            idle: palette::SURFACE_ELEVATED,
            hover: palette::GHOST_HOVER,
            pressed: palette::GHOST_HOVER.mix(&Color::BLACK, 0.14),
        },
        ButtonKind::Ghost => StyledButton {
            idle: palette::GHOST,
            hover: palette::GHOST_HOVER,
            pressed: palette::GHOST_HOVER.mix(&Color::BLACK, 0.14),
        },
    };

    let text_color = if matches!(kind, ButtonKind::Primary) {
        Color::BLACK
    } else {
        palette::TEXT_PRIMARY
    };

    parent
        .spawn((
            Node {
                width: Val::Percent(100.0),
                min_height: Val::Px(56.0),
                padding: UiRect::axes(Val::Px(spacing::MEDIUM), Val::Px(spacing::SMALL)),
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                border: UiRect::all(Val::Px(1.0)),
                border_radius: BorderRadius::all(Val::Px(18.0)),
                ..default()
            },
            Button,
            BackgroundColor(palette.idle),
            BorderColor::all(if matches!(kind, ButtonKind::Primary) {
                palette::ACCENT
            } else {
                palette::BORDER
            }),
            palette,
        ))
        .with_child((
            Text::new(label),
            TextFont {
                font_size: typography::BODY_MEDIUM,
                ..default()
            },
            TextColor(text_color),
        ))
        .id()
}

/// Applies hover and pressed styling to shared buttons.
#[allow(clippy::type_complexity)]
pub(crate) fn button_interaction_system(
    mut query: Query<
        (&Interaction, &StyledButton, &mut BackgroundColor),
        (Changed<Interaction>, With<Button>),
    >,
) {
    for (interaction, palette, mut background) in query.iter_mut() {
        background.0 = match *interaction {
            Interaction::Pressed => palette.pressed,
            Interaction::Hovered => palette.hover,
            Interaction::None => palette.idle,
        };
    }
}
