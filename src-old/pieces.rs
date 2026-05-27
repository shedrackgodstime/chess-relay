use bevy::prelude::*;
use bevy::picking::Pickable;

#[derive(Clone, Copy, Default, PartialEq, Eq, Debug)]
pub enum PieceColor {
    #[default]
    White,
    Black,
}

impl PieceColor {
    pub fn opposite(&self) -> Self {
        match self {
            PieceColor::White => PieceColor::Black,
            PieceColor::Black => PieceColor::White,
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Default, Debug)]
pub enum PieceType {
    #[default]
    King,
    Queen,
    Bishop,
    Knight,
    Rook,
    Pawn,
}

#[derive(Clone, Copy, Component)]
pub struct Piece {
    pub color: PieceColor,
    pub piece_type: PieceType,
    pub x: u8,
    pub y: u8,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Resource)]
pub struct CastlingRights {
    pub white_kingside: bool,
    pub white_queenside: bool,
    pub black_kingside: bool,
    pub black_queenside: bool,
}

impl CastlingRights {
    pub fn can_castle_kingside(&self, color: PieceColor) -> bool {
        match color {
            PieceColor::White => self.white_kingside,
            PieceColor::Black => self.black_kingside,
        }
    }
    pub fn can_castle_queenside(&self, color: PieceColor) -> bool {
        match color {
            PieceColor::White => self.white_queenside,
            PieceColor::Black => self.black_queenside,
        }
    }
    pub fn revoke_king(&mut self, color: PieceColor) {
        match color {
            PieceColor::White => {
                self.white_kingside = false;
                self.white_queenside = false;
            }
            PieceColor::Black => {
                self.black_kingside = false;
                self.black_queenside = false;
            }
        }
    }
    pub fn revoke_rook(&mut self, color: PieceColor, x: u8, y: u8) {
        let home = match color {
            PieceColor::White => 0,
            PieceColor::Black => 7,
        };
        if x == home {
            match y {
                0 => {
                    if color == PieceColor::White {
                        self.white_queenside = false;
                    } else {
                        self.black_queenside = false;
                    }
                }
                7 => {
                    if color == PieceColor::White {
                        self.white_kingside = false;
                    } else {
                        self.black_kingside = false;
                    }
                }
                _ => {}
            }
        }
    }
}

impl Default for CastlingRights {
    fn default() -> Self {
        Self {
            white_kingside: true,
            white_queenside: true,
            black_kingside: true,
            black_queenside: true,
        }
    }
}

pub fn create_pieces(
    mut commands: Commands,
    asset_server: Res<AssetServer>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    let king: Handle<Mesh> = asset_server.load("models/chess_kit/pieces.glb#Mesh0/Primitive0");
    let king_cross: Handle<Mesh> = asset_server.load("models/chess_kit/pieces.glb#Mesh1/Primitive0");
    let pawn: Handle<Mesh> = asset_server.load("models/chess_kit/pieces.glb#Mesh2/Primitive0");
    let knight_1: Handle<Mesh> = asset_server.load("models/chess_kit/pieces.glb#Mesh3/Primitive0");
    let knight_2: Handle<Mesh> = asset_server.load("models/chess_kit/pieces.glb#Mesh4/Primitive0");
    let rook: Handle<Mesh> = asset_server.load("models/chess_kit/pieces.glb#Mesh5/Primitive0");
    let bishop: Handle<Mesh> = asset_server.load("models/chess_kit/pieces.glb#Mesh6/Primitive0");
    let queen: Handle<Mesh> = asset_server.load("models/chess_kit/pieces.glb#Mesh7/Primitive0");

    let white = materials.add(Color::srgb(1.0, 0.8, 0.8));
    let black = materials.add(Color::srgb(0.0, 0.2, 0.2));

    spawn_rook(&mut commands, rook.clone(), white.clone(), PieceColor::White, (0, 0));
    spawn_knight(&mut commands, knight_1.clone(), knight_2.clone(), white.clone(), PieceColor::White, (0, 1));
    spawn_bishop(&mut commands, bishop.clone(), white.clone(), PieceColor::White, (0, 2));
    spawn_queen(&mut commands, queen.clone(), white.clone(), PieceColor::White, (0, 3));
    spawn_king(&mut commands, king.clone(), king_cross.clone(), white.clone(), PieceColor::White, (0, 4));
    spawn_bishop(&mut commands, bishop.clone(), white.clone(), PieceColor::White, (0, 5));
    spawn_knight(&mut commands, knight_1.clone(), knight_2.clone(), white.clone(), PieceColor::White, (0, 6));
    spawn_rook(&mut commands, rook.clone(), white.clone(), PieceColor::White, (0, 7));
    for i in 0..8 {
        spawn_pawn(&mut commands, pawn.clone(), white.clone(), PieceColor::White, (1, i));
    }

    spawn_rook(&mut commands, rook.clone(), black.clone(), PieceColor::Black, (7, 0));
    spawn_knight(&mut commands, knight_1.clone(), knight_2.clone(), black.clone(), PieceColor::Black, (7, 1));
    spawn_bishop(&mut commands, bishop.clone(), black.clone(), PieceColor::Black, (7, 2));
    spawn_queen(&mut commands, queen.clone(), black.clone(), PieceColor::Black, (7, 3));
    spawn_king(&mut commands, king.clone(), king_cross.clone(), black.clone(), PieceColor::Black, (7, 4));
    spawn_bishop(&mut commands, bishop.clone(), black.clone(), PieceColor::Black, (7, 5));
    spawn_knight(&mut commands, knight_1.clone(), knight_2.clone(), black.clone(), PieceColor::Black, (7, 6));
    spawn_rook(&mut commands, rook.clone(), black.clone(), PieceColor::Black, (7, 7));
    for i in 0..8 {
        spawn_pawn(&mut commands, pawn.clone(), black.clone(), PieceColor::Black, (6, i));
    }
}

fn spawn_king(
    commands: &mut Commands,
    mesh: Handle<Mesh>,
    mesh_cross: Handle<Mesh>,
    material: Handle<StandardMaterial>,
    color: PieceColor,
    pos: (u8, u8),
) {
    commands.spawn((
        Piece { color, piece_type: PieceType::King, x: pos.0, y: pos.1 },
        Transform::from_translation(Vec3::new(pos.0 as f32, 0.0, pos.1 as f32)),
        Visibility::default(),
    )).with_children(|parent| {
        parent.spawn((
            Mesh3d(mesh),
            MeshMaterial3d(material.clone()),
            Transform::from_translation(Vec3::new(-0.2, 0.0, -1.9)).with_scale(Vec3::splat(0.2)),
            Pickable::IGNORE,
        ));
        parent.spawn((
            Mesh3d(mesh_cross),
            MeshMaterial3d(material),
            Transform::from_translation(Vec3::new(-0.2, 0.0, -1.9)).with_scale(Vec3::splat(0.2)),
            Pickable::IGNORE,
        ));
    });
}

fn spawn_knight(
    commands: &mut Commands,
    mesh_1: Handle<Mesh>,
    mesh_2: Handle<Mesh>,
    material: Handle<StandardMaterial>,
    color: PieceColor,
    pos: (u8, u8),
) {
    commands.spawn((
        Piece { color, piece_type: PieceType::Knight, x: pos.0, y: pos.1 },
        Transform::from_translation(Vec3::new(pos.0 as f32, 0.0, pos.1 as f32)),
        Visibility::default(),
    )).with_children(|parent| {
        parent.spawn((
            Mesh3d(mesh_1),
            MeshMaterial3d(material.clone()),
            Transform::from_translation(Vec3::new(-0.2, 0.0, 0.9)).with_scale(Vec3::splat(0.2)),
            Pickable::IGNORE,
        ));
        parent.spawn((
            Mesh3d(mesh_2),
            MeshMaterial3d(material),
            Transform::from_translation(Vec3::new(-0.2, 0.0, 0.9)).with_scale(Vec3::splat(0.2)),
            Pickable::IGNORE,
        ));
    });
}

fn spawn_queen(
    commands: &mut Commands,
    mesh: Handle<Mesh>,
    material: Handle<StandardMaterial>,
    color: PieceColor,
    pos: (u8, u8),
) {
    commands.spawn((
        Piece { color, piece_type: PieceType::Queen, x: pos.0, y: pos.1 },
        Transform::from_translation(Vec3::new(pos.0 as f32, 0.0, pos.1 as f32)),
        Visibility::default(),
    )).with_children(|parent| {
        parent.spawn((
            Mesh3d(mesh),
            MeshMaterial3d(material),
            Transform::from_translation(Vec3::new(-0.2, 0.0, -0.95)).with_scale(Vec3::splat(0.2)),
            Pickable::IGNORE,
        ));
    });
}

fn spawn_bishop(
    commands: &mut Commands,
    mesh: Handle<Mesh>,
    material: Handle<StandardMaterial>,
    color: PieceColor,
    pos: (u8, u8),
) {
    commands.spawn((
        Piece { color, piece_type: PieceType::Bishop, x: pos.0, y: pos.1 },
        Transform::from_translation(Vec3::new(pos.0 as f32, 0.0, pos.1 as f32)),
        Visibility::default(),
    )).with_children(|parent| {
        parent.spawn((
            Mesh3d(mesh),
            MeshMaterial3d(material),
            Transform::from_translation(Vec3::new(-0.1, 0.0, 0.0)).with_scale(Vec3::splat(0.2)),
            Pickable::IGNORE,
        ));
    });
}

fn spawn_rook(
    commands: &mut Commands,
    mesh: Handle<Mesh>,
    material: Handle<StandardMaterial>,
    color: PieceColor,
    pos: (u8, u8),
) {
    commands.spawn((
        Piece { color, piece_type: PieceType::Rook, x: pos.0, y: pos.1 },
        Transform::from_translation(Vec3::new(pos.0 as f32, 0.0, pos.1 as f32)),
        Visibility::default(),
    )).with_children(|parent| {
        parent.spawn((
            Mesh3d(mesh),
            MeshMaterial3d(material),
            Transform::from_translation(Vec3::new(-0.1, 0.0, 1.8)).with_scale(Vec3::splat(0.2)),
            Pickable::IGNORE,
        ));
    });
}

pub fn spawn_piece(
    commands: &mut Commands,
    asset_server: &AssetServer,
    materials: &mut Assets<StandardMaterial>,
    piece_type: PieceType,
    color: PieceColor,
    pos: (u8, u8),
) {
    let mat = match color {
        PieceColor::White => materials.add(Color::srgb(1.0, 0.8, 0.8)),
        PieceColor::Black => materials.add(Color::srgb(0.0, 0.2, 0.2)),
    };
    commands.spawn((
        Piece { color, piece_type, x: pos.0, y: pos.1 },
        Transform::from_translation(Vec3::new(pos.0 as f32, 0.0, pos.1 as f32)),
        Visibility::default(),
    )).with_children(|parent| {
        let (meshes, offsets): (&[&str], &[Vec3]) = match piece_type {
            PieceType::Queen => (
                &["models/chess_kit/pieces.glb#Mesh7/Primitive0"],
                &[Vec3::new(-0.2, 0.0, -0.95)],
            ),
            PieceType::Rook => (
                &["models/chess_kit/pieces.glb#Mesh5/Primitive0"],
                &[Vec3::new(-0.1, 0.0, 1.8)],
            ),
            PieceType::Bishop => (
                &["models/chess_kit/pieces.glb#Mesh6/Primitive0"],
                &[Vec3::new(-0.1, 0.0, 0.0)],
            ),
            PieceType::Knight => (
                &["models/chess_kit/pieces.glb#Mesh3/Primitive0", "models/chess_kit/pieces.glb#Mesh4/Primitive0"],
                &[Vec3::new(-0.2, 0.0, 0.9), Vec3::new(-0.2, 0.0, 0.9)],
            ),
            PieceType::King => (
                &["models/chess_kit/pieces.glb#Mesh0/Primitive0", "models/chess_kit/pieces.glb#Mesh1/Primitive0"],
                &[Vec3::new(-0.2, 0.0, -1.9), Vec3::new(-0.2, 0.0, -1.9)],
            ),
            PieceType::Pawn => (
                &["models/chess_kit/pieces.glb#Mesh2/Primitive0"],
                &[Vec3::new(-0.2, 0.0, 2.6)],
            ),
        };
        for (i, mesh_path) in meshes.iter().enumerate() {
            parent.spawn((
                Mesh3d(asset_server.load(*mesh_path)),
                MeshMaterial3d(mat.clone()),
                Transform::from_translation(offsets[i]).with_scale(Vec3::splat(0.2)),
                Pickable::IGNORE,
            ));
        }
    });
}

fn spawn_pawn(
    commands: &mut Commands,
    mesh: Handle<Mesh>,
    material: Handle<StandardMaterial>,
    color: PieceColor,
    pos: (u8, u8),
) {
    commands.spawn((
        Piece { color, piece_type: PieceType::Pawn, x: pos.0, y: pos.1 },
        Transform::from_translation(Vec3::new(pos.0 as f32, 0.0, pos.1 as f32)),
        Visibility::default(),
    )).with_children(|parent| {
        parent.spawn((
            Mesh3d(mesh),
            MeshMaterial3d(material),
            Transform::from_translation(Vec3::new(-0.2, 0.0, 2.6)).with_scale(Vec3::splat(0.2)),
            Pickable::IGNORE,
        ));
    });
}
