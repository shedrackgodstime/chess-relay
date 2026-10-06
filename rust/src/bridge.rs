//! Godot bridge: the single `GodotClass` node owning the core.
//!
//! Phase 5 spike scope: prove Rust-inside-Godot on a real phone — call
//! into chess core, get facts back as signals. Threading rule (arch doc
//! §Godot integration): Rust never calls Godot APIs off-frame. Commands
//! emit signals immediately; the outbox drains in `process()`.
//!
//! Spike shortcut, documented honestly: the bridge admits a second,
//! spike-only key so one phone can play both sides with authority
//! intact (every action is still signed by its side's key). Networked
//! play replaces the second key with the transport path in Phase 6.

use crate::app::{App, Command, Event, Query, QueryResult};
use crate::chess_core::{Color as ChessColor, Move, Square};
use crate::session::PeerId;
use ed25519_dalek::{Signer, SigningKey};
use godot::prelude::*;
use std::str::FromStr;

const LOCAL_SEED: [u8; 32] = [1u8; 32];
const SPIKE_PEER_SEED: [u8; 32] = [2u8; 32];

#[derive(GodotClass)]
#[class(base = Node, init)]
pub struct ChessRelayBridge {
    base: Base<Node>,
    app: Option<App>,
    local: PeerId,
    peer: PeerId,
}

#[godot_api]
impl ChessRelayBridge {
    #[signal]
    fn session_created(white: GString, black: GString);
    #[signal]
    fn ready_changed(peer: GString);
    #[signal]
    fn game_started();
    #[signal]
    fn move_applied(seq: i64, uci: GString, by: GString, agreed: bool);
    #[signal]
    fn move_agreed(seq: i64);
    #[signal]
    fn game_ended(reason: GString);
    #[signal]
    fn bridge_error(message: GString);

    /// Creates the session as host and runs the spike lifecycle.
    ///
    /// Joins the spike peer (co-signing genesis with its admitted key)
    /// and marks both sides ready, so one phone demonstrates the full
    /// path to a playable game. Networked play replaces the peer side
    /// with the transport path in Phase 6.
    #[func]
    fn start(&mut self) {
        let local_key = SigningKey::from_bytes(&LOCAL_SEED);
        let peer_key = SigningKey::from_bytes(&SPIKE_PEER_SEED);
        let (white, black) = (PeerId::of(&local_key), PeerId::of(&peer_key));
        let mut app = App::with_local(local_key);
        app.admit(peer_key.clone());
        match app.handle(&Command::StartGame { white, black }) {
            Ok(events) => self.emit_all(&events),
            Err(err) => {
                self.emit_error(&err.to_string());
                return;
            }
        }
        let genesis_hash = match app.query(&Query::MoveLog) {
            Ok(QueryResult::MoveLog(entries)) => entries[0].hash(),
            _ => {
                self.emit_error("genesis missing");
                return;
            }
        };
        let co_sig = peer_key.sign(&genesis_hash).to_bytes();
        self.app = Some(app);
        self.local = white;
        self.peer = black;
        // Each step emits; failures surface as `bridge_error`.
        let steps = [
            Command::NotePeerJoined {
                peer: black,
                co_sig,
            },
            Command::SetReady { peer: white },
            Command::SetReady { peer: black },
        ];
        for command in steps {
            let result = self
                .app
                .as_mut()
                .map(|app| app.handle(&command))
                .expect("app just stored");
            match result {
                Ok(events) => self.emit_all(&events),
                Err(err) => self.emit_error(&err.to_string()),
            }
        }
    }

    /// Marks a side ready (`"white"` or `"black"`); second starts play.
    #[func]
    fn set_ready(&mut self, side: GString) {
        let Some(app) = self.app.as_mut() else {
            self.emit_error("bridge not started");
            return;
        };
        let peer = match side.to_string().as_str() {
            "white" => self.local,
            _ => self.peer,
        };
        match app.handle(&Command::SetReady { peer }) {
            Ok(events) => self.emit_all(&events),
            Err(err) => self.emit_error(&err.to_string()),
        }
    }

    /// Plays `uci` for whoever owns the turn; emits `move_applied`.
    #[func]
    fn submit_move(&mut self, uci: GString) -> bool {
        let mv: Move = match uci.to_string().parse() {
            Ok(mv) => mv,
            Err(err) => {
                self.emit_error(&err.to_string());
                return false;
            }
        };
        let Some(app) = self.app.as_mut() else {
            self.emit_error("bridge not started");
            return false;
        };
        let peer = match game_side(Some(app)) {
            Some(ChessColor::White) => self.local,
            Some(ChessColor::Black) => self.peer,
            None => {
                self.emit_error("game not started");
                return false;
            }
        };
        match app.handle(&Command::SubmitMove { peer, mv }) {
            Ok(events) => {
                self.emit_all(&events);
                true
            }
            Err(err) => {
                self.emit_error(&err.to_string());
                false
            }
        }
    }

    /// Current position in FEN (observation, never authority).
    #[func]
    fn fen(&self) -> GString {
        match self
            .app
            .as_ref()
            .and_then(|app| app.query(&Query::GameState).ok())
        {
            Some(QueryResult::GameState(view)) => GString::from(&view.fen),
            _ => GString::from(""),
        }
    }

    /// Side to move as `"white"`, `"black"`, or `""` before play starts.
    #[func]
    fn turn(&self) -> GString {
        match game_side(self.app.as_ref()) {
            Some(ChessColor::White) => GString::from("white"),
            Some(ChessColor::Black) => GString::from("black"),
            None => GString::from(""),
        }
    }

    /// Target squares for legal moves departing `square` (e.g. `"e2"`).
    ///
    /// Empty when the square is unparseable, vacant, or the game has not
    /// started; legality itself stays in the core.
    #[func]
    fn legal_moves_from(&self, square: GString) -> Array<GString> {
        let mut targets = Array::new();
        let from = Square::from_str(&square.to_string());
        let moves = self
            .app
            .as_ref()
            .and_then(|app| app.query(&Query::LegalMoves { from: from.ok() }).ok());
        if let Some(QueryResult::LegalMoves(moves)) = moves {
            for mv in moves {
                targets.push(&GString::from(&mv.to.to_string()));
            }
        }
        targets
    }
}

#[godot_api]
impl INode for ChessRelayBridge {
    fn process(&mut self, _delta: f64) {
        // Drain off-frame events first so a handler calling back into the
        // bridge never meets a held borrow: take, then emit.
        let queued = self.app.as_mut().map(App::drain).unwrap_or_default();
        for event in &queued {
            self.emit_one(event);
        }
    }
}

impl ChessRelayBridge {
    fn emit_all(&mut self, events: &[Event]) {
        for event in events {
            self.emit_one(event);
        }
    }

    fn emit_one(&mut self, event: &Event) {
        match event {
            Event::SessionCreated { white, black, .. } => {
                let (white, black) = (
                    GString::from(&white.to_string()),
                    GString::from(&black.to_string()),
                );
                self.signals().session_created().emit(&white, &black);
            }
            Event::PeerJoined { peer } => {
                let peer = GString::from(&peer.to_string());
                self.signals().ready_changed().emit(&peer);
            }
            Event::ReadyChanged { peer } => {
                let peer = GString::from(&peer.to_string());
                self.signals().ready_changed().emit(&peer);
            }
            Event::GameStarted => {
                self.signals().game_started().emit();
            }
            Event::MoveApplied {
                seq,
                mv,
                by,
                agreed,
            } => {
                let (uci, by) = (
                    GString::from(&mv.to_string()),
                    GString::from(&by.to_string()),
                );
                self.signals()
                    .move_applied()
                    .emit(*seq as i64, &uci, &by, *agreed);
            }
            Event::MoveAgreed { seq } => {
                self.signals().move_agreed().emit(*seq as i64);
            }
            Event::MoveRejected { reason } => self.emit_error(reason),
            Event::DrawOffered { .. } | Event::DrawAnswered { .. } => {}
            Event::GameEnded { reason } => {
                let reason = GString::from(&format!("{reason:?}"));
                self.signals().game_ended().emit(&reason);
            }
        }
    }

    fn emit_error(&mut self, message: &str) {
        self.signals().bridge_error().emit(message);
    }
}

fn game_side(app: Option<&App>) -> Option<ChessColor> {
    match app?.query(&Query::GameState) {
        Ok(QueryResult::GameState(view)) => Some(view.side_to_move),
        _ => None,
    }
}

struct ChessRelayExtension;

#[gdextension]
unsafe impl ExtensionLibrary for ChessRelayExtension {}
