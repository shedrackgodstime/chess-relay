//! Godot bridge: the single `GodotClass` node owning the core.
//!
//! Threading rule (arch doc §Godot integration): the scene tree is
//! single-threaded and Rust threads must never call Godot APIs. All
//! shared state lives in [`CoreState`] behind one mutex. Every `#[func]`
//! locks, operates, drops the guard, and only then emits signals —
//! otherwise a GDScript handler calling back into the bridge would
//! deadlock on the held lock. Async network tasks (slice B) follow the
//! same rule: they push facts into the outbox and never touch Godot.
//!
//! Spike shortcut, documented honestly: the bridge admits a second,
//! spike-only key so one phone can play both sides with authority
//! intact (every action is still signed by its side's key). Networked
//! play replaces the second key with the transport path.

use crate::app::{App, Command, Event, Query, QueryResult};
use crate::chess_core::{Color as ChessColor, Move, Square};
use crate::session::{LogStore, PeerId};
use ed25519_dalek::{Signer, SigningKey};
use godot::prelude::*;
use std::collections::VecDeque;
use std::str::FromStr;
use std::sync::{Mutex, MutexGuard};

const LOCAL_SEED: [u8; 32] = [1u8; 32];
const SPIKE_PEER_SEED: [u8; 32] = [2u8; 32];

/// Everything the bridge shares between the scene thread and (later)
/// network tasks. Always accessed through [`ChessRelayBridge::lock`],
/// never held across signal emission or `.await`.
#[derive(Default)]
struct CoreState {
    app: Option<App>,
    local: PeerId,
    peer: PeerId,
    offer_by: Option<PeerId>,
    save_path: Option<String>,
    outbox: VecDeque<Event>,
}

#[derive(GodotClass)]
#[class(base = Node, init)]
pub struct ChessRelayBridge {
    base: Base<Node>,
    #[init(val = std::sync::Arc::new(std::sync::Mutex::new(CoreState::default())))]
    core: std::sync::Arc<Mutex<CoreState>>,
}

impl ChessRelayBridge {
    /// Locks the shared core. Never panics on poison: a dead network
    /// task must not wedge the game, so its writes are kept.
    fn lock(&self) -> MutexGuard<'_, CoreState> {
        self.core.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }
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
    fn draw_offered(by: GString, seq: i64);
    #[signal]
    fn draw_answered(by: GString, accept: bool);
    #[signal]
    fn game_ended(reason: GString);
    #[signal]
    fn bridge_error(message: GString);

    /// Creates the session as host and runs the spike lifecycle.
    ///
    /// Joins the spike peer (co-signing genesis with its admitted key)
    /// and marks both sides ready, so one phone demonstrates the full
    /// path to a playable game. Networked play replaces the peer side
    /// with the transport path.
    #[func]
    fn start(&mut self) {
        let local_key = SigningKey::from_bytes(&LOCAL_SEED);
        let peer_key = SigningKey::from_bytes(&SPIKE_PEER_SEED);
        let (events, errors) = {
            let mut core = self.lock();
            start_fresh(&mut core, local_key, peer_key)
        };
        self.emit_all(&events);
        for message in &errors {
            self.emit_error(message);
        }
    }

    /// Starts with a persistent identity, resuming the saved game if any.
    ///
    /// Loads the local seed from `identity_path` (generating and saving
    /// one on first run), then restores the log at `save_path` when it
    /// holds a playable or finished session. Returns true when a saved
    /// game resumed. Paths come from the platform (`user://` resolved by
    /// Godot); this layer only reads and writes bytes.
    #[func]
    fn start_resumable(&mut self, identity_path: String, save_path: String) -> bool {
        let seed = match load_or_create_seed(&identity_path) {
            Ok(seed) => seed,
            Err(err) => {
                self.emit_error(&err.to_string());
                return false;
            }
        };
        // Same spike peer model as start(): one device plays both sides
        // until transport arrives. Only the local identity persists.
        let local_key = SigningKey::from_bytes(&seed);
        let peer_key = SigningKey::from_bytes(&SPIKE_PEER_SEED);
        let (restored, events) = {
            let mut core = self.lock();
            core.save_path = Some(save_path.clone());
            let mut app = App::with_local(local_key.clone());
            app.admit(peer_key.clone());
            match crate::session::FileStore::new(std::path::Path::new(&save_path)).load() {
                Ok(entries) if !entries.is_empty() => match app.restore(entries) {
                    Ok(events) => {
                        core.app = Some(app);
                        core.local = PeerId::of(&local_key);
                        core.peer = PeerId::of(&peer_key);
                        (true, events)
                    }
                    Err(_) => (false, Vec::new()),
                },
                _ => (false, Vec::new()),
            }
        };
        if restored {
            self.emit_all(&events);
            return true;
        }
        let (events, errors) = {
            let mut core = self.lock();
            start_fresh(&mut core, local_key, peer_key)
        };
        self.emit_all(&events);
        for message in &errors {
            self.emit_error(message);
        }
        false
    }

    /// Persists the current move log to the configured save path.
    ///
    /// No-op (false) without a path or session; the screen calls this
    /// after every applied move and game end.
    #[func]
    fn save_game(&mut self) -> bool {
        let result = {
            let core = self.lock();
            let (Some(path), Some(app)) = (core.save_path.clone(), core.app.as_ref()) else {
                return false;
            };
            let entries = match app.query(&Query::MoveLog) {
                Ok(QueryResult::MoveLog(entries)) => entries,
                _ => return false,
            };
            crate::session::FileStore::new(std::path::Path::new(&path)).save(&entries)
        };
        match result {
            Ok(()) => true,
            Err(err) => {
                self.emit_error(&err.to_string());
                false
            }
        }
    }

    /// Marks a side ready (`"white"` or `"black"`); second starts play.
    #[func]
    fn set_ready(&mut self, side: GString) {
        let peer = {
            let core = self.lock();
            core.app.as_ref().map(|_| match side.to_string().as_str() {
                "white" => core.local,
                _ => core.peer,
            })
        };
        let Some(peer) = peer else {
            self.emit_error("bridge not started");
            return;
        };
        let events = {
            let mut core = self.lock();
            match core.app.as_mut() {
                Some(app) => {
                    app.handle(&Command::SetReady { peer }).map_err(|err| err.to_string())
                }
                None => Err("bridge not started".to_string()),
            }
        };
        match events {
            Ok(events) => self.emit_all(&events),
            Err(message) => self.emit_error(&message),
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
        let events = {
            let mut core = self.lock();
            let peer = match turn_peer(&core) {
                Some(peer) => peer,
                None => return false,
            };
            let Some(app) = core.app.as_mut() else {
                return false;
            };
            match app.handle(&Command::SubmitMove { peer, mv }) {
                Ok(events) => events,
                Err(err) => {
                    drop(core);
                    self.emit_error(&err.to_string());
                    return false;
                }
            }
        };
        self.emit_all(&events);
        true
    }

    /// Current position in FEN (observation, never authority).
    #[func]
    fn fen(&self) -> GString {
        match self
            .lock()
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
        let core = self.lock();
        match turn_peer(&core) {
            Some(peer) if peer == core.local => GString::from("white"),
            Some(_) => GString::from("black"),
            None => GString::from(""),
        }
    }

    /// King square of the side to move while in check, else `""`.
    #[func]
    fn check_square(&self) -> GString {
        match self
            .lock()
            .app
            .as_ref()
            .and_then(|app| app.query(&Query::GameState).ok())
        {
            Some(QueryResult::GameState(view)) => GString::from(&view.check),
            _ => GString::from(""),
        }
    }

    /// Fullmove number derived from the signed log (not a client counter).
    #[func]
    fn move_number(&self) -> i64 {
        match self
            .lock()
            .app
            .as_ref()
            .and_then(|app| app.query(&Query::MoveLog).ok())
        {
            Some(QueryResult::MoveLog(entries)) => {
                let moves = entries
                    .iter()
                    .filter(|entry| {
                        matches!(entry.payload, crate::session::LogPayload::Move { .. })
                    })
                    .count();
                (moves / 2 + 1) as i64
            }
            _ => 1,
        }
    }

    /// Resigns the side to move (hotseat: the human giving up).
    #[func]
    fn resign(&mut self) -> bool {
        let command = {
            let core = self.lock();
            match turn_peer(&core) {
                Some(peer) => Command::Resign { peer },
                None => return false,
            }
        };
        self.run_command(command)
    }

    /// Offers a draw for the side to move; records the offerer.
    #[func]
    fn offer_draw(&mut self) -> bool {
        let peer = {
            let core = self.lock();
            match turn_peer(&core) {
                Some(peer) => peer,
                None => return false,
            }
        };
        if !self.run_command(Command::OfferDraw { peer }) {
            return false;
        }
        self.lock().offer_by = Some(peer);
        true
    }

    /// Answers the open offer as the other side.
    #[func]
    fn answer_draw(&mut self, accept: bool) -> bool {
        let command = {
            let core = self.lock();
            let offerer = match core.offer_by {
                Some(offerer) => offerer,
                None => return false,
            };
            let sides = match sides(&core) {
                Some(sides) => sides,
                None => return false,
            };
            let peer = if offerer == sides.0 { sides.1 } else { sides.0 };
            Command::AnswerDraw { peer, accept }
        };
        if !self.run_command(command) {
            return false;
        }
        self.lock().offer_by = None;
        true
    }

    /// Target squares for legal moves departing `square` (e.g. `"e2"`).
    ///
    /// Empty when the square is unparseable, vacant, or the game has not
    /// started; legality itself stays in the core.
    #[func]
    fn legal_moves_from(&self, square: GString) -> Array<GString> {
        let mut targets = Array::new();
        let from = Square::from_str(&square.to_string());
        let moves = self.lock().app.as_ref().and_then(|app| {
            app.query(&Query::LegalMoves { from: from.ok() }).ok()
        });
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
        // bridge never meets a held lock: take, then emit.
        let queued: Vec<Event> = {
            let mut core = self.lock();
            let mut drained = core
                .app
                .as_mut()
                .map(App::drain)
                .unwrap_or_default();
            drained.extend(core.outbox.drain(..));
            drained
        };
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

    /// Runs a command, emitting its events; errors surface as `bridge_error`.
    fn run_command(&mut self, command: Command) -> bool {
        let events = {
            let mut core = self.lock();
            match core.app.as_mut().map(|app| app.handle(&command)) {
                Some(Ok(events)) => events,
                Some(Err(err)) => {
                    drop(core);
                    self.emit_error(&err.to_string());
                    return false;
                }
                None => {
                    drop(core);
                    self.emit_error("bridge not started");
                    return false;
                }
            }
        };
        self.emit_all(&events);
        true
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
            Event::DrawOffered { by, seq } => {
                let by = GString::from(&by.to_string());
                self.signals().draw_offered().emit(&by, *seq as i64);
            }
            Event::DrawAnswered { by, accept } => {
                let by = GString::from(&by.to_string());
                self.signals().draw_answered().emit(&by, *accept);
            }
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

/// Runs the spike lifecycle for a fresh local game: create, join the
/// admitted peer, mark both ready. Returns emitted events plus error
/// messages (the caller emits both after the lock drops).
fn start_fresh(
    core: &mut CoreState,
    local_key: SigningKey,
    peer_key: SigningKey,
) -> (Vec<Event>, Vec<String>) {
    let mut events = Vec::new();
    let mut errors = Vec::new();
    let (white, black) = (PeerId::of(&local_key), PeerId::of(&peer_key));
    let mut app = App::with_local(local_key);
    app.admit(peer_key.clone());
    match app.handle(&Command::StartGame { white, black }) {
        Ok(step) => events.extend(step),
        Err(err) => {
            errors.push(err.to_string());
            return (events, errors);
        }
    }
    let genesis_hash = match app.query(&Query::MoveLog) {
        Ok(QueryResult::MoveLog(entries)) => entries[0].hash(),
        _ => {
            errors.push("genesis missing".to_string());
            return (events, errors);
        }
    };
    let co_sig = peer_key.sign(&genesis_hash).to_bytes();
    core.app = Some(app);
    core.local = white;
    core.peer = black;
    for command in [
        Command::NotePeerJoined {
            peer: black,
            co_sig,
        },
        Command::SetReady { peer: white },
        Command::SetReady { peer: black },
    ] {
        let result = core
            .app
            .as_mut()
            .map(|app| app.handle(&command))
            .expect("app just stored");
        match result {
            Ok(step) => events.extend(step),
            Err(err) => errors.push(err.to_string()),
        }
    }
    (events, errors)
}

fn turn_peer(core: &CoreState) -> Option<PeerId> {
    let (white, black) = sides(core)?;
    match game_side(core.app.as_ref()) {
        Some(ChessColor::White) => Some(white),
        Some(ChessColor::Black) => Some(black),
        None => None,
    }
}

fn sides(core: &CoreState) -> Option<(PeerId, PeerId)> {
    match core.app.as_ref()?.query(&Query::SessionState).ok()? {
        QueryResult::SessionState(view) => Some((view.white, view.black)),
        _ => None,
    }
}

fn game_side(app: Option<&App>) -> Option<ChessColor> {
    match app?.query(&Query::GameState) {
        Ok(QueryResult::GameState(view)) => Some(view.side_to_move),
        _ => None,
    }
}

/// Loads the 32-byte local seed, generating and saving one on first run.
fn load_or_create_seed(path: &str) -> Result<[u8; 32], crate::session::StoreError> {
    use crate::session::StoreError;
    let bytes = match std::fs::read(path) {
        Ok(bytes) => bytes,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
            let mut seed = [0u8; 32];
            getrandom::getrandom(&mut seed).map_err(|err| StoreError::io(err.to_string()))?;
            std::fs::write(path, seed).map_err(StoreError::from)?;
            return Ok(seed);
        }
        Err(err) => return Err(err.into()),
    };
    if bytes.len() != 32 {
        return Err(StoreError::decode(
            "identity seed must be 32 bytes".to_string(),
        ));
    }
    let mut seed = [0u8; 32];
    seed.copy_from_slice(&bytes);
    Ok(seed)
}

struct ChessRelayExtension;

#[gdextension]
unsafe impl ExtensionLibrary for ChessRelayExtension {}
