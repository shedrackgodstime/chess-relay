mod chess;
mod screens;
mod theme;

use bevy::ecs::name::Name;
use bevy::picking::prelude::MeshPickingPlugin;
use bevy::prelude::*;

#[derive(Component)]
struct GameCamera;

fn main() {
    App::new()
        .add_plugins(DefaultPlugins)
        .add_plugins(MeshPickingPlugin)
        .add_plugins(screens::ScreenPlugin)
        .register_type::<Transform>()
        .register_type::<Mesh3d>()
        .register_type::<MeshMaterial3d<StandardMaterial>>()
        .register_type::<Visibility>()
        .register_type::<InheritedVisibility>()
        .register_type::<ViewVisibility>()
        .register_type::<Name>()
        .register_type::<bevy::camera::primitives::Aabb>()
        .add_systems(Startup, spawn_3d_world)
        .add_systems(Update, update_game_camera)
        .add_systems(Update, theme::widgets::button_interaction_system)
        .run();
}

fn spawn_3d_world(mut commands: Commands) {
    // 3D camera (used by Game screen; 2D camera is for UI)
    commands.spawn((
        Camera3d::default(),
        Transform::from_xyz(-6.0, 11.5, 3.5).looking_at(Vec3::new(3.5, 0.0, 3.5), Vec3::Y),
        Camera::default(),
        Projection::Perspective(PerspectiveProjection {
            fov: std::f32::consts::FRAC_PI_4,
            ..default()
        }),
        GameCamera,
    ));

    // Directional light
    commands.spawn((
        DirectionalLight {
            illuminance: 10_000.0,
            shadows_enabled: true,
            ..default()
        },
        Transform::from_xyz(4.5, 12.0, 5.5).looking_at(Vec3::new(3.5, 0.0, 3.5), Vec3::Y),
    ));
}

fn update_game_camera(
    windows: Query<&Window>,
    mut cameras: Query<(&mut Transform, &mut Projection), With<GameCamera>>,
) {
    let Ok(window) = windows.single() else {
        return;
    };
    let Ok((mut transform, mut projection)) = cameras.single_mut() else {
        return;
    };

    let aspect_ratio = window.width() / window.height().max(1.0);
    let center = Vec3::new(3.5, 0.0, 3.5);

    if aspect_ratio < 1.0 {
        *transform = Transform::from_xyz(3.5, 14.5, 11.0).looking_at(center, Vec3::Y);
        if let Projection::Perspective(perspective) = &mut *projection {
            perspective.fov = 0.95;
        }
    } else {
        *transform = Transform::from_xyz(-6.0, 11.5, 3.5).looking_at(center, Vec3::Y);
        if let Projection::Perspective(perspective) = &mut *projection {
            perspective.fov = std::f32::consts::FRAC_PI_4;
        }
    }
}
