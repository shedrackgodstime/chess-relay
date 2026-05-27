//! Camera setup and adaptive framing for the 3D scene and UI layer.

use bevy::camera::ClearColorConfig;
use bevy::prelude::*;

const DESKTOP_CAMERA_TARGET: Vec3 = Vec3::new(0.0, 0.0, 0.8);
const MOBILE_CAMERA_TARGET: Vec3 = Vec3::new(0.0, 0.0, 1.1);
const DESKTOP_CAMERA_POSITION: Vec3 = Vec3::new(0.0, 13.5, -11.5);
const MOBILE_CAMERA_POSITION: Vec3 = Vec3::new(0.0, 16.5, -13.0);

/// Marker for the primary 3D gameplay camera.
#[derive(Component)]
pub(crate) struct MainCamera3d;

/// Marker for the primary 2D UI camera.
#[derive(Component)]
pub(crate) struct MainCamera2d;

#[derive(Resource, Clone, Copy, PartialEq, Eq, Debug, Default)]
enum CameraLayoutMode {
    #[default]
    Desktop,
    Mobile,
}

/// Configures the application cameras and viewport-dependent framing.
pub(super) struct CameraPlugin;

impl Plugin for CameraPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<CameraLayoutMode>()
            .add_systems(Startup, spawn_cameras)
            .add_systems(Update, sync_camera_viewport);
    }
}

fn spawn_cameras(mut commands: Commands) {
    commands.spawn((
        Camera3d::default(),
        Camera {
            order: 0,
            ..default()
        },
        Transform::from_translation(DESKTOP_CAMERA_POSITION)
            .looking_at(DESKTOP_CAMERA_TARGET, Vec3::Y),
        MainCamera3d,
    ));

    commands.spawn((
        Camera2d,
        Camera {
            order: 1,
            clear_color: ClearColorConfig::None,
            ..default()
        },
        IsDefaultUiCamera,
        MainCamera2d,
    ));
}

fn sync_camera_viewport(
    windows: Query<&Window>,
    mut layout_mode: ResMut<CameraLayoutMode>,
    mut cameras: Query<&mut Transform, With<MainCamera3d>>,
) {
    let Ok(window) = windows.single() else {
        return;
    };
    let Ok(mut transform) = cameras.single_mut() else {
        return;
    };

    let next_layout_mode = if window.height() > window.width() {
        CameraLayoutMode::Mobile
    } else {
        CameraLayoutMode::Desktop
    };

    if *layout_mode == next_layout_mode {
        return;
    }

    let desired_position = if next_layout_mode == CameraLayoutMode::Mobile {
        MOBILE_CAMERA_POSITION
    } else {
        DESKTOP_CAMERA_POSITION
    };
    let desired_target = if next_layout_mode == CameraLayoutMode::Mobile {
        MOBILE_CAMERA_TARGET
    } else {
        DESKTOP_CAMERA_TARGET
    };

    *transform = Transform::from_translation(desired_position).looking_at(desired_target, Vec3::Y);
    *layout_mode = next_layout_mode;
}
