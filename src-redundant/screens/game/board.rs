use bevy::picking::prelude::*;
use bevy::prelude::*;

use crate::screens::game::GameEntity;
use crate::screens::game::input::{PendingPromotion, PendingSquareClick};

/// Marker for the 3D board root entity.
#[derive(Component)]
#[allow(dead_code)]
pub struct BoardRoot;

/// Marker for a square entity.
#[derive(Component)]
#[allow(dead_code)]
pub struct BoardSquare {
    pub file: u8,
    pub rank: u8,
}

fn on_square_click(
    event: On<Pointer<Click>>,
    squares: Query<&BoardSquare>,
    pending_promotion: Res<PendingPromotion>,
    mut pending_square_click: ResMut<PendingSquareClick>,
) {
    if pending_promotion.0.is_some() {
        return;
    }

    let Ok(square) = squares.get(event.event_target()) else {
        return;
    };
    pending_square_click.0 = Some((square.file, square.rank));
}

/// Spawn the 3D checkerboard.
pub fn spawn_board(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    let light_color = Color::srgb(0.9, 0.9, 0.85);
    let dark_color = Color::srgb(0.2, 0.15, 0.1);

    let square_mesh = meshes.add(Cuboid::from_size(Vec3::new(0.95, 0.05, 0.95)));

    for file in 0..8u8 {
        for rank in 0..8u8 {
            let x = file as f32;
            let z = rank as f32;
            let is_light = (file + rank) % 2 == 0;
            let color = if is_light { light_color } else { dark_color };

            let entity = commands
                .spawn((
                    Mesh3d(square_mesh.clone()),
                    MeshMaterial3d(materials.add(color)),
                    Transform::from_xyz(x, -0.025, z),
                    BoardSquare { file, rank },
                    Pickable::default(),
                    GameEntity,
                ))
                .id();
            commands.entity(entity).observe(on_square_click);
        }
    }
}
