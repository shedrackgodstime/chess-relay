//! Full-game behaviour through the public API: mates, draws, rejection.

use chess_relay_core::chess_core::{DrawReason, Game, Outcome};

#[test]
fn fools_mate_checkmates_black() {
    let mut game = Game::from_startpos();
    for uci in ["f2f3", "e7e5", "g2g4", "d8h4"] {
        let mv = uci.parse().unwrap();
        let outcome = game.play(&mv).unwrap();
        if uci == "d8h4" {
            assert_eq!(
                outcome,
                Outcome::Checkmate {
                    winner: chess_relay_core::chess_core::Color::Black
                }
            );
        } else {
            assert_eq!(outcome, Outcome::Ongoing);
        }
    }
}

#[test]
fn knights_dance_draws_by_repetition() {
    let mut game = Game::from_startpos();
    let mut outcome = Outcome::Ongoing;
    for uci in [
        "g1f3", "g8f6", "f3g1", "f6g8", "g1f3", "g8f6", "f3g1", "f6g8",
    ] {
        outcome = game.play(&uci.parse().unwrap()).unwrap();
    }
    assert_eq!(outcome, Outcome::Draw(DrawReason::Threefold));
}

#[test]
fn bare_kings_draw_immediately() {
    let game = Game::new("4k3/8/8/8/8/8/8/4K3 w - - 0 1".parse().unwrap());
    assert_eq!(
        game.outcome(),
        Outcome::Draw(DrawReason::InsufficientMaterial)
    );
}

#[test]
fn illegal_moves_leave_no_trace() {
    let mut game = Game::from_startpos();
    let before = game.board().to_fen();
    for bad in ["e2e5", "b1b3", "e7e5"] {
        let err = game.play(&bad.parse().unwrap()).unwrap_err();
        assert!(err.is_not_legal(), "{bad}");
    }
    assert_eq!(game.board().to_fen(), before);
}
