pub mod ai;
pub mod local;
pub mod network;

use bevy::prelude::*;

use crate::chess::{Move, PieceType};

/// Simple queue for moves requested by any input source.
#[derive(Resource, Default)]
pub struct PendingMoves(pub Vec<Move>);

/// The next board square click captured by Bevy's picking pipeline.
#[derive(Resource, Default, Debug)]
pub struct PendingSquareClick(pub Option<(u8, u8)>);

/// Local UI state for a promotion that still needs a piece choice.
#[derive(Resource, Default, Debug)]
pub struct PendingPromotion(pub Option<PromotionRequest>);

#[derive(Clone, Debug)]
pub struct PromotionRequest {
    pub from_file: u8,
    pub from_rank: u8,
    pub to_file: u8,
    pub to_rank: u8,
    pub choices: Vec<PieceType>,
}

/// Tag enum for which input strategies are active.
#[derive(Resource, Clone, PartialEq, Eq, Debug)]
#[allow(dead_code)]
pub enum GameInput {
    /// Both players on the same screen (hot-seat).
    Local,
    /// Human vs computer.
    Ai,
    /// Online multiplayer.
    Network,
}

/// Marker for the local input selection state.
#[derive(Resource, Default, Debug)]
pub struct LocalSelection {
    pub selected_file: Option<u8>,
    pub selected_rank: Option<u8>,
}
