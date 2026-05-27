use bevy::prelude::*;

use crate::chess::{Board, PieceColor, PieceType};

use super::GameEntity;

#[derive(Resource, Clone)]
pub struct PieceVisualAssets {
    king: Handle<Mesh>,
    king_cross: Handle<Mesh>,
    pawn: Handle<Mesh>,
    knight_primary: Handle<Mesh>,
    knight_secondary: Handle<Mesh>,
    rook: Handle<Mesh>,
    bishop: Handle<Mesh>,
    queen: Handle<Mesh>,
    white_material: Handle<StandardMaterial>,
    black_material: Handle<StandardMaterial>,
}

impl PieceVisualAssets {
    pub fn load(asset_server: &AssetServer, materials: &mut Assets<StandardMaterial>) -> Self {
        Self {
            king: asset_server.load("models/chess_kit/pieces.glb#Mesh0/Primitive0"),
            king_cross: asset_server.load("models/chess_kit/pieces.glb#Mesh1/Primitive0"),
            pawn: asset_server.load("models/chess_kit/pieces.glb#Mesh2/Primitive0"),
            knight_primary: asset_server.load("models/chess_kit/pieces.glb#Mesh3/Primitive0"),
            knight_secondary: asset_server.load("models/chess_kit/pieces.glb#Mesh4/Primitive0"),
            rook: asset_server.load("models/chess_kit/pieces.glb#Mesh5/Primitive0"),
            bishop: asset_server.load("models/chess_kit/pieces.glb#Mesh6/Primitive0"),
            queen: asset_server.load("models/chess_kit/pieces.glb#Mesh7/Primitive0"),
            white_material: materials.add(Color::srgb(1.0, 0.8, 0.8)),
            black_material: materials.add(Color::srgb(0.0, 0.2, 0.2)),
        }
    }

    fn material(&self, color: PieceColor) -> Handle<StandardMaterial> {
        match color {
            PieceColor::White => self.white_material.clone(),
            PieceColor::Black => self.black_material.clone(),
        }
    }
}

/// Marker for a 3D piece entity.
#[derive(Component)]
#[allow(dead_code)]
pub struct PieceEntity {
    pub file: u8,
    pub rank: u8,
    pub piece_type: PieceType,
    pub color: PieceColor,
}

/// Spawn all pieces for a given board state.
pub fn spawn_pieces(mut commands: Commands, assets: &PieceVisualAssets, board: &Board) {
    for (file, rank, piece) in board.iter() {
        spawn_piece_entity(
            &mut commands,
            assets,
            file,
            rank,
            piece.piece_type,
            piece.color,
        );
    }
}

fn spawn_piece_entity(
    commands: &mut Commands,
    assets: &PieceVisualAssets,
    file: u8,
    rank: u8,
    piece_type: PieceType,
    color: PieceColor,
) {
    let x = file as f32;
    let z = rank as f32;
    let material = assets.material(color);

    commands
        .spawn((
            Transform::from_xyz(x, 0.0, z),
            PieceEntity {
                file,
                rank,
                piece_type,
                color,
            },
            GameEntity,
        ))
        .with_children(|parent| match piece_type {
            PieceType::Queen => {
                parent.spawn((
                    Mesh3d(assets.queen.clone()),
                    MeshMaterial3d(material.clone()),
                    Transform::from_translation(Vec3::new(-0.2, 0.0, -0.95))
                        .with_scale(Vec3::splat(0.2)),
                ));
            }
            PieceType::Rook => {
                parent.spawn((
                    Mesh3d(assets.rook.clone()),
                    MeshMaterial3d(material.clone()),
                    Transform::from_translation(Vec3::new(-0.1, 0.0, 1.8))
                        .with_scale(Vec3::splat(0.2)),
                ));
            }
            PieceType::Bishop => {
                parent.spawn((
                    Mesh3d(assets.bishop.clone()),
                    MeshMaterial3d(material.clone()),
                    Transform::from_translation(Vec3::new(-0.1, 0.0, 0.0))
                        .with_scale(Vec3::splat(0.2)),
                ));
            }
            PieceType::Knight => {
                parent.spawn((
                    Mesh3d(assets.knight_primary.clone()),
                    MeshMaterial3d(material.clone()),
                    Transform::from_translation(Vec3::new(-0.2, 0.0, 0.9))
                        .with_scale(Vec3::splat(0.2)),
                ));
                parent.spawn((
                    Mesh3d(assets.knight_secondary.clone()),
                    MeshMaterial3d(material.clone()),
                    Transform::from_translation(Vec3::new(-0.2, 0.0, 0.9))
                        .with_scale(Vec3::splat(0.2)),
                ));
            }
            PieceType::King => {
                parent.spawn((
                    Mesh3d(assets.king.clone()),
                    MeshMaterial3d(material.clone()),
                    Transform::from_translation(Vec3::new(-0.2, 0.0, -1.9))
                        .with_scale(Vec3::splat(0.2)),
                ));
                parent.spawn((
                    Mesh3d(assets.king_cross.clone()),
                    MeshMaterial3d(material.clone()),
                    Transform::from_translation(Vec3::new(-0.2, 0.0, -1.9))
                        .with_scale(Vec3::splat(0.2)),
                ));
            }
            PieceType::Pawn => {
                parent.spawn((
                    Mesh3d(assets.pawn.clone()),
                    MeshMaterial3d(material),
                    Transform::from_translation(Vec3::new(-0.2, 0.0, 2.6))
                        .with_scale(Vec3::splat(0.2)),
                ));
            }
        });
}
