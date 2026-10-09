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
use crate::session::{FinishReason, LogEntry, LogStore, PeerId, RecentPeerStore, SessionState};
use crate::transport::{Connection, Endpoint as _, TransportError, TransportQuality};
use crate::transport_iroh::ticket_peer_id;
use ed25519_dalek::{Signer, SigningKey};
use godot::prelude::*;
use sha2::{Digest, Sha256};
use std::collections::{HashMap, VecDeque};
use std::str::FromStr;
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Arc, Mutex, MutexGuard};
use std::thread::JoinHandle;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const LOCAL_SPIKE_LABEL: &[u8] = b"chess-relay/local-spike/v1";
const AI_SPIKE_LABEL: &[u8] = b"chess-relay/local-ai/v1";

/// Everything the bridge shares between the scene thread and (later)
/// network tasks. Always accessed through [`ChessRelayBridge::lock`],
/// never held across signal emission or `.await`.
#[derive(Default)]
struct CoreState {
    app: Option<App>,
    /// This device's peer. Set at start/join; the spike flow defaults it.
    me: PeerId,
    /// Connected remote peer, if any.
    remote_peer: Option<PeerId>,
    /// Peer whose invitation was accepted into a game session on this
    /// network. A redial from this peer skips the invite handshake and
    /// resumes the game session directly (AUDIT-INVITE-RECONNECT-001).
    /// Cleared on every network start; the generation gate retires
    /// in-flight users.
    game_peer: Option<PeerId>,
    offer_by: Option<PeerId>,
    save_path: Option<String>,
    profile_path: Option<std::path::PathBuf>,
    display_name: Option<String>,
    recent_peers_path: Option<std::path::PathBuf>,
    outbox: VecDeque<Event>,
    net: Option<NetState>,
    net_notes: VecDeque<NetNote>,
    network_setup: Option<NetworkSetup>,
    next_setup_revision: u64,
    network_snapshot: NetworkSnapshot,
    network_peer_loaded: bool,
    ai: Option<AiState>,
    /// Bumped on every host/join/leave so late tasks from a retired
    /// network go silent instead of emitting stale signals.
    net_generation: u64,
    next_invite_id: u64,
    presence: HashMap<PeerId, PeerPresence>,
    pending_invite: Option<PendingInvite>,
    remote_left: bool,
    local_secret: Option<SigningKey>,
    next_rematch_id: u64,
    pending_rematch: Option<(u64, PeerId)>,
    outgoing_rematch: Option<u64>,
    rematch_host: bool,
    rematch_generation: u64,
}

/// Presence is a live observation owned by the Rust bridge, never inferred by
/// Godot from a saved ticket or timestamp.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum PeerPresence {
    Unknown,
    Online,
    Offline,
}

impl PeerPresence {
    fn as_str(self) -> &'static str {
        match self {
            Self::Unknown => "unknown",
            Self::Online => "online",
            Self::Offline => "offline",
        }
    }
}

struct PendingInvite {
    invite_id: u64,
    response: tokio::sync::oneshot::Sender<bool>,
}

/// Durable transport observation consumed by every UI surface. Quality is
/// peer-path quality, not device radio RSSI.
#[derive(Clone, Debug, PartialEq, Eq)]
struct NetworkSnapshot {
    lifecycle: String,
    level: i64,
    rtt_ms: i64,
    loss_percent: i64,
    direct: bool,
}

impl Default for NetworkSnapshot {
    fn default() -> Self {
        Self {
            lifecycle: "idle".to_string(),
            level: 0,
            rtt_ms: -1,
            loss_percent: -1,
            direct: false,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct NetworkSetup {
    revision: u64,
    side: String,
    time: String,
    variant: String,
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
    /// Published host invitation, if this network owns one.
    invite_code: Option<String>,
}

/// Driver input: local progress or lifecycle events worth sending to the peer.
#[derive(Debug)]
enum NetCmd {
    UpdateSetup {
        revision: u64,
        side: String,
        time: String,
        variant: String,
    },
    Loaded,
    HostStarted {
        genesis: Box<LogEntry>,
        revision: u64,
        side: String,
        time: String,
        variant: String,
    },
    SendReady,
    Flush,
    Leave {
        acknowledged: tokio::sync::oneshot::Sender<()>,
    },
    RematchRequest {
        rematch_id: u64,
    },
    RematchResponse {
        rematch_id: u64,
        accepted: bool,
    },
}

/// A live network handoff: everything a link task needs after setup.
struct NetLaunch {
    endpoint: crate::IrohEndpoint,
    generation: u64,
    cmd_rx: tokio::sync::mpsc::UnboundedReceiver<NetCmd>,
}

/// Facts from network tasks for the scene thread to announce.
#[derive(Debug)]
enum NetNote {
    Connected(PeerId),
    PeerAddress {
        peer: PeerId,
        ticket: String,
    },
    IncomingInvite {
        invite_id: u64,
        peer: PeerId,
        response: tokio::sync::oneshot::Sender<bool>,
    },
    IncomingInviteReady {
        invite_id: u64,
        peer: PeerId,
    },
    InviteAccepted {
        invite_id: u64,
        peer: PeerId,
    },
    InviteDeclined {
        invite_id: u64,
        peer: PeerId,
    },
    PeerOffline(PeerId),
    PeerLeft,
    IncomingRematch {
        rematch_id: u64,
        peer: PeerId,
    },
    RematchResult {
        rematch_id: u64,
        peer: PeerId,
        accepted: bool,
        host: bool,
    },
    Reconnecting,
    Quality {
        level: u8,
        rtt_ms: u32,
        loss_percent: u8,
        direct: bool,
    },
    Setup {
        side: String,
        time: String,
        variant: String,
    },
    PeerLoaded,
    /// Slice C pushes this when its driver sees the peer go away.
    #[allow(dead_code)]
    Disconnected,
    Error(String),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum AcceptMode {
    Game,
    Invite,
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

    fn load_profile(&self, identity_path: &str) -> Result<(), String> {
        let path = profile_path(identity_path);
        let name = load_profile_name(&path)?;
        let mut core = self.lock();
        core.profile_path = Some(path);
        core.display_name = name;
        Ok(())
    }
}

#[godot_api]
impl ChessRelayBridge {
    #[signal]
    fn session_created(white: GString, black: GString, host: GString);
    #[signal]
    fn ready_changed(peer: GString);
    #[signal]
    fn setup_changed(side: GString, time: GString, variant: GString);
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
    /// Structured terminal fact, emitted alongside `game_ended`. Keys:
    /// `reason` (resignation/checkmate/agreed_draw/draw/stalemate/abort/
    /// ongoing), `actor/winner/loser_peer` + `actor/winner/loser_name`,
    /// `winner_side`/`loser_side` (white/black/""), `local_peer`,
    /// `local_won` (bool), `white_name`, `black_name`. Names resolve
    /// through the profile authority; identity through peer IDs. Terminal
    /// and replayable as a snapshot: a late subscriber reads the same
    /// values from the finished session.
    #[signal]
    fn game_result(result: Dictionary<GString, Variant>);
    #[signal]
    fn bridge_error(message: GString);
    #[signal]
    fn peer_connected(peer: GString);
    #[signal]
    fn incoming_invite(invite_id: i64, peer: GString);
    #[signal]
    fn invite_result(invite_id: i64, accepted: bool, peer: GString);
    #[signal]
    fn peer_presence(peer: GString, status: GString);
    #[signal]
    fn peer_left();
    #[signal]
    fn incoming_rematch(rematch_id: i64, peer: GString);
    #[signal]
    fn rematch_result(rematch_id: i64, accepted: bool, peer: GString, host: bool);
    #[signal]
    fn network_reconnecting();
    #[signal]
    fn network_quality(level: i64, rtt_ms: i64, loss_percent: i64, direct: bool);
    #[signal]
    fn network_snapshot_changed(
        lifecycle: GString,
        level: i64,
        rtt_ms: i64,
        loss_percent: i64,
        direct: bool,
    );
    #[signal]
    fn peer_disconnected();
    #[signal]
    fn peer_loaded();
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
        let mut seed = [0u8; 32];
        if let Err(err) = getrandom::getrandom(&mut seed) {
            self.emit_error(&format!("could not create local spike identity: {err}"));
            return;
        }
        let local_key = SigningKey::from_bytes(&seed);
        let peer_key = derive_role_key(&seed, LOCAL_SPIKE_LABEL);
        let (events, errors) = {
            let mut core = self.lock();
            start_fresh(&mut core, local_key, peer_key)
        };
        self.emit_all(&events);
        for message in &errors {
            self.emit_error(message);
        }
    }

    /// Starts with a persistent identity, resuming the saved game if any
    /// unless `fresh` explicitly requests a new match.
    ///
    /// Loads the local seed from `identity_path` (generating and saving
    /// one on first run), then restores the log at `save_path` when it
    /// holds an in-progress session. Finished logs are stale for
    /// resume-for-play and are purged before a fresh session is created.
    /// Returns true when a saved game resumed. Paths come from the platform
    /// (`user://` resolved by Godot); this layer only reads and writes bytes.
    #[func]
    fn start_resumable(&mut self, identity_path: String, save_path: String, fresh: bool) -> bool {
        let seed = match load_or_create_seed(&identity_path) {
            Ok(seed) => seed,
            Err(err) => {
                self.emit_error(&err.to_string());
                return false;
            }
        };
        if let Err(err) = self.load_profile(&identity_path) {
            self.emit_error(&err);
            return false;
        }
        if fresh && let Err(err) = clear_saved_game(&save_path) {
            self.emit_error(&err.to_string());
            return false;
        }
        // Same local peer model as start(): one device plays both sides until
        // transport arrives. Only the local identity persists; the peer role
        // is derived, never a committed identity.
        let local_key = SigningKey::from_bytes(&seed);
        let peer_key = derive_role_key(&seed, LOCAL_SPIKE_LABEL);
        let (restored, events, stale_finished) = {
            let mut core = self.lock();
            core.save_path = Some(save_path.clone());
            let mut app = App::with_local(local_key.clone());
            app.admit(peer_key.clone());
            match (!fresh)
                .then(|| crate::session::FileStore::new(std::path::Path::new(&save_path)).load())
            {
                Some(Ok(entries)) if !entries.is_empty() => match app.restore(entries) {
                    Ok(events) if !contains_game_end(&events) => {
                        core.app = Some(app);
                        core.me = PeerId::of(&local_key);
                        (true, events, false)
                    }
                    Ok(_) => (false, Vec::new(), true),
                    Err(_) => (false, Vec::new(), false),
                },
                _ => (false, Vec::new(), false),
            }
        };
        if stale_finished && let Err(err) = clear_saved_game(&save_path) {
            self.emit_error(&err.to_string());
            return false;
        }
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
        fresh: bool,
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
        if let Err(err) = self.load_profile(&identity_path) {
            self.emit_error(&err);
            return false;
        }
        if fresh && let Err(err) = clear_saved_game(&save_path) {
            self.emit_error(&err.to_string());
            return false;
        }
        let local_key = SigningKey::from_bytes(&seed);
        let ai_key = derive_role_key(&seed, AI_SPIKE_LABEL);
        let local_peer = PeerId::of(&local_key);
        let ai_peer = PeerId::of(&ai_key);
        let difficulty = parse_difficulty(&difficulty.to_string());
        let side = side.to_string();
        let local_is_black = side.eq_ignore_ascii_case("black")
            || (side.eq_ignore_ascii_case("random") && local_peer.bytes()[0] & 1 == 1);
        let (events, errors, restored, stale_finished) = {
            let mut core = self.lock();
            core.save_path = Some(save_path.clone());
            let mut app = App::with_local(local_key.clone());
            app.admit(ai_key.clone());
            let restored_events = (!fresh).then(|| {
                crate::session::FileStore::new(std::path::Path::new(&save_path))
                    .load()
                    .ok()
                    .filter(|entries| !entries.is_empty())
                    .and_then(|entries| app.restore(entries).ok())
            });
            let restored_events = restored_events.flatten();
            match restored_events {
                Some(events) if !contains_game_end(&events) => {
                    core.app = Some(app);
                    core.me = local_peer;
                    (events, Vec::new(), true, false)
                }
                Some(_) => (Vec::new(), Vec::new(), false, true),
                None => {
                    let (events, errors) =
                        start_ai_fresh(&mut core, app, local_key, ai_key, local_is_black);
                    (events, errors, false, false)
                }
            }
        };
        if stale_finished && let Err(err) = clear_saved_game(&save_path) {
            self.emit_error(&err.to_string());
            return false;
        }
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

    /// Hosts a networked game: loads the installation identity, binds one
    /// endpoint from it, publishes a short invitation code, and returns that
    /// code. Accept runs in the
    /// background; the guest's arrival surfaces as `peer_connected`.
    /// The handshake that starts play on the wire is slice C.
    #[func]
    fn host_game(&mut self, identity_path: String) -> GString {
        let seed = match load_or_create_seed(&identity_path) {
            Ok(seed) => seed,
            Err(err) => {
                self.emit_error(&err.to_string());
                return GString::new();
            }
        };
        if let Err(err) = self.load_profile(&identity_path) {
            self.emit_error(&err);
            return GString::new();
        }
        let old = {
            let mut core = self.lock();
            begin_retire(&mut core)
        };
        finish_retire(old);
        let launch = {
            let mut core = self.lock();
            match start_network(&mut core, seed, recent_peers_path(&identity_path)) {
                Ok(launch) => launch,
                Err(message) => {
                    drop(core);
                    self.emit_error(&message);
                    return GString::new();
                }
            }
        };
        let ticket = launch.endpoint.ticket();
        let ticket = match iroh_tickets::endpoint::EndpointTicket::from_str(&ticket) {
            Ok(ticket) => ticket,
            Err(_) => {
                self.leave_network();
                self.emit_error("host ticket could not be encoded");
                return GString::new();
            }
        };
        let endpoint_id = launch.endpoint.id_bytes();
        let code = invite_code_from_endpoint_id(&endpoint_id);
        let publisher = {
            let core = self.lock();
            core.net.as_ref().map(|net| net.runtime.handle().clone())
        };
        let Some(publisher) = publisher else {
            self.leave_network();
            self.emit_error("host network disappeared");
            return GString::new();
        };
        if publisher
            .block_on(crate::publish_once(&code, &ticket))
            .is_err()
        {
            self.leave_network();
            self.emit_error("invite code could not be published");
            return GString::new();
        }
        publisher.spawn(crate::publish_loop(code.clone(), ticket));
        {
            let mut core = self.lock();
            if let Some(net) = core.net.as_mut() {
                net.invite_code = Some(code.clone());
            }
        }
        {
            let core = self.lock();
            if let Some(net) = core.net.as_ref() {
                net.runtime.spawn(accept_task(
                    Arc::clone(&self.core),
                    launch.endpoint,
                    launch.generation,
                    launch.cmd_rx,
                    AcceptMode::Game,
                ));
            }
        }
        GString::from(&code)
    }

    /// Joins a networked game by resolving its short rendezvous code in the
    /// background. Returns false only when setup fails
    /// outright; dial success or failure surfaces as `peer_connected`
    /// or `network_error`.
    #[func]
    fn join_game(&mut self, ticket: GString, identity_path: String) -> bool {
        let ticket = ticket.to_string();
        if ticket.is_empty() {
            self.emit_error("empty invite code");
            return false;
        }
        let seed = match load_or_create_seed(&identity_path) {
            Ok(seed) => seed,
            Err(err) => {
                self.emit_error(&err.to_string());
                return false;
            }
        };
        if let Err(err) = self.load_profile(&identity_path) {
            self.emit_error(&err);
            return false;
        }
        let old = {
            let mut core = self.lock();
            begin_retire(&mut core)
        };
        finish_retire(old);
        let launch = {
            let mut core = self.lock();
            match start_network(&mut core, seed, recent_peers_path(&identity_path)) {
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
                    launch.generation,
                    launch.cmd_rx,
                ));
            }
        }
        true
    }

    /// Keeps a network endpoint listening in the multiplayer hub so a saved
    /// peer can reach this installation with an invitation.
    #[func]
    fn start_presence(&mut self, identity_path: String) -> bool {
        let seed = match load_or_create_seed(&identity_path) {
            Ok(seed) => seed,
            Err(err) => {
                self.emit_error(&err.to_string());
                return false;
            }
        };
        if let Err(err) = self.load_profile(&identity_path) {
            self.emit_error(&err);
            return false;
        }
        let old = {
            let mut core = self.lock();
            begin_retire(&mut core)
        };
        finish_retire(old);
        let launch = {
            let mut core = self.lock();
            match start_network(&mut core, seed, recent_peers_path(&identity_path)) {
                Ok(launch) => launch,
                Err(message) => {
                    drop(core);
                    self.emit_error(&message);
                    return false;
                }
            }
        };
        let core = self.lock();
        if let Some(net) = core.net.as_ref() {
            net.runtime.spawn(accept_task(
                Arc::clone(&self.core),
                launch.endpoint,
                launch.generation,
                launch.cmd_rx,
                AcceptMode::Invite,
            ));
            true
        } else {
            false
        }
    }

    /// Dials a saved peer ticket and sends a new game invitation.
    #[func]
    fn invite_peer(&mut self, ticket: GString, identity_path: String) -> bool {
        let ticket = ticket.to_string();
        if ticket.is_empty() {
            self.emit_error("selected peer has no usable endpoint ticket");
            return false;
        }
        let seed = match load_or_create_seed(&identity_path) {
            Ok(seed) => seed,
            Err(err) => {
                self.emit_error(&err.to_string());
                return false;
            }
        };
        if let Err(err) = self.load_profile(&identity_path) {
            self.emit_error(&err);
            return false;
        }
        let old = {
            let mut core = self.lock();
            begin_retire(&mut core)
        };
        finish_retire(old);
        let launch = {
            let mut core = self.lock();
            match start_network(&mut core, seed, recent_peers_path(&identity_path)) {
                Ok(launch) => launch,
                Err(message) => {
                    drop(core);
                    self.emit_error(&message);
                    return false;
                }
            }
        };
        let invite_id = {
            let mut core = self.lock();
            core.next_invite_id = core.next_invite_id.wrapping_add(1).max(1);
            core.next_invite_id
        };
        let core = self.lock();
        if let Some(net) = core.net.as_ref() {
            net.runtime.spawn(invite_task(
                Arc::clone(&self.core),
                launch.endpoint,
                ticket,
                invite_id,
                launch.generation,
                launch.cmd_rx,
            ));
            true
        } else {
            false
        }
    }

    /// Answers the one currently displayed incoming invitation.
    #[func]
    fn respond_to_invite(&mut self, invite_id: i64, accepted: bool) -> bool {
        let invite_id = match u64::try_from(invite_id) {
            Ok(value) => value,
            Err(_) => return false,
        };
        let pending = {
            let mut core = self.lock();
            let matches = core
                .pending_invite
                .as_ref()
                .is_some_and(|pending| pending.invite_id == invite_id);
            if matches {
                core.pending_invite.take()
            } else {
                None
            }
        };
        let Some(pending) = pending else {
            self.emit_error("invitation is no longer pending");
            return false;
        };
        pending.response.send(accepted).is_ok()
    }

    /// Requests a fresh game over the still-authenticated peer connection.
    #[func]
    fn request_rematch(&mut self) -> bool {
        let (tx, rematch_id) = {
            let mut core = self.lock();
            let tx = match can_request_rematch(&core) {
                Ok(tx) => tx,
                Err(message) => {
                    drop(core);
                    self.emit_error(message);
                    return false;
                }
            };
            core.next_rematch_id = core.next_rematch_id.wrapping_add(1).max(1);
            let rematch_id = core.next_rematch_id;
            core.outgoing_rematch = Some(rematch_id);
            core.rematch_host = true;
            (tx, rematch_id)
        };
        if tx.send(NetCmd::RematchRequest { rematch_id }).is_err() {
            self.emit_error("network connection closed");
            return false;
        }
        true
    }

    /// Answers the currently displayed rematch request.
    #[func]
    fn respond_to_rematch(&mut self, rematch_id: i64, accepted: bool) -> bool {
        let rematch_id = match u64::try_from(rematch_id) {
            Ok(value) => value,
            Err(_) => return false,
        };
        let response = {
            let mut core = self.lock();
            if let Some(message) = rematch_response_error(&core, rematch_id, accepted) {
                Err(message)
            } else if let (Some((_, peer)), Some(tx)) = (
                core.pending_rematch,
                core.net.as_ref().map(|net| net.cmd_tx.clone()),
            ) {
                core.pending_rematch = None;
                if accepted {
                    reset_for_rematch(&mut core, false);
                }
                Ok((tx, peer))
            } else {
                // Unreachable: the predicate above already required a
                // matching pending request and a live network.
                Err("rematch is no longer pending")
            }
        };
        let (tx, peer) = match response {
            Ok(value) => value,
            Err(message) => {
                self.emit_error(message);
                return false;
            }
        };
        if tx
            .send(NetCmd::RematchResponse {
                rematch_id,
                accepted,
            })
            .is_err()
        {
            return false;
        }
        if accepted {
            let generation = self.lock().net_generation;
            note(
                &self.core,
                generation,
                NetNote::RematchResult {
                    rematch_id,
                    peer,
                    accepted: true,
                    host: false,
                },
            );
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

    /// Starts the networked game as host with the chosen side ("white", "black", "random").
    /// Creates the genesis session and notifies the session driver.
    #[func]
    fn start_network_game(&mut self, side: GString, time: GString, variant: GString) -> bool {
        let (events, genesis, revision) = {
            let mut core = self.lock();
            if core.net.is_none() {
                drop(core);
                self.emit_error("no network active");
                return false;
            }
            let me = core.me;
            let Some(guest) = core.remote_peer else {
                drop(core);
                self.emit_error("no guest connected");
                return false;
            };
            let revision = core
                .network_setup
                .as_ref()
                .map_or(0, |setup| setup.revision);
            let side_str = side.to_string().to_lowercase();
            let (white, black) = match side_str.as_str() {
                "black" => (guest, me),
                "random" => {
                    let mut buf = [0u8; 1];
                    let _ = getrandom::getrandom(&mut buf);
                    if buf[0] % 2 == 0 {
                        (me, guest)
                    } else {
                        (guest, me)
                    }
                }
                _ => (me, guest),
            };
            let Some(app) = core.app.as_mut() else {
                drop(core);
                self.emit_error("no app state");
                return false;
            };
            let events = match app.handle(&Command::StartGame { white, black }) {
                Ok(ev) => ev,
                Err(err) => {
                    let msg = err.to_string();
                    drop(core);
                    self.emit_error(&msg);
                    return false;
                }
            };
            let genesis = match app.query(&Query::MoveLog) {
                Ok(QueryResult::MoveLog(entries)) => entries.first().copied(),
                _ => None,
            };
            let Some(genesis) = genesis else {
                drop(core);
                self.emit_error("failed to create genesis");
                return false;
            };
            (events, genesis, revision)
        };
        self.emit_all(&events);
        if let Some(tx) = self.lock().net.as_ref().map(|n| n.cmd_tx.clone()) {
            let _ = tx.send(NetCmd::HostStarted {
                genesis: Box::new(genesis),
                revision,
                side: side.to_string(),
                time: time.to_string(),
                variant: variant.to_string(),
            });
        }
        true
    }

    /// Announces that this device's network game screen is loaded. The board
    /// remains hidden until the peer sends the same fact.
    #[func]
    fn mark_network_loaded(&mut self) -> bool {
        let Some(tx) = self.lock().net.as_ref().map(|net| net.cmd_tx.clone()) else {
            self.emit_error("no network active");
            return false;
        };
        if tx.send(NetCmd::Loaded).is_err() {
            self.emit_error("network connection closed");
            return false;
        }
        true
    }

    /// Snapshot for screens that subscribe after the peer-loaded signal.
    #[func]
    fn network_peer_loaded(&self) -> bool {
        self.lock().network_peer_loaded
    }

    /// Publishes the host's current lobby choices. This is metadata only:
    /// the core still starts standard chess without an authoritative clock.
    #[func]
    fn update_network_setup(&mut self, side: GString, time: GString, variant: GString) -> bool {
        if variant != "Standard" {
            self.emit_error("unsupported network variant");
            return false;
        }
        let revision = {
            let mut core = self.lock();
            core.next_setup_revision = core.next_setup_revision.saturating_add(1);
            core.next_setup_revision
        };
        let setup = NetworkSetup {
            revision,
            side: side.to_string(),
            time: time.to_string(),
            variant: variant.to_string(),
        };
        let tx = {
            let mut core = self.lock();
            if core.net.is_none() {
                drop(core);
                self.emit_error("no network active");
                return false;
            }
            core.network_setup = Some(setup.clone());
            core.net.as_ref().map(|net| net.cmd_tx.clone())
        };
        if let Some(tx) = tx
            && tx
                .send(NetCmd::UpdateSetup {
                    revision: setup.revision,
                    side: setup.side,
                    time: setup.time,
                    variant: setup.variant,
                })
                .is_err()
        {
            self.emit_error("network connection closed");
            return false;
        }
        true
    }

    /// Returns the last host-owned lobby snapshot, or an empty array before
    /// the host has published one.
    #[func]
    fn network_setup(&self) -> PackedStringArray {
        let core = self.lock();
        let mut values = PackedStringArray::new();
        if let Some(setup) = core.network_setup.as_ref() {
            values.push(&GString::from(setup.side.as_str()));
            values.push(&GString::from(setup.time.as_str()));
            values.push(&GString::from(setup.variant.as_str()));
        }
        values
    }

    /// Durable network observation for screens that bind after an event was
    /// emitted. The order is lifecycle, level, RTT ms, loss percent, direct.
    #[func]
    fn network_snapshot(&self) -> PackedStringArray {
        let snapshot = self.lock().network_snapshot.clone();
        let mut values = PackedStringArray::new();
        values.push(&GString::from(snapshot.lifecycle.as_str()));
        values.push(&GString::from(snapshot.level.to_string().as_str()));
        values.push(&GString::from(snapshot.rtt_ms.to_string().as_str()));
        values.push(&GString::from(snapshot.loss_percent.to_string().as_str()));
        values.push(&GString::from(if snapshot.direct {
            "true"
        } else {
            "false"
        }));
        values
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

    /// Returns the ordered local index of peers seen through successful
    /// network connections. The index is observation data, not session truth.
    #[func]
    fn recent_players(&mut self, identity_path: String) -> PackedStringArray {
        let mut players = PackedStringArray::new();
        match RecentPeerStore::new(&recent_peers_path(&identity_path)).load() {
            Ok(records) => {
                for record in records {
                    let display = record.peer.to_string();
                    let display = GString::from(display.as_str());
                    players.push(&display);
                }
            }
            Err(err) => {
                self.emit_error(&format!("recent peer history unavailable: {err}"));
            }
        }
        players
    }

    /// Returns the Rust-owned recent-peer records, newest contact first.
    ///
    /// The timestamp and ticket are observations. Neither implies that the
    /// peer is currently online; presence requires a live backend signal.
    #[func]
    fn recent_peer_records(
        &mut self,
        identity_path: String,
    ) -> Array<Dictionary<Variant, Variant>> {
        let mut result = Array::new();
        match RecentPeerStore::new(&recent_peers_path(&identity_path)).load() {
            Ok(records) => {
                for record in records {
                    let mut item = Dictionary::<Variant, Variant>::new();
                    let peer = GString::from(&record.peer.to_string());
                    item.set("peer", &peer);
                    let ticket = record
                        .ticket
                        .map(|ticket| GString::from(ticket.as_str()))
                        .unwrap_or_default();
                    item.set("ticket", &ticket);
                    item.set("last_seen_unix_secs", record.last_seen_unix_secs as i64);
                    let presence = self
                        .lock()
                        .presence
                        .get(&record.peer)
                        .copied()
                        .unwrap_or(PeerPresence::Unknown)
                        .as_str()
                        .to_string();
                    let presence_text = GString::from(presence.as_str());
                    item.set("presence", &presence_text);
                    result.push(&item);
                }
            }
            Err(err) => {
                self.emit_error(&format!("recent peer history unavailable: {err}"));
            }
        }
        result
    }

    /// Reports whether the local recent-peer index can be read.
    #[func]
    fn recent_players_status(&self, identity_path: String) -> GString {
        let status = match RecentPeerStore::new(&recent_peers_path(&identity_path)).load() {
            Ok(_) => "ready",
            Err(_) => "unavailable",
        };
        GString::from(status)
    }

    /// Marks a side ready (`"white"` or `"black"`); second starts play.
    #[func]
    fn set_ready(&mut self, side: GString) {
        let peer = {
            let core = self.lock();
            if core.net.is_some() {
                Some(core.me)
            } else {
                sides(&core).map(|(white, black)| match side.to_string().as_str() {
                    "white" => white,
                    _ => black,
                })
            }
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
            Ok(events) => {
                self.emit_all(&events);
                if let Some(tx) = self.lock().net.as_ref().map(|net| net.cmd_tx.clone()) {
                    let _ = tx.send(NetCmd::SendReady);
                }
            }
            Err(message) => self.emit_error(&message),
        }
    }

    /// Plays `uci` for whoever owns the turn; emits `move_applied`.
    #[func]
    fn submit_move(&mut self, uci: GString) -> bool {
        if self
            .lock()
            .net
            .as_ref()
            .is_some_and(|net| net.cmd_tx.is_closed())
        {
            self.emit_error("network connection closed");
            return false;
        }
        let mv: Move = match uci.to_string().parse() {
            Ok(mv) => mv,
            Err(err) => {
                self.emit_error(&err.to_string());
                return false;
            }
        };
        let outcome: Result<Vec<Event>, String> = {
            let mut core = self.lock();
            let peer = if core.net.is_some() || core.ai.is_some() {
                if turn_peer(&core) != Some(core.me) {
                    return {
                        drop(core);
                        self.emit_error("waiting for opponent");
                        false
                    };
                }
                Some(core.me)
            } else {
                turn_peer(&core)
            };
            match peer {
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

    /// Returns the authoritative occupied squares for rendering and hit-test
    /// decoration. The UI receives typed facts; it does not parse FEN.
    #[func]
    fn position_pieces(&self) -> Array<Dictionary<Variant, Variant>> {
        let mut result = Array::new();
        let fen = self.fen().to_string();
        let Ok(board) = Board::from_fen(&fen) else {
            return result;
        };
        for rank in 0..8 {
            for file in 0..8 {
                let Ok(square) = Square::from_xy(file, rank) else {
                    continue;
                };
                let Some(piece) = board.piece_at(square) else {
                    continue;
                };
                let mut item = Dictionary::<Variant, Variant>::new();
                let square_text = GString::from(square.to_string().as_str());
                let side_text = GString::from(piece.color.to_string().as_str());
                let role = match piece.role {
                    crate::chess_core::Role::Pawn => "pawn",
                    crate::chess_core::Role::Knight => "knight",
                    crate::chess_core::Role::Bishop => "bishop",
                    crate::chess_core::Role::Rook => "rook",
                    crate::chess_core::Role::Queen => "queen",
                    crate::chess_core::Role::King => "king",
                };
                let role_text = GString::from(role);
                item.set("square", &square_text);
                item.set("side", &side_text);
                item.set("role", &role_text);
                result.push(&item);
            }
        }
        result
    }

    /// En-passant target square (e.g. `"e3"`) for capture decoration, or
    /// `""` when none exists. Same precedent as `position_pieces`: parsed
    /// from our own canonical FEN inside Rust, never in GDScript
    /// (AUDIT-FEN-001).
    #[func]
    fn en_passant_square(&self) -> GString {
        let fen = self.fen().to_string();
        let Ok(board) = Board::from_fen(&fen) else {
            return GString::new();
        };
        match board.en_passant() {
            Some(square) => GString::from(square.to_string().as_str()),
            None => GString::new(),
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

    /// Whether the authoritative session is terminal, including after restore.
    #[func]
    fn session_finished(&self) -> bool {
        match self
            .lock()
            .app
            .as_ref()
            .and_then(|app| app.query(&Query::SessionState).ok())
        {
            Some(QueryResult::SessionState(view)) => {
                matches!(view.state, crate::session::SessionState::Finished(_))
            }
            _ => false,
        }
    }

    /// Resigns unilaterally (hotseat: side to move; networked/ai: local player).
    #[func]
    fn resign(&mut self) -> bool {
        let command = {
            let core = self.lock();
            let peer = if core.net.is_some() || core.ai.is_some() {
                core.me
            } else {
                match turn_peer(&core) {
                    Some(peer) => peer,
                    None => return false,
                }
            };
            Command::Resign { peer }
        };
        self.run_command(command)
    }

    /// Offers a draw (hotseat: side to move; networked/ai: local player).
    #[func]
    fn offer_draw(&mut self) -> bool {
        let peer = {
            let core = self.lock();
            if core.net.is_some() || core.ai.is_some() {
                core.me
            } else {
                match turn_peer(&core) {
                    Some(peer) => peer,
                    None => return false,
                }
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
            let peer = if core.net.is_some() || core.ai.is_some() {
                core.me
            } else {
                let offerer = match core.offer_by {
                    Some(offerer) => offerer,
                    None => return false,
                };
                let sides = match sides(&core) {
                    Some(sides) => sides,
                    None => return false,
                };
                if offerer == sides.0 { sides.1 } else { sides.0 }
            };
            Command::AnswerDraw { peer, accept }
        };
        if !self.run_command(command) {
            return false;
        }
        self.lock().offer_by = None;
        true
    }

    /// Aborts unilaterally (any unfinished state).
    #[func]
    fn abort(&mut self) -> bool {
        let command = {
            let core = self.lock();
            let peer = if core.net.is_some() || core.ai.is_some() {
                core.me
            } else {
                match turn_peer(&core) {
                    Some(peer) => peer,
                    None => return false,
                }
            };
            Command::Abort { peer }
        };
        self.run_command(command)
    }

    /// Side of the given peer ("white", "black", or "" if unknown).
    #[func]
    fn side_of_peer(&self, peer: GString) -> GString {
        let core = self.lock();
        let peer_str = peer.to_string();
        match sides(&core) {
            Some((white, _)) if white.to_string() == peer_str => GString::from("white"),
            Some((_, black)) if black.to_string() == peer_str => GString::from("black"),
            _ => GString::from(""),
        }
    }

    /// Peer identity assigned to a side, or empty before a session exists.
    #[func]
    fn peer_for_side(&self, side: GString) -> GString {
        let core = self.lock();
        let Some((white, black)) = sides(&core) else {
            return GString::new();
        };
        match side.to_string().to_ascii_lowercase().as_str() {
            "white" => GString::from(&white.to_string()),
            "black" => GString::from(&black.to_string()),
            _ => GString::new(),
        }
    }

    /// Local peer ID string.
    #[func]
    fn my_peer(&self) -> GString {
        GString::from(&self.lock().me.to_string())
    }

    /// The local profile name, or its deterministic identity-derived fallback.
    #[func]
    fn my_player_name(&self) -> GString {
        let core = self.lock();
        GString::from(&player_name(&core, core.me))
    }

    /// The authoritative display name for a participant identity.
    #[func]
    fn player_name(&self, peer: GString) -> GString {
        let core = self.lock();
        let wanted = peer.to_string();
        let known = [core.me, core.remote_peer.unwrap_or_default()];
        for candidate in known {
            if candidate.to_string() == wanted {
                return GString::from(&player_name(&core, candidate));
            }
        }
        if core
            .ai
            .as_ref()
            .is_some_and(|ai| ai.peer.to_string() == wanted)
        {
            return GString::from("Chess AI");
        }
        GString::from(&format!("Player {wanted}"))
    }

    /// Updates and persists the local display name. Empty text restores the
    /// deterministic fallback without changing the cryptographic identity.
    /// Takes the identity path so a name set before any session still
    /// persists; the file sits next to the identity key.
    #[func]
    fn set_player_name(&mut self, name: GString, identity_path: GString) -> bool {
        let name = match clean_player_name(&name.to_string()) {
            Ok(name) => name,
            Err(err) => {
                self.emit_error(&err);
                return false;
            }
        };
        let path = profile_path(&identity_path.to_string());
        if let Err(err) = save_profile_name(&path, name.as_deref()) {
            self.emit_error(&err);
            return false;
        }
        let mut core = self.lock();
        core.profile_path = Some(path);
        core.display_name = name;
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
                    let peer = GString::from(&peer.to_string());
                    self.signals().peer_connected().emit(&peer);
                }
                NetNote::PeerAddress { peer, ticket } => {
                    {
                        let mut core = self.lock();
                        core.presence.insert(*peer, PeerPresence::Online);
                    }
                    let record_error = {
                        let core = self.lock();
                        core.recent_peers_path.as_ref().and_then(|path| {
                            let timestamp = SystemTime::now()
                                .duration_since(UNIX_EPOCH)
                                .map(|duration| duration.as_secs());
                            match timestamp {
                                Ok(timestamp) => RecentPeerStore::new(path)
                                    .upsert(*peer, Some(ticket.clone()), timestamp)
                                    .err()
                                    .map(|err| err.to_string()),
                                Err(err) => {
                                    Some(format!("system clock is before Unix epoch: {err}"))
                                }
                            }
                        })
                    };
                    if let Some(message) = record_error {
                        self.emit_error(&format!("recent peer history unavailable: {message}"));
                    }
                    let peer_text = GString::from(&peer.to_string());
                    let status = GString::from(PeerPresence::Online.as_str());
                    self.signals().peer_presence().emit(&peer_text, &status);
                }
                NetNote::IncomingInviteReady { invite_id, peer } => {
                    let peer_text = GString::from(&peer.to_string());
                    self.signals()
                        .incoming_invite()
                        .emit(*invite_id as i64, &peer_text);
                }
                NetNote::IncomingInvite { .. } => {}
                NetNote::InviteAccepted { invite_id, peer } => {
                    self.lock().presence.insert(*peer, PeerPresence::Online);
                    let peer_text = GString::from(&peer.to_string());
                    self.signals()
                        .invite_result()
                        .emit(*invite_id as i64, true, &peer_text);
                }
                NetNote::InviteDeclined { invite_id, peer } => {
                    {
                        let mut core = self.lock();
                        core.presence.insert(*peer, PeerPresence::Online);
                    }
                    let peer_text = GString::from(&peer.to_string());
                    self.signals()
                        .invite_result()
                        .emit(*invite_id as i64, false, &peer_text);
                }
                NetNote::PeerOffline(peer) => {
                    self.lock().presence.insert(*peer, PeerPresence::Offline);
                    let peer_text = GString::from(&peer.to_string());
                    let status = GString::from(PeerPresence::Offline.as_str());
                    self.signals().peer_presence().emit(&peer_text, &status);
                }
                NetNote::PeerLeft => {
                    self.lock().remote_left = true;
                    self.signals().peer_left().emit();
                }
                NetNote::IncomingRematch { rematch_id, peer } => {
                    let peer_text = GString::from(&peer.to_string());
                    self.signals()
                        .incoming_rematch()
                        .emit(*rematch_id as i64, &peer_text);
                }
                NetNote::RematchResult {
                    rematch_id,
                    peer,
                    accepted,
                    host,
                } => {
                    let peer_text = GString::from(&peer.to_string());
                    self.signals().rematch_result().emit(
                        *rematch_id as i64,
                        *accepted,
                        &peer_text,
                        *host,
                    );
                }
                NetNote::Reconnecting => {
                    self.signals().network_reconnecting().emit();
                }
                NetNote::Quality {
                    level,
                    rtt_ms,
                    loss_percent,
                    direct,
                } => {
                    self.signals().network_quality().emit(
                        i64::from(*level),
                        i64::from(*rtt_ms),
                        i64::from(*loss_percent),
                        *direct,
                    );
                }
                NetNote::Setup {
                    side,
                    time,
                    variant,
                } => {
                    let side = GString::from(side.as_str());
                    let time = GString::from(time.as_str());
                    let variant = GString::from(variant.as_str());
                    self.signals().setup_changed().emit(&side, &time, &variant);
                }
                NetNote::Disconnected => {
                    self.signals().peer_disconnected().emit();
                }
                NetNote::PeerLoaded => {
                    self.signals().peer_loaded().emit();
                }
                NetNote::Error(message) => {
                    let message = GString::from(message);
                    self.signals().network_error().emit(&message);
                }
            }
        }
        if !notes.is_empty() {
            let snapshot = { self.lock().network_snapshot.clone() };
            let lifecycle = GString::from(snapshot.lifecycle.as_str());
            self.signals().network_snapshot_changed().emit(
                &lifecycle,
                snapshot.level,
                snapshot.rtt_ms,
                snapshot.loss_percent,
                snapshot.direct,
            );
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
            if core.net.as_ref().is_some_and(|net| net.cmd_tx.is_closed()) {
                drop(core);
                self.emit_error("network connection closed");
                return false;
            }
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
            Event::SessionCreated { white, black, host } => {
                let (white, black) = (
                    GString::from(&white.to_string()),
                    GString::from(&black.to_string()),
                );
                let host = GString::from(&host.to_string());
                self.signals().session_created().emit(&white, &black, &host);
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
                {
                    self.lock().offer_by = Some(*by);
                }
                let by = GString::from(&by.to_string());
                self.signals().draw_offered().emit(&by, *seq as i64);
            }
            Event::DrawAnswered { by, accept } => {
                {
                    self.lock().offer_by = None;
                }
                let by = GString::from(&by.to_string());
                self.signals().draw_answered().emit(&by, *accept);
            }
            Event::GameEnded { reason } => {
                {
                    self.lock().offer_by = None;
                }
                let reason = GString::from(&format!("{reason:?}"));
                self.signals().game_ended().emit(&reason);
                let result = result_snapshot(&self.lock());
                self.signals().game_result().emit(&result);
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

fn reset_for_rematch(core: &mut CoreState, host: bool) {
    if let Some(secret) = core.local_secret.clone() {
        core.app = Some(App::with_local(secret));
    }
    core.network_setup = None;
    core.next_setup_revision = 0;
    core.network_peer_loaded = false;
    core.outbox.clear();
    core.offer_by = None;
    core.pending_rematch = None;
    core.outgoing_rematch = None;
    core.rematch_host = host;
    core.rematch_generation = core.rematch_generation.wrapping_add(1);
}

/// Builds a runtime, binds an endpoint on the persisted installation seed, records `me`,
/// clears any previous session, and retires any previous network.
/// Returns the handoff a link task needs after setup.
fn start_network(
    core: &mut CoreState,
    seed: [u8; 32],
    recent_path: std::path::PathBuf,
) -> Result<NetLaunch, String> {
    let secret = SigningKey::from_bytes(&seed);
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .map_err(|err| err.to_string())?;
    let endpoint = runtime
        .block_on(crate::IrohEndpoint::bind_with_seed(seed))
        .map_err(|err| format!("endpoint bind failed: {err}"))?;
    // Relay readiness improves the ticket but is not required for a direct
    // path; retain the bounded wait without making relay availability a
    // hidden hard dependency.
    let _online = runtime.block_on(endpoint.wait_online(Duration::from_secs(10)));
    let me = PeerId::of(&secret);
    if endpoint.id_bytes() != me.bytes() {
        return Err("endpoint identity diverged from peer identity".to_string());
    }
    core.net_generation += 1;
    let generation = core.net_generation;
    core.me = me;
    core.remote_peer = None;
    core.game_peer = None;
    core.presence.clear();
    core.pending_invite = None;
    core.remote_left = false;
    core.local_secret = Some(secret.clone());
    core.pending_rematch = None;
    core.outgoing_rematch = None;
    core.rematch_host = false;
    core.rematch_generation = 0;
    core.network_setup = None;
    core.next_setup_revision = 0;
    core.network_snapshot = NetworkSnapshot {
        lifecycle: "connecting".to_string(),
        ..NetworkSnapshot::default()
    };
    core.network_peer_loaded = false;
    core.recent_peers_path = Some(recent_path);
    core.app = Some(App::with_local(secret));
    core.outbox.clear();
    core.offer_by = None;
    let (cmd_tx, cmd_rx) = tokio::sync::mpsc::unbounded_channel();
    core.net = Some(NetState {
        runtime,
        endpoint: endpoint.clone(),
        cmd_tx,
        invite_code: None,
    });
    Ok(NetLaunch {
        endpoint,
        generation,
        cmd_rx,
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
    core.network_snapshot = NetworkSnapshot {
        lifecycle: "lost".to_string(),
        ..NetworkSnapshot::default()
    };
    core.net_notes.clear();
    core.presence.clear();
    core.pending_invite = None;
    core.remote_left = false;
    core.pending_rematch = None;
    core.outgoing_rematch = None;
    core.rematch_host = false;
    core.net.take()
}

/// Shuts a detached network down: graceful close so the peer sees the
/// disconnect, then runtime drop once its tasks have exited. Call with
/// no CoreState guard held (see `begin_retire`).
fn finish_retire(net: Option<NetState>) {
    if let Some(net) = net {
        net.runtime.block_on(async {
            let (ack_tx, ack_rx) = tokio::sync::oneshot::channel();
            let _ = net.cmd_tx.send(NetCmd::Leave {
                acknowledged: ack_tx,
            });
            let _ = tokio::time::timeout(Duration::from_millis(500), ack_rx).await;
            if let Some(code) = net.invite_code.as_deref() {
                crate::unpublish(code).await;
            }
            net.endpoint.close().await;
            tokio::task::yield_now().await;
        });
    }
}

/// Background accept for the host: links the guest and immediately
/// drives the session. Silent when a newer network retired this one mid-flight.
async fn accept_task(
    core: Arc<Mutex<CoreState>>,
    mut endpoint: crate::IrohEndpoint,
    generation: u64,
    mut cmd_rx: tokio::sync::mpsc::UnboundedReceiver<NetCmd>,
    mode: AcceptMode,
) {
    loop {
        let conn = match endpoint.accept().await {
            Ok(conn) => conn,
            Err(err) => {
                if is_current(&core, generation) {
                    note(&core, generation, NetNote::Error(short_error(&err)));
                }
                return;
            }
        };
        let guest = PeerId::from_bytes(conn.peer_id_bytes());
        {
            let mut guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
            if guard.net_generation != generation {
                return;
            }
            guard.remote_peer = Some(guest);
        }
        let local_ticket = endpoint.ticket();
        match mode {
            AcceptMode::Game => {
                note(&core, generation, NetNote::Connected(guest));
                drive_session(
                    &core,
                    conn,
                    local_ticket,
                    &mut cmd_rx,
                    generation,
                    true,
                    true,
                )
                .await;
            }
            AcceptMode::Invite => {
                // A redial from the peer whose invitation already became a
                // game resumes that session: routing it back through the
                // invite handshake would reject game messages as invalid
                // (AUDIT-INVITE-RECONNECT-001).
                if redial_resumes_game(&core, generation, guest) {
                    note(&core, generation, NetNote::Connected(guest));
                    drive_session(
                        &core,
                        conn,
                        local_ticket,
                        &mut cmd_rx,
                        generation,
                        false,
                        false,
                    )
                    .await;
                } else if drive_incoming_invite(&core, conn, local_ticket, &mut cmd_rx, generation)
                    .await
                {
                    let mut guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
                    if guard.net_generation == generation {
                        guard.game_peer = Some(guest);
                    }
                }
            }
        }
        if remote_left(&core, generation) {
            return;
        }
        if !is_current(&core, generation) || cmd_rx.is_closed() {
            return;
        }
        note(&core, generation, NetNote::Reconnecting);
    }
}

/// Handles one incoming invitation on the hub's presence endpoint. The
/// connection remains open while Godot displays the Morgan invite card.
/// Returns true when the invitation became a game session, so the accept
/// loop can route that peer's redials straight back into it.
async fn drive_incoming_invite(
    core: &Arc<Mutex<CoreState>>,
    mut conn: crate::IrohConnection,
    local_ticket: String,
    cmd_rx: &mut tokio::sync::mpsc::UnboundedReceiver<NetCmd>,
    generation: u64,
) -> bool {
    let peer = {
        let guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        guard.remote_peer
    };
    let Some(peer) = peer else {
        note(
            core,
            generation,
            NetNote::Error("peer identity missing".to_string()),
        );
        return false;
    };
    if conn
        .send(&Msg::LobbyHello {
            version: PROTOCOL_VERSION,
            ticket: local_ticket.clone(),
        })
        .await
        .is_err()
    {
        return false;
    }
    let Ok(remote_hello) = conn.recv().await else {
        note(
            core,
            generation,
            NetNote::Error("invite handshake failed".to_string()),
        );
        return false;
    };
    if on_msg(core, &mut conn, remote_hello, generation, false)
        .await
        .is_err()
    {
        return false;
    }
    let invite = match conn.recv().await {
        Ok(Msg::InviteRequest { invite_id, sender }) if sender == peer => (invite_id, sender),
        Ok(_) => {
            note(
                core,
                generation,
                NetNote::Error("invalid invitation request".to_string()),
            );
            return false;
        }
        Err(_) => return false,
    };
    let (response_tx, response_rx) = tokio::sync::oneshot::channel();
    note(
        core,
        generation,
        NetNote::IncomingInvite {
            invite_id: invite.0,
            peer: invite.1,
            response: response_tx,
        },
    );
    let accepted = tokio::select! {
        result = response_rx => result.unwrap_or(false),
        command = cmd_rx.recv() => {
            if let Some(NetCmd::Leave { acknowledged }) = command {
                let _ = conn.send(&Msg::Leave).await;
                let _ = acknowledged.send(());
            }
            return false;
        }
        result = conn.recv() => {
            if result.is_err() {
                return false;
            }
            return false;
        }
    };
    if conn
        .send(&Msg::InviteResponse {
            invite_id: invite.0,
            accepted,
        })
        .await
        .is_err()
    {
        return false;
    }
    if !accepted {
        note(
            core,
            generation,
            NetNote::InviteDeclined {
                invite_id: invite.0,
                peer,
            },
        );
        return false;
    }
    note(core, generation, NetNote::Connected(peer));
    drive_session(core, conn, local_ticket, cmd_rx, generation, false, false).await;
    true
}

/// Dials a saved ticket and waits for the recipient's explicit response
/// before converting the connection into a game session.
async fn invite_task(
    core: Arc<Mutex<CoreState>>,
    endpoint: crate::IrohEndpoint,
    ticket: String,
    invite_id: u64,
    generation: u64,
    mut cmd_rx: tokio::sync::mpsc::UnboundedReceiver<NetCmd>,
) {
    let mut endpoint = endpoint;
    let mut conn = match endpoint.connect(&ticket).await {
        Ok(conn) => conn,
        Err(err) => {
            if let Some(peer) = ticket_peer_id(&ticket).map(|id| PeerId::from_bytes(*id.as_bytes()))
            {
                note(&core, generation, NetNote::PeerOffline(peer));
            }
            note(
                &core,
                generation,
                NetNote::Error(format!("peer invite could not connect: {err}")),
            );
            return;
        }
    };
    let peer = PeerId::from_bytes(conn.peer_id_bytes());
    {
        let mut guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        if guard.net_generation != generation {
            return;
        }
        guard.remote_peer = Some(peer);
    }
    let local_ticket = endpoint.ticket();
    if conn
        .send(&Msg::LobbyHello {
            version: PROTOCOL_VERSION,
            ticket: local_ticket.clone(),
        })
        .await
        .is_err()
    {
        return;
    }
    let Ok(remote_hello) = conn.recv().await else {
        note(
            &core,
            generation,
            NetNote::Error("invite handshake failed".to_string()),
        );
        return;
    };
    if on_msg(&core, &mut conn, remote_hello, generation, true)
        .await
        .is_err()
    {
        return;
    }
    if conn
        .send(&Msg::InviteRequest {
            invite_id,
            sender: {
                let guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
                guard.me
            },
        })
        .await
        .is_err()
    {
        return;
    }
    let accepted = loop {
        tokio::select! {
            command = cmd_rx.recv() => {
                if let Some(NetCmd::Leave { acknowledged }) = command {
                    let _ = conn.send(&Msg::Leave).await;
                    let _ = acknowledged.send(());
                }
                return;
            }
            message = conn.recv() => match message {
                Ok(Msg::InviteResponse {
                    invite_id: response_id,
                    accepted,
                }) if response_id == invite_id => break accepted,
                Ok(Msg::LobbyHello { .. }) => continue,
                Ok(_) => continue,
                Err(_) => return,
            }
        }
    };
    if !accepted {
        note(
            &core,
            generation,
            NetNote::InviteDeclined { invite_id, peer },
        );
        return;
    }
    note(
        &core,
        generation,
        NetNote::InviteAccepted { invite_id, peer },
    );
    note(&core, generation, NetNote::Connected(peer));
    drive_session(
        &core,
        conn,
        local_ticket,
        &mut cmd_rx,
        generation,
        true,
        false,
    )
    .await;
}

/// Background dial for the guest: resolves short codes through
/// rendezvous, dials tickets directly, and immediately drives the session.
/// Silent when retired mid-flight.
async fn join_task(
    core: Arc<Mutex<CoreState>>,
    endpoint: crate::IrohEndpoint,
    ticket: String,
    generation: u64,
    mut cmd_rx: tokio::sync::mpsc::UnboundedReceiver<NetCmd>,
) {
    let dial = match iroh_tickets::endpoint::EndpointTicket::from_str(&ticket) {
        Ok(_) => ticket.clone(),
        Err(_) => match crate::resolve_ticket(&ticket, Duration::from_secs(120)).await {
            Ok(resolved) => resolved.to_string(),
            Err(err) => {
                note(
                    &core,
                    generation,
                    NetNote::Error(format!("invite discovery failed for {ticket}: {err}")),
                );
                return;
            }
        },
    };
    let mut endpoint = endpoint;
    let mut failures = 0u32;
    loop {
        if !is_current(&core, generation) || cmd_rx.is_closed() {
            return;
        }
        let conn = match endpoint.connect(&dial).await {
            Ok(conn) => conn,
            Err(err) => {
                failures += 1;
                if failures >= 30 {
                    note(
                        &core,
                        generation,
                        NetNote::Error(format!(
                            "invite reconnect failed after {failures} attempts: {err}"
                        )),
                    );
                    note(&core, generation, NetNote::Disconnected);
                    return;
                }
                note(&core, generation, NetNote::Reconnecting);
                tokio::time::sleep(Duration::from_secs(1)).await;
                continue;
            }
        };
        let host = PeerId::from_bytes(conn.peer_id_bytes());
        {
            let mut guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
            if guard.net_generation != generation {
                return;
            }
            guard.remote_peer = Some(host);
        }
        failures = 0;
        note(&core, generation, NetNote::Connected(host));
        let local_ticket = endpoint.ticket();
        drive_session(
            &core,
            conn,
            local_ticket,
            &mut cmd_rx,
            generation,
            false,
            true,
        )
        .await;
        if remote_left(&core, generation) {
            return;
        }
        if !is_current(&core, generation) || cmd_rx.is_closed() {
            return;
        }
        note(&core, generation, NetNote::Reconnecting);
    }
}

/// Routing for a presence-endpoint redial: true when this peer already
/// turned an invitation into a game session on the live generation, so
/// the accept loop resumes the session instead of re-handshaking.
fn redial_resumes_game(core: &Arc<Mutex<CoreState>>, generation: u64, guest: PeerId) -> bool {
    let guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    guard.net_generation == generation && guard.game_peer == Some(guest)
}

/// True while `generation` is still the live network.
fn is_current(core: &Arc<Mutex<CoreState>>, generation: u64) -> bool {
    core.lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .net_generation
        == generation
}

fn remote_left(core: &Arc<Mutex<CoreState>>, generation: u64) -> bool {
    let guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    guard.net_generation == generation && guard.remote_left
}

/// Pushes a note for the scene thread, unless a newer network retired
/// this session mid-flight.
fn note(core: &Arc<Mutex<CoreState>>, generation: u64, note: NetNote) {
    let mut guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    if guard.net_generation == generation {
        if let NetNote::IncomingInvite {
            invite_id,
            peer,
            response,
        } = note
        {
            if let Some(previous) = guard.pending_invite.take() {
                let _ = previous.response.send(false);
            }
            guard.pending_invite = Some(PendingInvite {
                invite_id,
                response,
            });
            guard
                .net_notes
                .push_back(NetNote::IncomingInviteReady { invite_id, peer });
            return;
        }
        match &note {
            NetNote::Connected(_) => {
                guard.network_snapshot.lifecycle = "connected".to_string();
            }
            NetNote::Reconnecting => {
                guard.network_snapshot.lifecycle = "degraded".to_string();
            }
            NetNote::Quality {
                level,
                rtt_ms,
                loss_percent,
                direct,
            } => {
                guard.network_snapshot.lifecycle = "connected".to_string();
                guard.network_snapshot.level = i64::from(*level);
                guard.network_snapshot.rtt_ms = i64::from(*rtt_ms);
                guard.network_snapshot.loss_percent = i64::from(*loss_percent);
                guard.network_snapshot.direct = *direct;
            }
            NetNote::Disconnected | NetNote::Error(_) => {
                guard.network_snapshot.lifecycle = "lost".to_string();
                guard.network_snapshot.level = 0;
                guard.network_snapshot.rtt_ms = -1;
                guard.network_snapshot.loss_percent = -1;
            }
            NetNote::PeerLeft => {
                guard.remote_left = true;
                guard.network_snapshot.lifecycle = "lost".to_string();
                guard.network_snapshot.level = 0;
                guard.network_snapshot.rtt_ms = -1;
                guard.network_snapshot.loss_percent = -1;
            }
            NetNote::Setup { .. }
            | NetNote::PeerLoaded
            | NetNote::PeerAddress { .. }
            | NetNote::IncomingInvite { .. }
            | NetNote::IncomingInviteReady { .. }
            | NetNote::InviteAccepted { .. }
            | NetNote::InviteDeclined { .. }
            | NetNote::PeerOffline(_)
            | NetNote::IncomingRematch { .. }
            | NetNote::RematchResult { .. } => {}
        }
        // An unannounced transport loss ends reachability, not just the
        // link: without this the recent-peer row keeps a stale online
        // indicator until the next dial (AUDIT-PRESENCE-001). Reconnect
        // success re-marks the peer online through PeerAddress.
        // An unannounced transport loss ends reachability, not just the
        // link: without this the recent-peer row keeps a stale online
        // indicator until the next dial (AUDIT-PRESENCE-001). Reconnect
        // success re-marks the peer online through PeerAddress.
        if matches!(note, NetNote::Disconnected)
            && let Some(peer) = guard.remote_peer
        {
            guard.presence.insert(peer, PeerPresence::Offline);
            guard.net_notes.push_back(NetNote::PeerOffline(peer));
        }
        guard.net_notes.push_back(note);
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

/// Session loop driving local commands and wire events: local progress
/// flushes unsent log entries, remote entries ingest and agree back, and
/// readiness/genesis exchange runs asynchronously.
async fn drive_session<C: Connection>(
    core: &Arc<Mutex<CoreState>>,
    mut conn: C,
    local_ticket: String,
    cmd_rx: &mut tokio::sync::mpsc::UnboundedReceiver<NetCmd>,
    generation: u64,
    host_role: bool,
    handshake: bool,
) {
    let mut sent_seq = next_local_seq(core);
    let mut seen_rematch_generation = core
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .rematch_generation;
    let mut quality_tick = tokio::time::interval(Duration::from_secs(2));
    quality_tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    if handshake {
        if conn
            .send(&Msg::LobbyHello {
                version: PROTOCOL_VERSION,
                ticket: local_ticket,
            })
            .await
            .is_err()
        {
            note(core, generation, NetNote::Disconnected);
            return;
        }
        if send_resume_snapshot(core, &mut conn, generation, host_role)
            .await
            .is_err()
        {
            note(core, generation, NetNote::Disconnected);
            return;
        }
    }
    loop {
        let rematch_generation = core
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .rematch_generation;
        if rematch_generation != seen_rematch_generation {
            sent_seq = next_local_seq(core);
            seen_rematch_generation = rematch_generation;
        }
        tokio::select! {
            _ = quality_tick.tick() => {
                if let Some(sample) = conn.quality() {
                    note(core, generation, NetNote::Quality {
                        level: quality_level(sample),
                        rtt_ms: sample.rtt_ms,
                        loss_percent: sample.loss_percent,
                        direct: sample.direct,
                    });
                }
            }
            cmd = cmd_rx.recv() => {
                match cmd {
                    Some(NetCmd::UpdateSetup { revision, side, time, variant }) => {
                        if !host_role || conn.send(&Msg::Setup { revision, side, time, variant }).await.is_err() {
                            note(core, generation, NetNote::Disconnected);
                            return;
                        }
                    }
                    Some(NetCmd::Loaded) => {
                        if conn.send(&Msg::Loaded).await.is_err() {
                            note(core, generation, NetNote::Disconnected);
                            return;
                        }
                    }
                    Some(NetCmd::HostStarted {
                        genesis,
                        revision,
                        side,
                        time,
                        variant,
                    }) => {
                        if conn.send(&Msg::Hello {
                            version: PROTOCOL_VERSION,
                            genesis: *genesis,
                        }).await.is_err() {
                            note(core, generation, NetNote::Disconnected);
                            return;
                        }
                        if conn
                            .send(&Msg::Setup {
                                revision,
                                side,
                                time,
                                variant,
                            })
                            .await
                            .is_err()
                        {
                            note(core, generation, NetNote::Disconnected);
                            return;
                        }
                    }
                    Some(NetCmd::SendReady) => {
                        let me = {
                            let guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
                            guard.me
                        };
                        if conn.send(&Msg::Ready { peer: me }).await.is_err() {
                            note(core, generation, NetNote::Disconnected);
                            return;
                        }
                    }
                    Some(NetCmd::Flush) => {
                        if flush_unsent(core, &mut conn, &mut sent_seq, generation)
                            .await
                            .is_err()
                        {
                            note(core, generation, NetNote::Disconnected);
                            return;
                        }
                    }
                    Some(NetCmd::Leave { acknowledged }) => {
                        let _ = conn.send(&Msg::Leave).await;
                        let _ = acknowledged.send(());
                        return;
                    }
                    Some(NetCmd::RematchRequest { rematch_id }) => {
                        if conn.send(&Msg::RematchRequest { rematch_id }).await.is_err() {
                            note(core, generation, NetNote::Disconnected);
                            return;
                        }
                    }
                    Some(NetCmd::RematchResponse { rematch_id, accepted }) => {
                        if conn.send(&Msg::RematchResponse { rematch_id, accepted }).await.is_err() {
                            note(core, generation, NetNote::Disconnected);
                            return;
                        }
                    }
                    None => return,
                }
            }
            msg = conn.recv() => {
                match msg {
                    Ok(msg) => {
                        if on_msg(core, &mut conn, msg, generation, host_role).await.is_err() {
                            return;
                        }
                    }
                    Err(_) => {
                        note(core, generation, NetNote::Disconnected);
                        return;
                    }
                }
            }
        }
    }
}

fn quality_level(sample: TransportQuality) -> u8 {
    match (sample.rtt_ms, sample.loss_percent) {
        (0..=100, 0..=1) => 4,
        (0..=250, 0..=3) => 3,
        (0..=500, 0..=8) => 2,
        _ => 1,
    }
}

fn next_local_seq(core: &Arc<Mutex<CoreState>>) -> u64 {
    let guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    guard
        .app
        .as_ref()
        .and_then(|app| app.query(&Query::MoveLog).ok())
        .and_then(|result| match result {
            QueryResult::MoveLog(entries) => entries
                .iter()
                .filter(|entry| entry.mover == guard.me)
                .map(|entry| entry.seq + 1)
                .max(),
            _ => None,
        })
        .unwrap_or(1)
}

async fn send_resume_snapshot<C: Connection>(
    core: &Arc<Mutex<CoreState>>,
    conn: &mut C,
    generation: u64,
    host_role: bool,
) -> Result<(), ()> {
    let (entries, setup) = {
        let guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        if guard.net_generation != generation {
            return Err(());
        }
        let entries = guard
            .app
            .as_ref()
            .and_then(|app| app.query(&Query::MoveLog).ok())
            .and_then(|result| match result {
                QueryResult::MoveLog(entries) => Some(entries),
                _ => None,
            })
            .unwrap_or_default();
        (entries, guard.network_setup.clone())
    };
    // A lone genesis belongs to the initial Hello handshake. Sending it as a
    // resume before the guest has joined would make the guest treat setup as
    // a move. Once play has produced at least one entry beyond genesis, the
    // complete log is the reconnect source of truth.
    if entries.len() > 1 && conn.send(&Msg::Resume { entries }).await.is_err() {
        return Err(());
    }
    if host_role && let Some(setup) = setup {
        conn.send(&Msg::Setup {
            revision: setup.revision,
            side: setup.side,
            time: setup.time,
            variant: setup.variant,
        })
        .await
        .map_err(|_| ())?;
    }
    Ok(())
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
                // The local log also contains entries received from the
                // peer. Only the local author's entries belong on this
                // outbound stream; resending a remote entry makes the peer
                // reject it as out-of-order on the next flush.
                .filter(|entry| entry.mover == guard.me && entry.seq >= *sent_seq)
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
/// complete our moves, readiness is updated, and genesis exchange completes setup.
async fn on_msg<C: Connection>(
    core: &Arc<Mutex<CoreState>>,
    conn: &mut C,
    msg: Msg,
    generation: u64,
    host_role: bool,
) -> Result<(), ()> {
    match msg {
        Msg::LobbyHello { version, ticket } => {
            if version != PROTOCOL_VERSION {
                note(
                    core,
                    generation,
                    NetNote::Error("version mismatch".to_string()),
                );
                return Err(());
            }
            let peer = {
                let guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
                guard.remote_peer
            };
            let Some(peer) = peer else {
                note(
                    core,
                    generation,
                    NetNote::Error("peer identity missing".to_string()),
                );
                return Err(());
            };
            if ticket.is_empty() {
                // MemoryTransport tests do not have an Iroh ticket. Real
                // network handshakes always carry one and are validated.
                return Ok(());
            }
            let Some(ticket_peer) = ticket_peer_id(&ticket) else {
                note(
                    core,
                    generation,
                    NetNote::Error("invalid peer ticket".to_string()),
                );
                return Err(());
            };
            if ticket_peer.as_bytes() != &peer.bytes() {
                note(
                    core,
                    generation,
                    NetNote::Error("peer ticket identity mismatch".to_string()),
                );
                return Err(());
            }
            note(core, generation, NetNote::PeerAddress { peer, ticket });
            Ok(())
        }
        Msg::Leave => {
            note(core, generation, NetNote::PeerLeft);
            Err(())
        }
        Msg::RematchRequest { rematch_id } => {
            // Locks are scoped and dropped before any note(): note()
            // locks the core itself, so holding a guard across it
            // deadlocks the driver.
            let remote = {
                let guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
                guard.remote_peer
            };
            let Some(peer) = remote else {
                note(
                    core,
                    generation,
                    NetNote::Error("rematch peer identity missing".to_string()),
                );
                return Err(());
            };
            let finished = {
                let guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
                session_is_finished(&guard)
            };
            if !finished {
                note(
                    core,
                    generation,
                    NetNote::Error("rematch requires a finished game".to_string()),
                );
                return Ok(());
            }
            {
                let mut guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
                guard.pending_rematch = Some((rematch_id, peer));
            }
            note(
                core,
                generation,
                NetNote::IncomingRematch { rematch_id, peer },
            );
            Ok(())
        }
        Msg::RematchResponse {
            rematch_id,
            accepted,
        } => {
            let result = {
                let mut guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
                if guard.outgoing_rematch != Some(rematch_id) {
                    Err("rematch identifier mismatch")
                } else if let Some(peer) = guard.remote_peer {
                    if accepted {
                        if !session_is_finished(&guard) {
                            Err("rematch requires a finished game")
                        } else {
                            reset_for_rematch(&mut guard, true);
                            Ok(peer)
                        }
                    } else {
                        guard.outgoing_rematch = None;
                        Ok(peer)
                    }
                } else {
                    Err("rematch peer identity missing")
                }
            };
            let peer = match result {
                Ok(peer) => peer,
                Err(message) => {
                    note(core, generation, NetNote::Error(message.to_string()));
                    return Err(());
                }
            };
            note(
                core,
                generation,
                NetNote::RematchResult {
                    rematch_id,
                    peer,
                    accepted,
                    host: true,
                },
            );
            Ok(())
        }
        Msg::Hello { version, genesis } => {
            if version != PROTOCOL_VERSION {
                note(
                    core,
                    generation,
                    NetNote::Error("version mismatch".to_string()),
                );
                return Err(());
            }
            if !is_current(core, generation) {
                return Err(());
            }
            let me = {
                let guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
                guard.me
            };
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
            let co_sig = {
                let guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
                match guard
                    .app
                    .as_ref()
                    .and_then(|app| app.query(&Query::MoveLog).ok())
                {
                    Some(QueryResult::MoveLog(entries)) => entries.first().and_then(|e| e.co_sig),
                    _ => None,
                }
            };
            let Some(co_sig) = co_sig else {
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
                note(core, generation, NetNote::Disconnected);
                return Err(());
            }
            Ok(())
        }
        Msg::Agreed { seq, sig } => {
            if !is_current(core, generation) {
                return Err(());
            }
            if seq == 0 {
                let guest = {
                    let guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
                    guard.remote_peer
                };
                let Some(guest) = guest else {
                    note(
                        core,
                        generation,
                        NetNote::Error("no remote peer".to_string()),
                    );
                    return Err(());
                };
                if apply(
                    core,
                    Command::NotePeerJoined {
                        peer: guest,
                        co_sig: sig,
                    },
                )
                .is_err()
                {
                    note(
                        core,
                        generation,
                        NetNote::Error("genesis agreement rejected".to_string()),
                    );
                    return Err(());
                }
                let me = {
                    let guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
                    guard.me
                };
                if apply(core, Command::SetReady { peer: me }).is_err() {
                    note(
                        core,
                        generation,
                        NetNote::Error("host readiness rejected".to_string()),
                    );
                    return Err(());
                }
                if conn.send(&Msg::Ready { peer: me }).await.is_err() {
                    note(core, generation, NetNote::Disconnected);
                    return Err(());
                }
                Ok(())
            } else {
                match apply(core, Command::NoteMoveAgreed { seq, co_sig: sig }) {
                    Ok(()) => Ok(()),
                    Err(reason) => {
                        note(core, generation, NetNote::Error(reason));
                        Err(())
                    }
                }
            }
        }
        Msg::Ready { peer } => {
            if !is_current(core, generation) {
                return Err(());
            }
            // Readiness is bound to the authenticated transport peer: the
            // session already rejects strangers, but only this check stops a
            // peer from marking the *other* side ready early
            // (AUDIT-AUTH-001).
            let remote = {
                let guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
                guard.remote_peer
            };
            if Some(peer) != remote {
                note(
                    core,
                    generation,
                    NetNote::Error("readiness identity mismatch".to_string()),
                );
                return Err(());
            }
            if apply(core, Command::NotePeerReady { peer }).is_err() {
                note(
                    core,
                    generation,
                    NetNote::Error("readiness rejected".to_string()),
                );
                return Err(());
            }
            if host_role {
                if conn.send(&Msg::Started).await.is_err() {
                    note(core, generation, NetNote::Disconnected);
                    return Err(());
                }
            } else {
                let me = {
                    let guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
                    guard.me
                };
                if conn.send(&Msg::Ready { peer: me }).await.is_err() {
                    note(core, generation, NetNote::Disconnected);
                    return Err(());
                }
            }
            Ok(())
        }
        Msg::Started => {
            if host_role || !is_current(core, generation) {
                return Err(());
            }
            let me = {
                let guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
                guard.me
            };
            let host = {
                let guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
                guard.remote_peer
            };
            let Some(host) = host else {
                note(
                    core,
                    generation,
                    NetNote::Error("host identity missing".to_string()),
                );
                return Err(());
            };
            if apply(core, Command::NotePeerReady { peer: host }).is_err() {
                note(
                    core,
                    generation,
                    NetNote::Error("host readiness rejected".to_string()),
                );
                return Err(());
            }
            if apply(core, Command::SetReady { peer: me }).is_err() {
                note(
                    core,
                    generation,
                    NetNote::Error("host start rejected".to_string()),
                );
                return Err(());
            }
            Ok(())
        }
        Msg::Loaded => {
            if !is_current(core, generation) {
                return Err(());
            }
            {
                let mut guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
                guard.network_peer_loaded = true;
            }
            note(core, generation, NetNote::PeerLoaded);
            Ok(())
        }
        Msg::Setup {
            revision,
            side,
            time,
            variant,
        } => {
            if !is_current(core, generation) {
                return Err(());
            }
            // Setup is host-owned: a guest-originated snapshot is a
            // protocol violation, not a lobby update (AUDIT-AUTH-001).
            // Setup is host-owned: a guest-originated snapshot is a
            // protocol violation, not a lobby update (AUDIT-AUTH-001).
            if host_role {
                note(
                    core,
                    generation,
                    NetNote::Error("guest setup rejected".to_string()),
                );
                return Err(());
            }
            if variant != "Standard" {
                note(
                    core,
                    generation,
                    NetNote::Error(format!("unsupported network variant: {variant}")),
                );
                return Err(());
            }
            {
                let mut guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
                if guard
                    .network_setup
                    .as_ref()
                    .is_some_and(|current| current.revision > revision)
                {
                    return Ok(());
                }
                guard.network_setup = Some(NetworkSetup {
                    revision,
                    side: side.clone(),
                    time: time.clone(),
                    variant: variant.clone(),
                });
            }
            note(
                core,
                generation,
                NetNote::Setup {
                    side,
                    time,
                    variant,
                },
            );
            Ok(())
        }
        Msg::Resume { entries } => {
            let agreements = match sync_resume(core, &entries, generation) {
                Ok(agreements) => agreements,
                Err(reason) => {
                    note(core, generation, NetNote::Error(reason));
                    return Err(());
                }
            };
            for (seq, sig) in agreements {
                if conn.send(&Msg::Agreed { seq, sig }).await.is_err() {
                    note(core, generation, NetNote::Disconnected);
                    return Err(());
                }
            }
            Ok(())
        }
        Msg::Entry(entry) => {
            enum Ingest {
                Agree(u64, [u8; 64]),
                Applied,
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
                                    None => Ingest::Applied,
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
                Ingest::Applied => Ok(()),
                Ingest::Agree(seq, sig) => {
                    if conn.send(&Msg::Agreed { seq, sig }).await.is_err() {
                        note(core, generation, NetNote::Disconnected);
                        return Err(());
                    }
                    Ok(())
                }
            }
        }
        Msg::Done => {
            note(core, generation, NetNote::Disconnected);
            Err(())
        }
        Msg::Tip { .. } | Msg::Fen { .. } => Ok(()),
        Msg::InviteRequest { .. } | Msg::InviteResponse { .. } => {
            note(
                core,
                generation,
                NetNote::Error("invite message arrived outside invite handshake".to_string()),
            );
            Err(())
        }
    }
}

/// Reconciles a complete signed log received after reconnect. Existing
/// entries must have identical hashes; only the contiguous suffix may be
/// ingested. This keeps the session log, rather than either UI, authoritative.
fn sync_resume(
    core: &Arc<Mutex<CoreState>>,
    remote: &[LogEntry],
    generation: u64,
) -> Result<Vec<(u64, [u8; 64])>, String> {
    let mut agreements = Vec::new();
    let mut guard = core.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    if guard.net_generation != generation {
        return Err("resume rejected: network retired".to_string());
    }
    for remote_entry in remote {
        let local = match guard
            .app
            .as_ref()
            .and_then(|app| app.query(&Query::MoveLog).ok())
        {
            Some(QueryResult::MoveLog(entries)) => entries,
            _ => {
                return Err("resume rejected: no move log".to_string());
            }
        };
        if remote_entry.seq < local.len() as u64 {
            let existing = local[remote_entry.seq as usize];
            if existing.hash() != remote_entry.hash() {
                return Err("resume rejected: log mismatch".to_string());
            }
            if remote_entry.seq > 0
                && existing.co_sig.is_none()
                && let Some(sig) = remote_entry.co_sig
            {
                let app = guard
                    .app
                    .as_mut()
                    .ok_or_else(|| "resume rejected: no session".to_string())?;
                let mut events = app
                    .handle(&Command::NoteMoveAgreed {
                        seq: remote_entry.seq,
                        co_sig: sig,
                    })
                    .map_err(|err| err.to_string())?;
                events.extend(app.drain());
                guard.outbox.extend(events);
            }
            continue;
        }
        if remote_entry.seq != local.len() as u64 {
            return Err("resume rejected: log gap".to_string());
        }
        let (events, agreement) = {
            let app = guard
                .app
                .as_mut()
                .ok_or_else(|| "resume rejected: no session".to_string())?;
            app.ingest_remote(remote_entry)
                .map_err(|err| err.to_string())?;
            let events = app.drain();
            let agreement = if remote_entry.seq > 0 {
                match app.query(&Query::MoveLog) {
                    Ok(QueryResult::MoveLog(entries)) => entries
                        .last()
                        .and_then(|entry| entry.co_sig)
                        .map(|sig| (remote_entry.seq, sig)),
                    _ => None,
                }
            } else {
                None
            };
            (events, agreement)
        };
        guard.outbox.extend(events);
        if let Some(agreement) = agreement {
            agreements.push(agreement);
        }
    }
    Ok(agreements)
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

fn profile_path(identity_path: &str) -> std::path::PathBuf {
    std::path::Path::new(identity_path).with_extension("profile")
}

fn load_profile_name(path: &std::path::Path) -> Result<Option<String>, String> {
    match std::fs::read_to_string(path) {
        Ok(value) => {
            clean_player_name(&value).map_err(|_| "saved player name is invalid".to_string())
        }
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(err) => Err(format!("could not read player profile: {err}")),
    }
}

fn save_profile_name(path: &std::path::Path, name: Option<&str>) -> Result<(), String> {
    std::fs::write(path, name.unwrap_or_default())
        .map_err(|err| format!("could not save player profile: {err}"))
}

fn fallback_player_name(peer: PeerId) -> String {
    format!("Player {}", peer)
}

fn player_name(core: &CoreState, peer: PeerId) -> String {
    if peer == core.me
        && let Some(name) = core.display_name.as_deref()
    {
        return name.to_string();
    }
    if core.ai.as_ref().is_some_and(|ai| ai.peer == peer) {
        return "Chess AI".to_string();
    }
    fallback_player_name(peer)
}

/// Pure terminal mapping: session facts to (reason, actor, winner, loser).
/// Identity only, no names or Dictionary shaping: the live-game modal bug
/// (a resignation showing Defeat to the winner) came from inferring the
/// winner out of a display string instead of this mapping.
fn terminal_outcome(
    session: &crate::app::SessionStateView,
) -> (&'static str, Option<PeerId>, Option<PeerId>, Option<PeerId>) {
    match session.state {
        SessionState::Finished(FinishReason::Resignation { by }) => (
            "resignation",
            Some(by),
            Some(if by == session.white {
                session.black
            } else {
                session.white
            }),
            Some(by),
        ),
        SessionState::Finished(FinishReason::Abort { by }) => ("abort", Some(by), None, None),
        SessionState::Finished(FinishReason::AgreedDraw) => ("agreed_draw", None, None, None),
        SessionState::Finished(FinishReason::Rules(outcome)) => match outcome {
            crate::chess_core::Outcome::Checkmate { winner: side } => {
                let winner = if side == ChessColor::White {
                    session.white
                } else {
                    session.black
                };
                let loser = if winner == session.white {
                    session.black
                } else {
                    session.white
                };
                ("checkmate", None, Some(winner), Some(loser))
            }
            crate::chess_core::Outcome::Stalemate => ("stalemate", None, None, None),
            crate::chess_core::Outcome::Draw(_) => ("draw", None, None, None),
            crate::chess_core::Outcome::Ongoing => ("ongoing", None, None, None),
        },
        _ => ("ongoing", None, None, None),
    }
}

/// Shared display-name rule: trim, reject long or control-bearing text,
/// fold empty to the deterministic fallback. One rule for saves and loads
/// so a name the UI accepts can never fail to reload.
fn clean_player_name(raw: &str) -> Result<Option<String>, String> {
    let name = raw.trim().to_string();
    if name.chars().count() > 24 || name.chars().any(char::is_control) {
        return Err("player name must be 24 characters or fewer".to_string());
    }
    Ok((!name.is_empty()).then_some(name))
}

/// Whether the local application session reached a terminal state.
/// Rematch may only be requested, accepted, or applied from there:
/// resetting earlier would discard a live match (AUDIT-REMATCH-001).
fn session_is_finished(core: &CoreState) -> bool {
    core.app
        .as_ref()
        .and_then(|app| app.query(&Query::SessionState).ok())
        .is_some_and(|result| {
            matches!(
                result,
                QueryResult::SessionState(view)
                    if matches!(view.state, SessionState::Finished(_))
            )
        })
}

/// Send-gate for a rematch request, extracted so the rule is unit
/// testable without a Godot runtime: network must exist and the session
/// must already be finished. Returns the command channel on success.
fn can_request_rematch(
    core: &CoreState,
) -> Result<tokio::sync::mpsc::UnboundedSender<NetCmd>, &'static str> {
    let Some(tx) = core.net.as_ref().map(|net| net.cmd_tx.clone()) else {
        return Err("no network active");
    };
    if !session_is_finished(core) {
        return Err("rematch is only available after the game ends");
    }
    Ok(tx)
}

/// Accept-gate for answering a rematch request, extracted for the same
/// reason: the pending ID must match, the network must exist, and an
/// acceptance requires a finished session.
fn rematch_response_error(
    core: &CoreState,
    rematch_id: u64,
    accepted: bool,
) -> Option<&'static str> {
    match core.pending_rematch {
        None => Some("rematch is no longer pending"),
        Some((pending_id, _)) if pending_id != rematch_id => Some("rematch identifier mismatch"),
        Some(_) if core.net.is_none() => Some("no network active"),
        Some(_) if accepted && !session_is_finished(core) => {
            Some("rematch is only available after the game ends")
        }
        Some(_) => None,
    }
}

fn result_snapshot(core: &CoreState) -> Dictionary<GString, Variant> {
    let mut result = Dictionary::new();
    let Some(app) = core.app.as_ref() else {
        return result;
    };
    let Some(QueryResult::SessionState(session)) = app.query(&Query::SessionState).ok() else {
        return result;
    };
    let (reason, actor, winner, loser) = terminal_outcome(&session);
    result.set("reason", reason);
    result.set(
        "actor_peer",
        actor.map_or_else(String::new, |peer| peer.to_string()),
    );
    result.set(
        "actor_name",
        actor.map_or_else(String::new, |peer| player_name(core, peer)),
    );
    result.set(
        "winner_peer",
        winner.map_or_else(String::new, |peer| peer.to_string()),
    );
    result.set(
        "winner_name",
        winner.map_or_else(String::new, |peer| player_name(core, peer)),
    );
    result.set(
        "loser_peer",
        loser.map_or_else(String::new, |peer| peer.to_string()),
    );
    result.set(
        "loser_name",
        loser.map_or_else(String::new, |peer| player_name(core, peer)),
    );
    result.set(
        "winner_side",
        winner
            .map(|peer| {
                if peer == session.white {
                    "white"
                } else {
                    "black"
                }
            })
            .unwrap_or_default(),
    );
    result.set(
        "loser_side",
        loser
            .map(|peer| {
                if peer == session.white {
                    "white"
                } else {
                    "black"
                }
            })
            .unwrap_or_default(),
    );
    result.set("local_peer", core.me.to_string());
    result.set("local_won", winner == Some(core.me));
    result.set("white_name", player_name(core, session.white));
    result.set("black_name", player_name(core, session.black));
    result
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

/// Derives an in-process local role from the persisted installation seed.
/// This keeps the hot-seat/AI spike usable without shipping a shared identity
/// that makes every installation look like the same peer.
fn derive_role_key(seed: &[u8; 32], label: &[u8]) -> SigningKey {
    let mut hasher = Sha256::new();
    hasher.update(label);
    hasher.update(seed);
    let digest: [u8; 32] = hasher.finalize().into();
    SigningKey::from_bytes(&digest)
}

/// Removes the previous local match before an explicit fresh start.
fn clear_saved_game(path: &str) -> Result<(), crate::session::StoreError> {
    match std::fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(err) => Err(err.into()),
    }
}

fn contains_game_end(events: &[Event]) -> bool {
    events
        .iter()
        .any(|event| matches!(event, Event::GameEnded { .. }))
}

/// Keeps identity material and the peer index in the same installation-owned
/// directory without making the index part of the identity file itself.
fn recent_peers_path(identity_path: &str) -> std::path::PathBuf {
    std::path::Path::new(identity_path).with_file_name("chess_relay_recent_peers.bin")
}

const INVITE_CODE_ALPHABET: &[u8] = b"23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
const INVITE_CODE_LENGTH: usize = 8;

/// Derives the stable user-facing invitation code from the endpoint identity.
///
/// The endpoint identity is already public in the dial ticket, so this does
/// not expose a new secret. Five bits per character gives an exact mapping to
/// the 32-character alphabet without modulo bias.
fn invite_code_from_endpoint_id(endpoint_id: &[u8; 32]) -> String {
    let hash = Sha256::digest(endpoint_id);
    let mut code = String::with_capacity(INVITE_CODE_LENGTH);
    let mut bits = 0u64;
    let mut bit_count = 0u8;

    for &byte in hash.as_slice() {
        bits = (bits << 8) | u64::from(byte);
        bit_count += 8;
        while bit_count >= 5 && code.len() < INVITE_CODE_LENGTH {
            bit_count -= 5;
            let index = ((bits >> bit_count) & 0b1_1111) as usize;
            code.push(INVITE_CODE_ALPHABET[index] as char);
        }
        if code.len() == INVITE_CODE_LENGTH {
            break;
        }
    }
    code
}

struct ChessRelayExtension;

#[gdextension]
unsafe impl ExtensionLibrary for ChessRelayExtension {}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::transport::MemoryTransport;

    #[allow(dead_code)]
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

    async fn poll_until_named(label: &str, condition: impl Fn() -> bool) {
        tokio::time::timeout(Duration::from_secs(10), async {
            while !condition() {
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
        })
        .await
        .unwrap_or_else(|_| panic!("condition met in time: {label}"));
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

    /// Handshake plus one move across memory links: the host starts the
    /// match as White, the guest receives genesis and auto-acknowledges
    /// readiness, both start, and both sides can exchange moves without
    /// resending the peer's already-received entries.
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
        let (host_tx, mut host_rx) = tokio::sync::mpsc::unbounded_channel();
        let (guest_tx, mut guest_rx) = tokio::sync::mpsc::unbounded_channel();

        let host_seed = [7u8; 32];
        let guest_seed = [9u8; 32];
        let host_key = SigningKey::from_bytes(&host_seed);
        let guest_key = SigningKey::from_bytes(&guest_seed);
        let host_peer = PeerId::of(&host_key);
        let guest_peer = PeerId::of(&guest_key);

        {
            let mut guard = host_core.lock().unwrap();
            guard.net_generation = 1;
            guard.me = host_peer;
            guard.remote_peer = Some(guest_peer);
            guard.local_secret = Some(host_key.clone());
            guard.app = Some(App::with_local(host_key));
        }
        {
            let mut guard = guest_core.lock().unwrap();
            guard.net_generation = 1;
            guard.me = guest_peer;
            guard.remote_peer = Some(host_peer);
            guard.local_secret = Some(guest_key.clone());
            guard.app = Some(App::with_local(guest_key));
        }

        let host_task = tokio::spawn({
            let core = Arc::clone(&host_core);
            async move {
                drive_session(&core, host_conn, String::new(), &mut host_rx, 1, true, true).await;
            }
        });
        let guest_task = tokio::spawn({
            let core = Arc::clone(&guest_core);
            async move {
                drive_session(
                    &core,
                    guest_conn,
                    String::new(),
                    &mut guest_rx,
                    1,
                    false,
                    true,
                )
                .await;
            }
        });

        // Host starts the game
        let (events, genesis) = {
            let mut guard = host_core.lock().unwrap();
            let app = guard.app.as_mut().unwrap();
            let events = app
                .handle(&Command::StartGame {
                    white: host_peer,
                    black: guest_peer,
                })
                .unwrap();
            let genesis = match app.query(&Query::MoveLog).unwrap() {
                QueryResult::MoveLog(entries) => entries[0],
                _ => panic!("missing genesis"),
            };
            (events, genesis)
        };
        host_core.lock().unwrap().outbox.extend(events);
        host_tx
            .send(NetCmd::HostStarted {
                genesis: Box::new(genesis),
                revision: 1,
                side: "White".to_string(),
                time: "5 | 3".to_string(),
                variant: "Standard".to_string(),
            })
            .unwrap();

        // Wait until guest receives hello and sets up session
        poll_until(|| {
            let guard = guest_core.lock().unwrap();
            guard
                .app
                .as_ref()
                .and_then(|a| a.query(&Query::SessionState).ok())
                .is_some()
        })
        .await;

        // The guest auto-acknowledges the host's readiness.
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
                    peer: host_peer,
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

        {
            let mut guard = guest_core
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            let app = guard.app.as_mut().expect("guest session live");
            let events = app
                .handle(&Command::SubmitMove {
                    peer: guest_peer,
                    mv: "e7e5".parse().unwrap(),
                })
                .expect("guest reply legal after host move");
            let mut all = events;
            all.extend(app.drain());
            guard.outbox.extend(all);
        }
        guest_tx.send(NetCmd::Flush).unwrap();
        poll_until(|| move_log_len(&host_core) == 3 && move_log_len(&guest_core) == 3).await;
        poll_until(|| has_move_agreed(&guest_core, 2)).await;
        assert_eq!(fen_of(&host_core), fen_of(&guest_core));

        // A rematch is a protocol exchange, not a local scene reset. The
        // game must finish first: rematch from a live position is
        // rejected, so the host resigns, the entry crosses on the wire,
        // and both sides observe the terminal state before resetting.
        {
            let mut guard = host_core
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            let app = guard.app.as_mut().expect("host session live");
            let events = app
                .handle(&Command::Resign { peer: host_peer })
                .expect("host resignation legal mid-game");
            let mut all = events;
            all.extend(app.drain());
            guard.outbox.extend(all);
        }
        host_tx.send(NetCmd::Flush).unwrap();
        poll_until_named("both peers observe the terminal state", || {
            let host_done = host_core
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner())
                .app
                .as_ref()
                .and_then(|app| app.query(&Query::SessionState).ok())
                .is_some_and(|result| {
                    matches!(
                        result,
                        QueryResult::SessionState(view)
                            if matches!(view.state, SessionState::Finished(_))
                    )
                });
            let guest_done = guest_core
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner())
                .app
                .as_ref()
                .and_then(|app| app.query(&Query::SessionState).ok())
                .is_some_and(|result| {
                    matches!(
                        result,
                        QueryResult::SessionState(view)
                            if matches!(view.state, SessionState::Finished(_))
                    )
                });
            host_done && guest_done
        })
        .await;
        // The guest receives the request, accepts it, and both authenticated
        // peers enter a fresh setup generation with an empty move log.
        host_core
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .outgoing_rematch = Some(41);
        host_tx
            .send(NetCmd::RematchRequest { rematch_id: 41 })
            .unwrap();
        poll_until_named("guest received rematch request", || {
            guest_core
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner())
                .pending_rematch
                == Some((41, host_peer))
        })
        .await;
        {
            let mut guard = guest_core
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            reset_for_rematch(&mut guard, false);
        }
        guest_tx
            .send(NetCmd::RematchResponse {
                rematch_id: 41,
                accepted: true,
            })
            .unwrap();
        tokio::time::sleep(Duration::from_millis(200)).await;
        let host_generation = host_core
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .rematch_generation;
        let guest_generation = guest_core
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .rematch_generation;
        assert_eq!(
            (
                move_log_len(&host_core),
                move_log_len(&guest_core),
                host_generation,
                guest_generation
            ),
            (0, 0, 1, 1),
            "both peers must reset for rematch"
        );

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

    #[tokio::test]
    async fn rematch_control_rejects_stale_and_handles_decline_and_duplicate() {
        let hub = MemoryTransport::new();
        let mut host_ep = hub.endpoint();
        let mut guest_ep = hub.endpoint();
        let ticket = host_ep.ticket();
        let _guest_conn = guest_ep.connect(&ticket).await.unwrap();
        let mut host_conn = host_ep.accept().await.unwrap();
        let host_peer = peer_of([31u8; 32]);
        let guest_peer = peer_of([32u8; 32]);
        let host_core = Arc::new(Mutex::new(CoreState::default()));
        let guest_core = Arc::new(Mutex::new(CoreState::default()));
        {
            let mut guard = host_core.lock().unwrap();
            guard.me = host_peer;
            guard.remote_peer = Some(guest_peer);
            guard.outgoing_rematch = Some(7);
        }
        {
            let mut guard = guest_core.lock().unwrap();
            guard.me = guest_peer;
            guard.remote_peer = Some(host_peer);
            // A finished session: play the real handshake, then resign, so
            // rematch requests below are decided against a terminal state.
            let (_host_app, guest_app, _, _) = playing_pair([31u8; 32], [32u8; 32]);
            let mut guest_app = guest_app;
            guest_app
                .handle(&Command::Resign { peer: guest_peer })
                .expect("guest resignation finishes");
            guard.app = Some(guest_app);
        }

        let stale = on_msg(
            &host_core,
            &mut host_conn,
            Msg::RematchResponse {
                rematch_id: 99,
                accepted: true,
            },
            0,
            true,
        )
        .await;
        assert!(stale.is_err(), "stale rematch IDs must be rejected");
        assert_eq!(
            host_core.lock().unwrap().outgoing_rematch,
            Some(7),
            "a stale response must not consume the pending request"
        );

        on_msg(
            &host_core,
            &mut host_conn,
            Msg::RematchResponse {
                rematch_id: 7,
                accepted: false,
            },
            0,
            true,
        )
        .await
        .expect("matching decline is a valid response");
        assert_eq!(
            host_core.lock().unwrap().outgoing_rematch,
            None,
            "decline clears the pending request"
        );

        on_msg(
            &guest_core,
            &mut host_conn,
            Msg::RematchRequest { rematch_id: 8 },
            0,
            false,
        )
        .await
        .expect("first rematch request is accepted");
        on_msg(
            &guest_core,
            &mut host_conn,
            Msg::RematchRequest { rematch_id: 8 },
            0,
            false,
        )
        .await
        .expect("duplicate rematch request is idempotent");
        assert_eq!(
            guest_core.lock().unwrap().pending_rematch,
            Some((8, host_peer)),
            "duplicate request must not create a different pending ID"
        );
    }

    /// Drives two apps through the real handshake to a playing session:
    /// host starts, guest joins from genesis, genesis is co-signed both
    /// ways, both sides ready. Returns host app, guest app, host peer,
    /// guest peer.
    fn playing_pair(host_seed: [u8; 32], guest_seed: [u8; 32]) -> (App, App, PeerId, PeerId) {
        let host_peer = peer_of(host_seed);
        let guest_peer = peer_of(guest_seed);
        let mut host_app = App::with_local(SigningKey::from_bytes(&host_seed));
        host_app
            .handle(&Command::StartGame {
                white: host_peer,
                black: guest_peer,
            })
            .expect("host session starts");
        let genesis = match host_app.query(&Query::MoveLog).expect("move log readable") {
            QueryResult::MoveLog(entries) => entries[0],
            _ => unreachable!("move log query answers with entries"),
        };
        let mut guest_app = App::with_local(SigningKey::from_bytes(&guest_seed));
        guest_app
            .handle(&Command::JoinGame {
                peer: guest_peer,
                genesis: Box::new(genesis),
            })
            .expect("guest session joins");
        let co_sig = match guest_app.query(&Query::MoveLog).expect("move log readable") {
            QueryResult::MoveLog(entries) => entries[0].co_sig.expect("guest co-signs genesis"),
            _ => unreachable!("move log query answers with entries"),
        };
        host_app
            .handle(&Command::NotePeerJoined {
                peer: guest_peer,
                co_sig,
            })
            .expect("host notes guest arrival");
        host_app
            .handle(&Command::NotePeerReady { peer: guest_peer })
            .expect("host notes guest readiness");
        host_app
            .handle(&Command::SetReady { peer: host_peer })
            .expect("host readies");
        guest_app
            .handle(&Command::NotePeerReady { peer: host_peer })
            .expect("guest notes host readiness");
        guest_app
            .handle(&Command::SetReady { peer: guest_peer })
            .expect("guest readies");
        (host_app, guest_app, host_peer, guest_peer)
    }

    /// A rematch request against a live game is ignored without storing
    /// anything: only a finished session may reset (AUDIT-REMATCH-001).
    #[tokio::test]
    async fn rematch_request_requires_a_finished_game() {
        let hub = MemoryTransport::new();
        let mut host_ep = hub.endpoint();
        let mut guest_ep = hub.endpoint();
        let ticket = host_ep.ticket();
        let _guest_conn = guest_ep.connect(&ticket).await.unwrap();
        let mut host_conn = host_ep.accept().await.unwrap();
        let (host_app, _guest_app, host_peer, guest_peer) = playing_pair([33u8; 32], [34u8; 32]);
        let core = Arc::new(Mutex::new(CoreState::default()));
        {
            let mut guard = core.lock().unwrap();
            guard.me = host_peer;
            guard.remote_peer = Some(guest_peer);
            guard.app = Some(host_app);
        }

        on_msg(
            &core,
            &mut host_conn,
            Msg::RematchRequest { rematch_id: 3 },
            0,
            true,
        )
        .await
        .expect("live-game rematch stays connected");
        assert_eq!(
            core.lock().unwrap().pending_rematch,
            None,
            "a live game must not store a rematch request"
        );

        {
            let mut guard = core.lock().unwrap();
            guard
                .app
                .as_mut()
                .expect("session live")
                .handle(&Command::Resign { peer: host_peer })
                .expect("resignation finishes");
        }
        on_msg(
            &core,
            &mut host_conn,
            Msg::RematchRequest { rematch_id: 4 },
            0,
            true,
        )
        .await
        .expect("finished-game rematch is accepted");
        assert_eq!(
            core.lock().unwrap().pending_rematch,
            Some((4, guest_peer)),
            "a finished game stores the rematch request"
        );
    }

    /// Forged readiness is rejected: only the authenticated transport peer
    /// may mark itself ready (AUDIT-AUTH-001).
    #[tokio::test]
    async fn forged_readiness_is_rejected() {
        let hub = MemoryTransport::new();
        let mut host_ep = hub.endpoint();
        let mut guest_ep = hub.endpoint();
        let ticket = host_ep.ticket();
        let mut guest_conn = guest_ep.connect(&ticket).await.unwrap();
        let _host_conn = host_ep.accept().await.unwrap();
        let host_peer = peer_of([35u8; 32]);
        let guest_peer = peer_of([36u8; 32]);
        let core = Arc::new(Mutex::new(CoreState::default()));
        {
            let mut guard = core.lock().unwrap();
            guard.me = guest_peer;
            guard.remote_peer = Some(host_peer);
            // Guest joins from the host genesis so the session sits in
            // SettingUp, where readiness is actually decided.
            let mut host_app = App::with_local(SigningKey::from_bytes(&[35u8; 32]));
            host_app
                .handle(&Command::StartGame {
                    white: host_peer,
                    black: guest_peer,
                })
                .expect("host session starts");
            let genesis = match host_app.query(&Query::MoveLog).expect("move log readable") {
                QueryResult::MoveLog(entries) => entries[0],
                _ => unreachable!("move log query answers with entries"),
            };
            let mut app = App::with_local(SigningKey::from_bytes(&[36u8; 32]));
            app.handle(&Command::JoinGame {
                peer: guest_peer,
                genesis: Box::new(genesis),
            })
            .expect("guest session joins");
            guard.app = Some(app);
        }

        // This core is the guest: the wire peer is the host, so the only
        // legitimate readiness on this side is the host's own. A message
        // marking the guest ready from the wire short-circuits the local
        // readiness path.
        let forged = on_msg(
            &core,
            &mut guest_conn,
            Msg::Ready { peer: guest_peer },
            0,
            false,
        )
        .await;
        assert!(
            forged.is_err(),
            "readiness claimed for the other side must fail"
        );
        on_msg(
            &core,
            &mut guest_conn,
            Msg::Ready { peer: host_peer },
            0,
            false,
        )
        .await
        .expect("the transport peer may mark itself ready");
    }

    /// Guest-originated setup snapshots are rejected: setup is
    /// host-owned (AUDIT-AUTH-001).
    #[tokio::test]
    async fn guest_setup_is_rejected() {
        let hub = MemoryTransport::new();
        let mut host_ep = hub.endpoint();
        let mut guest_ep = hub.endpoint();
        let ticket = host_ep.ticket();
        let mut guest_conn = guest_ep.connect(&ticket).await.unwrap();
        let _host_conn = host_ep.accept().await.unwrap();
        let core = Arc::new(Mutex::new(CoreState::default()));
        let setup = Msg::Setup {
            revision: 1,
            side: "White".to_string(),
            time: "5 | 3".to_string(),
            variant: "Standard".to_string(),
        };
        let rejected = on_msg(&core, &mut guest_conn, setup.clone(), 0, true).await;
        assert!(
            rejected.is_err(),
            "a host must never accept a guest setup snapshot"
        );
        on_msg(&core, &mut guest_conn, setup, 0, false)
            .await
            .expect("a guest accepts host setup");
    }

    /// Rematch send/accept gates without a Godot runtime: no network,
    /// live game, stale ID, and the finished-game pass case
    /// (AUDIT-REMATCH-001).
    #[test]
    fn rematch_predicates_require_network_and_finished_game() {
        let bare = CoreState::default();
        assert_eq!(can_request_rematch(&bare).unwrap_err(), "no network active");
        assert_eq!(
            rematch_response_error(&bare, 1, true),
            Some("rematch is no longer pending")
        );

        let runtime = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .unwrap();
        let endpoint = runtime
            .block_on(crate::IrohEndpoint::bind_with_seed([71u8; 32]))
            .unwrap();
        let (cmd_tx, _cmd_rx) = tokio::sync::mpsc::unbounded_channel();
        let (host_app, _guest_app, host_peer, guest_peer) = playing_pair([71u8; 32], [72u8; 32]);
        let mut live = CoreState {
            me: host_peer,
            remote_peer: Some(guest_peer),
            net: Some(NetState {
                runtime,
                endpoint,
                cmd_tx,
                invite_code: None,
            }),
            app: Some(host_app),
            ..Default::default()
        };
        assert_eq!(
            can_request_rematch(&live).unwrap_err(),
            "rematch is only available after the game ends"
        );
        live.pending_rematch = Some((9, guest_peer));
        assert_eq!(
            rematch_response_error(&live, 9, true),
            Some("rematch is only available after the game ends")
        );
        assert_eq!(
            rematch_response_error(&live, 8, true),
            Some("rematch identifier mismatch")
        );

        live.app
            .as_mut()
            .expect("session live")
            .handle(&Command::Resign { peer: host_peer })
            .expect("resignation finishes");
        live.pending_rematch = Some((9, guest_peer));
        assert!(
            can_request_rematch(&live).is_ok(),
            "a finished game may request rematch"
        );
        assert_eq!(rematch_response_error(&live, 9, true), None);
        assert_eq!(rematch_response_error(&live, 9, false), None);
    }

    /// A redial from the peer whose invitation already became a game
    /// resumes that session instead of re-running the invite handshake
    /// (AUDIT-INVITE-RECONNECT-001). The routing predicate below is the    /// unit under test; the reconnected `drive_session` resume itself is
    /// covered by the sync/resume path tests. A loopback-Iroh accept-loop
    /// test remains open (needs real endpoints, not memory transport).
    /// The computer opponent resolves through the same naming authority
    /// as humans: reserved AI identity renders a stable label, strangers
    /// render deterministic fallbacks, never invented names.
    #[test]
    fn ai_peer_resolves_through_the_same_naming_authority() {
        let me = peer_of([81u8; 32]);
        let ai_peer = peer_of([82u8; 32]);
        let stranger = peer_of([83u8; 32]);
        let (request_tx, _request_rx) = std::sync::mpsc::channel();
        let (_result_tx, result_rx) = std::sync::mpsc::channel();
        let core = CoreState {
            me,
            ai: Some(AiState {
                peer: ai_peer,
                tx: request_tx,
                rx: result_rx,
                control: None,
                generation: 0,
                thread: None,
            }),
            ..Default::default()
        };
        assert_eq!(player_name(&core, ai_peer), "Chess AI");
        assert_eq!(player_name(&core, me), format!("Player {me}"));
        assert_eq!(player_name(&core, stranger), format!("Player {stranger}"));
    }

    #[test]
    fn invite_redial_routes_to_game_session() {
        let peer = peer_of([61u8; 32]);
        let other = peer_of([62u8; 32]);
        let wrap = |game_peer| {
            Arc::new(Mutex::new(CoreState {
                net_generation: 1,
                game_peer,
                ..Default::default()
            }))
        };
        assert!(
            !redial_resumes_game(&wrap(None), 1, peer),
            "no game yet: a first dial runs the invite handshake"
        );
        assert!(
            redial_resumes_game(&wrap(Some(peer)), 1, peer),
            "accepted game: the same peer's redial resumes the session"
        );
        assert!(
            !redial_resumes_game(&wrap(Some(peer)), 1, other),
            "a different peer still runs the invite handshake"
        );
        assert!(
            !redial_resumes_game(&wrap(Some(peer)), 2, peer),
            "a retired generation never resumes"
        );
    }

    /// An unannounced transport loss marks the known peer offline so the
    /// recent-peer row cannot keep a stale online indicator
    /// (AUDIT-PRESENCE-001).
    #[test]
    fn disconnect_marks_known_peer_offline() {
        let core = Arc::new(Mutex::new(CoreState::default()));
        let peer = peer_of([41u8; 32]);
        {
            let mut guard = core.lock().unwrap();
            guard.net_generation = 1;
            guard.remote_peer = Some(peer);
            guard.presence.insert(peer, PeerPresence::Online);
        }
        note(&core, 1, NetNote::Disconnected);
        let guard = core.lock().unwrap();
        assert_eq!(
            guard.presence.get(&peer),
            Some(&PeerPresence::Offline),
            "disconnect must retire the online observation"
        );
        assert!(
            guard
                .net_notes
                .iter()
                .any(|note| matches!(note, NetNote::PeerOffline(p) if *p == peer)),
            "disconnect must emit the offline transition for the scene thread"
        );
    }

    /// Host chooses Black: guest is assigned White, receives genesis,
    /// guest makes the opening move, and host ingests it.
    #[tokio::test]
    async fn session_drives_host_as_black_over_memory() {
        let hub = MemoryTransport::new();
        let mut host_ep = hub.endpoint();
        let mut guest_ep = hub.endpoint();
        let ticket = host_ep.ticket();
        let guest_conn = guest_ep.connect(&ticket).await.unwrap();
        let host_conn = host_ep.accept().await.unwrap();

        let host_core = Arc::new(Mutex::new(CoreState::default()));
        let guest_core = Arc::new(Mutex::new(CoreState::default()));
        let (host_tx, mut host_rx) = tokio::sync::mpsc::unbounded_channel();
        let (guest_tx, mut guest_rx) = tokio::sync::mpsc::unbounded_channel();

        let host_seed = [21u8; 32];
        let guest_seed = [22u8; 32];
        let host_key = SigningKey::from_bytes(&host_seed);
        let guest_key = SigningKey::from_bytes(&guest_seed);
        let host_peer = PeerId::of(&host_key);
        let guest_peer = PeerId::of(&guest_key);

        {
            let mut guard = host_core.lock().unwrap();
            guard.net_generation = 1;
            guard.me = host_peer;
            guard.remote_peer = Some(guest_peer);
            guard.app = Some(App::with_local(host_key));
        }
        {
            let mut guard = guest_core.lock().unwrap();
            guard.net_generation = 1;
            guard.me = guest_peer;
            guard.remote_peer = Some(host_peer);
            guard.app = Some(App::with_local(guest_key));
        }

        let host_task = tokio::spawn({
            let core = Arc::clone(&host_core);
            async move {
                drive_session(&core, host_conn, String::new(), &mut host_rx, 1, true, true).await;
            }
        });
        let guest_task = tokio::spawn({
            let core = Arc::clone(&guest_core);
            async move {
                drive_session(
                    &core,
                    guest_conn,
                    String::new(),
                    &mut guest_rx,
                    1,
                    false,
                    true,
                )
                .await;
            }
        });

        // Host starts game choosing Black (guest is White, host is Black)
        let (events, genesis) = {
            let mut guard = host_core.lock().unwrap();
            let app = guard.app.as_mut().unwrap();
            let events = app
                .handle(&Command::StartGame {
                    white: guest_peer,
                    black: host_peer,
                })
                .unwrap();
            let genesis = match app.query(&Query::MoveLog).unwrap() {
                QueryResult::MoveLog(entries) => entries[0],
                _ => panic!("missing genesis"),
            };
            (events, genesis)
        };
        host_core.lock().unwrap().outbox.extend(events);
        host_tx
            .send(NetCmd::HostStarted {
                genesis: Box::new(genesis),
                revision: 1,
                side: "White".to_string(),
                time: "5 | 3".to_string(),
                variant: "Standard".to_string(),
            })
            .unwrap();

        poll_until(|| {
            let guard = guest_core.lock().unwrap();
            guard
                .app
                .as_ref()
                .and_then(|a| a.query(&Query::SessionState).ok())
                .is_some()
        })
        .await;

        // The guest auto-acknowledges the host's readiness.
        poll_until(|| has_game_started(&host_core) && has_game_started(&guest_core)).await;

        // Guest is White: plays e2e4
        {
            let mut guard = guest_core
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            let app = guard.app.as_mut().expect("guest session live");
            let events = app
                .handle(&Command::SubmitMove {
                    peer: guest_peer,
                    mv: "e2e4".parse().unwrap(),
                })
                .expect("guest opening move legal");
            let mut all = events;
            all.extend(app.drain());
            guard.outbox.extend(all);
        }
        guest_tx.send(NetCmd::Flush).unwrap();

        poll_until(|| move_log_len(&host_core) == 2 && move_log_len(&guest_core) == 2).await;
        poll_until(|| has_move_agreed(&guest_core, 1)).await;
        assert_eq!(fen_of(&host_core), fen_of(&guest_core));

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

    /// Resignation over memory link: guest resigns, host ingests the
    /// entry, and host outbox reflects GameEnded.
    #[tokio::test]
    async fn session_drives_resignation_over_memory() {
        let hub = MemoryTransport::new();
        let mut host_ep = hub.endpoint();
        let mut guest_ep = hub.endpoint();
        let ticket = host_ep.ticket();
        let guest_conn = guest_ep.connect(&ticket).await.unwrap();
        let host_conn = host_ep.accept().await.unwrap();

        let host_core = Arc::new(Mutex::new(CoreState::default()));
        let guest_core = Arc::new(Mutex::new(CoreState::default()));
        let (host_tx, mut host_rx) = tokio::sync::mpsc::unbounded_channel();
        let (guest_tx, mut guest_rx) = tokio::sync::mpsc::unbounded_channel();

        let host_seed = [11u8; 32];
        let guest_seed = [12u8; 32];
        let host_key = SigningKey::from_bytes(&host_seed);
        let guest_key = SigningKey::from_bytes(&guest_seed);
        let host_peer = PeerId::of(&host_key);
        let guest_peer = PeerId::of(&guest_key);

        {
            let mut guard = host_core.lock().unwrap();
            guard.net_generation = 1;
            guard.me = host_peer;
            guard.remote_peer = Some(guest_peer);
            guard.app = Some(App::with_local(host_key));
        }
        {
            let mut guard = guest_core.lock().unwrap();
            guard.net_generation = 1;
            guard.me = guest_peer;
            guard.remote_peer = Some(host_peer);
            guard.app = Some(App::with_local(guest_key));
        }

        let host_task = tokio::spawn({
            let core = Arc::clone(&host_core);
            async move {
                drive_session(&core, host_conn, String::new(), &mut host_rx, 1, true, true).await;
            }
        });
        let guest_task = tokio::spawn({
            let core = Arc::clone(&guest_core);
            async move {
                drive_session(
                    &core,
                    guest_conn,
                    String::new(),
                    &mut guest_rx,
                    1,
                    false,
                    true,
                )
                .await;
            }
        });

        // Host starts game
        let (events, genesis) = {
            let mut guard = host_core.lock().unwrap();
            let app = guard.app.as_mut().unwrap();
            let events = app
                .handle(&Command::StartGame {
                    white: host_peer,
                    black: guest_peer,
                })
                .unwrap();
            let genesis = match app.query(&Query::MoveLog).unwrap() {
                QueryResult::MoveLog(entries) => entries[0],
                _ => panic!("missing genesis"),
            };
            (events, genesis)
        };
        host_core.lock().unwrap().outbox.extend(events);
        host_tx
            .send(NetCmd::HostStarted {
                genesis: Box::new(genesis),
                revision: 1,
                side: "White".to_string(),
                time: "5 | 3".to_string(),
                variant: "Standard".to_string(),
            })
            .unwrap();

        poll_until(|| {
            let guard = guest_core.lock().unwrap();
            guard
                .app
                .as_ref()
                .and_then(|a| a.query(&Query::SessionState).ok())
                .is_some()
        })
        .await;

        // The guest auto-acknowledges the host's readiness.
        poll_until(|| has_game_started(&host_core) && has_game_started(&guest_core)).await;

        {
            let mut guard = guest_core.lock().unwrap();
            let app = guard.app.as_mut().expect("guest session live");
            let events = app
                .handle(&Command::Resign { peer: guest_peer })
                .expect("guest resignation accepted");
            guard.outbox.extend(events);
        }
        guest_tx.send(NetCmd::Flush).unwrap();

        poll_until(|| {
            host_core
                .lock()
                .unwrap()
                .outbox
                .iter()
                .any(|e| matches!(e, Event::GameEnded { .. }))
        })
        .await;

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
                invite_code: None,
            });
        }
        spawner.spawn(accept_task(
            core.clone(),
            endpoint,
            1,
            cmd_rx,
            AcceptMode::Game,
        ));
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

    #[test]
    fn installation_identity_is_created_once_and_reused() {
        let path = std::env::temp_dir().join(format!(
            "chess-relay-identity-{}-{}",
            std::process::id(),
            std::thread::current().name().unwrap_or("test")
        ));
        let path = path.to_string_lossy().into_owned();
        let _ = std::fs::remove_file(&path);

        let first = load_or_create_seed(&path).expect("identity is created");
        let second = load_or_create_seed(&path).expect("identity is loaded");

        assert_eq!(first, second);
        assert_eq!(std::fs::metadata(&path).expect("identity exists").len(), 32);
        std::fs::remove_file(path).expect("test identity is removed");
    }

    /// The live-game modal bug: a resignation named the resigner by peer ID
    /// in a display string, and Godot showed Defeat to the winner. The
    /// winner must come out of this mapping by identity.
    #[test]
    fn resignation_names_winner_by_identity() {
        let white = peer_of([11u8; 32]);
        let black = peer_of([12u8; 32]);
        let session = crate::app::SessionStateView {
            state: SessionState::Finished(FinishReason::Resignation { by: black }),
            white,
            black,
            host: white,
            white_ready: true,
            black_ready: true,
        };
        let (reason, actor, winner, loser) = terminal_outcome(&session);
        assert_eq!(reason, "resignation");
        assert_eq!(actor, Some(black));
        assert_eq!(winner, Some(white));
        assert_eq!(loser, Some(black));
    }

    #[test]
    fn player_name_rule_trims_and_rejects() {
        assert_eq!(
            clean_player_name("  Alex  ").expect("padded name trims"),
            Some("Alex".to_string())
        );
        assert_eq!(clean_player_name("").expect("empty clears"), None);
        assert!(clean_player_name(&"x".repeat(25)).is_err());
        assert!(clean_player_name("a\tb").is_err());
    }

    #[test]
    fn invite_code_is_stable_and_has_the_public_shape() {
        let first_id = [7u8; 32];
        let second_id = [8u8; 32];
        let code = invite_code_from_endpoint_id(&first_id);
        assert_eq!(code.len(), INVITE_CODE_LENGTH);
        assert!(
            code.bytes()
                .all(|byte| INVITE_CODE_ALPHABET.contains(&byte))
        );
        assert_eq!(code, invite_code_from_endpoint_id(&first_id));
        assert_ne!(code, invite_code_from_endpoint_id(&second_id));
    }
}
