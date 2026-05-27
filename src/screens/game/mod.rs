//! Game screen plugin, board interaction, and local match state orchestration.

mod board;
mod hud;
mod pieces;

use bevy::camera::primitives::{Aabb, MeshAabb};
use bevy::math::Affine3A;
use bevy::prelude::*;

use crate::chess::{ChessMove, GameState, GameStatus, PieceColor, PieceType};
use crate::screens::Screen;
use board::{BOARD_HALF_SPAN, BoardSquare, SquareMaterialSet};

pub(super) struct GamePlugin;

/// Match-opponent category used by the game HUD and future match setup flows.
#[derive(Clone, Copy, PartialEq, Eq)]
pub(crate) enum OpponentKind {
    Online,
    SameDevice,
    Computer,
}

/// Pending match presentation details passed into the game screen on entry.
#[derive(Resource, Clone)]
pub(crate) struct PendingMatchPresentation {
    /// The opponent badge model used for HUD rendering.
    pub opponent: OpponentBadgeModel,
}

/// Lightweight opponent identity used by the top-right match badge.
#[derive(Clone)]
pub(crate) struct OpponentBadgeModel {
    /// The display name shown in the opponent badge.
    pub display_name: String,
    /// The category of opponent (Online / SameDevice / Computer).
    pub kind: OpponentKind,
    /// Whether the opponent is currently connected (online only).
    pub online: bool,
}

impl PendingMatchPresentation {
    /// Creates a presentation for a local same-device match.
    pub(crate) fn same_device(display_name: impl Into<String>) -> Self {
        Self {
            opponent: OpponentBadgeModel {
                display_name: display_name.into(),
                kind: OpponentKind::SameDevice,
                online: false,
            },
        }
    }

    /// Creates a presentation for a computer match.
    pub(crate) fn computer(display_name: impl Into<String>) -> Self {
        Self {
            opponent: OpponentBadgeModel {
                display_name: display_name.into(),
                kind: OpponentKind::Computer,
                online: false,
            },
        }
    }

    /// Creates a presentation for an online match.
    pub(crate) fn online(display_name: impl Into<String>, online: bool) -> Self {
        Self {
            opponent: OpponentBadgeModel {
                display_name: display_name.into(),
                kind: OpponentKind::Online,
                online,
            },
        }
    }
}

impl Default for PendingMatchPresentation {
    fn default() -> Self {
        Self::computer("Anton Bot")
    }
}

/// Wraps the active chess game state as a Bevy resource.
#[derive(Resource, Default)]
pub(crate) struct CurrentGame(pub GameState);

/// Marker component for entities belonging to the game screen.
#[derive(Component)]
pub(crate) struct GameScreenEntity;

/// Marker component for the root transform of the 3D game scene.
#[derive(Component)]
pub(crate) struct GameSceneRoot;

#[derive(Component)]
pub(crate) struct PieceEntity {
    pub file: u8,
    pub rank: u8,
}

#[derive(Resource, Default)]
struct SelectedSquare(Option<(u8, u8)>);

#[derive(Resource, Default)]
struct HighlightedSquares(Vec<HighlightedSquare>);

#[derive(Clone, Copy, PartialEq, Eq)]
struct HighlightedSquare {
    file: u8,
    rank: u8,
    kind: HighlightKind,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum HighlightKind {
    Move,
    Capture,
}

/// Holds a board-square click pending processing in the next system tick.
#[derive(Resource, Default)]
pub(crate) struct PendingSquareClick(Option<(u8, u8)>);

/// Holds pending promotion choices while the pawn-promotion overlay is open.
#[derive(Resource, Default)]
pub(crate) struct PendingPromotion(Option<PromotionChoices>);

/// The set of legal promotion moves for the currently promoting pawn.
#[derive(Clone)]
pub(crate) struct PromotionChoices {
    pub moves: Vec<ChessMove>,
}

/// Tracks ray-casting resolution messages for debugging click handling.
#[derive(Resource, Default)]
pub(crate) struct ClickDiagnostics {
    pub last_resolution: String,
}

pub(crate) const ROTATION_STEP_RADIANS: f32 = std::f32::consts::FRAC_PI_8;

/// Holds the terminal game status once the game reaches a decisive end.
#[derive(Resource, Default)]
pub(crate) struct GameOverData(pub Option<GameStatus>);

/// Marker for the "Rematch" button in the game-over overlay.
#[derive(Component)]
pub(crate) struct RematchButton;

/// Marker for the game-over overlay root entity.
#[derive(Component)]
pub(crate) struct GameOverOverlay;

/// Persistent opponent configuration for the current match.
#[derive(Resource)]
pub(crate) struct MatchConfig {
    pub opponent: OpponentKind,
}

/// AI turn state machine: 0=idle, 1=scheduled, 2=think, 3=execute.
#[derive(Resource)]
struct AiState {
    phase: u8,
    timer: f32,
}

impl Default for AiState {
    fn default() -> Self {
        Self {
            phase: 0,
            timer: 0.0,
        }
    }
}

/// How long the AI waits before making a move, simulating "thinking time".
const AI_DELAY_SECONDS: f32 = 1.5;

impl Plugin for GamePlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<SelectedSquare>()
            .init_resource::<HighlightedSquares>()
            .init_resource::<PendingSquareClick>()
            .init_resource::<PendingPromotion>()
            .init_resource::<ClickDiagnostics>()
            .init_resource::<GameOverData>()
            .init_resource::<hud::HudIcons>()
            .init_resource::<AiState>()
            .add_systems(OnEnter(Screen::Game), setup_game)
            .add_systems(OnExit(Screen::Game), teardown_game)
            .add_systems(
                Update,
                (
                    capture_board_square_click,
                    process_square_clicks,
                    detect_game_over,
                    schedule_ai_turn,
                    execute_ai_turn,
                    sync_piece_entities,
                    hud::update_captured_display,
                    hud::update_turn_indicator,
                    update_square_materials,
                    hud::sync_promotion_overlay,
                    hud::sync_game_over_overlay,
                    hud::handle_navigation_action,
                    hud::handle_rotation_actions,
                    hud::handle_promotion_actions,
                    hud::handle_game_over_actions,
                    rotate_game_scene,
                )
                    .chain()
                    .run_if(in_state(Screen::Game)),
            );
    }
}

fn setup_game(
    mut commands: Commands,
    asset_server: Res<AssetServer>,
    icons: Res<hud::HudIcons>,
    pending_match: Option<Res<PendingMatchPresentation>>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    let game_state = GameState::new();
    let scene_root = commands
        .spawn((
            Transform::default(),
            Visibility::default(),
            GameSceneRoot,
            GameScreenEntity,
        ))
        .id();

    commands.insert_resource(CurrentGame(game_state.clone()));
    commands.insert_resource(SelectedSquare::default());
    commands.insert_resource(HighlightedSquares::default());
    commands.insert_resource(PendingSquareClick::default());
    commands.insert_resource(PendingPromotion::default());
    commands.insert_resource(ClickDiagnostics {
        last_resolution: "Awaiting input".to_string(),
    });
    commands.insert_resource(AiState::default());
    commands.entity(scene_root).with_children(|parent| {
        board::spawn_board(parent, &mut meshes, &mut materials);
        pieces::spawn_pieces(
            parent,
            asset_server.as_ref(),
            &mut materials,
            &game_state.board,
        );
    });
    let match_presentation = pending_match.as_deref().cloned().unwrap_or_default();
    commands.insert_resource(MatchConfig {
        opponent: match_presentation.opponent.kind,
    });
    hud::spawn_hud(&mut commands, icons.as_ref(), &match_presentation.opponent);
}

fn teardown_game(mut commands: Commands, entities: Query<Entity, With<GameScreenEntity>>) {
    for entity in entities.iter() {
        commands
            .entity(entity)
            .despawn_related::<Children>()
            .despawn();
    }

    commands.remove_resource::<CurrentGame>();
    commands.remove_resource::<SelectedSquare>();
    commands.remove_resource::<HighlightedSquares>();
    commands.remove_resource::<PendingSquareClick>();
    commands.remove_resource::<PendingPromotion>();
    commands.remove_resource::<ClickDiagnostics>();
    commands.remove_resource::<MatchConfig>();
    commands.remove_resource::<AiState>();
}

fn rotate_game_scene(
    keys: Res<ButtonInput<KeyCode>>,
    time: Res<Time>,
    mut roots: Query<&mut Transform, With<GameSceneRoot>>,
) {
    let Ok(mut transform) = roots.single_mut() else {
        return;
    };

    let mut rotation_delta = 0.0;
    if keys.pressed(KeyCode::KeyQ) || keys.pressed(KeyCode::ArrowLeft) {
        rotation_delta += 1.3 * time.delta_secs();
    }
    if keys.pressed(KeyCode::KeyE) || keys.pressed(KeyCode::ArrowRight) {
        rotation_delta -= 1.3 * time.delta_secs();
    }

    if rotation_delta != 0.0 {
        transform.rotate_y(rotation_delta);
    }
}

fn detect_game_over(current_game: Res<CurrentGame>, mut game_over: ResMut<GameOverData>) {
    if !current_game.is_changed() {
        return;
    }
    let status = current_game.0.status();
    match status {
        GameStatus::Checkmate { .. }
        | GameStatus::Stalemate
        | GameStatus::FiftyMoveDraw
        | GameStatus::ThreefoldRepetitionDraw
        | GameStatus::InsufficientMaterialDraw => {
            game_over.0 = Some(status);
        }
        _ => {}
    }
}

fn schedule_ai_turn(
    match_config: Res<MatchConfig>,
    current_game: Res<CurrentGame>,
    game_over: Res<GameOverData>,
    mut ai_state: ResMut<AiState>,
) {
    if ai_state.phase != 0 {
        return;
    }
    if match_config.opponent != OpponentKind::Computer {
        return;
    }
    if game_over.0.is_some() {
        return;
    }
    if current_game.0.turn != PieceColor::Black {
        return;
    }

    ai_state.phase = 1;
}

fn execute_ai_turn(
    current_game: Res<CurrentGame>,
    mut ai_state: ResMut<AiState>,
    time: Res<Time>,
    mut commands: Commands,
) {
    match ai_state.phase {
        1 => {
            ai_state.timer = 0.0;
            ai_state.phase = 2;
        }
        2 => {
            ai_state.timer += time.delta_secs();
            if ai_state.timer < AI_DELAY_SECONDS {
                return;
            }
            ai_state.phase = 3;
        }
        3 => {
            let best_move = crate::chess::ai::find_best_move(&current_game.0);
            if let Some(chess_move) = best_move {
                let mut next = current_game.0.clone();
                next.apply_move(&chess_move);
                commands.insert_resource(CurrentGame(next));
            }
            ai_state.phase = 0;
        }
        _ => {}
    }
}

#[allow(clippy::too_many_arguments)]
fn capture_board_square_click(
    buttons: Res<ButtonInput<MouseButton>>,
    touches: Res<Touches>,
    game_over: Res<GameOverData>,
    windows: Query<&Window>,
    cameras: Query<(&Camera, &GlobalTransform), With<crate::app::MainCamera3d>>,
    board_root: Query<&GlobalTransform, With<GameSceneRoot>>,
    piece_roots: Query<(&PieceEntity, &GlobalTransform, &Children)>,
    piece_meshes: Query<(&Transform, &Mesh3d, Option<&Aabb>)>,
    meshes: Res<Assets<Mesh>>,
    selected_square: Res<SelectedSquare>,
    highlighted_squares: Res<HighlightedSquares>,
    pending_promotion: Res<PendingPromotion>,
    mut click_diagnostics: ResMut<ClickDiagnostics>,
    mut pending_click: ResMut<PendingSquareClick>,
) {
    let screen_position = if buttons.just_pressed(MouseButton::Left) {
        None
    } else if let Some(touch) = touches.iter_just_pressed().next() {
        Some(touch.position())
    } else {
        return;
    };
    if game_over.0.is_some() {
        return;
    }
    if pending_promotion.0.is_some() {
        click_diagnostics.last_resolution = "Promotion pending: board input blocked".to_string();
        return;
    }
    if pending_click.0.is_some() {
        click_diagnostics.last_resolution = "Input busy: previous click still pending".to_string();
        return;
    }

    let Ok(window) = windows.single() else {
        click_diagnostics.last_resolution = "Input failed: no window".to_string();
        return;
    };
    let input_position = screen_position.or_else(|| window.cursor_position());
    let Some(input_position) = input_position else {
        click_diagnostics.last_resolution = "Input failed: no input position".to_string();
        return;
    };
    let Ok((camera, camera_transform)) = cameras.single() else {
        click_diagnostics.last_resolution = "Input failed: main camera missing".to_string();
        return;
    };
    let Ok(board_transform) = board_root.single() else {
        click_diagnostics.last_resolution = "Input failed: board root missing".to_string();
        return;
    };

    let Ok(ray) = camera.viewport_to_world(camera_transform, input_position) else {
        click_diagnostics.last_resolution =
            "Input failed: could not project cursor ray".to_string();
        return;
    };
    let ray_direction = *ray.direction;

    let board_square = resolve_board_square_from_ray(ray.origin, ray_direction, board_transform);
    if let Some(square) = board_square
        && (selected_square.0 == Some(square)
            || highlighted_squares
                .0
                .iter()
                .any(|highlight| (highlight.file, highlight.rank) == square))
    {
        pending_click.0 = Some(square);
        click_diagnostics.last_resolution = format!(
            "Resolved legal board square {}",
            square_name(square.0, square.1)
        );
        return;
    }

    let mut best_piece_hit: Option<((u8, u8), f32)> = None;
    for (piece, transform, children) in piece_roots.iter() {
        let mut combined_min = Vec3::splat(f32::INFINITY);
        let mut combined_max = Vec3::splat(f32::NEG_INFINITY);
        let mut found_bounds = false;

        for child in children.iter() {
            let Ok((child_transform, mesh_handle, aabb)) = piece_meshes.get(child) else {
                continue;
            };

            let local_aabb = aabb
                .copied()
                .or_else(|| meshes.get(mesh_handle).and_then(MeshAabb::compute_aabb));
            let Some(local_aabb) = local_aabb else {
                continue;
            };

            let (child_min, child_max) =
                transformed_aabb_min_max(&child_transform.compute_affine(), local_aabb);
            combined_min = combined_min.min(child_min);
            combined_max = combined_max.max(child_max);
            found_bounds = true;
        }

        if !found_bounds {
            continue;
        }

        let inverse_piece = transform.affine().inverse();
        let local_origin = inverse_piece.transform_point3(ray.origin);
        let local_direction = inverse_piece.transform_vector3(ray_direction);

        let Some(distance) =
            ray_aabb_hit_distance(local_origin, local_direction, combined_min, combined_max)
        else {
            continue;
        };

        match best_piece_hit {
            Some((_, best_distance)) if distance >= best_distance => {}
            _ => {
                best_piece_hit = Some(((piece.file, piece.rank), distance));
            }
        }
    }

    if let Some(((file, rank), _)) = best_piece_hit {
        pending_click.0 = Some((file, rank));
        click_diagnostics.last_resolution =
            format!("Resolved piece body {}", square_name(file, rank));
        return;
    }

    pending_click.0 = board_square;
    click_diagnostics.last_resolution = match board_square {
        Some((file, rank)) => format!("Resolved board square {}", square_name(file, rank)),
        None => "Click missed board and pieces".to_string(),
    };
}

fn resolve_board_square_from_ray(
    ray_origin: Vec3,
    ray_direction: Vec3,
    board_transform: &GlobalTransform,
) -> Option<(u8, u8)> {
    let inverse_board = board_transform.affine().inverse();
    let local_origin = inverse_board.transform_point3(ray_origin);
    let local_direction = inverse_board.transform_vector3(ray_direction);

    if local_direction.y.abs() < f32::EPSILON {
        return None;
    }

    let distance_to_plane = -local_origin.y / local_direction.y;
    if distance_to_plane < 0.0 {
        return None;
    }

    let local_hit = local_origin + local_direction * distance_to_plane;
    if local_hit.x < -BOARD_HALF_SPAN
        || local_hit.x >= BOARD_HALF_SPAN
        || local_hit.z < -BOARD_HALF_SPAN
        || local_hit.z >= BOARD_HALF_SPAN
    {
        return None;
    }

    Some((
        (local_hit.x + BOARD_HALF_SPAN).floor() as u8,
        (local_hit.z + BOARD_HALF_SPAN).floor() as u8,
    ))
}

fn square_name(file: u8, rank: u8) -> String {
    let file_char = char::from(b'a' + file);
    let rank_char = char::from(b'1' + rank);
    format!("{file_char}{rank_char}")
}

fn transformed_aabb_min_max(transform: &Affine3A, aabb: Aabb) -> (Vec3, Vec3) {
    let min = aabb.min();
    let max = aabb.max();
    let corners = [
        Vec3::new(min.x, min.y, min.z),
        Vec3::new(min.x, min.y, max.z),
        Vec3::new(min.x, max.y, min.z),
        Vec3::new(min.x, max.y, max.z),
        Vec3::new(max.x, min.y, min.z),
        Vec3::new(max.x, min.y, max.z),
        Vec3::new(max.x, max.y, min.z),
        Vec3::new(max.x, max.y, max.z),
    ];

    let mut transformed_min = Vec3::splat(f32::INFINITY);
    let mut transformed_max = Vec3::splat(f32::NEG_INFINITY);
    for corner in corners {
        let transformed = transform.transform_point3(corner);
        transformed_min = transformed_min.min(transformed);
        transformed_max = transformed_max.max(transformed);
    }

    (transformed_min, transformed_max)
}

fn ray_aabb_hit_distance(origin: Vec3, direction: Vec3, min: Vec3, max: Vec3) -> Option<f32> {
    let mut t_min: f32 = 0.0;
    let mut t_max = f32::INFINITY;

    for axis in 0..3 {
        let origin_component = origin[axis];
        let direction_component = direction[axis];
        let min_component = min[axis];
        let max_component = max[axis];

        if direction_component.abs() < f32::EPSILON {
            if origin_component < min_component || origin_component > max_component {
                return None;
            }
            continue;
        }

        let inv_direction = 1.0 / direction_component;
        let mut t1 = (min_component - origin_component) * inv_direction;
        let mut t2 = (max_component - origin_component) * inv_direction;
        if t1 > t2 {
            std::mem::swap(&mut t1, &mut t2);
        }

        t_min = t_min.max(t1);
        t_max = t_max.min(t2);
        if t_min > t_max {
            return None;
        }
    }

    if t_max < 0.0 {
        None
    } else {
        Some(t_min.max(0.0))
    }
}

fn process_square_clicks(
    mut current_game: ResMut<CurrentGame>,
    mut selected_square: ResMut<SelectedSquare>,
    mut highlighted_squares: ResMut<HighlightedSquares>,
    mut pending_promotion: ResMut<PendingPromotion>,
    mut pending_click: ResMut<PendingSquareClick>,
    game_over: Res<GameOverData>,
) {
    if game_over.0.is_some() {
        pending_click.0 = None;
        return;
    }
    if pending_promotion.0.is_some() {
        pending_click.0 = None;
        return;
    }

    let Some((file, rank)) = pending_click.0.take() else {
        return;
    };

    let clicked_piece = current_game.0.board.get(file, rank);

    if let Some((selected_file, selected_rank)) = selected_square.0 {
        if (selected_file, selected_rank) == (file, rank) {
            selected_square.0 = None;
            highlighted_squares.0.clear();
            return;
        }

        let legal_moves = current_game.0.legal_moves_for(selected_file, selected_rank);
        let matching_moves: Vec<ChessMove> = legal_moves
            .iter()
            .copied()
            .filter(|chess_move| chess_move.to_file == file && chess_move.to_rank == rank)
            .collect();

        if !matching_moves.is_empty() {
            if matching_moves
                .iter()
                .any(|chess_move| chess_move.promotion.is_some())
            {
                pending_promotion.0 = Some(PromotionChoices {
                    moves: matching_moves,
                });
            } else {
                current_game.0.apply_move(&matching_moves[0]);
                selected_square.0 = None;
                highlighted_squares.0.clear();
            }
            return;
        }

        if let Some(piece) = clicked_piece
            && piece.color == current_game.0.turn
        {
            selected_square.0 = Some((file, rank));
            highlighted_squares.0 = build_highlights(&current_game.0, file, rank);
            return;
        }

        selected_square.0 = None;
        highlighted_squares.0.clear();
        return;
    }

    if let Some(piece) = clicked_piece
        && piece.color == current_game.0.turn
    {
        selected_square.0 = Some((file, rank));
        highlighted_squares.0 = build_highlights(&current_game.0, file, rank);
    }
}

fn update_square_materials(
    current_game: Res<CurrentGame>,
    selected_square: Res<SelectedSquare>,
    highlighted_squares: Res<HighlightedSquares>,
    mut squares: Query<(
        &BoardSquare,
        &SquareMaterialSet,
        &mut MeshMaterial3d<StandardMaterial>,
    )>,
) {
    if !current_game.is_changed()
        && !selected_square.is_changed()
        && !highlighted_squares.is_changed()
    {
        return;
    }

    let last_move_squares = current_game.0.last_move.map(|chess_move| {
        [
            (chess_move.from_file, chess_move.from_rank),
            (chess_move.to_file, chess_move.to_rank),
        ]
    });

    let checked_king_square = match current_game.0.status() {
        GameStatus::Check(color) => current_game.0.board.find_king(color),
        GameStatus::Checkmate { winner } => current_game.0.board.find_king(winner.opponent()),
        GameStatus::InProgress
        | GameStatus::Stalemate
        | GameStatus::FiftyMoveDraw
        | GameStatus::ThreefoldRepetitionDraw
        | GameStatus::InsufficientMaterialDraw => None,
    };

    for (square, materials, mut material) in squares.iter_mut() {
        if selected_square.0 == Some((square.file, square.rank)) {
            material.0 = materials.selected.clone();
        } else if let Some(highlight) = highlighted_squares
            .0
            .iter()
            .find(|highlight| highlight.file == square.file && highlight.rank == square.rank)
        {
            material.0 = match highlight.kind {
                HighlightKind::Move => materials.legal.clone(),
                HighlightKind::Capture => materials.capture.clone(),
            };
        } else if checked_king_square == Some((square.file, square.rank)) {
            material.0 = materials.check.clone();
        } else if last_move_squares
            .is_some_and(|squares_for_move| squares_for_move.contains(&(square.file, square.rank)))
        {
            material.0 = materials.last_move.clone();
        } else {
            material.0 = materials.idle.clone();
        }
    }
}

fn build_highlights(current_game: &GameState, file: u8, rank: u8) -> Vec<HighlightedSquare> {
    let Some(selected_piece) = current_game.board.get(file, rank) else {
        return vec![];
    };

    current_game
        .legal_moves_for(file, rank)
        .into_iter()
        .map(|chess_move| HighlightedSquare {
            file: chess_move.to_file,
            rank: chess_move.to_rank,
            kind: highlight_kind(current_game, selected_piece.piece_type, &chess_move),
        })
        .collect()
}

fn highlight_kind(
    current_game: &GameState,
    selected_piece_type: PieceType,
    chess_move: &ChessMove,
) -> HighlightKind {
    if current_game
        .board
        .get(chess_move.to_file, chess_move.to_rank)
        .is_some()
    {
        return HighlightKind::Capture;
    }

    let is_en_passant_capture = selected_piece_type == PieceType::Pawn
        && chess_move.from_file != chess_move.to_file
        && current_game
            .board
            .get(chess_move.to_file, chess_move.to_rank)
            .is_none()
        && current_game.en_passant == Some((chess_move.to_file, chess_move.to_rank));

    if is_en_passant_capture {
        HighlightKind::Capture
    } else {
        HighlightKind::Move
    }
}

fn sync_piece_entities(
    mut commands: Commands,
    current_game: Res<CurrentGame>,
    scene_root: Query<Entity, With<GameSceneRoot>>,
    pieces_on_board: Query<Entity, With<PieceEntity>>,
    asset_server: Res<AssetServer>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    if !current_game.is_changed() {
        return;
    }

    let Ok(scene_root) = scene_root.single() else {
        return;
    };

    for entity in pieces_on_board.iter() {
        commands
            .entity(entity)
            .despawn_related::<Children>()
            .despawn();
    }

    commands.entity(scene_root).with_children(|parent| {
        pieces::spawn_pieces(
            parent,
            asset_server.as_ref(),
            &mut materials,
            &current_game.0.board,
        );
    });
}
