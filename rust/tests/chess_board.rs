//! Board behaviour checks through the public API.
//!
//! FEN vectors double as cross-oracle pins: they must agree with both
//! the GDScript prototype and shakmaty.

use chess_relay_core::chess_core::Board;

#[test]
fn startpos_matches_the_standard_string() {
    let board = Board::startpos();
    assert_eq!(
        board.to_fen(),
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    );
}

#[test]
fn famous_positions_round_trip() {
    for fen in [
        "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
        "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
        "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
        "rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2",
    ] {
        let board: Board = fen.parse().unwrap();
        assert_eq!(board.to_string(), fen);
    }
}

#[test]
fn garbage_never_panics_and_never_parses() {
    for bad in [
        "",
        "not a fen",
        "8/8/8/8/8/8/8/8 w - - 0 1", // kingless
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq e9 0 1",
    ] {
        assert!(bad.parse::<Board>().is_err(), "{bad:?}");
    }
}
