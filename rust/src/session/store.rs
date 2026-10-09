//! Local persistence seam: save the signed log, load it on resume.
//!
//! The only storage v1 needs. Format and validation live here; *where*
//! the file lives is the platform's call (Godot hands an absolute path
//! resolved from `user://`, identical on desktop and mobile). Nothing
//! here knows chess rules beyond asking the session to re-validate.
//!
//! File layout: magic `CRLOG1` (6 bytes), format version `u16`
//! little-endian (currently 1), then the postcard-encoded entry vector.
//! Anything else is a [`StoreError`] decode failure, never a partial load.
//!
//! # Examples
//!
//! ```
//! use chess_relay_core::session::{LogStore, MemoryStore};
//!
//! let mut store = MemoryStore::new();
//! assert!(store.load().unwrap().is_empty());
//! ```

use super::log::LogEntry;
use super::log::PeerId;
use serde::{Deserialize, Serialize};
use std::backtrace::Backtrace;
use std::fmt::{self, Display, Formatter};
use std::path::{Path, PathBuf};

/// File magic: `CRLOG1`.
const MAGIC: &[u8; 6] = b"CRLOG1";
/// File format version.
const FILE_VERSION: u16 = 1;
/// File magic for the local recent-peer index.
const RECENT_MAGIC: &[u8; 6] = b"CRPEER";
/// Recent-peer index format version with endpoint and last-seen metadata.
const RECENT_FILE_VERSION: u16 = 2;
/// Previous recent-peer index format, retained for one-way migration.
const LEGACY_RECENT_FILE_VERSION: u16 = 1;
/// Bound local history so the index cannot grow without limit.
const MAX_RECENT_PEERS: usize = 20;

/// Local persistence behind an interface: save entries, load them back.
pub trait LogStore {
    /// Persists the full log, replacing any previous save.
    ///
    /// # Errors
    ///
    /// Returns [`StoreError`] when encoding or writing fails.
    fn save(&mut self, entries: &[LogEntry]) -> Result<(), StoreError>;
    /// Loads the saved log, empty when nothing was saved.
    ///
    /// # Errors
    ///
    /// Returns [`StoreError`] on unreadable or malformed content.
    fn load(&self) -> Result<Vec<LogEntry>, StoreError>;
}

/// Storage-layer failure: I/O or malformed content.
///
/// Sole error type of this seam. Detail strings carry the underlying
/// message; callers match on kinds, not text.
#[derive(Debug)]
pub struct StoreError {
    kind: StoreErrorKind,
    backtrace: Backtrace,
    detail: Option<String>,
}

#[derive(Debug)]
enum StoreErrorKind {
    /// Filesystem or encoding failure.
    Io,
    /// Magic, version, or body did not validate.
    Decode,
}

impl StoreError {
    pub(crate) fn io(detail: String) -> Self {
        Self {
            kind: StoreErrorKind::Io,
            backtrace: Backtrace::capture(),
            detail: Some(detail),
        }
    }

    pub(crate) fn decode(detail: String) -> Self {
        Self {
            kind: StoreErrorKind::Decode,
            backtrace: Backtrace::capture(),
            detail: Some(detail),
        }
    }

    /// Whether the filesystem or encoding failed.
    #[must_use]
    pub fn is_io(&self) -> bool {
        matches!(self.kind, StoreErrorKind::Io)
    }

    /// Whether saved content failed validation.
    #[must_use]
    pub fn is_decode(&self) -> bool {
        matches!(self.kind, StoreErrorKind::Decode)
    }
}

impl Display for StoreError {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        let summary = match self.kind {
            StoreErrorKind::Io => "store I/O failed",
            StoreErrorKind::Decode => "saved game failed validation",
        };
        write!(f, "store error: {summary}")?;
        if let Some(detail) = &self.detail {
            write!(f, " ({detail})")?;
        }
        use std::backtrace::BacktraceStatus::Captured;
        if self.backtrace.status() == Captured {
            write!(f, "\n{}", self.backtrace)?;
        }
        Ok(())
    }
}

impl std::error::Error for StoreError {}

impl From<std::io::Error> for StoreError {
    fn from(err: std::io::Error) -> Self {
        Self::io(err.to_string())
    }
}

impl From<postcard::Error> for StoreError {
    fn from(err: postcard::Error) -> Self {
        Self::decode(err.to_string())
    }
}

/// File-backed log store at a platform-provided path.
pub struct FileStore {
    path: PathBuf,
}

/// Rust-owned local index of peers observed through successful network links.
///
/// Ordering is the freshness contract: index zero is the most recently
/// connected peer. Peer IDs are deduplicated, and the index is bounded.
pub struct RecentPeerStore {
    path: PathBuf,
}

/// Durable observation of a peer previously reached by this installation.
///
/// `ticket` is the last dialable endpoint ticket received for this peer. It is
/// an addressing observation, not a presence guarantee: the endpoint may be
/// offline or its address may have changed since `last_seen_unix_secs`.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RecentPeerRecord {
    /// Stable endpoint/session identity.
    pub peer: PeerId,
    /// Last usable endpoint ticket, when one was available.
    pub ticket: Option<String>,
    /// Unix timestamp in seconds of the last successful contact.
    pub last_seen_unix_secs: u64,
}

impl RecentPeerStore {
    /// Stores the index at `path`.
    #[must_use]
    pub fn new(path: &Path) -> Self {
        Self {
            path: path.to_path_buf(),
        }
    }

    /// Loads the ordered peer records, newest contact first.
    pub fn load(&self) -> Result<Vec<RecentPeerRecord>, StoreError> {
        let bytes = match std::fs::read(&self.path) {
            Ok(bytes) => bytes,
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
            Err(err) => return Err(err.into()),
        };
        if bytes.len() < 8 || &bytes[..6] != RECENT_MAGIC {
            return Err(StoreError::decode("bad recent-peer magic".to_string()));
        }
        let version = u16::from_le_bytes(
            bytes[6..8]
                .try_into()
                .map_err(|_| StoreError::decode("short recent-peer header".to_string()))?,
        );
        let records: Vec<RecentPeerRecord> = match version {
            RECENT_FILE_VERSION => postcard::from_bytes(&bytes[8..])?,
            LEGACY_RECENT_FILE_VERSION => postcard::from_bytes::<Vec<PeerId>>(&bytes[8..])?
                .into_iter()
                .map(|peer| RecentPeerRecord {
                    peer,
                    ticket: None,
                    last_seen_unix_secs: 0,
                })
                .collect(),
            _ => {
                return Err(StoreError::decode(
                    "unsupported recent-peer version".to_string(),
                ));
            }
        };
        if records.len() > MAX_RECENT_PEERS {
            return Err(StoreError::decode(
                "recent-peer index exceeds bound".to_string(),
            ));
        }
        if records.windows(2).any(|pair| pair[0].peer == pair[1].peer) {
            return Err(StoreError::decode(
                "recent-peer index contains duplicates".to_string(),
            ));
        }
        if records.iter().any(|record| {
            record
                .ticket
                .as_ref()
                .is_some_and(|ticket| ticket.is_empty())
        }) {
            return Err(StoreError::decode(
                "recent-peer record contains an empty ticket".to_string(),
            ));
        }
        Ok(records)
    }

    /// Inserts or replaces one successfully contacted peer.
    pub fn upsert(
        &mut self,
        peer: PeerId,
        ticket: Option<String>,
        last_seen_unix_secs: u64,
    ) -> Result<(), StoreError> {
        if ticket.as_ref().is_some_and(String::is_empty) {
            return Err(StoreError::decode(
                "recent-peer ticket cannot be empty".to_string(),
            ));
        }
        let mut records = self.load()?;
        records.retain(|known| known.peer != peer);
        records.insert(
            0,
            RecentPeerRecord {
                peer,
                ticket,
                last_seen_unix_secs,
            },
        );
        records.truncate(MAX_RECENT_PEERS);
        let mut bytes = Vec::with_capacity(8 + records.len() * 64);
        bytes.extend_from_slice(RECENT_MAGIC);
        bytes.extend_from_slice(&RECENT_FILE_VERSION.to_le_bytes());
        bytes.extend(postcard::to_stdvec(&records)?);
        std::fs::write(&self.path, bytes)?;
        Ok(())
    }
}

impl FileStore {
    /// Stores at `path` (created on first save, parent must exist).
    #[must_use]
    pub fn new(path: &Path) -> Self {
        Self {
            path: path.to_path_buf(),
        }
    }

    /// Configured path, for diagnostics.
    #[must_use]
    pub fn path(&self) -> &Path {
        &self.path
    }
}

impl LogStore for FileStore {
    fn save(&mut self, entries: &[LogEntry]) -> Result<(), StoreError> {
        let mut bytes = Vec::with_capacity(8 + entries.len() * 200);
        bytes.extend_from_slice(MAGIC);
        bytes.extend_from_slice(&FILE_VERSION.to_le_bytes());
        bytes.extend(postcard::to_stdvec(entries)?);
        std::fs::write(&self.path, bytes)?;
        Ok(())
    }

    fn load(&self) -> Result<Vec<LogEntry>, StoreError> {
        let bytes = match std::fs::read(&self.path) {
            Ok(bytes) => bytes,
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
            Err(err) => return Err(err.into()),
        };
        if bytes.len() < 8 || &bytes[..6] != MAGIC {
            return Err(StoreError::decode("bad magic".to_string()));
        }
        if u16::from_le_bytes(
            bytes[6..8]
                .try_into()
                .map_err(|_| StoreError::decode("short header".to_string()))?,
        ) != FILE_VERSION
        {
            return Err(StoreError::decode("unsupported version".to_string()));
        }
        Ok(postcard::from_bytes(&bytes[8..])?)
    }
}

/// In-memory log store for tests.
#[derive(Default)]
pub struct MemoryStore {
    entries: Vec<LogEntry>,
}

impl MemoryStore {
    /// Empty store.
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }
}

impl LogStore for MemoryStore {
    fn save(&mut self, entries: &[LogEntry]) -> Result<(), StoreError> {
        self.entries = entries.to_vec();
        Ok(())
    }

    fn load(&self) -> Result<Vec<LogEntry>, StoreError> {
        Ok(self.entries.clone())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::session::{PeerId, Session, SessionConfig, SessionState};
    use ed25519_dalek::SigningKey;

    fn secrets() -> (SigningKey, SigningKey) {
        (
            SigningKey::from_bytes(&[1u8; 32]),
            SigningKey::from_bytes(&[2u8; 32]),
        )
    }

    fn playing_pair() -> (Session, SigningKey, SigningKey) {
        let (host, guest) = secrets();
        let config =
            SessionConfig::new(PeerId::of(&host), PeerId::of(&guest), PeerId::of(&host)).unwrap();
        let mut session = Session::create(&host, config).unwrap();
        session.join(&guest).unwrap();
        session.set_ready(&host).unwrap();
        session.set_ready(&guest).unwrap();
        session.start(&host).unwrap();
        (session, host, guest)
    }

    #[test]
    fn memory_round_trip() {
        let (mut session, host, _) = playing_pair();
        let mv: crate::chess_core::Move = "e2e4".parse().unwrap();
        session.submit_move(&host, &mv).unwrap();
        let mut store = MemoryStore::new();
        store.save(session.log()).unwrap();
        let loaded = store.load().unwrap();
        assert_eq!(loaded, session.log());
    }

    #[test]
    fn file_round_trip_and_resume() {
        let (mut session, host, guest) = playing_pair();
        let mv: crate::chess_core::Move = "e2e4".parse().unwrap();
        session.submit_move(&host, &mv).unwrap();
        session.agree(&guest, 1).unwrap();
        let path =
            std::env::temp_dir().join(format!("chess-relay-resume-{}.bin", std::process::id()));
        let mut store = FileStore::new(&path);
        store.save(session.log()).unwrap();
        let loaded = FileStore::new(&path).load().unwrap();
        assert_eq!(loaded, session.log());

        let mut resumed = Session::resume(loaded).unwrap();
        assert_eq!(resumed.state(), SessionState::Playing);
        assert_eq!(
            resumed.game().unwrap().board().to_fen(),
            session.game().unwrap().board().to_fen()
        );
        // Play continues from the resumed view.
        let reply: crate::chess_core::Move = "e7e5".parse().unwrap();
        resumed.submit_move(&guest, &reply).unwrap();
        resumed.verify().unwrap();
        std::fs::remove_file(&path).ok();
    }

    #[test]
    fn tampered_file_fails_decode() {
        let path =
            std::env::temp_dir().join(format!("chess-relay-tamper-{}.bin", std::process::id()));
        std::fs::write(&path, b"GARBAGE-NOT-A-LOG").unwrap();
        let err = FileStore::new(&path).load().unwrap_err();
        assert!(err.is_decode());
        std::fs::remove_file(&path).ok();
    }

    #[test]
    fn missing_file_loads_empty() {
        let path = std::env::temp_dir().join(format!(
            "chess-relay-missing-{}-{}.bin",
            std::process::id(),
            7
        ));
        assert!(FileStore::new(&path).load().unwrap().is_empty());
    }

    #[test]
    fn recent_peer_store_deduplicates_and_orders_by_latest_connection() {
        let path = std::env::temp_dir().join(format!(
            "chess-relay-recent-peers-{}-{}.bin",
            std::process::id(),
            std::thread::current().name().unwrap_or("test")
        ));
        let first = PeerId::of(&SigningKey::from_bytes(&[3u8; 32]));
        let second = PeerId::of(&SigningKey::from_bytes(&[4u8; 32]));
        let mut store = RecentPeerStore::new(&path);
        store.upsert(first, None, 1).unwrap();
        store.upsert(second, None, 2).unwrap();
        store.upsert(first, None, 3).unwrap();
        assert_eq!(
            store
                .load()
                .unwrap()
                .into_iter()
                .map(|record| record.peer)
                .collect::<Vec<_>>(),
            vec![first, second]
        );
        std::fs::remove_file(path).ok();
    }

    #[test]
    fn recent_peer_store_retains_latest_ticket_and_timestamp() {
        let path = std::env::temp_dir().join(format!(
            "chess-relay-recent-record-{}-{}",
            std::process::id(),
            std::thread::current().name().unwrap_or("test")
        ));
        let peer = PeerId::of(&SigningKey::from_bytes(&[5u8; 32]));
        let mut store = RecentPeerStore::new(&path);
        store
            .upsert(peer, Some("endpoint-ticket".to_string()), 1234)
            .unwrap();
        assert_eq!(
            store.load().unwrap(),
            vec![RecentPeerRecord {
                peer,
                ticket: Some("endpoint-ticket".to_string()),
                last_seen_unix_secs: 1234,
            }]
        );
        std::fs::remove_file(path).ok();
    }

    #[test]
    fn resume_rejects_empty_and_finished() {
        assert!(Session::resume(Vec::new()).unwrap_err().is_log_mismatch());
        let (mut session, host, guest) = playing_pair();
        session.resign(&guest).unwrap();
        let mut resumed = Session::resume(session.log().to_vec()).unwrap();
        assert!(matches!(resumed.state(), SessionState::Finished(_)));
        assert!(
            resumed
                .submit_move(&host, &"e2e4".parse().unwrap())
                .unwrap_err()
                .is_game_over()
        );
    }
}
