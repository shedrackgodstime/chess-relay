use bevy::prelude::*;
use bevy::picking::hover::PickingInteraction;

use crate::moves::{has_any_legal_move, is_player_in_check, legal_moves};
use crate::pieces::{spawn_piece, CastlingRights, Piece, PieceColor, PieceType};

#[derive(Clone, Copy, Component)]
pub struct Square {
    pub x: u8,
    pub y: u8,
}

impl Square {
    pub fn is_white(&self) -> bool {
        (self.x + self.y + 1) % 2 == 0
    }
}

#[derive(Resource, Default)]
pub struct SelectedPiece {
    pub entity: Option<Entity>,
}

#[derive(Resource, Default)]
pub struct Turn(pub PieceColor);

#[derive(Resource, Default)]
pub struct LegalMoves(pub Vec<(u8, u8)>);

#[derive(Resource, Default)]
pub struct InCheck(pub bool);

#[derive(Resource, Default)]
pub struct EnPassantTarget(pub Option<(u8, u8)>);

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum GameOver {
    Playing,
    Checkmate(PieceColor),
    Stalemate,
}

#[derive(Resource)]
pub struct GameState(pub GameOver);

impl Default for GameState {
    fn default() -> Self {
        Self(GameOver::Playing)
    }
}

#[derive(Resource, Default)]
pub struct PendingPromotion(pub Option<Entity>);

#[derive(Default)]
enum MoveAction {
    Select(Entity),
    Deselect,
    Move {
        piece: Entity,
        target_x: u8,
        target_y: u8,
    },
    #[default]
    None,
}

#[derive(Resource, Default)]
struct PendingAction(MoveAction);

fn create_board(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    let mesh = meshes.add(Plane3d::default().mesh().size(1.0, 1.0));

    for i in 0..8 {
        for j in 0..8 {
            let color = if (i + j + 1) % 2 == 0 {
                Color::srgb(1.0, 0.9, 0.9)
            } else {
                Color::srgb(0.0, 0.1, 0.1)
            };

            let entity = commands.spawn((
                Mesh3d(mesh.clone()),
                MeshMaterial3d(materials.add(color)),
                Transform::from_translation(Vec3::new(i as f32, 0.0, j as f32)),
                Square { x: i, y: j },
                Pickable::default(),
            )).id();

            commands.entity(entity).observe(on_square_click);
        }
    }
}

fn on_square_click(
    event: On<Pointer<Click>>,
    squares: Query<&Square>,
    pieces: Query<(Entity, &Piece)>,
    selected: Res<SelectedPiece>,
    turn: Res<Turn>,
    promotion: Res<PendingPromotion>,
    mut pending: ResMut<PendingAction>,
) {
    if promotion.0.is_some() {
        return;
    }

    let square_entity = event.event_target();
    let Ok(square) = squares.get(square_entity) else { return };

    let piece_at_square = pieces
        .iter()
        .find(|(_, p)| p.x == square.x && p.y == square.y);

    match (selected.entity, piece_at_square) {
        (None, Some((piece_entity, piece)))
            if piece.color == turn.0 =>
        {
            pending.0 = MoveAction::Select(piece_entity);
        }
        (Some(selected_entity), Some((piece_entity, _)))
            if selected_entity == piece_entity =>
        {
            pending.0 = MoveAction::Deselect;
        }
        (Some(piece_entity), _) => {
            pending.0 = MoveAction::Move {
                piece: piece_entity,
                target_x: square.x,
                target_y: square.y,
            };
        }
        _ => {}
    }
}

fn finish_turn(
    turn: &mut Turn,
    in_check: &mut InCheck,
    state: &mut GameState,
    castling: &CastlingRights,
    en_passant: &EnPassantTarget,
    piece_data: &[(Entity, PieceColor, PieceType, u8, u8)],
) {
    let next = match turn.0 {
        PieceColor::White => PieceColor::Black,
        PieceColor::Black => PieceColor::White,
    };
    turn.0 = next;

    let checked = is_player_in_check(next, piece_data);
    in_check.0 = checked;

    if !has_any_legal_move(next, piece_data, castling, en_passant.0) {
        if checked {
            let winner = next.opposite();
            state.0 = GameOver::Checkmate(winner);
            println!("Checkmate! {:?} wins!", winner);
        } else {
            state.0 = GameOver::Stalemate;
            println!("Stalemate!");
        }
    } else if checked {
        println!("{:?} is in check!", next);
    }
}

fn handle_move(
    mut pending: ResMut<PendingAction>,
    mut pieces: Query<(Entity, &mut Piece, &mut Transform)>,
    mut commands: Commands,
    mut selected: ResMut<SelectedPiece>,
    mut legal: ResMut<LegalMoves>,
    mut turn: ResMut<Turn>,
    mut in_check: ResMut<InCheck>,
    mut state: ResMut<GameState>,
    mut castling: ResMut<CastlingRights>,
    mut en_passant: ResMut<EnPassantTarget>,
    mut promotion: ResMut<PendingPromotion>,
) {
    if promotion.0.is_some() {
        return;
    }

    let action = std::mem::take(&mut pending.0);

    if state.0 != GameOver::Playing {
        return;
    }

    match action {
        MoveAction::Select(piece_entity) => {
            selected.entity = Some(piece_entity);
            let piece_data: Vec<(Entity, PieceColor, PieceType, u8, u8)> = pieces
                .iter()
                .map(|(e, p, _)| (e, p.color, p.piece_type, p.x, p.y))
                .collect();
            legal.0 = legal_moves(piece_entity, &piece_data, &*castling, en_passant.0);
        }
        MoveAction::Move {
            piece,
            target_x,
            target_y,
        } => {
            if !legal.0.contains(&(target_x, target_y)) {
                legal.0.clear();
                selected.entity = None;
                return;
            }

            let (from_x, from_y, piece_type, piece_color) = pieces
                .get(piece)
                .map(|(_, p, _)| (p.x, p.y, p.piece_type, p.color))
                .unwrap_or_default();

            let mut captured_entity: Option<Entity> = None;

            if piece_type == PieceType::King {
                let home = match piece_color {
                    PieceColor::White => 0,
                    PieceColor::Black => 7,
                };
                if from_x == home && from_y == 4 {
                    if target_y == 6 {
                        move_rook(&mut pieces, piece_color, home, 7, home, 5);
                    } else if target_y == 2 {
                        move_rook(&mut pieces, piece_color, home, 0, home, 3);
                    }
                }
            }

            if piece_type == PieceType::Pawn && en_passant.0 == Some((target_x, target_y)) {
                let forward: i8 = match piece_color {
                    PieceColor::White => 1,
                    PieceColor::Black => -1,
                };
                let cap_x = (target_x as i8 - forward) as u8;
                for (e, p, _) in pieces.iter() {
                    if e != piece && p.x == cap_x && p.y == target_y {
                        captured_entity = Some(e);
                        break;
                    }
                }
            }

            if let Ok((_, mut piece_comp, mut transform)) = pieces.get_mut(piece) {
                piece_comp.x = target_x;
                piece_comp.y = target_y;
                transform.translation = Vec3::new(target_x as f32, 0.0, target_y as f32);
            }

            for (e, p, _) in pieces.iter() {
                if e == piece {
                    continue;
                }
                if p.x == target_x && p.y == target_y {
                    commands.entity(e).despawn();
                    castling.revoke_rook(p.color, p.x, p.y);
                }
            }
            if let Some(cap) = captured_entity {
                commands.entity(cap).despawn();
                castling.revoke_rook(piece_color.opposite(), 0, 0);
            }

            castling.revoke_king(piece_color);
            castling.revoke_rook(piece_color, from_x, from_y);

            if piece_type == PieceType::Pawn && from_x.abs_diff(target_x) == 2 {
                let ep_y = (from_x + target_x) / 2;
                en_passant.0 = Some((ep_y, from_y));
            } else {
                en_passant.0 = None;
            }

            if piece_type == PieceType::Pawn && target_x == match piece_color {
                PieceColor::White => 7,
                PieceColor::Black => 0,
            } {
                promotion.0 = Some(piece);
                selected.entity = None;
                legal.0.clear();
                println!("Pawn promotion! Press Q / R / B / N to choose piece");
                return;
            }

            let piece_data: Vec<(Entity, PieceColor, PieceType, u8, u8)> = pieces
                .iter()
                .map(|(e, p, _)| (e, p.color, p.piece_type, p.x, p.y))
                .collect();
            selected.entity = None;
            legal.0.clear();
            finish_turn(&mut turn, &mut in_check, &mut state, &*castling, &en_passant, &piece_data);
        }
        MoveAction::Deselect => {
            selected.entity = None;
            legal.0.clear();
        }
        MoveAction::None => {}
    }
}

fn move_rook(
    pieces: &mut Query<(Entity, &mut Piece, &mut Transform)>,
    color: PieceColor,
    from_x: u8,
    from_y: u8,
    to_x: u8,
    to_y: u8,
) {
    for (_, mut p, mut t) in pieces.iter_mut() {
        if p.piece_type == PieceType::Rook && p.color == color && p.x == from_x && p.y == from_y {
            p.x = to_x;
            p.y = to_y;
            t.translation = Vec3::new(to_x as f32, 0.0, to_y as f32);
            break;
        }
    }
}

fn read_promotion_keyboard(
    mut promotion: ResMut<PendingPromotion>,
    pieces: Query<(Entity, &mut Piece, &mut Transform)>,
    mut commands: Commands,
    mut turn: ResMut<Turn>,
    mut in_check: ResMut<InCheck>,
    mut state: ResMut<GameState>,
    castling: Res<CastlingRights>,
    en_passant: Res<EnPassantTarget>,
    keys: Res<ButtonInput<KeyCode>>,
    asset_server: Res<AssetServer>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    let Some(piece_entity) = promotion.0 else { return };

    let chosen = if keys.just_pressed(KeyCode::KeyQ) {
        Some(PieceType::Queen)
    } else if keys.just_pressed(KeyCode::KeyR) {
        Some(PieceType::Rook)
    } else if keys.just_pressed(KeyCode::KeyB) {
        Some(PieceType::Bishop)
    } else if keys.just_pressed(KeyCode::KeyN) {
        Some(PieceType::Knight)
    } else {
        None
    };

    if let Some(chosen_type) = chosen {
        let piece_data: Vec<(Entity, PieceColor, PieceType, u8, u8)> = pieces
            .iter()
            .map(|(e, p, _)| (e, p.color, p.piece_type, p.x, p.y))
            .collect();

        let (pawn_color, pawn_x, pawn_y) = piece_data
            .iter()
            .find(|(e, _, _, _, _)| *e == piece_entity)
            .map(|(_, c, _, x, y)| (*c, *x, *y))
            .unwrap();

        commands.entity(piece_entity).despawn();
        spawn_piece(&mut commands, &asset_server, &mut materials, chosen_type, pawn_color, (pawn_x, pawn_y));
        promotion.0 = None;
        println!("Promoted to {:?}", chosen_type);

        let new_piece_data: Vec<(Entity, PieceColor, PieceType, u8, u8)> = piece_data
            .into_iter()
            .map(|(e, c, t, x, y)| if e == piece_entity {
                (e, pawn_color, chosen_type, pawn_x, pawn_y)
            } else {
                (e, c, t, x, y)
            })
            .collect();

        finish_turn(&mut turn, &mut in_check, &mut state, &*castling, &en_passant, &new_piece_data);
    }
}

fn color_squares(
    pickable_query: Query<(
        Entity,
        &Square,
        &MeshMaterial3d<StandardMaterial>,
        Option<&PickingInteraction>,
    )>,
    selected: Res<SelectedPiece>,
    legal: Res<LegalMoves>,
    pieces: Query<&Piece>,
    in_check: Res<InCheck>,
    turn: Res<Turn>,
    state: Res<GameState>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    for (_entity, square, material_handle, picking) in pickable_query.iter() {
        if let Some(material) = materials.get_mut(material_handle.id()) {
            let is_selected = selected
                .entity
                .and_then(|e| pieces.get(e).ok())
                .is_some_and(|p| p.x == square.x && p.y == square.y);

            let is_king_in_check = state.0 == GameOver::Playing
                && in_check.0
                && pieces.iter().any(|p| {
                    p.piece_type == PieceType::King
                        && p.color == turn.0
                        && p.x == square.x
                        && p.y == square.y
                });

            if is_selected {
                material.base_color = Color::srgb(0.9, 0.1, 0.1);
            } else if legal.0.contains(&(square.x, square.y)) {
                material.base_color = Color::srgb(0.2, 0.8, 0.2);
            } else if is_king_in_check {
                material.base_color = Color::srgb(0.9, 0.6, 0.0);
            } else if matches!(picking, Some(PickingInteraction::Hovered)) {
                material.base_color = Color::srgb(0.8, 0.9, 0.9);
            } else if square.is_white() {
                material.base_color = Color::srgb(1.0, 0.9, 0.9);
            } else {
                material.base_color = Color::srgb(0.0, 0.1, 0.1);
            }
        }
    }
}

pub struct BoardPlugin;

impl Plugin for BoardPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<SelectedPiece>()
            .init_resource::<Turn>()
            .init_resource::<LegalMoves>()
            .init_resource::<InCheck>()
            .init_resource::<EnPassantTarget>()
            .init_resource::<GameState>()
            .init_resource::<CastlingRights>()
            .init_resource::<PendingPromotion>()
            .insert_resource(PendingAction(MoveAction::None))
            .add_systems(Startup, create_board)
            .add_systems(
                Update,
                (handle_move, read_promotion_keyboard, color_squares),
            );
    }
}
