mod components;

use bevy::prelude::*;

use crate::screens::Screen;
use crate::screens::game::GameConfig;
use crate::theme::palette;
use crate::theme::widgets;
use components::*;

pub struct HomePlugin;

impl Plugin for HomePlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(OnEnter(Screen::Home), spawn_home)
            .add_systems(OnExit(Screen::Home), despawn_home)
            .add_systems(Update, handle_home_buttons.run_if(in_state(Screen::Home)));
    }
}

fn spawn_home(mut commands: Commands) {
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
            ScreenRoot,
        ))
        .with_children(|parent| {
            parent
                .spawn((
                    Node {
                        flex_direction: FlexDirection::Column,
                        align_items: AlignItems::Center,
                        row_gap: Val::Px(16.0),
                        ..default()
                    },
                    BackgroundColor(Color::NONE),
                ))
                .with_children(|parent| {
                    widgets::logo(parent);
                    widgets::divider(parent, 220.0);
                    let play_btn = widgets::primary_button(parent, "Play Online");
                    let local_btn = widgets::secondary_button(parent, "Local Game");
                    let settings_lnk = widgets::text_link(parent, "Settings");
                    parent.commands().entity(play_btn).insert(PlayOnlineButton);
                    parent.commands().entity(local_btn).insert(LocalGameButton);
                    parent
                        .commands()
                        .entity(settings_lnk)
                        .insert(SettingsButton);
                });

            widgets::footer(parent);
        });
}

fn despawn_home(mut commands: Commands, query: Query<Entity, With<ScreenRoot>>) {
    for entity in query.iter() {
        commands.entity(entity).despawn();
    }
}

type InteractionQuery<'w, 's> =
    Query<'w, 's, (&'static Interaction, Entity), (Changed<Interaction>, With<Button>)>;

fn handle_home_buttons(
    mut next_screen: ResMut<NextState<Screen>>,
    mut commands: Commands,
    interaction_query: InteractionQuery,
    play_online: Query<Entity, With<PlayOnlineButton>>,
    local_game: Query<Entity, With<LocalGameButton>>,
    settings: Query<Entity, With<SettingsButton>>,
) {
    for (interaction, entity) in interaction_query.iter() {
        if *interaction != Interaction::Pressed {
            continue;
        }
        if play_online.get(entity).is_ok() {
            next_screen.set(Screen::Lobby);
        } else if local_game.get(entity).is_ok() {
            commands.insert_resource(GameConfig::default());
            next_screen.set(Screen::Game);
        } else if settings.get(entity).is_ok() {
            next_screen.set(Screen::Settings);
        }
    }
}
