mod game;
mod home;
mod lobby;
mod settings;

use bevy::prelude::*;

#[derive(States, Clone, PartialEq, Eq, Debug, Hash, Default)]
pub enum Screen {
    #[default]
    Home,
    Lobby,
    Game,
    Settings,
}

pub struct ScreenPlugin;

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
