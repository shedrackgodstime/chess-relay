use bevy::prelude::*;

use crate::theme::palette;

pub struct SettingsPlugin;

impl Plugin for SettingsPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(OnEnter(super::Screen::Settings), spawn_settings)
            .add_systems(OnExit(super::Screen::Settings), despawn_settings)
            .add_systems(
                Update,
                handle_settings_back.run_if(in_state(super::Screen::Settings)),
            );
    }
}

#[derive(Component)]
struct SettingsRoot;

#[derive(Component)]
struct BackButton;

fn spawn_settings(mut commands: Commands) {
    commands
        .spawn((
            Node {
                width: Val::Percent(100.0),
                height: Val::Percent(100.0),
                flex_direction: FlexDirection::Column,
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                row_gap: Val::Px(16.0),
                ..default()
            },
            BackgroundColor(palette::BACKGROUND),
            SettingsRoot,
        ))
        .with_children(|parent| {
            parent.spawn((
                Text::new("Settings"),
                TextFont {
                    font_size: 32.0,
                    ..default()
                },
                TextColor(palette::TEXT_PRIMARY),
            ));

            parent
                .spawn((
                    Node {
                        width: Val::Px(200.0),
                        height: Val::Px(44.0),
                        justify_content: JustifyContent::Center,
                        align_items: AlignItems::Center,
                        border: UiRect::all(Val::Px(1.0)),
                        border_radius: BorderRadius::all(Val::Px(6.0)),
                        ..default()
                    },
                    Button,
                    BackgroundColor(palette::ACCENT),
                    BorderColor::all(palette::ACCENT),
                    BackButton,
                ))
                .with_child((
                    Text::new("← Back"),
                    TextFont {
                        font_size: 18.0,
                        ..default()
                    },
                    TextColor(Color::BLACK),
                ));
        });
}

fn despawn_settings(mut commands: Commands, query: Query<Entity, With<SettingsRoot>>) {
    for entity in query.iter() {
        commands.entity(entity).despawn();
    }
}

fn handle_settings_back(
    mut next_screen: ResMut<NextState<super::Screen>>,
    query: Query<&Interaction, (Changed<Interaction>, With<BackButton>)>,
) {
    for interaction in query.iter() {
        if *interaction == Interaction::Pressed {
            next_screen.set(super::Screen::Home);
        }
    }
}
