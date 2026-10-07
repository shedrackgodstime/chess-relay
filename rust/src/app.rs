//! Application contract: commands, queries, events.
//!
//! The frozen v1 surface clients program against. Local intent enters as
//! [`Command`]s through [`App::handle`], which returns facts as a vector
//! of [`Event`]s immediately. State reads go through [`App::query`] and
//! never mutate. Entries arriving off-frame (remote moves, later the
//! transport) enter via [`App::ingest_remote`] and wait in an outbox the
//! bridge drains with [`App::drain`] — the exact pattern the Godot bridge
//! will use in `process()`.
//!
//! Names are frozen here (arch doc names were examples). Transport-owned
//! connection events (`PeerDisconnected`, `PeerReconnected`) are reserved
//! for the transport slice and intentionally absent. Remote lifecycle
//! sync (offers, resignations over the wire) likewise arrives with the
//! protocol; [`App::ingest_remote`] accepts moves only.
//!
//! Phase 6 additive lesson: [`Query::LegalMoves`] joined the frozen set.
//! The board must highlight legal targets, and legality lives in the
//! core, so the query has to exist; it changes nothing already frozen.
//!
//! Authority is explicit: the app holds secrets, commands name a peer,
//! and acting without that peer's secret fails with `NotLocal`. The
//! production client holds one key; tests admit two to simulate both
//! sides through the same frozen surface.
//!
//! # Examples
//!
//! ```
//! use chess_relay_core::app::{App, Command, Event, Query, QueryResult};
//! use chess_relay_core::session::PeerId;
//! use ed25519_dalek::SigningKey;
//!
//! let host = SigningKey::from_bytes(&[1u8; 32]);
//! let guest = SigningKey::from_bytes(&[2u8; 32]);
//! let (white, black) = (PeerId::of(&host), PeerId::of(&guest));
//!
//! let mut app = App::with_local(host);
//! let events = app.handle(&Command::StartGame { white, black })?;
//! assert!(matches!(events[0], Event::SessionCreated { .. }));
//! # Ok::<(), chess_relay_core::app::AppError>(())
//! ```

use crate::chess_core::{Color, Move, Outcome, Square};
use crate::session::{
    FinishReason, LogEntry, LogPayload, PeerId, Session, SessionConfig, SessionError, SessionState,
};
use ed25519_dalek::SigningKey;
use std::backtrace::Backtrace;
use std::collections::HashMap;
use std::fmt::{self, Display, Formatter};

/// Local intent: the only way to change application state.
#[derive(Clone, Debug)]
pub enum Command {
    /// Creates a session as host (local must play a side).
    StartGame {
        /// Peer playing White.
        white: PeerId,
        /// Peer playing Black.
        black: PeerId,
    },
    /// Joins as `peer` from the host's genesis entry.
    JoinGame {
        /// Joining peer (must hold its key, must not be host).
        peer: PeerId,
        /// Genesis entry received from the host.
        genesis: Box<LogEntry>,
    },
    /// Records the guest's verified arrival (transport-fed).
    NotePeerJoined {
        /// Arriving guest.
        peer: PeerId,
        /// Guest's genesis co-signature.
        co_sig: [u8; 64],
    },
    /// Marks `peer` ready; second readiness starts play.
    SetReady {
        /// Peer signalling readiness.
        peer: PeerId,
    },
    /// Records `peer`'s readiness as delivered by transport.
    NotePeerReady {
        /// Ready peer.
        peer: PeerId,
    },
    /// Plays a move for the side to move.
    SubmitMove {
        /// Moving peer (must hold its key and the turn).
        peer: PeerId,
        /// Move to play.
        mv: Move,
    },
    /// Records the opponent's verified co-signature (transport-fed).
    NoteMoveAgreed {
        /// Agreed entry sequence.
        seq: u64,
        /// Opponent's co-signature.
        co_sig: [u8; 64],
    },
    /// Resigns unilaterally.
    Resign {
        /// Resigning peer.
        peer: PeerId,
    },
    /// Offers an agreed draw.
    OfferDraw {
        /// Offering peer.
        peer: PeerId,
    },
    /// Answers the open offer.
    AnswerDraw {
        /// Answering peer (must not be the offerer).
        peer: PeerId,
        /// Acceptance ends the session drawn.
        accept: bool,
    },
    /// Cancels unilaterally.
    Abort {
        /// Aborting peer.
        peer: PeerId,
    },
}

/// State reads; never mutate.
#[derive(Clone, Debug)]
pub enum Query {
    /// Current position, turn, and rules outcome.
    GameState,
    /// Lifecycle, participants, and readiness.
    SessionState,
    /// Full signed log in sequence order.
    MoveLog,
    /// Legal moves, optionally departing from one square.
    LegalMoves {
        /// Departure square filter, if any.
        from: Option<Square>,
    },
}

/// Current position snapshot.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GameStateView {
    /// Position in FEN.
    pub fen: String,
    /// Side to move.
    pub side_to_move: Color,
    /// Rules outcome now.
    pub outcome: Outcome,
    /// King square of the side to move while in check, else empty.
    pub check: String,
}

/// Lifecycle snapshot.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SessionStateView {
    /// Lifecycle state.
    pub state: SessionState,
    /// Peer playing White.
    pub white: PeerId,
    /// Peer playing Black.
    pub black: PeerId,
    /// Session host.
    pub host: PeerId,
    /// White's readiness.
    pub white_ready: bool,
    /// Black's readiness.
    pub black_ready: bool,
}

/// Query answers.
#[derive(Clone, Debug)]
pub enum QueryResult {
    /// Answer to [`Query::GameState`].
    GameState(GameStateView),
    /// Answer to [`Query::SessionState`].
    SessionState(SessionStateView),
    /// Answer to [`Query::MoveLog`].
    MoveLog(Vec<LogEntry>),
    /// Answer to [`Query::LegalMoves`].
    LegalMoves(Vec<Move>),
}

/// Facts that already happened: the only thing clients render.
#[derive(Clone, Debug)]
pub enum Event {
    /// Session created by host.
    SessionCreated {
        /// Peer playing White.
        white: PeerId,
        /// Peer playing Black.
        black: PeerId,
        /// Creating host.
        host: PeerId,
    },
    /// Guest arrived (created or joined view).
    PeerJoined {
        /// Arriving peer.
        peer: PeerId,
    },
    /// A peer's readiness flipped.
    ReadyChanged {
        /// Ready peer.
        peer: PeerId,
    },
    /// Both ready; play began.
    GameStarted,
    /// A move entered the log.
    MoveApplied {
        /// Entry sequence.
        seq: u64,
        /// Played move.
        mv: Move,
        /// Moving peer.
        by: PeerId,
        /// Whether both peers have signed.
        agreed: bool,
    },
    /// Opponent co-signed entry `seq`.
    MoveAgreed {
        /// Entry sequence.
        seq: u64,
    },
    /// A remote move failed validation (diagnostic text included).
    MoveRejected {
        /// Human-readable cause for logs and debugging.
        reason: String,
    },
    /// A draw was offered.
    DrawOffered {
        /// Offering peer.
        by: PeerId,
        /// Offer entry sequence.
        seq: u64,
    },
    /// The offer was answered.
    DrawAnswered {
        /// Answering peer.
        by: PeerId,
        /// Acceptance ends the session drawn.
        accept: bool,
    },
    /// The session finished.
    GameEnded {
        /// Why it finished.
        reason: FinishReason,
    },
}

/// Application-layer failure: authority, usage, or session causes.
///
/// Sole error type of this layer. Session failures arrive as causes via
/// `From<SessionError>`.
///
/// # Examples
///
/// ```
/// use chess_relay_core::app::AppError;
///
/// let err = AppError::not_local();
/// assert!(err.is_not_local());
/// ```
#[derive(Debug)]
pub struct AppError {
    kind: AppErrorKind,
    backtrace: Backtrace,
    detail: Option<String>,
    cause: Option<SessionError>,
}

#[derive(Debug)]
enum AppErrorKind {
    /// Acting peer holds no key here.
    NotLocal,
    /// Command unusable now or malformed.
    BadCommand,
    /// Session layer rejected the action.
    Session,
}

impl AppError {
    /// Acting without that peer's secret.
    #[must_use]
    pub fn not_local() -> Self {
        Self::bare(AppErrorKind::NotLocal)
    }

    pub(crate) fn bad_command(detail: String) -> Self {
        Self::caused(AppErrorKind::BadCommand, detail)
    }

    fn bare(kind: AppErrorKind) -> Self {
        Self {
            kind,
            backtrace: Backtrace::capture(),
            detail: None,
            cause: None,
        }
    }

    fn caused(kind: AppErrorKind, detail: String) -> Self {
        Self {
            kind,
            backtrace: Backtrace::capture(),
            detail: Some(detail),
            cause: None,
        }
    }

    /// Whether the acting peer holds no key here.
    #[must_use]
    pub fn is_not_local(&self) -> bool {
        matches!(self.kind, AppErrorKind::NotLocal)
    }

    /// Whether the command was unusable or malformed.
    #[must_use]
    pub fn is_bad_command(&self) -> bool {
        matches!(self.kind, AppErrorKind::BadCommand)
    }

    /// Whether the session layer rejected the action.
    #[must_use]
    pub fn is_session(&self) -> bool {
        matches!(self.kind, AppErrorKind::Session)
    }

    /// Underlying session failure, if any.
    #[must_use]
    pub fn session_cause(&self) -> Option<&SessionError> {
        self.cause.as_ref()
    }
}

impl Display for AppError {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        let summary = match self.kind {
            AppErrorKind::NotLocal => "no key for acting peer",
            AppErrorKind::BadCommand => "command unusable or malformed",
            AppErrorKind::Session => "session rejected the action",
        };
        write!(f, "app error: {summary}")?;
        if let Some(detail) = &self.detail {
            write!(f, " ({detail})")?;
        }
        if let Some(cause) = &self.cause {
            write!(f, " ({cause})")?;
        }
        use std::backtrace::BacktraceStatus::Captured;
        if self.backtrace.status() == Captured {
            write!(f, "\n{}", self.backtrace)?;
        }
        Ok(())
    }
}

impl std::error::Error for AppError {}

impl From<SessionError> for AppError {
    fn from(cause: SessionError) -> Self {
        Self {
            kind: AppErrorKind::Session,
            backtrace: Backtrace::capture(),
            detail: None,
            cause: Some(cause),
        }
    }
}

/// Application root: one session view plus held identities.
pub struct App {
    session: Option<Session>,
    local: PeerId,
    keys: HashMap<PeerId, SigningKey>,
    outbox: Vec<Event>,
}

impl App {
    /// Creates an app holding one local identity.
    #[must_use]
    pub fn with_local(secret: SigningKey) -> Self {
        let local = PeerId::of(&secret);
        let mut keys = HashMap::new();
        keys.insert(local, secret);
        Self {
            session: None,
            local,
            keys,
            outbox: Vec::new(),
        }
    }

    /// Admits another identity (tests and multi-profile clients).
    pub fn admit(&mut self, secret: SigningKey) {
        self.keys.insert(PeerId::of(&secret), secret);
    }

    /// Handles a command, returning facts immediately.
    ///
    /// # Errors
    ///
    /// Returns [`AppError`] for missing authority, misuse, or session
    /// rejection; failed commands change nothing.
    pub fn handle(&mut self, command: &Command) -> Result<Vec<Event>, AppError> {
        match command {
            Command::StartGame { white, black } => {
                if self.session.is_some() {
                    return Err(AppError::bad_command("session already exists".to_string()));
                }
                let config = SessionConfig::new(*white, *black, self.local)
                    .map_err(|_| AppError::not_local())?;
                let secret = self.key_for(self.local)?;
                self.session = Some(Session::create(secret, config)?);
                Ok(vec![Event::SessionCreated {
                    white: *white,
                    black: *black,
                    host: self.local,
                }])
            }
            Command::JoinGame { peer, genesis } => {
                if self.session.is_some() {
                    return Err(AppError::bad_command("session already exists".to_string()));
                }
                let LogPayload::Genesis {
                    white, black, host, ..
                } = genesis.payload
                else {
                    return Err(AppError::bad_command(
                        "join needs a genesis entry".to_string(),
                    ));
                };
                if *peer == host {
                    return Err(AppError::bad_command(
                        "host starts; guests join".to_string(),
                    ));
                }
                let secret = self.key_for(*peer)?.clone();
                let config = SessionConfig::new(white, black, host)?;
                let mut session = Session::join_config(config);
                session.receive(genesis)?;
                session.agree(&secret, 0)?;
                self.session = Some(session);
                Ok(vec![Event::PeerJoined { peer: *peer }])
            }
            Command::NotePeerJoined { peer, co_sig } => {
                let session = self.session_mut()?;
                session.note_peer_joined(*peer, *co_sig)?;
                Ok(vec![Event::PeerJoined { peer: *peer }])
            }
            Command::SetReady { peer } => {
                let secret = self.key_for(*peer)?.clone();
                let local_secret = self.key_for(self.local)?.clone();
                let session = self.session_mut()?;
                let was_setting_up = session.state() == SessionState::SettingUp;
                session.set_ready(&secret)?;
                let mut events = vec![Event::ReadyChanged { peer: *peer }];
                if was_setting_up && session.state() == SessionState::Ready {
                    session.start(&local_secret)?;
                    events.push(Event::GameStarted);
                }
                Ok(events)
            }
            Command::NotePeerReady { peer } => {
                let local_secret = self.key_for(self.local)?.clone();
                let session = self.session_mut()?;
                let was_setting_up = session.state() == SessionState::SettingUp;
                session.note_peer_ready(*peer)?;
                let mut events = vec![Event::ReadyChanged { peer: *peer }];
                if was_setting_up && session.state() == SessionState::Ready {
                    session.start(&local_secret)?;
                    events.push(Event::GameStarted);
                }
                Ok(events)
            }
            Command::SubmitMove { peer, mv } => {
                let secret = self.key_for(*peer)?.clone();
                let session = self.session_mut()?;
                let (seq, _) = session.submit_move(&secret, mv)?;
                let mut events = vec![Event::MoveApplied {
                    seq,
                    mv: *mv,
                    by: *peer,
                    agreed: false,
                }];
                if let Some(reason) = finished_reason(session) {
                    events.push(Event::GameEnded { reason });
                }
                Ok(events)
            }
            Command::NoteMoveAgreed { seq, co_sig } => {
                let session = self.session_mut()?;
                session.note_move_agreed(*seq, *co_sig)?;
                Ok(vec![Event::MoveAgreed { seq: *seq }])
            }
            Command::Resign { peer } => {
                let secret = self.key_for(*peer)?.clone();
                let session = self.session_mut()?;
                session.resign(&secret)?;
                Ok(vec![Event::GameEnded {
                    reason: finish_of(session),
                }])
            }
            Command::OfferDraw { peer } => {
                let secret = self.key_for(*peer)?.clone();
                let session = self.session_mut()?;
                let seq = session.offer_draw(&secret)?;
                Ok(vec![Event::DrawOffered { by: *peer, seq }])
            }
            Command::AnswerDraw { peer, accept } => {
                let secret = self.key_for(*peer)?.clone();
                let session = self.session_mut()?;
                session.answer_draw(&secret, *accept)?;
                let mut events = vec![Event::DrawAnswered {
                    by: *peer,
                    accept: *accept,
                }];
                if *accept {
                    events.push(Event::GameEnded {
                        reason: finish_of(session),
                    });
                }
                Ok(events)
            }
            Command::Abort { peer } => {
                let secret = self.key_for(*peer)?.clone();
                let session = self.session_mut()?;
                session.abort(&secret)?;
                Ok(vec![Event::GameEnded {
                    reason: finish_of(session),
                }])
            }
        }
    }

    /// Restores a session from saved entries (restart recovery).
    ///
    /// Replaces any current session. Emits `GameStarted` when play resumes
    /// or `GameEnded` when the log already finished; a pre-game save
    /// restores silently for readiness to complete.
    ///
    /// # Errors
    ///
    /// Returns [`AppError`] when the log fails validation; the current
    /// session, if any, is left untouched.
    pub fn restore(&mut self, entries: Vec<LogEntry>) -> Result<Vec<Event>, AppError> {
        let session = Session::resume(entries)?;
        self.session = Some(session);
        let session = self.session()?;
        match session.state() {
            SessionState::Playing => Ok(vec![Event::GameStarted]),
            SessionState::Finished(reason) => Ok(vec![Event::GameEnded { reason }]),
            _ => Ok(Vec::new()),
        }
    }

    /// Reads state without changing it.
    ///
    /// # Errors
    ///
    /// Returns [`AppError`] without a session, or before play starts
    /// for [`Query::GameState`].
    pub fn query(&self, query: &Query) -> Result<QueryResult, AppError> {
        let session = self.session()?;
        match query {
            Query::GameState => {
                let game = session
                    .game()
                    .ok_or_else(|| AppError::bad_command("game not started".to_string()))?;
                let board = game.board();
                let side = board.side_to_move();
                let check = if crate::chess_core::is_in_check(board, side) {
                    crate::chess_core::king_square(board, side)
                        .map_or_else(String::new, |sq| sq.to_string())
                } else {
                    String::new()
                };
                Ok(QueryResult::GameState(GameStateView {
                    fen: board.to_fen(),
                    side_to_move: side,
                    outcome: game.outcome(),
                    check,
                }))
            }
            Query::SessionState => {
                let config = session.config();
                Ok(QueryResult::SessionState(SessionStateView {
                    state: session.state(),
                    white: config.white,
                    black: config.black,
                    host: config.host,
                    white_ready: session.is_ready(Color::White),
                    black_ready: session.is_ready(Color::Black),
                }))
            }
            Query::MoveLog => Ok(QueryResult::MoveLog(session.log().to_vec())),
            Query::LegalMoves { from } => {
                let game = session
                    .game()
                    .ok_or_else(|| AppError::bad_command("game not started".to_string()))?;
                let moves = game
                    .legal_moves()
                    .into_iter()
                    .filter(|mv| from.is_none_or(|square| mv.from == square))
                    .collect();
                Ok(QueryResult::LegalMoves(moves))
            }
        }
    }

    /// Ingests a remote move entry: validates, applies, agrees, queues.
    ///
    /// Moves only; remote lifecycle sync arrives with the protocol.
    /// Queues [`Event::MoveApplied`] (or [`Event::MoveRejected`] plus
    /// the error) for [`App::drain`].
    ///
    /// # Errors
    ///
    /// Returns [`AppError`] on any validation failure.
    pub fn ingest_remote(&mut self, entry: &LogEntry) -> Result<(), AppError> {
        let LogPayload::Move { mv } = entry.payload else {
            return Err(AppError::bad_command(
                "remote lifecycle sync arrives with protocol".to_string(),
            ));
        };
        let agreer = self.agreeing_peer(entry.mover)?;
        let local_secret = self.key_for(agreer)?.clone();
        let session = self.session_mut()?;
        if let Err(err) = session.receive(entry).and_then(|()| session.replay_game()) {
            self.outbox.push(Event::MoveRejected {
                reason: err.to_string(),
            });
            return Err(err.into());
        }
        if let Err(err) = session.agree(&local_secret, entry.seq) {
            self.outbox.push(Event::MoveRejected {
                reason: err.to_string(),
            });
            return Err(err.into());
        }
        self.outbox.push(Event::MoveApplied {
            seq: entry.seq,
            mv,
            by: entry.mover,
            agreed: true,
        });
        Ok(())
    }

    /// Takes queued off-frame events (bridge drains this per frame).
    #[must_use]
    pub fn drain(&mut self) -> Vec<Event> {
        std::mem::take(&mut self.outbox)
    }

    fn session(&self) -> Result<&Session, AppError> {
        self.session
            .as_ref()
            .ok_or_else(|| AppError::bad_command("no session".to_string()))
    }

    fn session_mut(&mut self) -> Result<&mut Session, AppError> {
        self.session
            .as_mut()
            .ok_or_else(|| AppError::bad_command("no session".to_string()))
    }

    fn key_for(&self, peer: PeerId) -> Result<&SigningKey, AppError> {
        self.keys.get(&peer).ok_or_else(AppError::not_local)
    }

    fn agreeing_peer(&self, mover: PeerId) -> Result<PeerId, AppError> {
        let session = self.session()?;
        let config = session.config();
        [config.white, config.black]
            .into_iter()
            .find(|peer| *peer != mover && self.keys.contains_key(peer))
            .ok_or_else(AppError::not_local)
    }
}

fn finished_reason(session: &Session) -> Option<FinishReason> {
    match session.state() {
        SessionState::Finished(reason) => Some(reason),
        _ => None,
    }
}

fn finish_of(session: &Session) -> FinishReason {
    finished_reason(session).expect("action finished the session")
}
