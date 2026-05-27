//! Global scene configuration shared across screens.

use bevy::prelude::*;

use crate::theme::palette;

/// Applies scene-wide rendering resources such as the clear color.
pub(super) struct ScenePlugin;

impl Plugin for ScenePlugin {
    fn build(&self, app: &mut App) {
        app.insert_resource(ClearColor(palette::APP_BACKGROUND));
    }
}
