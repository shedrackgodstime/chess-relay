//! Move-generation behaviour through the public API.
//!
//! Counts are oracle pins: startpos and kiwipete must agree with both
//! the GDScript prototype and shakmaty.

use chess_relay_core::chess_core::{Board, Color, legal_moves, perft};

#[test]
fn startpos_gives_twenty_opening_moves() {
    let board = Board::startpos();
    let moves = legal_moves(&board, Color::White);
    assert_eq!(moves.len(), 20);
    assert_eq!(perft(&board, 2), 400);
}

#[test]
fn kiwipete_counts_match() {
    let board: Board = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
        .parse()
        .unwrap();
    assert_eq!(legal_moves(&board, Color::White).len(), 48);
    assert_eq!(perft(&board, 2), 2_039);
}

#[test]
fn check_loses_moves() {
    let board: Board = "4rk2/8/8/8/8/8/5PPP/R3K2R w KQkq - 0 1".parse().unwrap();
    let moves = legal_moves(&board, Color::White);
    // King in check from the e-file rook: only evasions survive.
    assert!(!moves.is_empty());
    assert!(moves.len() < 10);
}
