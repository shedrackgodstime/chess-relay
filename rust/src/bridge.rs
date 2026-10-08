//! Godot bridge: the single `GodotClass` node owning the core.
//!
//! Threading rule (arch doc §Godot integration): the scene tree is
//! single-threaded and Rust threads must never call Godot APIs. All
//! shared state lives in `CoreState` behind one mutex. Every `#[func]`
//! locks, operates, drops the guard, and only then emits signals —
//! otherwise a GDScript handler calling back into the bridge would
//! deadlock on the held lock. Async network tasks (slice B) follow the
//! same rule: they push facts into the outbox and never touch Godot.
//!
//! Spike shortcut, documented honestly: the bridge admits a second,
//! spike-only key so one phone can play both sides with authority
//! intact (every action is still signed by its side's key). Networked
//! play replaces the second key with the transport path.

use crate::ai::{Adaptation, Difficulty, LocalAiEngine, Personality, SearchControl};
use crate::app::{App, Command, Event, Query, QueryResult};
use crate::chess_core::{Board, Color as ChessColor, Move, Square};
use crate::protocol::{Msg, PROTOCOL_VERSION};
use crate::session::{LogEntry, LogStore, PeerId};
use crate::transport::{Connection, Endpoint as _, TransportError};
use ed25519_dalek::{Signer, SigningKey};
use godot::prelude::*;
use std::collections::VecDeque;
use std::str::FromStr;
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Arc, Mutex, MutexGuard};
use std::thread::JoinHandle;
use std::time::Duration;

const LOCAL_SEED: [u8; 32] = [1u8; 32];
const SPIKE_PEER_SEED: [u8; 32] = [2u8; 32];

/// Everything the bridge shares between the scene thread and (later)
/// network tasks. Always accessed through [`ChessRelayBridge::lock`],
/// never held across signal emission or `.await`.
#[derive(Default)]
struct CoreState {
    app: Option<App>,
    /// This device's peer. Set at start/join; the spike flow defaults it.
    me: PeerId,
    offer_by: Option<PeerId>,
    save_path: Option<String>,
    outbox: VecDeque<Event>,
    net: Option<NetState>,
    net_notes: VecDeque<NetNote>,
    ai: Option<AiState>,
    /// Bumped on every host/join/leave so late tasks from a retired
    /// network go silent instead of emitting stale signals.
    net_generation: u64,
}

struct AiRequest {
    board: Board,
    control: SearchControl,
    generation: u64,
}

struct AiResult {
    mv: Option<Move>,
    generation: u64,
}

struct AiState {
    peer: PeerId,
    tx: Sender<AiRequest>,
    rx: Receiver<AiResult>,
    control: Option<SearchControl>,
    generation: u64,
    thread: Option<JoinHandle<()>>,
}

/// Network ownership: the runtime keeps background tasks alive, the
/// endpoint is a cloneable handle (a link task accepts on its own
/// clone, the bridge closes on its own), and the command sender feeds
/// the session driver owned by those tasks.
struct NetState {
    runtime: tokio::runtime::Runtime,
    endpoint: crate::IrohEndpoint,
    /// Driver inbox: local progress notifications for the session task.
    cmd_tx: tokio::sync::mpsc::UnboundedSender<NetCmd>,
}

/// Driver input: local log progress worth sending to the peer.
#[derive(Debug)]
enum NetCmd {
    Flush,
}

/// Session side for the handshake: the host starts the game and sends
/// the first message, the guest joins from it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Role {
    Host,
    Guest,
}

/// A live network handoff: everything a link task needs after setup.
struct NetLaunch {
    endpoint: crate::IrohEndpoint,
    generation: u64,
    cmd_rx: tokio::sync::mpsc::UnboundedReceiver<NetCmd>,
    seed: [u8; 32],
}

/// Facts from network tasks for the scene thread to announce.
#[derive(Debug)]
enum NetNote {
    Connected(String),
    /// Slice C pushes this when its driver sees the peer go away.
    #[allow(dead_code)]
    Disconnected,
    Error(String),
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
        self.core
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
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
    #[signal]
    fn peer_connected(peer: GString);
    #[signal]
    fn peer_disconnected();
    #[signal]
    fn network_error(message: GString);

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
                        core.me = PeerId::of(&local_key);
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

    /// Starts a local game against the Rust AI. The AI is an application
    /// client: its worker returns a move, and the bridge submits it through
    /// the same `Command::SubmitMove` path used by human input.
    #[func]
    fn start_ai(
        &mut self,
        identity_path: String,
        save_path: String,
        side: GString,
        difficulty: GString,
    ) -> bool {
        let old_net = {
            let mut core = self.lock();
            begin_retire(&mut core)
        };
        finish_retire(old_net);
        let old_ai = {
            let mut core = self.lock();
            begin_ai_retire(&mut core)
        };
        finish_ai_retire(old_ai);

        let seed = match load_or_create_seed(&identity_path) {
            Ok(seed) => seed,
            Err(err) => {
                self.emit_error(&err.to_string());
                return false;
            }
        };
        let local_key = SigningKey::from_bytes(&seed);
        let ai_key = SigningKey::from_bytes(&SPIKE_PEER_SEED);
        let local_peer = PeerId::of(&local_key);
        let ai_peer = PeerId::of(&ai_key);
        let difficulty = parse_difficulty(&difficulty.to_string());
        let side = side.to_string();
        let local_is_black = side.eq_ignore_ascii_case("black")
            || (side.eq_ignore_ascii_case("random") && local_peer.bytes()[0] & 1 == 1);
        let (events, errors, restored) = {
            let mut core = self.lock();
            core.save_path = Some(save_path.clone());
            let mut app = App::with_local(local_key.clone());
            app.admit(ai_key.clone());
            let restored_events =
                match crate::session::FileStore::new(std::path::Path::new(&save_path)).load() {
                    Ok(entries) if !entries.is_empty() => app.restore(entries).ok(),
                    _ => None,
                };
            if let Some(events) = restored_events {
                core.app = Some(app);
                core.me = local_peer;
                (events, Vec::new(), true)
            } else {
                let (events, errors) =
                    start_ai_fresh(&mut core, app, local_key, ai_key, local_is_black);
                (events, errors, false)
            }
        };
        for message in &errors {
            self.emit_error(message);
        }
        if !errors.is_empty() {
            return false;
        }
        {
            let mut core = self.lock();
            let generation = core.net_generation.wrapping_add(1);
            core.net_generation = generation;
            core.ai = Some(start_ai_worker(ai_peer, difficulty, generation));
            schedule_ai(&mut core);
        }
        self.emit_all(&events);
        let _ = restored;
        true
    }

    /// Cancels and retires the local AI worker.
    #[func]
    fn stop_ai(&mut self) {
        let old_ai = {
            let mut core = self.lock();
            begin_ai_retire(&mut core)
        };
        finish_ai_retire(old_ai);
    }

    /// Hosts a networked game: binds an endpoint on a fresh identity
    /// and returns its ticket for the guest. Accept runs in the
    /// background; the guest's arrival surfaces as `peer_connected`.
    /// The handshake that starts play on the wire is slice C.
    #[func]
    fn host_game(&mut self) -> GString {
        let old = {
            let mut core = self.lock();
            begin_retire(&mut core)
        };
        finish_retire(old);
        let launch = {
            let mut core = self.lock();
            match start_network(&mut core) {
                Ok(launch) => launch,
                Err(message) => {
                    drop(core);
                    self.emit_error(&message);
                    return GString::new();
                }
            }
        };
        let ticket = launch.endpoint.ticket();
        {
            let core = self.lock();
            if let Some(net) = core.net.as_ref() {
                net.runtime.spawn(accept_task(
                    Arc::clone(&self.core),
                    launch.endpoint,
                    launch.seed,
                    launch.generation,
                    launch.cmd_rx,
                ));
            }
        }
        GString::from(&ticket)
    }

    /// Joins a networked game: dials `ticket` (or a short rendezvous
    /// code) in the background. Returns false only when setup fails
    /// outright; dial success or failure surfaces as `peer_connected`
    /// or `network_error`. The handshake is slice C.
    #[func]
    fn join_game(&mut self, ticket: GString) -> bool {
        let ticket = ticket.to_string();
        if ticket.is_empty() {
            self.emit_error("empty ticket");
            return false;
        }
        let old = {
            let mut core = self.lock();
            begin_retire(&mut core)
        };
        finish_retire(old);
        let launch = {
            let mut core = self.lock();
            match start_network(&mut core) {
                Ok(launch) => launch,
                Err(message) => {
                    drop(core);
                    self.emit_error(&message);
                    return false;
                }
            }
        };
        {
            let core = self.lock();
            if let Some(net) = core.net.as_ref() {
                net.runtime.spawn(join_task(
                    Arc::clone(&self.core),
                    launch.endpoint,
                    ticket,
                    launch.seed,
                    launch.generation,
                    launch.cmd_rx,
                ));
            }
        }
        true
    }

    /// Leaves the networked game: closes the endpoint and retires the
    /// runtime. In-flight tasks go silent via the generation gate.
    #[func]
    fn leave_network(&mut self) {
        let old = {
            let mut core = self.lock();
            begin_retire(&mut core)
        };
        finish_retire(old);
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
            sides(&core).map(|(white, black)| match side.to_string().as_str() {
                "white" => white,
                _ => black,
            })
        };
        let Some(peer) = peer else {
            self.emit_error("bridge not started");
            return;
        };
        let events = {
            let mut core = self.lock();
            match core.app.as_mut() {
                Some(app) => app
                    .handle(&Command::SetReady { peer })
                    .map_err(|err| err.to_string()),
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
        let outcome: Result<Vec<Event>, String> = {
            let mut core = self.lock();
            match turn_peer(&core) {
                None => Err("game not started".to_string()),
                Some(peer) => match core.app.as_mut() {
                    Some(app) => app
                        .handle(&Command::SubmitMove { peer, mv })
                        .map_err(|err| err.to_string()),
                    None => Err("bridge not started".to_string()),
                },
            }
        };
        match outcome {
            Ok(events) => {
                self.emit_all(&events);
                self.flush_to_peer();
                true
            }
            Err(message) => {
                self.emit_error(&message);
                false
            }
        }
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
        match game_side(self.lock().app.as_ref()) {
            Some(ChessColor::White) => GString::from("white"),
            Some(ChessColor::Black) => GString::from("black"),
            None => GString::from(""),
        }
    }

    /// This device's side as `"white"`, `"black"`, or `""` when the
    /// session has no sides yet. The UI gates local input on this so a
    /// networked human can only touch their own pieces.
    #[func]
    fn my_side(&self) -> GString {
        let core = self.lock();
        match sides(&core) {
            Some((white, _)) if white == core.me => GString::from("white"),
            Some((_, black)) if black == core.me => GString::from("black"),
            _ => GString::from(""),
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
        let moves = self
            .lock()
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
        // bridge never meets a held lock: take, then emit.
        let queued: Vec<Event> = {
            let mut core = self.lock();
            drain_ai(&mut core);
            schedule_ai(&mut core);
            let mut drained = core.app.as_mut().map(App::drain).unwrap_or_default();
            drained.extend(core.outbox.drain(..));
            drained
        };
        for event in &queued {
            self.emit_one(event);
        }
        let notes: Vec<NetNote> = { self.lock().net_notes.drain(..).collect() };
        for note in &notes {
            match note {
                NetNote::Connected(peer) => {
                    let peer = GString::from(peer);
                    self.signals().peer_connected().emit(&peer);
                }
                NetNote::Disconnected => {
                    self.signals().peer_disconnected().emit();
                }
                NetNote::Error(message) => {
                    let message = GString::from(message);
                    self.signals().network_error().emit(&message);
                }
            }
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
        self.flush_to_peer();
        true
    }

    /// Tells the session driver to send unsent log entries, if
    /// networked. Fire-and-forget: a gone driver means a retired
    /// network, and an empty outbox means nothing to send.
    fn flush_to_peer(&self) {
        if let Some(tx) = self.lock().net.as_ref().map(|net| net.cmd_tx.clone()) {
            let _ = tx.send(NetCmd::Flush);
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
    core.me = white;
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

fn start_ai_fresh(
    core: &mut CoreState,
    mut app: App,
    local_key: SigningKey,
    ai_key: SigningKey,
    local_is_black: bool,
) -> (Vec<Event>, Vec<String>) {
    let local_peer = PeerId::of(&local_key);
    let ai_peer = PeerId::of(&ai_key);
    let (white, black) = if local_is_black {
        (ai_peer, local_peer)
    } else {
        (local_peer, ai_peer)
    };
    let mut events = Vec::new();
    let mut errors = Vec::new();
    if let Err(err) = app.handle(&Command::StartGame { white, black }) {
        errors.push(err.to_string());
        return (events, errors);
    }
    let genesis_hash = match app.query(&Query::MoveLog) {
        Ok(QueryResult::MoveLog(entries)) => entries[0].hash(),
        _ => {
            errors.push("genesis missing".to_string());
            return (events, errors);
        }
    };
    let co_sig = ai_key.sign(&genesis_hash).to_bytes();
    core.app = Some(app);
    core.me = local_peer;
    for command in [
        Command::NotePeerJoined {
            peer: ai_peer,
            co_sig,
        },
        Command::SetReady { peer: local_peer },
        Command::SetReady { peer: ai_peer },
    ] {
        match core
            .app
            .as_mut()
            .expect("AI app just stored")
            .handle(&command)
        {
            Ok(step) => events.extend(step),
            Err(err) => errors.push(err.to_string()),
        }
    }
    (events, errors)
}

fn parse_difficulty(value: &str) -> Difficulty {
    match value.to_ascii_lowercase().as_str() {
        "beginner" => Difficulty::Beginner,
        "easy" => Difficulty::Easy,
        "hard" => Difficulty::Hard,
        "expert" => Difficulty::Expert,
        _ => Difficulty::Normal,
    }
}

fn start_ai_worker(peer: PeerId, difficulty: Difficulty, generation: u64) -> AiState {
    let (request_tx, request_rx) = mpsc::channel::<AiRequest>();
    let (result_tx, result_rx) = mpsc::channel::<AiResult>();
    let thread = std::thread::spawn(move || {
        let mut engine = LocalAiEngine::new(
            difficulty,
            Adaptation::Fixed,
            Personality::Balanced,
            generation,
        );
        while let Ok(request) = request_rx.recv() {
            let result = engine.choose_move_with_control(&request.board, &request.control);
            if result_tx
                .send(AiResult {
                    mv: result.best_move,
                    generation: request.generation,
                })
                .is_err()
            {
                break;
            }
        }
    });
    AiState {
        peer,
        tx: request_tx,
        rx: result_rx,
        control: None,
        generation,
        thread: Some(thread),
    }
}

fn begin_ai_retire(core: &mut CoreState) -> Option<AiState> {
    core.ai.take()
}

fn finish_ai_retire(mut ai: Option<AiState>) {
    let Some(mut ai) = ai.take() else {
        return;
    };
    if let Some(control) = ai.control.take() {
        control.cancel();
    }
    drop(ai.tx);
    if let Some(thread) = ai.thread.take() {
        let _ = thread.join();
    }
}

fn schedule_ai(core: &mut CoreState) {
    let Some((peer, busy)) = core.ai.as_ref().map(|ai| (ai.peer, ai.control.is_some())) else {
        return;
    };
    if busy || turn_peer(core) != Some(peer) {
        return;
    }
    let board = match core
        .app
        .as_ref()
        .and_then(|app| app.query(&Query::GameState).ok())
    {
        Some(QueryResult::GameState(view))
            if view.outcome == crate::chess_core::Outcome::Ongoing =>
        {
            match Board::from_fen(&view.fen) {
                Ok(board) => board,
                Err(_) => return,
            }
        }
        Some(QueryResult::GameState(_)) | None => return,
        Some(_) => return,
    };
    let control = SearchControl::new();
    let Some(ai) = core.ai.as_mut() else {
        return;
    };
    if ai
        .tx
        .send(AiRequest {
            board,
            control: control.clone(),
            generation: ai.generation,
        })
        .is_ok()
    {
        ai.control = Some(control);
    }
}

fn drain_ai(core: &mut CoreState) {
    let results: Vec<AiResult> = core
        .ai
        .as_ref()
        .map(|ai| ai.rx.try_iter().collect())
        .unwrap_or_default();
    for result in results {
        let Some((peer, generation)) = core.ai.as_ref().map(|ai| (ai.peer, ai.generation)) else {
            continue;
        };
        if let Some(ai) = core.ai.as_mut() {
            ai.control = None;
        }
        if result.generation != generation || turn_peer(core) != Some(peer) {
            continue;
        }
        let Some(mv) = result.mv else {
            core.outbox.push_back(Event::MoveRejected {
                reason: "AI did not return a move".to_string(),
            });
            continue;
        };
        let result = core
            .app
            .as_mut()
            .and_then(|app| app.handle(&Command::SubmitMove { peer, mv }).ok());
        if let Some(events) = result {
            core.outbox.extend(events);
        } else {
            core.outbox.push_back(Event::MoveRejected {
                reason: "AI move was rejected by the application core".to_string(),
            });
        }
    }
}

fn turn_peer(core: &CoreState) -> Option<PeerId> {
    let (white, black) = sides(core)?;
    match game_side(core.app.as_ref()) {
        Some(ChessColor::White) => Some(white),
        Some(ChessColor::Black) => Some(black),
        None => None,
    }
}

/// Builds a runtime, binds an endpoint on a fresh seed, records `me`,
/// clears any previous session, and retires any previous network.
/// Returns the handoff a link task needs after setup.
fn start_network(core: &mut CoreState) -> Result<NetLaunch, String> {
    let mut seed = [0u8; 32];
    getrandom::getrandom(&mut seed).map_err(|_| "no randomness available".to_string())?;
    let secret = SigningKey::from_bytes(&seed);
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .map_err(|err| err.to_string())?;
    let endpoint = runtime
        .block_on(crate::IrohEndpoint::bind_with_seed(seed))
        .map_err(|_| "endpoint bind failed".to_string())?;
    let me = PeerId::of(&secret);
    if endpoint.id_bytes() != me.bytes() {
        return Err("endpoint identity diverged from peer identity".to_string());
    }
    core.net_generation += 1;
    let generation = core.net_generation;
    core.me = me;
    core.app = None;
    core.outbox.clear();
    core.offer_by = None;
    let (cmd_tx, cmd_rx) = tokio::sync::mpsc::unbounded_channel();
    core.net = Some(NetState {
        runtime,
        endpoint: endpoint.clone(),
        cmd_tx,
    });
    Ok(NetLaunch {
        endpoint,
        generation,
        cmd_rx,
        seed,
    })
}

/// Detaches the current network: bumps the generation so in-flight
/// tasks go silent, drops stale notes, and hands the old state out
/// for shutdown without the lock. The caller must pass the return to
/// `finish_retire` with no guard held: shutting down blocks until the
/// old tasks wind down, and those tails need the lock to go silent.
/// Holding the guard across shutdown deadlocks the scene thread.
fn begin_retire(core: &mut CoreState) -> Option<NetState> {
    core.net_generation += 1;
    core.net_notes.clear();
    core.net.take()
}

/// Shuts a detached network down: graceful close so the peer sees the
/// disconnect, then runtime drop once its tasks have exited. Call with
/// no CoreState guard held (see `begin_retire`).
fn finish_retire(net: Option<NetState>) {
    if let Some(net) = net {
        net.runtime.block_on(async {
            net.endpoint.close().await;
            tokio::task::yield_now().await;
        });
    }
}

/// Background accept for the host: links the guest, runs the host
/// handshake, then drives the session. Silent when a newer network
/// retired this one mid-flight.
async fn accept_task(
    core: Arc<Mutex<CoreState>>,
    mut endpoint: crate::IrohEndpoint,
    seed: [u8; 32],
    generation: u64,
    cmd_rx: tokio::sync::mpsc::UnboundedReceiver<NetCmd>,
) {
    let mut conn = match endpoint.accept().await {
        Ok(conn) => conn,
        Err(err) => {
            eprintln!("NET-TRACE host: accept failed"); // TEMP-DIAG
            note(&core, generation, NetNote::Error(short_error(&err)));
            return;
        }
    };
    let guest = PeerId::from_bytes(conn.peer_id_bytes());
    eprintln!("NET-TRACE host: accepted guest={guest}"); // TEMP-DIAG
    if handshake(&core, &mut conn, Role::Host, seed, Some(guest), generation)
        .await
        .is_ok()
    {
        drive_session(core, conn, cmd_rx, generation).await;
    }
}

/// Background dial for the guest: resolves short codes through
/// rendezvous, dials tickets directly, then runs the guest handshake
/// and drives the session. Silent when retired mid-flight.
async fn join_task(
    core: Arc<Mutex<CoreState>>,
    endpoint: crate::IrohEndpoint,
    ticket: String,
    seed: [u8; 32],
    generation: u64,
    cmd_rx: tokio::sync::mpsc::UnboundedReceiver<NetCmd>,
) {
    let dial = match iroh_tickets::endpoint::EndpointTicket::from_str(&ticket) {
        Ok(_) => ticket.clone(),
        Err(_) => match crate::resolve_ticket(&ticket, Duration::from_secs(120)).await {
            Ok(resolved) => resolved.to_string(),
            Err(_) => {
                note(
                    &core,
                    generation,
                    NetNote::Error(format!("code not found: {ticket}")),
                );
                return;
            }
        },
    };
    let mut endpoint = endpoint;
    let mut conn = match endpoint.connect(&dial).await {
        Ok(conn) => {
            eprintln!("NET-TRACE guest: dial ok"); // TEMP-DIAG
            conn
        }
        Err(err) => {
            note(&core, generation, NetNote::Error(short_error(&err)));
            return;
        }
    };
    if handshake(&core, &mut conn, Role::Guest, seed, None, generation)
        .await
        .is_ok()
    {
        drive_session(core, conn, cmd_rx, generation).await;
    }
}

/// True while `generation` is still the live network.
fn is_current(core: &Arc<Mutex<CoreState>>, generation: u64) -> bool {
    core.lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .net_generation
        == generation
}

/// Pushes a note for the scene thread, unless a newer network retired
/// this session mid-flight.
fn note(core: &Arc<Mutex<CoreState>>, generation: u64, note: NetNote) {
    let mut guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    if guard.net_generation == generation {
        guard.net_notes.push_back(note);
    }
}

/// How long one handshake step waits for the peer. Past this the
/// session is dead: a hang here used to freeze the UI on "starting
/// game" with nothing logged, on both sides.
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(30);

/// Receives one handshake message, noting transport death as a
/// disconnect and silence as a named timeout, and stopping the session
/// either way. Returns the message when it arrives in time.
async fn recv_handshake<C: Connection>(
    core: &Arc<Mutex<CoreState>>,
    conn: &mut C,
    waiting_for: &str,
    generation: u64,
) -> Result<Msg, ()> {
    match tokio::time::timeout(HANDSHAKE_TIMEOUT, conn.recv()).await {
        Ok(Ok(msg)) => Ok(msg),
        Ok(Err(_)) => {
            note(core, generation, NetNote::Disconnected);
            Err(())
        }
        Err(_) => {
            note(
                core,
                generation,
                NetNote::Error(format!("Timed out {waiting_for}.")),
            );
            Err(())
        }
    }
}

/// Runs a command and queues its events plus pending drains for
/// `process()` to emit off-frame.
fn apply(core: &Arc<Mutex<CoreState>>, command: Command) -> Result<(), String> {
    let mut guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    let Some(app) = guard.app.as_mut() else {
        return Err("no session".to_string());
    };
    let mut events = app.handle(&command).map_err(|err| err.to_string())?;
    events.extend(app.drain());
    guard.outbox.extend(events);
    Ok(())
}

/// Last move-log entry, cloned out from under the lock.
fn tip_entry(core: &Arc<Mutex<CoreState>>) -> Option<LogEntry> {
    let guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    match guard.app.as_ref().map(|app| app.query(&Query::MoveLog)) {
        Some(Ok(QueryResult::MoveLog(entries))) => entries.last().copied(),
        _ => None,
    }
}

/// Wire handshake, mirroring the CLI flow: the host starts the game and
/// sends hello, the guest joins from it, and both agree on genesis
/// before play. Transport failures note a disconnect, protocol
/// violations note an error; both stop the session.
async fn handshake<C: Connection>(
    core: &Arc<Mutex<CoreState>>,
    conn: &mut C,
    role: Role,
    seed: [u8; 32],
    remote: Option<PeerId>,
    generation: u64,
) -> Result<(), ()> {
    let secret = SigningKey::from_bytes(&seed);
    let me = PeerId::of(&secret);
    match role {
        Role::Host => {
            let Some(guest) = remote else {
                note(
                    core,
                    generation,
                    NetNote::Error("host link lost its guest".to_string()),
                );
                return Err(());
            };
            {
                let mut guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
                if guard.net_generation != generation {
                    return Err(());
                }
                guard.app = Some(App::with_local(secret));
            }
            if apply(
                core,
                Command::StartGame {
                    white: me,
                    black: guest,
                },
            )
            .is_err()
            {
                note(
                    core,
                    generation,
                    NetNote::Error("session start rejected".to_string()),
                );
                return Err(());
            }
            note(core, generation, NetNote::Connected(guest.to_string()));
            let Some(genesis) = tip_entry(core).filter(|entry| entry.seq == 0) else {
                note(
                    core,
                    generation,
                    NetNote::Error("genesis missing".to_string()),
                );
                return Err(());
            };
            if conn
                .send(&Msg::Hello {
                    version: PROTOCOL_VERSION,
                    genesis,
                })
                .await
                .is_err()
            {
                eprintln!("NET-TRACE host: hello send failed"); // TEMP-DIAG
                note(core, generation, NetNote::Disconnected);
                return Err(());
            }
            eprintln!("NET-TRACE host: hello sent"); // TEMP-DIAG
            match recv_handshake(core, conn, "waiting for the guest to get ready", generation)
                .await?
            {
                Msg::Ready { peer } if peer == guest => {
                    eprintln!("NET-TRACE host: guest ready"); // TEMP-DIAG
                }
                _ => {
                    note(
                        core,
                        generation,
                        NetNote::Error("guest readiness malformed".to_string()),
                    );
                    return Err(());
                }
            }
            let co_sig =
                match recv_handshake(core, conn, "waiting for the guest's agreement", generation)
                    .await?
                {
                    Msg::Agreed { seq: 0, sig } => {
                        eprintln!("NET-TRACE host: guest agreed"); // TEMP-DIAG
                        sig
                    }
                    _ => {
                        note(
                            core,
                            generation,
                            NetNote::Error("genesis agreement malformed".to_string()),
                        );
                        return Err(());
                    }
                };
            if !is_current(core, generation) {
                return Err(());
            }
            for command in [
                Command::NotePeerJoined {
                    peer: guest,
                    co_sig,
                },
                Command::NotePeerReady { peer: guest },
                Command::SetReady { peer: me },
            ] {
                if apply(core, command).is_err() {
                    note(
                        core,
                        generation,
                        NetNote::Error("guest arrival rejected".to_string()),
                    );
                    return Err(());
                }
            }
            if conn.send(&Msg::Ready { peer: me }).await.is_err() {
                eprintln!("NET-TRACE host: ready send failed"); // TEMP-DIAG
                note(core, generation, NetNote::Disconnected);
                return Err(());
            }
            eprintln!("NET-TRACE host: ready sent, handshake done"); // TEMP-DIAG
            Ok(())
        }
        Role::Guest => {
            let genesis =
                match recv_handshake(core, conn, "waiting for the host hello", generation).await? {
                    Msg::Hello { version, genesis } if version == PROTOCOL_VERSION => {
                        eprintln!("NET-TRACE guest: hello received"); // TEMP-DIAG
                        genesis
                    }
                    _ => {
                        note(
                            core,
                            generation,
                            NetNote::Error("hello rejected".to_string()),
                        );
                        return Err(());
                    }
                };
            if !is_current(core, generation) {
                return Err(());
            }
            {
                let mut guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
                guard.app = Some(App::with_local(secret));
            }
            if apply(
                core,
                Command::JoinGame {
                    peer: me,
                    genesis: Box::new(genesis),
                },
            )
            .is_err()
            {
                note(
                    core,
                    generation,
                    NetNote::Error("join rejected".to_string()),
                );
                return Err(());
            }
            note(core, generation, NetNote::Connected(me.to_string()));
            if apply(core, Command::SetReady { peer: me }).is_err() {
                note(
                    core,
                    generation,
                    NetNote::Error("readiness rejected".to_string()),
                );
                return Err(());
            }
            if conn.send(&Msg::Ready { peer: me }).await.is_err() {
                eprintln!("NET-TRACE guest: ready send failed"); // TEMP-DIAG
                note(core, generation, NetNote::Disconnected);
                return Err(());
            }
            eprintln!("NET-TRACE guest: ready sent"); // TEMP-DIAG
            let Some(agreed) = tip_entry(core).filter(|entry| entry.seq == 0) else {
                note(
                    core,
                    generation,
                    NetNote::Error("genesis missing".to_string()),
                );
                return Err(());
            };
            let Some(co_sig) = agreed.co_sig else {
                note(
                    core,
                    generation,
                    NetNote::Error("genesis agreement missing".to_string()),
                );
                return Err(());
            };
            if conn
                .send(&Msg::Agreed {
                    seq: 0,
                    sig: co_sig,
                })
                .await
                .is_err()
            {
                eprintln!("NET-TRACE guest: agreed send failed"); // TEMP-DIAG
                note(core, generation, NetNote::Disconnected);
                return Err(());
            }
            eprintln!("NET-TRACE guest: agreed sent"); // TEMP-DIAG
            match recv_handshake(
                core,
                conn,
                "waiting for the host to start the game",
                generation,
            )
            .await?
            {
                Msg::Ready { peer } => {
                    eprintln!("NET-TRACE guest: host ready, handshake done"); // TEMP-DIAG
                    if !is_current(core, generation) {
                        return Err(());
                    }
                    if apply(core, Command::NotePeerReady { peer }).is_err() {
                        note(
                            core,
                            generation,
                            NetNote::Error("host readiness rejected".to_string()),
                        );
                        return Err(());
                    }
                }
                _ => {
                    note(
                        core,
                        generation,
                        NetNote::Error("host readiness malformed".to_string()),
                    );
                    return Err(());
                }
            }
            Ok(())
        }
    }
}

/// Session loop after the handshake: local progress flushes unsent log
/// entries to the peer, remote entries ingest and agree back, and
/// agreements complete our moves. A closed command channel (retired
/// network) or a dead connection ends the loop.
async fn drive_session<C: Connection>(
    core: Arc<Mutex<CoreState>>,
    mut conn: C,
    mut cmd_rx: tokio::sync::mpsc::UnboundedReceiver<NetCmd>,
    generation: u64,
) {
    // Genesis travels in hello/join, never as an entry.
    let mut sent_seq = 1u64;
    loop {
        tokio::select! {
            cmd = cmd_rx.recv() => {
                match cmd {
                    Some(NetCmd::Flush) => {
                        if flush_unsent(&core, &mut conn, &mut sent_seq, generation)
                            .await
                            .is_err()
                        {
                            note(&core, generation, NetNote::Disconnected);
                            return;
                        }
                    }
                    None => return,
                }
            }
            msg = conn.recv() => {
                match msg {
                    Ok(msg) => {
                        if on_msg(&core, &mut conn, msg, generation).await.is_err() {
                            return;
                        }
                    }
                    Err(_) => {
                        note(&core, generation, NetNote::Disconnected);
                        return;
                    }
                }
            }
        }
    }
}

/// Sends every log entry the peer has not seen yet.
async fn flush_unsent<C: Connection>(
    core: &Arc<Mutex<CoreState>>,
    conn: &mut C,
    sent_seq: &mut u64,
    generation: u64,
) -> Result<(), ()> {
    let pending: Vec<LogEntry> = {
        let guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        if guard.net_generation != generation {
            return Err(());
        }
        match guard.app.as_ref().map(|app| app.query(&Query::MoveLog)) {
            Some(Ok(QueryResult::MoveLog(entries))) => entries
                .into_iter()
                .filter(|entry| entry.seq >= *sent_seq)
                .collect(),
            _ => Vec::new(),
        }
    };
    for entry in &pending {
        if conn.send(&Msg::Entry(*entry)).await.is_err() {
            return Err(());
        }
        *sent_seq = entry.seq + 1;
    }
    Ok(())
}

/// One incoming message: entries ingest and agree back, agreements
/// complete our moves, readiness is advisory after the handshake, and
/// a clean end reads as a disconnect. Hello, tips, and final positions
/// belong to future slices and wait out this one ignored.
async fn on_msg<C: Connection>(
    core: &Arc<Mutex<CoreState>>,
    conn: &mut C,
    msg: Msg,
    generation: u64,
) -> Result<(), ()> {
    match msg {
        Msg::Entry(entry) => {
            enum Ingest {
                Agree(u64, [u8; 64]),
                Reject(String),
                Stale,
            }
            let outcome = {
                let mut guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
                if guard.net_generation != generation {
                    Ingest::Stale
                } else {
                    match guard.app.as_mut() {
                        None => Ingest::Reject("no session".to_string()),
                        Some(app) => match app.ingest_remote(&entry) {
                            Ok(()) => {
                                let mut events = app.drain();
                                let agreed = match app.query(&Query::MoveLog) {
                                    Ok(QueryResult::MoveLog(entries)) => entries
                                        .last()
                                        .and_then(|tip| tip.co_sig.map(|sig| (tip.seq, sig))),
                                    _ => None,
                                };
                                guard.outbox.extend(events.drain(..));
                                match agreed {
                                    Some((seq, sig)) => Ingest::Agree(seq, sig),
                                    None => Ingest::Reject("agreement missing".to_string()),
                                }
                            }
                            Err(err) => {
                                let rejected = app.drain();
                                guard.outbox.extend(rejected);
                                Ingest::Reject(err.to_string())
                            }
                        },
                    }
                }
            };
            match outcome {
                Ingest::Stale => Err(()),
                Ingest::Reject(reason) => {
                    note(core, generation, NetNote::Error(reason));
                    Err(())
                }
                Ingest::Agree(seq, sig) => {
                    if conn.send(&Msg::Agreed { seq, sig }).await.is_err() {
                        note(core, generation, NetNote::Disconnected);
                        return Err(());
                    }
                    Ok(())
                }
            }
        }
        Msg::Agreed { seq, sig } => {
            if !is_current(core, generation) {
                return Err(());
            }
            match apply(core, Command::NoteMoveAgreed { seq, co_sig: sig }) {
                Ok(()) => Ok(()),
                Err(reason) => {
                    note(core, generation, NetNote::Error(reason));
                    Err(())
                }
            }
        }
        Msg::Ready { peer } => {
            if !is_current(core, generation) {
                return Err(());
            }
            let _ = apply(core, Command::NotePeerReady { peer });
            Ok(())
        }
        Msg::Done => {
            note(core, generation, NetNote::Disconnected);
            Err(())
        }
        Msg::Hello { .. } | Msg::Tip { .. } | Msg::Fen { .. } => Ok(()),
    }
}

/// UI-sized transport failure: the full error carries a backtrace meant
/// for logs, never for a phone screen.
fn short_error(err: &TransportError) -> String {
    if err.is_unavailable() {
        "peer unavailable".to_string()
    } else if err.is_closed() {
        "connection closed".to_string()
    } else {
        "undecodable frame".to_string()
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::transport::MemoryTransport;

    fn peer_of(seed: [u8; 32]) -> PeerId {
        PeerId::of(&SigningKey::from_bytes(&seed))
    }

    async fn poll_until(condition: impl Fn() -> bool) {
        tokio::time::timeout(Duration::from_secs(10), async {
            while !condition() {
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
        })
        .await
        .expect("condition met in time");
    }

    fn has_game_started(core: &Arc<Mutex<CoreState>>) -> bool {
        core.lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .outbox
            .iter()
            .any(|event| matches!(event, Event::GameStarted))
    }

    fn has_move_agreed(core: &Arc<Mutex<CoreState>>, seq: u64) -> bool {
        core.lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .outbox
            .iter()
            .any(|event| matches!(event, Event::MoveAgreed { seq: want } if *want == seq))
    }

    fn move_log_len(core: &Arc<Mutex<CoreState>>) -> usize {
        match core
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .app
            .as_ref()
            .map(|app| app.query(&Query::MoveLog))
        {
            Some(Ok(QueryResult::MoveLog(entries))) => entries.len(),
            _ => 0,
        }
    }

    fn fen_of(core: &Arc<Mutex<CoreState>>) -> String {
        match core
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .app
            .as_ref()
            .map(|app| app.query(&Query::GameState))
        {
            Some(Ok(QueryResult::GameState(view))) => view.fen,
            _ => String::new(),
        }
    }

    /// Handshake plus one move across memory links: both sides start
    /// play, the host's pawn push reaches the guest, and the guest's
    /// agreement completes the host's move with identical positions.
    #[tokio::test]
    async fn session_drives_handshake_and_move_over_memory() {
        let hub = MemoryTransport::new();
        let mut host_ep = hub.endpoint();
        let mut guest_ep = hub.endpoint();
        let ticket = host_ep.ticket();
        let guest_conn = guest_ep.connect(&ticket).await.unwrap();
        let host_conn = host_ep.accept().await.unwrap();

        let host_core = Arc::new(Mutex::new(CoreState::default()));
        let guest_core = Arc::new(Mutex::new(CoreState::default()));
        host_core.lock().unwrap().net_generation = 1;
        guest_core.lock().unwrap().net_generation = 1;
        let (host_tx, host_rx) = tokio::sync::mpsc::unbounded_channel();
        let (guest_tx, guest_rx) = tokio::sync::mpsc::unbounded_channel();

        let host_seed = [7u8; 32];
        let guest_seed = [9u8; 32];
        let guest_peer = peer_of(guest_seed);

        let host_task = tokio::spawn({
            let core = Arc::clone(&host_core);
            async move {
                let mut conn = host_conn;
                if handshake(&core, &mut conn, Role::Host, host_seed, Some(guest_peer), 1)
                    .await
                    .is_ok()
                {
                    drive_session(core, conn, host_rx, 1).await;
                }
            }
        });
        let guest_task = tokio::spawn({
            let core = Arc::clone(&guest_core);
            async move {
                let mut conn = guest_conn;
                if handshake(&core, &mut conn, Role::Guest, guest_seed, None, 1)
                    .await
                    .is_ok()
                {
                    drive_session(core, conn, guest_rx, 1).await;
                }
            }
        });

        poll_until(|| has_game_started(&host_core) && has_game_started(&guest_core)).await;
        assert_eq!(fen_of(&host_core), fen_of(&guest_core));
        assert!(!fen_of(&host_core).is_empty());

        {
            let mut guard = host_core
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            let app = guard.app.as_mut().expect("host session live");
            let events = app
                .handle(&Command::SubmitMove {
                    peer: peer_of(host_seed),
                    mv: "e2e4".parse().unwrap(),
                })
                .expect("host pawn push legal");
            let mut all = events;
            all.extend(app.drain());
            guard.outbox.extend(all);
        }
        host_tx.send(NetCmd::Flush).unwrap();
        poll_until(|| move_log_len(&host_core) == 2 && move_log_len(&guest_core) == 2).await;
        poll_until(|| has_move_agreed(&host_core, 1)).await;
        assert_eq!(fen_of(&host_core), fen_of(&guest_core));
        assert!(fen_of(&guest_core).contains("4P3/8"));

        drop(host_tx);
        drop(guest_tx);
        tokio::time::timeout(Duration::from_secs(5), host_task)
            .await
            .expect("host driver exits")
            .unwrap();
        tokio::time::timeout(Duration::from_secs(5), guest_task)
            .await
            .expect("guest driver exits")
            .unwrap();
    }

    /// Retiring with a link task pending on accept must return: the
    /// shutdown runs with no CoreState guard held, so the task tail can
    /// take the lock, go silent on the generation gate, and exit.
    /// (Holding the guard across shutdown deadlocked the scene thread.)
    /// Sync test, like production: the scene thread blocks from outside
    /// any runtime.
    #[test]
    fn retire_completes_with_pending_accept() {
        let core = Arc::new(Mutex::new(CoreState::default()));
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .unwrap();
        let endpoint = runtime
            .block_on(crate::IrohEndpoint::bind_with_seed([11u8; 32]))
            .unwrap();
        let (cmd_tx, cmd_rx) = tokio::sync::mpsc::unbounded_channel();
        let spawner = runtime.handle().clone();
        {
            let mut guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
            guard.net_generation = 1;
            guard.net = Some(NetState {
                runtime,
                endpoint: endpoint.clone(),
                cmd_tx,
            });
        }
        spawner.spawn(accept_task(core.clone(), endpoint, [11u8; 32], 1, cmd_rx));
        std::thread::sleep(Duration::from_millis(200));
        let old = {
            let mut guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
            begin_retire(&mut guard)
        };
        let (done_tx, done_rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            finish_retire(old);
            let _ = done_tx.send(());
        });
        done_rx
            .recv_timeout(Duration::from_secs(15))
            .expect("retire returns with a pending accept");
    }
}
