//! Lobby screen placeholder for future online play flows.

use bevy::prelude::*;

use crate::screens::Screen;
use crate::theme::{palette, widgets};
use crate::ui::components::ScreenRoot;

/// Registers the lobby screen plugin and its screen-local systems.
pub(super) struct LobbyPlugin;

#[derive(Component)]
struct BackButton;

impl Plugin for LobbyPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(OnEnter(Screen::Lobby), spawn_lobby)
            .add_systems(OnExit(Screen::Lobby), despawn_lobby)
            .add_systems(Update, handle_lobby_actions.run_if(in_state(Screen::Lobby)));
    }
}

fn spawn_lobby(mut commands: Commands) {
    commands
        .spawn((
            widgets::screen_root_node(),
            BackgroundColor(palette::APP_BACKGROUND),
            ScreenRoot,
        ))
        .with_children(|parent| {
            parent
                .spawn(widgets::panel_node(560.0))
                .with_children(|parent| {
                    parent.spawn(widgets::display_text("Lobby"));
                    parent.spawn(widgets::body_text(
                        "Networking is intentionally deferred, but the screen flow is already separated so it can be integrated cleanly later.",
                    ));
                    let back = widgets::button(parent, "Back Home", widgets::ButtonKind::Ghost);
                    parent.commands().entity(back).insert(BackButton);
                });
        });
}

fn despawn_lobby(mut commands: Commands, roots: Query<Entity, With<ScreenRoot>>) {
    for entity in roots.iter() {
        commands
            .entity(entity)
            .despawn_related::<Children>()
            .despawn();
    }
}

fn handle_lobby_actions(
    mut next_screen: ResMut<NextState<Screen>>,
    query: Query<&Interaction, (Changed<Interaction>, With<BackButton>)>,
) {
    for interaction in query.iter() {
        if *interaction == Interaction::Pressed {
            next_screen.set(Screen::Home);
        }
    }
}
