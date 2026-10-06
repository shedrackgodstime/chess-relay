//! Contract behaviour: two views converging through frozen commands.

use chess_relay_core::app::{App, Command, Event, Query, QueryResult};
use chess_relay_core::session::{PeerId, SessionState};
use ed25519_dalek::SigningKey;

fn host_secret() -> SigningKey {
    SigningKey::from_bytes(&[1u8; 32])
}

fn guest_secret() -> SigningKey {
    SigningKey::from_bytes(&[2u8; 32])
}

/// Two views with both keys admitted (simulating post-transport sync).
fn playing_pair() -> (App, App, PeerId, PeerId) {
    let (white, black) = (PeerId::of(&host_secret()), PeerId::of(&guest_secret()));
    let mut host = App::with_local(host_secret());
    host.admit(guest_secret());
    let mut guest = App::with_local(guest_secret());
    guest.admit(host_secret());

    host.handle(&Command::StartGame { white, black }).unwrap();
    let genesis = guest_genesis(&host);
    guest
        .handle(&Command::JoinGame {
            peer: black,
            genesis: Box::new(genesis),
        })
        .unwrap();
    let co_sig = guest_log(&guest)[0].co_sig.unwrap();
    host.handle(&Command::NotePeerJoined {
        peer: black,
        co_sig,
    })
    .unwrap();

    host.handle(&Command::SetReady { peer: white }).unwrap();
    guest.handle(&Command::SetReady { peer: black }).unwrap();
    host.handle(&Command::NotePeerReady { peer: black })
        .unwrap();
    guest
        .handle(&Command::NotePeerReady { peer: white })
        .unwrap();

    assert!(matches!(host_state(&host), SessionState::Playing));
    assert!(matches!(host_state(&guest), SessionState::Playing));
    (host, guest, white, black)
}

fn guest_genesis(host: &App) -> chess_relay_core::session::LogEntry {
    match host.query(&Query::MoveLog).unwrap() {
        QueryResult::MoveLog(entries) => entries[0],
        _ => unreachable!(),
    }
}

fn guest_log(app: &App) -> Vec<chess_relay_core::session::LogEntry> {
    match app.query(&Query::MoveLog).unwrap() {
        QueryResult::MoveLog(entries) => entries,
        _ => unreachable!(),
    }
}

fn host_state(app: &App) -> SessionState {
    match app.query(&Query::SessionState).unwrap() {
        QueryResult::SessionState(view) => view.state,
        _ => unreachable!(),
    }
}

fn last_entry(app: &App) -> chess_relay_core::session::LogEntry {
    guest_log(app).pop().unwrap()
}

#[test]
fn moves_flow_both_ways_and_views_converge() {
    let (mut host, mut guest, white, black) = playing_pair();

    // White moves on host view; guest ingests off-frame and drains.
    let events = host
        .handle(&Command::SubmitMove {
            peer: white,
            mv: "e2e4".parse().unwrap(),
        })
        .unwrap();
    assert!(matches!(
        events[0],
        Event::MoveApplied { agreed: false, .. }
    ));
    guest.ingest_remote(&last_entry(&host)).unwrap();
    let queued = guest.drain();
    assert!(matches!(queued[0], Event::MoveApplied { agreed: true, .. }));

    // Agreement crosses back; black replies symmetrically.
    let co_sig = guest_log(&guest).last().unwrap().co_sig.unwrap();
    let events = host
        .handle(&Command::NoteMoveAgreed { seq: 1, co_sig })
        .unwrap();
    assert!(matches!(events[0], Event::MoveAgreed { seq: 1 }));
    guest
        .handle(&Command::SubmitMove {
            peer: black,
            mv: "e7e5".parse().unwrap(),
        })
        .unwrap();
    host.ingest_remote(&last_entry(&guest)).unwrap();
    let queued = host.drain();
    assert!(matches!(queued[0], Event::MoveApplied { agreed: true, .. }));

    // Both views hold the same position and log.
    let fen_of = |app: &App| match app.query(&Query::GameState).unwrap() {
        QueryResult::GameState(view) => view.fen,
        _ => unreachable!(),
    };
    assert_eq!(fen_of(&host), fen_of(&guest));
    assert_eq!(guest_log(&host).len(), guest_log(&guest).len());
    assert!(guest_log(&host).iter().all(|entry| entry.is_agreed()));
}

#[test]
fn legal_moves_query_comes_from_core() {
    let (host, _, _, _) = playing_pair();
    let moves = match host.query(&Query::LegalMoves { from: None }).unwrap() {
        QueryResult::LegalMoves(moves) => moves,
        _ => unreachable!(),
    };
    assert_eq!(moves.len(), 20);
    let shown = match host
        .query(&Query::LegalMoves {
            from: Some("e2".parse().unwrap()),
        })
        .unwrap()
    {
        QueryResult::LegalMoves(moves) => moves,
        _ => unreachable!(),
    };
    let targets: Vec<String> = shown.iter().map(|mv| mv.to.to_string()).collect();
    assert_eq!(targets, vec!["e3".to_string(), "e4".to_string()]);
}

#[test]
fn resign_ends_through_contract() {
    let (mut host, _, white, black) = playing_pair();
    host.handle(&Command::SubmitMove {
        peer: white,
        mv: "e2e4".parse().unwrap(),
    })
    .unwrap();
    let events = host.handle(&Command::Resign { peer: black }).unwrap();
    assert!(matches!(events[0], Event::GameEnded { .. }));
    assert!(matches!(host_state(&host), SessionState::Finished(_)));
}

#[test]
fn contract_rejects_misuse() {
    let solo = App::with_local(host_secret());
    let white = PeerId::of(&host_secret());
    // No session yet.
    assert!(
        solo.query(&Query::SessionState)
            .unwrap_err()
            .is_bad_command()
    );
    // Acting for a peer with no key here.
    let mut app = App::with_local(host_secret());
    let err = app
        .handle(&Command::SubmitMove {
            peer: PeerId::of(&guest_secret()),
            mv: "e2e4".parse().unwrap(),
        })
        .unwrap_err();
    assert!(err.is_not_local());
    // Double creation refused.
    let black = PeerId::of(&guest_secret());
    app.handle(&Command::StartGame { white, black }).unwrap();
    assert!(
        app.handle(&Command::StartGame { white, black })
            .unwrap_err()
            .is_bad_command()
    );
}
