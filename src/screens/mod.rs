//! Screen-state plugins for the Chess Relay user interface.

mod game;
mod home;
mod lobby;
mod settings;

use bevy::prelude::*;

/// Top-level screen state for navigation.
#[derive(States, Clone, Copy, PartialEq, Eq, Debug, Hash, Default)]
pub(crate) enum Screen {
    #[default]
    Home,
    Lobby,
    Game,
    Settings,
}

/// Registers all screen plugins and the screen navigation state.
pub(crate) struct ScreenPlugin;

impl Plugin for ScreenPlugin {
    fn build(&self, app: &mut App) {
        app.init_state::<Screen>().add_plugins((
            home::HomePlugin,
            lobby::LobbyPlugin,
            game::GamePlugin,
            settings::SettingsPlugin,
        ));
    }
}
