mod board;
mod moves;
mod pieces;

use bevy::prelude::*;
use bevy::picking::prelude::MeshPickingPlugin;

fn main() {
    App::new()
        .add_plugins(DefaultPlugins)
        .add_plugins(MeshPickingPlugin)
        .add_systems(Startup, (setup, pieces::create_pieces))
        .add_plugins(board::BoardPlugin)
        .run();
}

fn setup(mut commands: Commands) {
    commands.spawn((
        Camera3d::default(),
        Transform::from_xyz(-7.0, 20.0, 4.0)
            .looking_at(Vec3::new(4.0, 0.0, 4.0), Vec3::Y),
    ));

    commands.spawn((
        DirectionalLight::default(),
        Transform::from_xyz(4.0, 8.0, 4.0),
    ));
}
