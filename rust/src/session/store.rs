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
use std::backtrace::Backtrace;
use std::fmt::{self, Display, Formatter};
use std::path::{Path, PathBuf};

/// File magic: `CRLOG1`.
const MAGIC: &[u8; 6] = b"CRLOG1";
/// File format version.
const FILE_VERSION: u16 = 1;

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
