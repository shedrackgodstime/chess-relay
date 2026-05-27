mod board;
mod controller;
mod hud;
mod input;
mod pieces;

use bevy::prelude::*;

use crate::chess;
use crate::screens::Screen;
use board::*;
use controller::*;
use hud::{handle_promotion_buttons, *};
use input::ai::{AiInput, ai_input_system};
use input::local::local_input_system;
use input::network::{NetworkInput, network_input_system};
use input::*;
use pieces::*;

/// Wrapper to make the pure chess GameState a Bevy Resource.
#[derive(Resource)]
pub struct CurrentGame(pub chess::GameState);

/// Marker for entities owned by the active game screen.
#[derive(Component)]
pub struct GameEntity;

/// Tells the Game screen how to set up.
#[derive(Resource, Clone)]
pub struct GameConfig {
    pub input_mode: GameInput,
    pub ai_color: Option<chess::PieceColor>,
}

impl Default for GameConfig {
    fn default() -> Self {
        GameConfig {
            input_mode: GameInput::Local,
            ai_color: None,
        }
    }
}

pub struct GamePlugin;

impl Plugin for GamePlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<PendingMoves>()
            .init_resource::<PendingSquareClick>()
            .init_resource::<PendingPromotion>()
            .init_resource::<LocalSelection>()
            .init_resource::<CheckWarning>()
            .add_systems(OnEnter(Screen::Game), setup_game)
            .add_systems(OnExit(Screen::Game), teardown_game)
            .add_systems(
                Update,
                (
                    local_input_system,
                    ai_input_system,
                    network_input_system,
                    handle_promotion_buttons,
                    controller_system,
                    sync_piece_entities,
                    update_hud,
                )
                    .chain()
                    .run_if(in_state(Screen::Game)),
            );
    }
}

fn setup_game(
    mut commands: Commands,
    meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    assets: Res<AssetServer>,
    config: Option<Res<GameConfig>>,
) {
    let config = config.map(|c| c.clone()).unwrap_or_default();
    let piece_assets = PieceVisualAssets::load(assets.as_ref(), &mut materials);

    // Core game state
    commands.insert_resource(CurrentGame(chess::GameState::new()));
    commands.insert_resource(piece_assets.clone());

    // Input strategy tag
    commands.insert_resource(config.input_mode.clone());

    // Input variant resources
    match &config.input_mode {
        GameInput::Ai => {
            let color = config.ai_color.unwrap_or(chess::PieceColor::Black);
            commands.insert_resource(AiInput::new(color));
        }
        GameInput::Network => {
            commands.insert_resource(NetworkInput);
        }
        GameInput::Local => {}
    }

    // 3D board
    spawn_board(commands.reborrow(), meshes, materials);

    // 3D pieces
    let board = chess::Board::new();
    spawn_pieces(commands.reborrow(), &piece_assets, &board);

    // HUD
    spawn_hud(commands);
}

fn teardown_game(mut commands: Commands, game_entities: Query<Entity, With<GameEntity>>) {
    for entity in game_entities.iter() {
        commands.entity(entity).despawn();
    }

    commands.remove_resource::<CurrentGame>();
    commands.remove_resource::<GameInput>();
    commands.remove_resource::<GameConfig>();
    commands.remove_resource::<AiInput>();
    commands.remove_resource::<NetworkInput>();
    commands.remove_resource::<LocalSelection>();
    commands.remove_resource::<CheckWarning>();
    commands.remove_resource::<PendingMoves>();
    commands.remove_resource::<PendingSquareClick>();
    commands.remove_resource::<PendingPromotion>();
    commands.remove_resource::<PieceVisualAssets>();
}

fn sync_piece_entities(
    mut commands: Commands,
    current_game: Option<Res<CurrentGame>>,
    piece_assets: Option<Res<PieceVisualAssets>>,
    existing_pieces: Query<Entity, With<PieceEntity>>,
) {
    let Some(current_game) = current_game else {
        return;
    };
    let Some(piece_assets) = piece_assets else {
        return;
    };
    if !current_game.is_changed() {
        return;
    }

    for entity in existing_pieces.iter() {
        commands.entity(entity).despawn();
    }

    spawn_pieces(commands, piece_assets.as_ref(), &current_game.0.board);
}
