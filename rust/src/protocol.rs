//! Wire boundary: application commands/events <-> bytes.
//!
//! Covers what crosses a process/device boundary (log entries,
//! offers, handshake, versions). Never decides move legality.
//!
//! The message set is extracted from the Phase 4 spike, which ran real
//! games across processes with exactly these shapes. Framing (length
//! prefixes on streams) belongs to transport; this layer owns message
//! meaning, the version gate, and malformed-input rejection.
//!
//! Versioning: the first message of every connection is a [`Msg::LobbyHello`]
//! carrying [`PROTOCOL_VERSION`]. The host sends [`Msg::Hello`] only after the
//! lobby setup is committed and a session genesis exists. Anything else first,
//! or a version mismatch, is [`ProtocolError`], never a panic.
//!
//! # Examples
//!
//! ```
//! use chess_relay_core::protocol::{Msg, PROTOCOL_VERSION};
//! use chess_relay_core::session::PeerId;
//! use chess_relay_core::app::{App, Command, Query, QueryResult};
//! use ed25519_dalek::SigningKey;
//!
//! let (white, black) = (
//!     PeerId::of(&SigningKey::from_bytes(&[1u8; 32])),
//!     PeerId::of(&SigningKey::from_bytes(&[2u8; 32])),
//! );
//! let mut app = App::with_local(SigningKey::from_bytes(&[1u8; 32]));
//! app.admit(SigningKey::from_bytes(&[2u8; 32]));
//! app.handle(&Command::StartGame { white, black }).unwrap();
//! let genesis = match app.query(&Query::MoveLog).unwrap() {
//!     QueryResult::MoveLog(entries) => entries[0],
//!     _ => unreachable!(),
//! };
//! let bytes = Msg::Hello { version: PROTOCOL_VERSION, genesis }.encode();
//! let back = Msg::decode(&bytes).unwrap();
//! assert_eq!(back, Msg::Hello { version: PROTOCOL_VERSION, genesis });
//! ```

use crate::session::{LogEntry, PeerId};
use serde::{Deserialize, Serialize};
use std::backtrace::Backtrace;
use std::fmt::{self, Display, Formatter};

/// Wire protocol version. Must match the session genesis version;
/// kept as one constant so the two cannot drift.
pub const PROTOCOL_VERSION: u16 = crate::session::PROTOCOL_VERSION;

/// One framed message on the game ALPN.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum Msg {
    /// First message every connection: establishes the protocol before a
    /// session exists. This allows the host-owned lobby to exchange setup
    /// previews without inventing a fake game genesis.
    LobbyHello {
        /// Must equal [`PROTOCOL_VERSION`].
        version: u16,
    },
    /// Session-start message: version gate plus genesis after the lobby.
    Hello {
        /// Must equal [`PROTOCOL_VERSION`].
        version: u16,
        /// Session-fixing entry, co-signed later like any genesis.
        genesis: LogEntry,
    },
    /// Host-owned setup snapshot. Sent after [`Msg::LobbyHello`] and may be
    /// repeated while the host changes the lobby selections.
    Setup {
        side: String,
        time: String,
        variant: String,
    },
    /// Readiness notification for a participant.
    Ready {
        /// Ready peer.
        peer: PeerId,
    },
    /// Host confirmation that the authoritative session has started. The
    /// guest waits for this before applying its own readiness locally, so
    /// both screens enter play from the same host commit.
    Started,
    /// A signed log entry of any kind: moves today, and offers, answers,
    /// resignations and aborts as sessions use them. The payload already
    /// distinguishes kinds; the protocol never interprets them, it only
    /// carries them (arch doc §Offers: the request/answer exchange rides
    /// here, while answering stays a session action).
    Entry(LogEntry),
    /// Opponent co-signature on entry `seq`.
    Agreed {
        /// Entry sequence.
        seq: u64,
        /// Co-signature bytes.
        #[serde(with = "serde_bytes")]
        sig: [u8; 64],
    },
    /// Resume request: next expected sequence plus tip hash.
    Tip {
        /// Next expected sequence.
        seq: u64,
        /// Tip entry hash (zeroed when empty).
        hash: [u8; 32],
    },
    /// Final position for convergence checks.
    Fen {
        /// Position in FEN.
        fen: String,
    },
    /// Clean end of script; connection may close.
    Done,
}

impl Msg {
    /// Encodes to compact binary (postcard).
    #[must_use]
    pub fn encode(&self) -> Vec<u8> {
        postcard::to_stdvec(self).expect("protocol messages are encodable")
    }

    /// Decodes and version-gates: a versioned greeting with the wrong version
    /// fails, so mismatched peers stop at the handshake.
    ///
    /// # Errors
    ///
    /// Returns [`ProtocolError`] on malformed bytes or version mismatch.
    pub fn decode(bytes: &[u8]) -> Result<Self, ProtocolError> {
        let msg: Self = postcard::from_bytes(bytes).map_err(|_| ProtocolError::decode())?;
        let version = match &msg {
            Self::LobbyHello { version } | Self::Hello { version, .. } => Some(*version),
            _ => None,
        };
        if version.is_some_and(|version| version != PROTOCOL_VERSION) {
            return Err(ProtocolError::bad_version(version.unwrap_or_default()));
        }
        Ok(msg)
    }
}

/// Protocol-layer failure: malformed bytes or version mismatch.
///
/// Sole error type of this layer (arch doc §Errors). Never panics on
/// hostile input: every byte pattern maps to `Err`.
#[derive(Debug)]
pub struct ProtocolError {
    kind: ProtocolErrorKind,
    backtrace: Backtrace,
}

#[derive(Debug)]
enum ProtocolErrorKind {
    /// Bytes do not decode to a message.
    Decode,
    /// Handshake version this side cannot speak.
    BadVersion {
        /// Received version.
        got: u16,
    },
}

impl ProtocolError {
    pub(crate) fn decode() -> Self {
        Self {
            kind: ProtocolErrorKind::Decode,
            backtrace: Backtrace::capture(),
        }
    }

    pub(crate) fn bad_version(got: u16) -> Self {
        Self {
            kind: ProtocolErrorKind::BadVersion { got },
            backtrace: Backtrace::capture(),
        }
    }

    /// Whether bytes failed to decode.
    #[must_use]
    pub fn is_decode(&self) -> bool {
        matches!(self.kind, ProtocolErrorKind::Decode)
    }

    /// Whether the peer speaks another version.
    #[must_use]
    pub fn is_bad_version(&self) -> bool {
        matches!(self.kind, ProtocolErrorKind::BadVersion { .. })
    }
}

impl Display for ProtocolError {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        match self.kind {
            ProtocolErrorKind::Decode => write!(f, "protocol error: malformed message"),
            ProtocolErrorKind::BadVersion { got } => {
                write!(
                    f,
                    "protocol error: peer speaks version {got}, want {PROTOCOL_VERSION}"
                )
            }
        }?;
        use std::backtrace::BacktraceStatus::Captured;
        if self.backtrace.status() == Captured {
            write!(f, "\n{}", self.backtrace)?;
        }
        Ok(())
    }
}

impl std::error::Error for ProtocolError {}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::app::{App, Command, Query, QueryResult};
    use ed25519_dalek::SigningKey;

    fn genesis_entry() -> LogEntry {
        let host = SigningKey::from_bytes(&[1u8; 32]);
        let guest = SigningKey::from_bytes(&[2u8; 32]);
        let mut app = App::with_local(host);
        app.admit(guest);
        let (white, black) = (PeerId::of(&host_secret()), PeerId::of(&guest_secret()));
        app.handle(&Command::StartGame { white, black }).unwrap();
        match app.query(&Query::MoveLog).unwrap() {
            QueryResult::MoveLog(entries) => entries[0],
            _ => unreachable!(),
        }
    }

    fn host_secret() -> SigningKey {
        SigningKey::from_bytes(&[1u8; 32])
    }

    fn guest_secret() -> SigningKey {
        SigningKey::from_bytes(&[2u8; 32])
    }

    #[test]
    fn hello_round_trip() {
        let genesis = genesis_entry();
        let msg = Msg::Hello {
            version: PROTOCOL_VERSION,
            genesis,
        };
        assert_eq!(Msg::decode(&msg.encode()).unwrap(), msg);
    }

    #[test]
    fn all_variants_round_trip() {
        let genesis = genesis_entry();
        let peer = PeerId::of(&guest_secret());
        let messages = [
            Msg::LobbyHello {
                version: PROTOCOL_VERSION,
            },
            Msg::Setup {
                side: "White".to_string(),
                time: "5 | 3".to_string(),
                variant: "Standard".to_string(),
            },
            Msg::Ready { peer },
            Msg::Started,
            Msg::Entry(genesis),
            Msg::Agreed {
                seq: 3,
                sig: [9u8; 64],
            },
            Msg::Tip {
                seq: 4,
                hash: [7u8; 32],
            },
            Msg::Fen {
                fen: "x".to_string(),
            },
            Msg::Done,
        ];
        for msg in messages {
            assert_eq!(Msg::decode(&msg.encode()).unwrap(), msg);
        }
    }

    #[test]
    fn wrong_version_stops_at_handshake() {
        let genesis = genesis_entry();
        let msg = Msg::Hello {
            version: PROTOCOL_VERSION + 1,
            genesis,
        };
        let err = Msg::decode(&msg.encode()).unwrap_err();
        assert!(err.is_bad_version());
        assert!(!err.is_decode());
    }

    #[test]
    fn garbage_never_panics_and_never_parses() {
        let inputs: &[&[u8]] = &[&[], &[0], &[255; 8], &[1, 2, 3, 4, 5], &[0; 128]];
        for input in inputs {
            assert!(Msg::decode(input).is_err(), "input {input:?}");
        }
        // Bit-flipped valid message stays an error or a different message,
        // never a panic; corrupt the length field of a real encoding.
        let mut bytes = Msg::Done.encode();
        bytes[0] ^= 0xff;
        let _ = Msg::decode(&bytes);
    }

    #[test]
    fn encoding_is_deterministic() {
        let msg = Msg::Tip {
            seq: 9,
            hash: [1u8; 32],
        };
        assert_eq!(msg.encode(), msg.encode());
    }
}
