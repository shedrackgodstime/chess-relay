//! Application bootstrap plugins for rendering, camera, and scene setup.

mod camera;
mod lighting;
mod scene;

use bevy::picking::prelude::MeshPickingPlugin;
use bevy::prelude::*;

pub(crate) use camera::MainCamera3d;

/// Configures the Bevy application shell and engine-facing plugins.
pub(crate) struct AppPlugin;

impl Plugin for AppPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins(DefaultPlugins.set(WindowPlugin {
            primary_window: Some(Window {
                title: "Chess Relay".to_string(),
                resolution: (1440, 960).into(),
                resizable: true,
                ..default()
            }),
            ..default()
        }))
        .add_plugins(MeshPickingPlugin)
        .add_plugins((
            camera::CameraPlugin,
            lighting::LightingPlugin,
            scene::ScenePlugin,
        ));
    }
}
