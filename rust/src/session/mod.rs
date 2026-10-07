//! Match wrapper: participants, lifecycle, and the move log.
//!
//! A [`Session`] models one peer's view of a match in Phase 2: both
//! participants are known up front (rendezvous is assumed; ticket
//! exchange arrives with transport). Each side constructs its own view
//! locally and exchanges entries; [`Session::receive`] ingests them.
//! The per-peer split of a shared object happens in the transport
//! slice, not here.
//!
//! Lifecycle: `Created -> SettingUp -> Ready -> Playing -> Finished`.
//! Game state and connection state stay separate machines; this layer
//! never blocks on transport.
//!
//! Every state-changing action is appended to the signed log, so two
//! peers holding the same entries hold the same match.
//!
//! # Examples
//!
//! ```
//! use chess_relay_core::session::{Session, SessionConfig};
//! use ed25519_dalek::SigningKey;
//!
//! let host = SigningKey::from_bytes(&[1u8; 32]);
//! let guest = SigningKey::from_bytes(&[2u8; 32]);
//! let config = SessionConfig::new(
//!     chess_relay_core::session::PeerId::of(&host),
//!     chess_relay_core::session::PeerId::of(&guest),
//!     chess_relay_core::session::PeerId::of(&host),
//! )?;
//! let mut session = Session::create(&host, config)?;
//! session.join(&guest)?;
//! # Ok::<(), chess_relay_core::session::SessionError>(())
//! ```

pub(crate) mod log;
pub(crate) mod store;

#[doc(inline)]
pub use log::{LogEntry, LogPayload, PeerId};
#[doc(inline)]
pub use store::{FileStore, LogStore, MemoryStore, StoreError};

use crate::chess_core::{Color, DrawReason, Game, IllegalMove, Move, Outcome};
use ed25519_dalek::{Signer, SigningKey};
use std::backtrace::Backtrace;
use std::fmt::{self, Display, Formatter};

/// Wire protocol version pinned by the genesis entry.
pub const PROTOCOL_VERSION: u16 = 1;

/// Match configuration fixed at creation.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SessionConfig {
    /// Peer playing White.
    pub white: PeerId,
    /// Peer playing Black.
    pub black: PeerId,
    /// Peer that created the session (sets config and sides).
    pub host: PeerId,
    /// Reserved clock configuration; unused in v1.
    pub clock: Option<ClockConfig>,
}

/// Clock configuration placeholder (reserved, unused in v1).
///
/// Present so a future clock needs no breaking change: time control
/// rides here, snapshots ride the protocol, and time never enters
/// signed-log validity.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[non_exhaustive]
pub struct ClockConfig {}

impl SessionConfig {
    /// Fixes sides and host; host must play a side.
    ///
    /// # Errors
    ///
    /// Returns [`SessionError`] when `host` is neither player.
    pub fn new(white: PeerId, black: PeerId, host: PeerId) -> Result<Self, SessionError> {
        if host != white && host != black {
            return Err(SessionError::not_participant());
        }
        Ok(Self {
            white,
            black,
            host,
            clock: None,
        })
    }

    /// Peer playing `side`.
    #[must_use]
    pub fn peer_for(&self, side: Color) -> PeerId {
        log::side_peer(self.white, self.black, side)
    }

    /// Side played by `peer`, if any.
    #[must_use]
    pub fn side_of(&self, peer: PeerId) -> Option<Color> {
        if peer == self.white {
            Some(Color::White)
        } else if peer == self.black {
            Some(Color::Black)
        } else {
            None
        }
    }
}

/// Lifecycle state of a session.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SessionState {
    /// Created by the host; guest unknown.
    Created,
    /// Both peers known; readiness pending.
    SettingUp,
    /// Both peers ready; game not started.
    Ready,
    /// Moves flowing.
    Playing,
    /// Over; see why.
    Finished(FinishReason),
}

/// Why a session finished.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FinishReason {
    /// Chess rules ended the game.
    Rules(Outcome),
    /// `by` resigned unilaterally.
    Resignation {
        /// Resigning peer.
        by: PeerId,
    },
    /// Both peers agreed the draw.
    AgreedDraw,
    /// `by` cancelled the session unilaterally.
    Abort {
        /// Aborting peer.
        by: PeerId,
    },
}

/// Session-layer failure: lifecycle, roles, or log integrity.
///
/// Sole error type of this layer (arch doc §Errors). Chess failures
/// arrive as causes via `From<IllegalMove>`.
///
/// # Examples
///
/// ```
/// use chess_relay_core::session::{PeerId, SessionConfig};
/// use ed25519_dalek::SigningKey;
///
/// let outsider = SigningKey::from_bytes(&[9u8; 32]);
/// let err = SessionConfig::new(
///     PeerId::of(&SigningKey::from_bytes(&[1u8; 32])),
///     PeerId::of(&SigningKey::from_bytes(&[2u8; 32])),
///     PeerId::of(&outsider),
/// )
/// .unwrap_err();
/// assert!(err.is_not_participant());
/// ```
#[derive(Debug)]
pub struct SessionError(Box<SessionErrorInner>);

#[derive(Debug)]
struct SessionErrorInner {
    kind: SessionErrorKind,
    backtrace: Backtrace,
    detail: Option<String>,
    cause: Option<IllegalMove>,
}

#[derive(Debug)]
pub(crate) enum SessionErrorKind {
    /// Action needs a later lifecycle state.
    NotReady,
    /// Unknown peer attempted a participant action.
    NotParticipant,
    /// Move submitted for the other side's turn.
    NotYourTurn,
    /// Action after the session finished.
    GameOver,
    /// Chain, genesis, or replay validation failed.
    LogMismatch,
    /// A signature did not verify.
    BadSignature,
    /// A public key did not decode.
    BadKey,
    /// No entry at the requested sequence.
    UnknownEntry,
    /// Entry cannot be co-signed (not a move or genesis).
    NotAgreeable,
    /// Chess rules rejected the content.
    Chess,
}

impl SessionError {
    pub(crate) fn not_ready() -> Self {
        Self::bare(SessionErrorKind::NotReady)
    }

    pub(crate) fn not_participant() -> Self {
        Self::bare(SessionErrorKind::NotParticipant)
    }

    pub(crate) fn not_your_turn() -> Self {
        Self::bare(SessionErrorKind::NotYourTurn)
    }

    pub(crate) fn game_over() -> Self {
        Self::bare(SessionErrorKind::GameOver)
    }

    pub(crate) fn log_mismatch(text: String) -> Self {
        Self::caused(SessionErrorKind::LogMismatch, text)
    }

    pub(crate) fn bad_signature() -> Self {
        Self::bare(SessionErrorKind::BadSignature)
    }

    pub(crate) fn bad_key() -> Self {
        Self::bare(SessionErrorKind::BadKey)
    }

    pub(crate) fn unknown_entry() -> Self {
        Self::bare(SessionErrorKind::UnknownEntry)
    }

    pub(crate) fn not_agreeable() -> Self {
        Self::bare(SessionErrorKind::NotAgreeable)
    }

    fn bare(kind: SessionErrorKind) -> Self {
        Self(Box::new(SessionErrorInner {
            kind,
            backtrace: Backtrace::capture(),
            detail: None,
            cause: None,
        }))
    }

    fn caused(kind: SessionErrorKind, detail: String) -> Self {
        Self(Box::new(SessionErrorInner {
            kind,
            backtrace: Backtrace::capture(),
            detail: Some(detail),
            cause: None,
        }))
    }

    /// Whether the lifecycle is too early for the action.
    #[must_use]
    pub fn is_not_ready(&self) -> bool {
        matches!(self.0.kind, SessionErrorKind::NotReady)
    }

    /// Whether an outsider attempted a participant action.
    #[must_use]
    pub fn is_not_participant(&self) -> bool {
        matches!(self.0.kind, SessionErrorKind::NotParticipant)
    }

    /// Whether a move missed its side's turn.
    #[must_use]
    pub fn is_not_your_turn(&self) -> bool {
        matches!(self.0.kind, SessionErrorKind::NotYourTurn)
    }

    /// Whether the session already finished.
    #[must_use]
    pub fn is_game_over(&self) -> bool {
        matches!(self.0.kind, SessionErrorKind::GameOver)
    }

    /// Whether log validation failed.
    #[must_use]
    pub fn is_log_mismatch(&self) -> bool {
        matches!(self.0.kind, SessionErrorKind::LogMismatch)
    }

    /// Whether a signature failed verification.
    #[must_use]
    pub fn is_bad_signature(&self) -> bool {
        matches!(self.0.kind, SessionErrorKind::BadSignature)
    }

    /// Whether no entry exists at the sequence.
    #[must_use]
    pub fn is_unknown_entry(&self) -> bool {
        matches!(self.0.kind, SessionErrorKind::UnknownEntry)
    }

    /// Whether the entry cannot be co-signed.
    #[must_use]
    pub fn is_not_agreeable(&self) -> bool {
        matches!(self.0.kind, SessionErrorKind::NotAgreeable)
    }

    /// Whether chess rules rejected the content.
    #[must_use]
    pub fn is_chess(&self) -> bool {
        matches!(self.0.kind, SessionErrorKind::Chess)
    }

    /// Underlying chess failure, if any.
    #[must_use]
    pub fn chess_cause(&self) -> Option<&IllegalMove> {
        self.0.cause.as_ref()
    }
}

impl Display for SessionError {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        let summary = match &self.0.kind {
            SessionErrorKind::NotReady => "session is not ready for that action",
            SessionErrorKind::NotParticipant => "unknown peer for this session",
            SessionErrorKind::NotYourTurn => "move submitted for the other side's turn",
            SessionErrorKind::GameOver => "session already finished",
            SessionErrorKind::LogMismatch => "move log failed validation",
            SessionErrorKind::BadSignature => "signature did not verify",
            SessionErrorKind::BadKey => "peer key did not decode",
            SessionErrorKind::UnknownEntry => "no log entry at that sequence",
            SessionErrorKind::NotAgreeable => "entry cannot be co-signed",
            SessionErrorKind::Chess => "chess rules rejected the content",
        };
        write!(f, "session error: {summary}")?;
        if let Some(detail) = &self.0.detail {
            write!(f, " ({detail})")?;
        }
        if let Some(cause) = &self.0.cause {
            write!(f, " ({cause})")?;
        }
        use std::backtrace::BacktraceStatus::Captured;
        if self.0.backtrace.status() == Captured {
            write!(f, "\n{}", self.0.backtrace)?;
        }
        Ok(())
    }
}

impl std::error::Error for SessionError {}

impl From<IllegalMove> for SessionError {
    fn from(cause: IllegalMove) -> Self {
        Self(Box::new(SessionErrorInner {
            kind: SessionErrorKind::Chess,
            backtrace: Backtrace::capture(),
            detail: None,
            cause: Some(cause),
        }))
    }
}

/// One peer's view of a match (see module docs for Phase 2 scope).
#[derive(Clone, Debug)]
pub struct Session {
    config: SessionConfig,
    state: SessionState,
    white_ready: bool,
    black_ready: bool,
    game: Option<Game>,
    log: Vec<LogEntry>,
    open_offer: Option<u64>,
}

impl Session {
    /// Creates a session; host signs the genesis entry.
    ///
    /// # Errors
    ///
    /// Returns [`SessionError`] when `host` is not configured... (config
    /// construction already enforces it; kept fallible for symmetry).
    pub fn create(host_secret: &SigningKey, config: SessionConfig) -> Result<Self, SessionError> {
        let host = PeerId::of(host_secret);
        if host != config.host {
            return Err(SessionError::not_participant());
        }
        let genesis = LogEntry::signed(
            0,
            [0u8; 32],
            LogPayload::Genesis {
                version: PROTOCOL_VERSION,
                white: config.white,
                black: config.black,
                host: config.host,
            },
            host_secret,
        );
        Ok(Self {
            config,
            state: SessionState::Created,
            white_ready: false,
            black_ready: false,
            game: None,
            log: vec![genesis],
            open_offer: None,
        })
    }

    /// Builds an empty view over known config; fills via [`Session::receive`].
    ///
    /// Used by the joining side (and gap recovery) before any entry
    /// has arrived.
    #[must_use]
    pub fn join_config(config: SessionConfig) -> Self {
        Self {
            config,
            state: SessionState::Created,
            white_ready: false,
            black_ready: false,
            game: None,
            log: Vec::new(),
            open_offer: None,
        }
    }

    /// Current lifecycle state.
    #[must_use]
    pub fn state(&self) -> SessionState {
        self.state
    }

    /// Fixed match configuration.
    #[must_use]
    pub fn config(&self) -> SessionConfig {
        self.config
    }

    /// Signed entries in sequence order.
    #[must_use]
    pub fn log(&self) -> &[LogEntry] {
        &self.log
    }

    /// Current game, once started.
    #[must_use]
    pub fn game(&self) -> Option<&Game> {
        self.game.as_ref()
    }

    /// Whether `side` has marked ready.
    #[must_use]
    pub fn is_ready(&self, side: Color) -> bool {
        match side {
            Color::White => self.white_ready,
            Color::Black => self.black_ready,
        }
    }

    /// Next sequence number and current tip hash (zero when empty).
    #[must_use]
    pub fn tip(&self) -> (u64, [u8; 32]) {
        match self.log.last() {
            None => (0, [0u8; 32]),
            Some(entry) => (entry.seq + 1, entry.hash()),
        }
    }

    /// Entries at and after `seq` (resume-after-gap support).
    #[must_use]
    pub fn entries_since(&self, seq: u64) -> &[LogEntry] {
        let skip = (seq as usize).min(self.log.len());
        &self.log[skip..]
    }

    /// Guest co-signs genesis and enters setup.
    ///
    /// # Errors
    ///
    /// Returns [`SessionError`] outside `Created`, or for non-guests.
    pub fn join(&mut self, guest_secret: &SigningKey) -> Result<(), SessionError> {
        if self.state != SessionState::Created {
            return Err(SessionError::not_ready());
        }
        self.agree(guest_secret, 0)?;
        debug_assert_eq!(self.state, SessionState::SettingUp);
        Ok(())
    }

    /// Marks a participant ready; both ready enters `Ready`.
    ///
    /// # Errors
    ///
    /// Returns [`SessionError`] outside setup, or for outsiders.
    pub fn set_ready(&mut self, secret: &SigningKey) -> Result<SessionState, SessionError> {
        if !matches!(self.state, SessionState::SettingUp | SessionState::Ready) {
            return Err(SessionError::not_ready());
        }
        match self.config.side_of(PeerId::of(secret)) {
            Some(Color::White) => self.white_ready = true,
            Some(Color::Black) => self.black_ready = true,
            None => return Err(SessionError::not_participant()),
        }
        if self.white_ready && self.black_ready {
            self.state = SessionState::Ready;
        }
        Ok(self.state)
    }

    /// Starts play from the standard initial position.
    ///
    /// # Errors
    ///
    /// Returns [`SessionError`] unless both peers are ready.
    pub fn start(&mut self, secret: &SigningKey) -> Result<(), SessionError> {
        if self.state != SessionState::Ready {
            return Err(SessionError::not_ready());
        }
        if self.config.side_of(PeerId::of(secret)).is_none() {
            return Err(SessionError::not_participant());
        }
        self.game = Some(Game::from_startpos());
        self.state = SessionState::Playing;
        Ok(())
    }

    /// Submits a move for the side to move; signs and appends it.
    ///
    /// Applies optimistically; the entry becomes agreed when the
    /// opponent re-validates and co-signs via [`Session::agree`].
    /// A decisive outcome finishes the session immediately.
    ///
    /// # Errors
    ///
    /// Returns [`SessionError`] for wrong state, wrong turn, outsiders,
    /// or chess-illegal moves (the position is left unchanged).
    pub fn submit_move(
        &mut self,
        secret: &SigningKey,
        mv: &Move,
    ) -> Result<(u64, Outcome), SessionError> {
        self.require_playing()?;
        self.require_participant(secret)?;
        let peer = PeerId::of(secret);
        let game = self.game.as_mut().expect("game exists while playing");
        let side = game.board().side_to_move();
        if self.config.peer_for(side) != peer {
            return Err(SessionError::not_your_turn());
        }
        let outcome = game.play(mv)?;
        let (next_seq, prev) = self.tip();
        let entry = LogEntry::signed(next_seq, prev, LogPayload::Move { mv: *mv }, secret);
        self.log.push(entry);
        if let Outcome::Draw(DrawReason::FiftyMove)
        | Outcome::Draw(DrawReason::Threefold)
        | Outcome::Draw(DrawReason::InsufficientMaterial)
        | Outcome::Checkmate { .. }
        | Outcome::Stalemate = outcome
        {
            self.state = SessionState::Finished(FinishReason::Rules(outcome));
        }
        Ok((next_seq, outcome))
    }

    /// Co-signs entry `seq` after re-validating the log through it.
    ///
    /// Genesis agreement also advances `Created` to `SettingUp`.
    ///
    /// # Errors
    ///
    /// Returns [`SessionError`] for unknown entries, non-moves (except
    /// genesis), self-signing, or replay failure (the peer disagrees:
    /// the game stops, per the two-peer rule).
    pub fn agree(&mut self, secret: &SigningKey, seq: u64) -> Result<(), SessionError> {
        let peer = PeerId::of(secret);
        if self.config.side_of(peer).is_none() {
            return Err(SessionError::not_participant());
        }
        let entry = self
            .log
            .get(seq as usize)
            .ok_or_else(SessionError::unknown_entry)?;
        if entry.mover == peer {
            return Err(SessionError::not_agreeable());
        }
        if entry.co_sig.is_some() {
            return Ok(());
        }
        match entry.payload {
            LogPayload::Genesis { .. } => {}
            LogPayload::Move { .. } => self.replay_through(seq)?,
            _ => return Err(SessionError::not_agreeable()),
        }
        let hash = entry.hash();
        let co = secret.sign(&hash).to_bytes();
        self.log[seq as usize].co_sig = Some(co);
        if seq == 0 && self.state == SessionState::Created {
            self.state = SessionState::SettingUp;
        }
        Ok(())
    }

    /// Offers an agreed draw (playing only).
    ///
    /// # Errors
    ///
    /// Returns [`SessionError`] outside play, for outsiders, or when an
    /// offer is already open.
    pub fn offer_draw(&mut self, secret: &SigningKey) -> Result<u64, SessionError> {
        self.require_playing()?;
        self.require_participant(secret)?;
        if self.open_offer.is_some() {
            return Err(SessionError::not_ready());
        }
        let (next_seq, prev) = self.tip();
        self.log.push(LogEntry::signed(
            next_seq,
            prev,
            LogPayload::DrawOffer,
            secret,
        ));
        self.open_offer = Some(next_seq);
        Ok(next_seq)
    }

    /// Answers the open draw offer; acceptance finishes the session.
    ///
    /// # Errors
    ///
    /// Returns [`SessionError`] without an open offer, for outsiders, or
    /// when the offerer answers their own offer.
    pub fn answer_draw(&mut self, secret: &SigningKey, accept: bool) -> Result<(), SessionError> {
        self.require_playing()?;
        let peer = PeerId::of(secret);
        self.require_participant(secret)?;
        let offer_seq = self.open_offer.ok_or_else(SessionError::not_ready)?;
        let offer = &self.log[offer_seq as usize];
        if offer.mover == peer {
            return Err(SessionError::not_agreeable());
        }
        if accept {
            let (next_seq, prev) = self.tip();
            self.log.push(LogEntry::signed(
                next_seq,
                prev,
                LogPayload::DrawAccept { offer_seq },
                secret,
            ));
            self.open_offer = None;
            self.state = SessionState::Finished(FinishReason::AgreedDraw);
        } else {
            self.open_offer = None;
        }
        Ok(())
    }

    /// Resigns unilaterally (playing only).
    ///
    /// # Errors
    ///
    /// Returns [`SessionError`] outside play or for outsiders.
    pub fn resign(&mut self, secret: &SigningKey) -> Result<(), SessionError> {
        self.require_playing()?;
        self.require_participant(secret)?;
        let peer = PeerId::of(secret);
        let (next_seq, prev) = self.tip();
        self.log
            .push(LogEntry::signed(next_seq, prev, LogPayload::Resign, secret));
        self.state = SessionState::Finished(FinishReason::Resignation { by: peer });
        Ok(())
    }

    /// Cancels unilaterally (any unfinished state).
    ///
    /// # Errors
    ///
    /// Returns [`SessionError`] after finish or for outsiders.
    pub fn abort(&mut self, secret: &SigningKey) -> Result<(), SessionError> {
        if matches!(self.state, SessionState::Finished(_)) {
            return Err(SessionError::game_over());
        }
        self.require_participant(secret)?;
        let peer = PeerId::of(secret);
        let (next_seq, prev) = self.tip();
        self.log
            .push(LogEntry::signed(next_seq, prev, LogPayload::Abort, secret));
        self.state = SessionState::Finished(FinishReason::Abort { by: peer });
        Ok(())
    }

    /// Records the guest's arrival with their genesis co-signature.
    ///
    /// Transport-fed: the guest's view co-signs genesis at join, and the
    /// host learns of it through this verified note (never bare claims).
    ///
    /// # Errors
    ///
    /// Returns [`SessionError`] outside `Created`, for the host itself,
    /// outsiders, or bad signatures.
    pub fn note_peer_joined(&mut self, peer: PeerId, co_sig: [u8; 64]) -> Result<(), SessionError> {
        if self.state != SessionState::Created {
            return Err(SessionError::not_ready());
        }
        if self.log.len() != 1 {
            return Err(SessionError::log_mismatch(
                "join expects genesis only".to_string(),
            ));
        }
        if self.config.side_of(peer).is_none() || peer == self.config.host {
            return Err(SessionError::not_participant());
        }
        let hash = self.log[0].hash();
        peer.verify(&hash, &co_sig)?;
        self.log[0].co_sig = Some(co_sig);
        self.state = SessionState::SettingUp;
        Ok(())
    }

    /// Records a peer's readiness as delivered by transport.
    ///
    /// Readiness is a bare notification (no log entry in v1); transport
    /// authenticates the sender in a later slice.
    ///
    /// # Errors
    ///
    /// Returns [`SessionError`] outside setup or for outsiders.
    pub fn note_peer_ready(&mut self, peer: PeerId) -> Result<(), SessionError> {
        if !matches!(self.state, SessionState::SettingUp | SessionState::Ready) {
            return Err(SessionError::not_ready());
        }
        match self.config.side_of(peer) {
            Some(Color::White) => self.white_ready = true,
            Some(Color::Black) => self.black_ready = true,
            None => return Err(SessionError::not_participant()),
        }
        if self.white_ready && self.black_ready {
            self.state = SessionState::Ready;
        }
        Ok(())
    }

    /// Records the opponent's co-signature on move `seq`, verified.
    ///
    /// Transport-fed: each view agrees locally first; the co-signature
    /// crosses on the wire and lands here.
    ///
    /// # Errors
    ///
    /// Returns [`SessionError`] for unknown or non-move entries, or bad
    /// signatures.
    pub fn note_move_agreed(&mut self, seq: u64, co_sig: [u8; 64]) -> Result<(), SessionError> {
        let entry = self
            .log
            .get(seq as usize)
            .ok_or_else(SessionError::unknown_entry)?;
        if !matches!(entry.payload, LogPayload::Move { .. }) {
            return Err(SessionError::not_agreeable());
        }
        if entry.co_sig.is_some() {
            return Ok(());
        }
        let other = self.other_peer(entry.mover);
        let hash = entry.hash();
        other.verify(&hash, &co_sig)?;
        self.log[seq as usize].co_sig = Some(co_sig);
        Ok(())
    }

    /// Rebuilds a session from saved entries (restart recovery).
    ///
    /// Validates the full chain exactly like [`Session::verify`], replays
    /// moves into a game, and derives lifecycle state: a terminal entry or
    /// decisive position finishes, anything playable resumes `Playing`.
    /// Readiness is not logged, so a pre-game save resumes `SettingUp`
    /// and both sides ready again. Genesis alone is not resumable.
    ///
    /// # Errors
    ///
    /// Returns [`SessionError`] on empty logs, genesis mismatch, any
    /// validation failure, or nothing worth resuming.
    pub fn resume(entries: Vec<LogEntry>) -> Result<Self, SessionError> {
        let genesis = entries
            .first()
            .ok_or_else(|| SessionError::log_mismatch("empty log".to_string()))?;
        let LogPayload::Genesis {
            version,
            white,
            black,
            host,
        } = genesis.payload
        else {
            return Err(SessionError::log_mismatch(
                "first entry is not genesis".to_string(),
            ));
        };
        if version != PROTOCOL_VERSION {
            return Err(SessionError::log_mismatch(
                "genesis version mismatch".to_string(),
            ));
        }
        let config = SessionConfig {
            white,
            black,
            host,
            clock: None,
        };
        let playable = entries.iter().any(|entry| {
            matches!(
                entry.payload,
                LogPayload::Move { .. }
                    | LogPayload::Resign
                    | LogPayload::Abort
                    | LogPayload::DrawAccept { .. }
            )
        });
        if !playable {
            return Err(SessionError::log_mismatch("nothing to resume".to_string()));
        }
        let mut session = Self {
            config,
            state: SessionState::SettingUp,
            white_ready: false,
            black_ready: false,
            game: None,
            log: entries,
            open_offer: None,
        };
        session.verify()?;
        let mut game = Game::from_startpos();
        let mut finished = None;
        for entry in &session.log {
            match entry.payload {
                LogPayload::Genesis { .. } | LogPayload::DrawOffer => {}
                LogPayload::Move { mv } => {
                    game.play(&mv).map_err(|_| {
                        SessionError::log_mismatch("replay hit illegal move".to_string())
                    })?;
                }
                LogPayload::Resign => {
                    finished = Some(FinishReason::Resignation { by: entry.mover })
                }
                LogPayload::Abort => finished = Some(FinishReason::Abort { by: entry.mover }),
                LogPayload::DrawAccept { .. } => finished = Some(FinishReason::AgreedDraw),
            }
            if let LogPayload::DrawOffer = entry.payload {
                session.open_offer = Some(entry.seq);
            }
            if matches!(entry.payload, LogPayload::DrawAccept { .. }) {
                session.open_offer = None;
            }
        }
        session.game = Some(game);
        session.state = match finished {
            Some(reason) => SessionState::Finished(reason),
            None => match session.game.as_ref().expect("game rebuilt").outcome() {
                Outcome::Ongoing => SessionState::Playing,
                outcome => SessionState::Finished(FinishReason::Rules(outcome)),
            },
        };
        Ok(session)
    }

    /// Ingests an entry from the other peer (transport receive path).
    ///
    /// Verifies order, chain link, and author signature before appending.
    /// Call [`Session::replay_game`] afterwards to re-sync positions.
    ///
    /// # Errors
    ///
    /// Returns [`SessionError`] on any validation failure.
    pub fn receive(&mut self, entry: &LogEntry) -> Result<(), SessionError> {
        let (next_seq, prev) = self.tip();
        if entry.seq != next_seq {
            return Err(SessionError::log_mismatch("out-of-order entry".to_string()));
        }
        if entry.prev_hash != prev {
            return Err(SessionError::log_mismatch("broken hash link".to_string()));
        }
        if self.config.side_of(entry.mover).is_none() {
            return Err(SessionError::not_participant());
        }
        if let LogPayload::Genesis {
            version,
            white,
            black,
            host,
        } = entry.payload
            && (version != PROTOCOL_VERSION
                || white != self.config.white
                || black != self.config.black
                || host != self.config.host)
        {
            return Err(SessionError::log_mismatch("genesis mismatch".to_string()));
        }
        let other = self.other_peer(entry.mover);
        entry.verify_sigs(other)?;
        self.log.push(*entry);
        Ok(())
    }

    /// Rebuilds the game by replaying agreed... all move entries in order.
    ///
    /// Used after [`Session::receive`] fills a gap. Terminal entries do
    /// not move pieces; lifecycle effects stay with their own actions.
    ///
    /// # Errors
    ///
    /// Returns [`SessionError`] when replay hits a chess-illegal move.
    pub fn replay_game(&mut self) -> Result<(), SessionError> {
        let mut game = Game::from_startpos();
        for entry in &self.log {
            if let LogPayload::Move { mv } = entry.payload {
                game.play(&mv).map_err(|_| {
                    SessionError::log_mismatch("replay hit illegal move".to_string())
                })?;
            }
        }
        self.game = Some(game);
        Ok(())
    }

    /// Fully validates chain, signatures, genesis, and chess replay.
    ///
    /// # Errors
    ///
    /// Returns [`SessionError`] on the first defect found.
    pub fn verify(&self) -> Result<(), SessionError> {
        let mut prev = [0u8; 32];
        let mut game = Game::from_startpos();
        for (index, entry) in self.log.iter().enumerate() {
            if entry.seq != index as u64 {
                return Err(SessionError::log_mismatch("sequence break".to_string()));
            }
            if entry.prev_hash != prev {
                return Err(SessionError::log_mismatch("broken hash link".to_string()));
            }
            if self.config.side_of(entry.mover).is_none() {
                return Err(SessionError::not_participant());
            }
            let other = self.other_peer(entry.mover);
            entry.verify_sigs(other)?;
            match entry.payload {
                LogPayload::Genesis {
                    version,
                    white,
                    black,
                    host,
                } => {
                    if index != 0
                        || version != PROTOCOL_VERSION
                        || white != self.config.white
                        || black != self.config.black
                        || host != self.config.host
                    {
                        return Err(SessionError::log_mismatch("genesis mismatch".to_string()));
                    }
                }
                LogPayload::Move { mv } => {
                    game.play(&mv).map_err(|_| {
                        SessionError::log_mismatch("replay hit illegal move".to_string())
                    })?;
                }
                LogPayload::DrawAccept { offer_seq } => match self.log.get(offer_seq as usize) {
                    Some(LogEntry {
                        payload: LogPayload::DrawOffer,
                        ..
                    }) => {}
                    _ => return Err(SessionError::log_mismatch("dangling accept".to_string())),
                },
                LogPayload::DrawOffer | LogPayload::Resign | LogPayload::Abort => {}
            }
            prev = entry.hash();
        }
        Ok(())
    }

    fn require_playing(&self) -> Result<(), SessionError> {
        match self.state {
            SessionState::Playing => Ok(()),
            SessionState::Finished(_) => Err(SessionError::game_over()),
            _ => Err(SessionError::not_ready()),
        }
    }

    fn require_participant(&self, secret: &SigningKey) -> Result<(), SessionError> {
        if self.config.side_of(PeerId::of(secret)).is_none() {
            return Err(SessionError::not_participant());
        }
        Ok(())
    }

    fn other_peer(&self, peer: PeerId) -> PeerId {
        if peer == self.config.white {
            self.config.black
        } else {
            self.config.white
        }
    }

    fn replay_through(&self, seq: u64) -> Result<(), SessionError> {
        let mut game = Game::from_startpos();
        for entry in self.log.iter().take(seq as usize + 1) {
            if let LogPayload::Move { mv } = entry.payload {
                game.play(&mv).map_err(|_| {
                    SessionError::log_mismatch("agreement replay failed".to_string())
                })?;
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn host_secret() -> SigningKey {
        SigningKey::from_bytes(&[1u8; 32])
    }

    fn guest_secret() -> SigningKey {
        SigningKey::from_bytes(&[2u8; 32])
    }

    fn outsider_secret() -> SigningKey {
        SigningKey::from_bytes(&[9u8; 32])
    }

    fn config() -> SessionConfig {
        SessionConfig::new(
            PeerId::of(&host_secret()),
            PeerId::of(&guest_secret()),
            PeerId::of(&host_secret()),
        )
        .unwrap()
    }

    fn playing() -> (Session, SigningKey, SigningKey) {
        let host = host_secret();
        let guest = guest_secret();
        let mut session = Session::create(&host, config()).unwrap();
        assert_eq!(session.state(), SessionState::Created);
        session.join(&guest).unwrap();
        assert_eq!(session.state(), SessionState::SettingUp);
        session.set_ready(&host).unwrap();
        session.set_ready(&guest).unwrap();
        assert_eq!(session.state(), SessionState::Ready);
        session.start(&host).unwrap();
        assert_eq!(session.state(), SessionState::Playing);
        (session, host, guest)
    }

    #[test]
    fn config_rejects_outsider_host() {
        let err = SessionConfig::new(
            PeerId::of(&host_secret()),
            PeerId::of(&guest_secret()),
            PeerId::of(&outsider_secret()),
        )
        .unwrap_err();
        assert!(err.is_not_participant());
    }

    #[test]
    fn lifecycle_guards_transitions() {
        let host = host_secret();
        let guest = guest_secret();
        let mut session = Session::create(&host, config()).unwrap();
        assert!(session.set_ready(&host).unwrap_err().is_not_ready());
        assert!(session.start(&host).unwrap_err().is_not_ready());
        session.join(&guest).unwrap();
        assert!(session.join(&guest).unwrap_err().is_not_ready());
        assert!(session.start(&guest).unwrap_err().is_not_ready());
        session.set_ready(&host).unwrap();
        assert_eq!(session.state(), SessionState::SettingUp);
        session.set_ready(&guest).unwrap();
        assert_eq!(session.set_ready(&guest).unwrap(), SessionState::Ready);
    }

    #[test]
    fn turn_ownership_enforced() {
        let (mut session, host, guest) = playing();
        // Host plays White; guest cannot open.
        assert!(
            session
                .submit_move(&guest, &"e2e4".parse().unwrap())
                .unwrap_err()
                .is_not_your_turn()
        );
        assert!(
            session
                .submit_move(&outsider_secret(), &"e2e4".parse().unwrap())
                .unwrap_err()
                .is_not_participant()
        );
        let (_, outcome) = session
            .submit_move(&host, &"e2e4".parse().unwrap())
            .unwrap();
        assert_eq!(outcome, Outcome::Ongoing);
        // Now Black's turn; host cannot move twice.
        assert!(
            session
                .submit_move(&host, &"e7e5".parse().unwrap())
                .unwrap_err()
                .is_not_your_turn()
        );
    }

    #[test]
    fn illegal_submit_leaves_no_trace() {
        let (mut session, host, _) = playing();
        let (tip_seq, tip_hash) = session.tip();
        let err = session
            .submit_move(&host, &"e2e5".parse().unwrap())
            .unwrap_err();
        assert!(err.is_chess());
        assert_eq!(session.tip(), (tip_seq, tip_hash));
    }

    #[test]
    fn moves_become_agreed() {
        let (mut session, host, guest) = playing();
        let (seq, _) = session
            .submit_move(&host, &"e2e4".parse().unwrap())
            .unwrap();
        assert!(!session.log()[seq as usize].is_agreed());
        session.agree(&guest, seq).unwrap();
        assert!(session.log()[seq as usize].is_agreed());
        assert!(session.agree(&guest, seq).is_ok());
        assert!(session.agree(&host, seq).unwrap_err().is_not_agreeable());
        assert!(session.agree(&guest, 99).unwrap_err().is_unknown_entry());
    }

    #[test]
    fn draw_offer_flow() {
        let (mut session, host, guest) = playing();
        session
            .submit_move(&host, &"e2e4".parse().unwrap())
            .unwrap();
        let offer = session.offer_draw(&guest).unwrap();
        assert!(session.offer_draw(&host).unwrap_err().is_not_ready());
        assert!(
            session
                .answer_draw(&guest, true)
                .unwrap_err()
                .is_not_agreeable()
        );
        session.answer_draw(&host, false).unwrap();
        assert_eq!(session.state(), SessionState::Playing);
        let offer2 = session.offer_draw(&host).unwrap();
        assert_ne!(offer, offer2);
        session.answer_draw(&guest, true).unwrap();
        assert_eq!(
            session.state(),
            SessionState::Finished(FinishReason::AgreedDraw)
        );
        assert!(
            session
                .submit_move(&guest, &"e7e5".parse().unwrap())
                .unwrap_err()
                .is_game_over()
        );
    }

    #[test]
    fn resign_and_abort_finish() {
        let (mut session, host, guest) = playing();
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

        let (mut early, _, _) = playing();
        early.abort(&guest).unwrap();
        assert!(matches!(
            early.state(),
            SessionState::Finished(FinishReason::Abort { .. })
        ));
        assert!(early.abort(&host).unwrap_err().is_game_over());
    }

    #[test]
    fn outsiders_rejected_everywhere() {
        let (mut session, _, _) = playing();
        let outsider = outsider_secret();
        assert!(
            session
                .agree(&outsider, 0)
                .unwrap_err()
                .is_not_participant()
        );
        assert!(session.resign(&outsider).unwrap_err().is_not_participant());

        // Readiness rejects outsiders while still setting up.
        let host = host_secret();
        let guest = guest_secret();
        let mut fresh = Session::create(&host, config()).unwrap();
        fresh.join(&guest).unwrap();
        assert!(fresh.set_ready(&outsider).unwrap_err().is_not_participant());
    }
}
