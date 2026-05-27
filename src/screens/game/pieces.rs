//! Piece spawning and model placement for the game scene.

use bevy::prelude::*;
use std::f32::consts::PI;

use crate::chess::{Board, PieceColor, PieceType};
use crate::theme::palette;

// The imported GLB pivots sit slightly above the visible base of the pieces,
// so we sink the piece roots to make the models read as grounded on the square.
const PIECE_ROOT_Y: f32 = -0.075;

pub(super) fn spawn_pieces(
    parent: &mut ChildSpawnerCommands,
    asset_server: &AssetServer,
    materials: &mut Assets<StandardMaterial>,
    board: &Board,
) {
    let white_material = materials.add(StandardMaterial {
        base_color: palette::PIECE_WHITE,
        perceptual_roughness: 0.76,
        ..default()
    });
    let black_material = materials.add(StandardMaterial {
        base_color: palette::PIECE_BLACK,
        perceptual_roughness: 0.84,
        metallic: 0.05,
        ..default()
    });

    for (file, rank, piece) in board.iter() {
        spawn_piece(
            parent,
            asset_server,
            piece.piece_type,
            piece.color,
            file,
            rank,
            white_material.clone(),
            black_material.clone(),
        );
    }
}

#[allow(clippy::too_many_arguments)]
fn spawn_piece(
    parent: &mut ChildSpawnerCommands,
    asset_server: &AssetServer,
    piece_type: PieceType,
    color: PieceColor,
    file: u8,
    rank: u8,
    white_material: Handle<StandardMaterial>,
    black_material: Handle<StandardMaterial>,
) {
    let material = match color {
        PieceColor::White => white_material,
        PieceColor::Black => black_material,
    };
    let rotation = match color {
        PieceColor::White => Quat::IDENTITY,
        PieceColor::Black => Quat::from_rotation_y(PI),
    };

    let root = parent
        .spawn((
            Transform {
                translation: Vec3::new(file as f32 - 3.5, PIECE_ROOT_Y, rank as f32 - 3.5),
                rotation,
                ..default()
            },
            Visibility::default(),
            super::PieceEntity { file, rank },
        ))
        .id();

    parent.commands().entity(root).with_children(|parent| {
        let (meshes, offsets): (&[&str], &[Vec3]) = match piece_type {
            PieceType::King => (
                &[
                    "models/chess_kit/pieces.glb#Mesh0/Primitive0",
                    "models/chess_kit/pieces.glb#Mesh1/Primitive0",
                ],
                &[Vec3::new(0.0, 0.0, -1.9), Vec3::new(0.0, 0.0, -1.9)],
            ),
            PieceType::Queen => (
                &["models/chess_kit/pieces.glb#Mesh7/Primitive0"],
                &[Vec3::new(0.0, 0.0, -0.95)],
            ),
            PieceType::Bishop => (
                &["models/chess_kit/pieces.glb#Mesh6/Primitive0"],
                &[Vec3::new(0.0, 0.0, 0.0)],
            ),
            PieceType::Knight => (
                &[
                    "models/chess_kit/pieces.glb#Mesh3/Primitive0",
                    "models/chess_kit/pieces.glb#Mesh4/Primitive0",
                ],
                &[Vec3::new(0.0, 0.0, 0.9), Vec3::new(0.0, 0.0, 0.9)],
            ),
            PieceType::Rook => (
                &["models/chess_kit/pieces.glb#Mesh5/Primitive0"],
                &[Vec3::new(0.0, 0.0, 1.8)],
            ),
            PieceType::Pawn => (
                &["models/chess_kit/pieces.glb#Mesh2/Primitive0"],
                &[Vec3::new(0.0, 0.0, 2.6)],
            ),
        };

        for (mesh_path, offset) in meshes.iter().zip(offsets.iter()) {
            parent.spawn((
                Mesh3d(asset_server.load(*mesh_path)),
                MeshMaterial3d(material.clone()),
                Transform::from_translation(*offset).with_scale(Vec3::splat(0.2)),
                Visibility::default(),
            ));
        }
    });
}
