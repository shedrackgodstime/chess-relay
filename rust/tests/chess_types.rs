//! Public-API behaviour checks for chess value types.
//!
//! Exercises only the exported surface (`Square`, `Move`, `Role` …),
//! mirroring how session and bridge code will consume this layer.

use chess_relay_core::chess_core::{IllegalMove, Move, Role, Square};

#[test]
fn every_square_parses_and_renders() {
    for rank in 1..=8u8 {
        for file in b'a'..=b'h' {
            let name = format!("{}{}", file as char, rank);
            let sq: Square = name.parse().unwrap();
            assert_eq!(sq.to_string(), name);
            assert_eq!(sq, Square::from_xy(file - b'a', rank - 1).unwrap());
        }
    }
}

#[test]
fn sample_game_opens_parse() {
    for uci in ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5"] {
        let mv: Move = uci.parse().unwrap();
        assert_eq!(mv.to_string(), uci);
        assert!(!mv.is_promotion());
    }
}

#[test]
fn all_promotion_targets_parse() {
    for (letter, role) in [
        ('q', Role::Queen),
        ('r', Role::Rook),
        ('b', Role::Bishop),
        ('n', Role::Knight),
    ] {
        let mv: Move = format!("a7a8{letter}").parse().unwrap();
        assert_eq!(mv.promotion, Some(role));
    }
}

#[test]
fn failures_report_their_kind() {
    let err: IllegalMove = "e4e4".parse::<Move>().unwrap_err();
    assert!(err.is_same_square());
    assert!(!err.is_parse());

    let err = Square::try_new(200).unwrap_err();
    assert!(err.is_out_of_range());

    let _: IllegalMove = "nope".parse::<Square>().unwrap_err();
}
