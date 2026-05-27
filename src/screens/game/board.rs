//! Board scene construction and square material state for the game screen.

use bevy::prelude::*;

use crate::theme::palette;

pub(super) const BOARD_HALF_SPAN: f32 = 4.0;
const BORDER_CENTER_Y: f32 = -0.20;
const SQUARE_CENTER_Y: f32 = -0.08;

#[derive(Component, Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct BoardSquare {
    pub file: u8,
    pub rank: u8,
}

#[derive(Component, Clone)]
pub(super) struct SquareMaterialSet {
    pub idle: Handle<StandardMaterial>,
    pub selected: Handle<StandardMaterial>,
    pub legal: Handle<StandardMaterial>,
    pub capture: Handle<StandardMaterial>,
    pub last_move: Handle<StandardMaterial>,
    pub check: Handle<StandardMaterial>,
}

pub(super) fn spawn_board(
    parent: &mut ChildSpawnerCommands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
) {
    let light_square = materials.add(StandardMaterial {
        base_color: palette::BOARD_LIGHT,
        perceptual_roughness: 0.92,
        ..default()
    });
    let dark_square = materials.add(StandardMaterial {
        base_color: palette::BOARD_DARK,
        perceptual_roughness: 0.96,
        ..default()
    });
    let border_material = materials.add(StandardMaterial {
        base_color: palette::BOARD_BORDER,
        perceptual_roughness: 0.8,
        metallic: 0.08,
        ..default()
    });

    let square_mesh = meshes.add(Cuboid::from_size(Vec3::new(0.96, 0.16, 0.96)));
    let border_mesh = meshes.add(Cuboid::from_size(Vec3::new(9.2, 0.24, 9.2)));

    parent.spawn((
        Mesh3d(border_mesh),
        MeshMaterial3d(border_material),
        Transform::from_xyz(0.0, BORDER_CENTER_Y, 0.0),
        Visibility::default(),
    ));

    for file in 0..8 {
        for rank in 0..8 {
            let is_light = (file + rank) % 2 == 0;
            let idle = if is_light {
                light_square.clone()
            } else {
                dark_square.clone()
            };
            let selected = materials.add(StandardMaterial {
                base_color: if is_light {
                    Color::srgb(0.94, 0.79, 0.45)
                } else {
                    Color::srgb(0.72, 0.53, 0.25)
                },
                perceptual_roughness: 0.90,
                ..default()
            });
            let legal = materials.add(StandardMaterial {
                base_color: if is_light {
                    Color::srgb(0.49, 0.71, 0.50)
                } else {
                    Color::srgb(0.26, 0.47, 0.27)
                },
                perceptual_roughness: 0.90,
                ..default()
            });
            let capture = materials.add(StandardMaterial {
                base_color: if is_light {
                    Color::srgb(0.82, 0.33, 0.31)
                } else {
                    Color::srgb(0.61, 0.16, 0.15)
                },
                perceptual_roughness: 0.88,
                ..default()
            });
            let last_move = materials.add(StandardMaterial {
                base_color: if is_light {
                    Color::srgb(0.55, 0.66, 0.82)
                } else {
                    Color::srgb(0.31, 0.40, 0.59)
                },
                perceptual_roughness: 0.88,
                ..default()
            });
            let check = materials.add(StandardMaterial {
                base_color: if is_light {
                    Color::srgb(0.88, 0.43, 0.39)
                } else {
                    Color::srgb(0.67, 0.22, 0.20)
                },
                perceptual_roughness: 0.86,
                ..default()
            });

            parent.spawn((
                Mesh3d(square_mesh.clone()),
                MeshMaterial3d(idle.clone()),
                Transform::from_xyz(
                    file as f32 - (BOARD_HALF_SPAN - 0.5),
                    SQUARE_CENTER_Y,
                    rank as f32 - (BOARD_HALF_SPAN - 0.5),
                ),
                Visibility::default(),
                BoardSquare { file, rank },
                SquareMaterialSet {
                    idle,
                    selected,
                    legal,
                    capture,
                    last_move,
                    check,
                },
            ));
        }
    }
}
