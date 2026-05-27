use bevy::prelude::*;

use super::palette;

pub fn logo(parent: &mut ChildSpawnerCommands) {
    parent.spawn((
        Text::new("♚ Chess Relay"),
        TextFont {
            font_size: 48.0,
            ..default()
        },
        TextColor(palette::TEXT_PRIMARY),
    ));
}

pub fn divider(parent: &mut ChildSpawnerCommands, width: f32) {
    parent.spawn((
        Node {
            width: Val::Px(width),
            height: Val::Px(1.0),
            margin: UiRect::vertical(Val::Px(8.0)),
            ..default()
        },
        BackgroundColor(palette::ACCENT),
    ));
}

pub fn primary_button(parent: &mut ChildSpawnerCommands, label: &str) -> Entity {
    parent
        .spawn((
            Node {
                width: Val::Px(260.0),
                height: Val::Px(52.0),
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                border: UiRect::all(Val::Px(1.0)),
                border_radius: BorderRadius::all(Val::Px(6.0)),
                ..default()
            },
            Button,
            BackgroundColor(palette::ACCENT),
            BorderColor::all(palette::ACCENT),
        ))
        .with_child((
            Text::new(label),
            TextFont {
                font_size: 18.0,
                ..default()
            },
            TextColor(Color::BLACK),
        ))
        .id()
}

pub fn secondary_button(parent: &mut ChildSpawnerCommands, label: &str) -> Entity {
    parent
        .spawn((
            Node {
                width: Val::Px(260.0),
                height: Val::Px(52.0),
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                border: UiRect::all(Val::Px(1.0)),
                border_radius: BorderRadius::all(Val::Px(6.0)),
                ..default()
            },
            Button,
            BackgroundColor(palette::ROSEWOOD),
            BorderColor::all(palette::ROSEWOOD),
        ))
        .with_child((
            Text::new(label),
            TextFont {
                font_size: 18.0,
                ..default()
            },
            TextColor(palette::TEXT_PRIMARY),
        ))
        .id()
}

pub fn text_link(parent: &mut ChildSpawnerCommands, label: &str) -> Entity {
    parent
        .spawn((
            Node {
                padding: UiRect::vertical(Val::Px(8.0)),
                ..default()
            },
            Button,
            BackgroundColor(Color::NONE),
        ))
        .with_child((
            Text::new(label),
            TextFont {
                font_size: 18.0,
                ..default()
            },
            TextColor(palette::TEXT_MUTED),
        ))
        .id()
}

pub fn footer(parent: &mut ChildSpawnerCommands) {
    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                bottom: Val::Px(24.0),
                ..default()
            },
            BackgroundColor(Color::NONE),
        ))
        .with_child((
            Text::new("v0.1.0 · Rust + Bevy"),
            TextFont {
                font_size: 14.0,
                ..default()
            },
            TextColor(palette::TEXT_MUTED),
        ));
}

type ButtonQuery<'w, 's> = Query<
    'w,
    's,
    (
        &'static Interaction,
        &'static mut BackgroundColor,
        &'static mut BorderColor,
    ),
    (Changed<Interaction>, With<Button>),
>;

// Global button interaction feedback
pub fn button_interaction_system(mut buttons: ButtonQuery) {
    for (interaction, mut bg, mut border) in buttons.iter_mut() {
        match *interaction {
            Interaction::Pressed => {
                bg.0 = bg.0.mix(&Color::BLACK, 0.3);
                border.top = border.top.mix(&Color::BLACK, 0.3);
                border.right = border.right.mix(&Color::BLACK, 0.3);
                border.bottom = border.bottom.mix(&Color::BLACK, 0.3);
                border.left = border.left.mix(&Color::BLACK, 0.3);
            }
            Interaction::Hovered => {
                bg.0 = bg.0.mix(&Color::WHITE, 0.15);
                border.top = border.top.mix(&Color::WHITE, 0.15);
                border.right = border.right.mix(&Color::WHITE, 0.15);
                border.bottom = border.bottom.mix(&Color::WHITE, 0.15);
                border.left = border.left.mix(&Color::WHITE, 0.15);
            }
            Interaction::None => {}
        }
    }
}
