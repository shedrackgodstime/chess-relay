use bevy::log::info;
use bevy::prelude::*;

use crate::theme::palette;
use crate::theme::widgets;

pub struct LobbyPlugin;

impl Plugin for LobbyPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(OnEnter(super::Screen::Lobby), spawn_lobby)
            .add_systems(OnExit(super::Screen::Lobby), despawn_lobby)
            .add_systems(
                Update,
                handle_lobby_buttons.run_if(in_state(super::Screen::Lobby)),
            );
    }
}

#[derive(Component)]
struct LobbyRoot;

#[derive(Component)]
struct FindMatchButton;

#[derive(Component)]
struct BackHomeButton;

fn spawn_lobby(mut commands: Commands) {
    commands
        .spawn((
            Node {
                width: Val::Percent(100.0),
                height: Val::Percent(100.0),
                flex_direction: FlexDirection::Column,
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                ..default()
            },
            BackgroundColor(palette::BACKGROUND),
            LobbyRoot,
        ))
        .with_children(|parent| {
            parent.spawn((
                Text::new("Lobby"),
                TextFont {
                    font_size: 32.0,
                    ..default()
                },
                TextColor(palette::TEXT_PRIMARY),
            ));

            widgets::divider(parent, 120.0);

            parent
                .spawn((
                    Node {
                        padding: UiRect::all(Val::Px(24.0)),
                        margin: UiRect::vertical(Val::Px(12.0)),
                        flex_direction: FlexDirection::Column,
                        align_items: AlignItems::Center,
                        row_gap: Val::Px(12.0),
                        width: Val::Px(320.0),
                        ..default()
                    },
                    BackgroundColor(Color::NONE),
                ))
                .with_children(|parent| {
                    parent.spawn((
                        Text::new("No players found"),
                        TextFont {
                            font_size: 16.0,
                            ..default()
                        },
                        TextColor(palette::TEXT_MUTED),
                    ));

                    parent.spawn((
                        Text::new("Waiting for opponents..."),
                        TextFont {
                            font_size: 14.0,
                            ..default()
                        },
                        TextColor(palette::TEXT_MUTED),
                    ));
                });

            let find_btn = widgets::primary_button(parent, "Find Match");
            let back_btn = widgets::text_link(parent, "← Back to Home");

            parent.commands().entity(find_btn).insert(FindMatchButton);
            parent.commands().entity(back_btn).insert(BackHomeButton);
        });
}

fn despawn_lobby(mut commands: Commands, query: Query<Entity, With<LobbyRoot>>) {
    for entity in query.iter() {
        commands.entity(entity).despawn();
    }
}

type InteractionQuery<'w, 's> =
    Query<'w, 's, (&'static Interaction, Entity), (Changed<Interaction>, With<Button>)>;

fn handle_lobby_buttons(
    mut next_screen: ResMut<NextState<super::Screen>>,
    interaction_query: InteractionQuery,
    find_match: Query<Entity, With<FindMatchButton>>,
    back_home: Query<Entity, With<BackHomeButton>>,
) {
    for (interaction, entity) in interaction_query.iter() {
        if *interaction != Interaction::Pressed {
            continue;
        }
        if find_match.get(entity).is_ok() {
            info!("Find Match clicked");
        } else if back_home.get(entity).is_ok() {
            next_screen.set(super::Screen::Home);
        }
    }
}
