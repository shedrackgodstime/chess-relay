//! Session behaviour through the public API: agreement, gaps, hostility.

use chess_relay_core::session::{
    FinishReason, LogEntry, LogPayload, PeerId, Session, SessionConfig, SessionState,
};
use ed25519_dalek::{Signer, SigningKey};

fn host_secret() -> SigningKey {
    SigningKey::from_bytes(&[1u8; 32])
}

fn guest_secret() -> SigningKey {
    SigningKey::from_bytes(&[2u8; 32])
}

fn config() -> SessionConfig {
    SessionConfig::new(
        PeerId::of(&host_secret()),
        PeerId::of(&guest_secret()),
        PeerId::of(&host_secret()),
    )
    .unwrap()
}

fn live_pair() -> (Session, SigningKey, SigningKey) {
    let host = host_secret();
    let guest = guest_secret();
    let mut session = Session::create(&host, config()).unwrap();
    session.join(&guest).unwrap();
    session.set_ready(&host).unwrap();
    session.set_ready(&guest).unwrap();
    session.start(&host).unwrap();
    (session, host, guest)
}

#[test]
fn scholars_mate_fully_agreed_verifies() {
    let (mut session, host, guest) = live_pair();
    let moves = ["e2e4", "e7e5", "d1h5", "b8c6", "f1c4", "g8f6", "h5f7"];
    for (index, uci) in moves.iter().enumerate() {
        let player = if index % 2 == 0 { &host } else { &guest };
        let other = if index % 2 == 0 { &guest } else { &host };
        let (seq, _) = session.submit_move(player, &uci.parse().unwrap()).unwrap();
        session.agree(other, seq).unwrap();
    }
    assert!(matches!(
        session.state(),
        SessionState::Finished(FinishReason::Rules(_))
    ));
    assert!(session.log().iter().all(LogEntry::is_agreed));
    session.verify().unwrap();
}

#[test]
fn lagging_peer_fills_gap_and_converges() {
    let (mut full, host, guest) = live_pair();
    for uci in ["e2e4", "e7e5", "g1f3"] {
        let player = if full.game().unwrap().board().side_to_move()
            == chess_relay_core::chess_core::Color::White
        {
            &host
        } else {
            &guest
        };
        full.submit_move(player, &uci.parse().unwrap()).unwrap();
    }

    // Lagging side knows config only; entries arrive in order.
    let mut lagging = Session::join_config(config());
    let (next, _) = lagging.tip();
    assert_eq!(next, 0);
    // Receives genesis plus the first move, then drops the connection.
    for entry in &full.entries_since(0)[..2] {
        lagging.receive(entry).unwrap();
    }
    // Tips differ; the missing tail replays from the shared log.
    assert_ne!(lagging.tip(), full.tip());
    for entry in full.entries_since(lagging.tip().0) {
        lagging.receive(entry).unwrap();
    }
    assert_eq!(lagging.tip(), full.tip());
    lagging.replay_game().unwrap();
    lagging.verify().unwrap();
    assert_eq!(
        lagging.game().unwrap().board().to_fen(),
        full.game().unwrap().board().to_fen()
    );
}

#[test]
fn forged_signature_rejected_on_receive() {
    let (mut full, _, _) = live_pair();
    full.submit_move(&host_secret(), &"e2e4".parse().unwrap())
        .unwrap();

    let mut lagging = Session::join_config(config());
    lagging.receive(&full.log()[0]).unwrap();
    let mut evil = full.log()[1];
    evil.mover_sig[0] ^= 0xff;
    let err = lagging.receive(&evil).unwrap_err();
    assert!(err.is_bad_signature());
}

#[test]
fn forged_move_passes_signature_but_fails_replay() {
    let (mut full, host, _) = live_pair();
    full.submit_move(&host, &"e2e4".parse().unwrap()).unwrap();

    // Evil peer signs a well-formed signature over an illegal move.
    let evil_move: chess_relay_core::chess_core::Move = "e2e5".parse().unwrap();
    let (next_seq, prev) = full.tip();
    let draft = LogEntry {
        seq: next_seq,
        prev_hash: prev,
        payload: LogPayload::Move { mv: evil_move },
        mover: PeerId::of(&host),
        mover_sig: [0u8; 64],
        co_sig: None,
    };
    let sig = host.sign(&draft.hash()).to_bytes();
    let forged = LogEntry {
        mover_sig: sig,
        ..draft
    };

    let mut lagging = Session::join_config(config());
    for entry in full.log().to_vec() {
        lagging.receive(&entry).unwrap();
    }
    // Chain and signature check out; the move itself does not.
    lagging.receive(&forged).unwrap();
    let err = lagging.replay_game().unwrap_err();
    assert!(err.is_log_mismatch());
    assert!(lagging.verify().unwrap_err().is_log_mismatch());
}

#[test]
fn resign_records_and_finishes() {
    let (mut session, host, guest) = live_pair();
    session
        .submit_move(&host, &"e2e4".parse().unwrap())
        .unwrap();
    session.resign(&guest).unwrap();
    assert_eq!(
        session.state(),
        SessionState::Finished(FinishReason::Resignation {
            by: PeerId::of(&guest)
        })
    );
    assert!(matches!(
        session.log().last().unwrap().payload,
        LogPayload::Resign
    ));
    session.verify().unwrap();
}
