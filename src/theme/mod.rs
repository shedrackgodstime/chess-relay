//! Shared theme tokens and widget helpers for the user interface.

pub(crate) mod palette;
pub(crate) mod spacing;
pub(crate) mod typography;
pub(crate) mod widgets;

use bevy::prelude::*;

/// Registers shared UI interaction styling systems.
pub(crate) struct ThemePlugin;

impl Plugin for ThemePlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Update, widgets::button_interaction_system);
    }
}
