//! Signed, hash-linked match record.
//!
//! Every entry carries its sequence number, the hash of the previous
//! entry, a payload, the mover's identity, and the mover's signature
//! over all of that. Move entries additionally collect the opponent's
//! co-signature once the opponent re-validates them: a move is agreed
//! only with both signatures on it.
//!
//! Hashing and signing use hand-rolled canonical bytes (little-endian
//! integers, fixed field order), so all peers hash identically without
//! a serialization framework. Wire encoding arrives with the protocol
//! slice; this layer only guarantees canonical content.
//!
//! Keys are ed25519. Session logic never sees Iroh: a [`PeerId`] is just
//! 32 public-key bytes, and the transport adapter maps Iroh endpoint
//! keys onto them later.

use crate::chess_core::{Color, Move, Role};
use ed25519_dalek::{Signature, Signer, SigningKey, Verifier, VerifyingKey};
use serde::{Deserialize, Serialize};

/// Peer identity: 32 ed25519 public-key bytes.
///
/// Faces other peers across the log and, later, the transport adapter
/// maps Iroh endpoint keys onto these bytes.
///
/// # Examples
///
/// ```
/// use chess_relay_core::session::PeerId;
/// use ed25519_dalek::SigningKey;
///
/// let peer = PeerId::of(&SigningKey::from_bytes(&[7u8; 32]));
/// assert_eq!(peer.to_string().len(), 8);
/// ```
#[derive(Clone, Copy, Default, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub struct PeerId([u8; 32]);

impl PeerId {
    /// Identity belonging to `secret`.
    #[must_use]
    pub fn of(secret: &SigningKey) -> Self {
        Self(VerifyingKey::from(secret).to_bytes())
    }

    /// Identity from raw public-key bytes (network-learned peers).
    ///
    /// Untrusted until signatures verify; the log does that on receipt.
    #[must_use]
    pub fn from_bytes(bytes: [u8; 32]) -> Self {
        Self(bytes)
    }

    /// Raw public-key bytes.
    #[must_use]
    pub fn bytes(&self) -> [u8; 32] {
        self.0
    }

    /// Verifies `sig` over `message` as signed by this peer.
    pub(crate) fn verify(&self, message: &[u8], sig: &[u8; 64]) -> Result<(), super::SessionError> {
        let key = VerifyingKey::from_bytes(&self.0).map_err(|_| super::SessionError::bad_key())?;
        let signature = Signature::from_bytes(sig);
        key.verify(message, &signature)
            .map_err(|_| super::SessionError::bad_signature())
    }
}

impl std::fmt::Debug for PeerId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "PeerId({})", hex_of(&self.0))
    }
}

impl std::fmt::Display for PeerId {
    /// Short hex prefix for logs and UI.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&hex_of(&self.0[..4]))
    }
}

fn hex_of(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut text = String::with_capacity(bytes.len() * 2);
    for &byte in bytes {
        text.push(HEX[(byte >> 4) as usize] as char);
        text.push(HEX[(byte & 0x0f) as usize] as char);
    }
    text
}

/// Log payload: what one entry records.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum LogPayload {
    /// First entry: pins protocol version, sides, and host.
    Genesis {
        /// Wire protocol version (must match ours).
        version: u16,
        /// Peer playing White.
        white: PeerId,
        /// Peer playing Black.
        black: PeerId,
        /// Peer that created the session.
        host: PeerId,
    },
    /// A played move (agreed once co-signed).
    Move {
        /// Played move.
        mv: Move,
    },
    /// Request for an agreed draw.
    DrawOffer,
    /// Acceptance of the offer at `offer_seq`.
    DrawAccept {
        /// Sequence of the answered offer.
        offer_seq: u64,
    },
    /// Unilateral early end by the mover.
    Resign,
    /// Unilateral cancellation by the mover.
    Abort,
}

/// One signed link in the match record.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LogEntry {
    /// Position in the log; must equal the entry index.
    pub seq: u64,
    /// Hash of the previous entry; all zeroes for genesis.
    pub prev_hash: [u8; 32],
    /// What this entry records.
    pub payload: LogPayload,
    /// Peer that authored (and signed) this entry.
    pub mover: PeerId,
    /// `mover`'s signature over the entry hash.
    #[serde(with = "serde_bytes")]
    pub mover_sig: [u8; 64],
    /// Opponent's co-signature (moves and genesis only).
    #[serde(with = "serde_bytes")]
    pub co_sig: Option<[u8; 64]>,
}

impl LogEntry {
    /// Hash over sequence, link, payload, and mover (never signatures).
    #[must_use]
    pub fn hash(&self) -> [u8; 32] {
        entry_hash(self.seq, &self.prev_hash, &self.payload, &self.mover)
    }

    /// Whether the opponent co-signed this entry.
    #[must_use]
    pub fn is_agreed(&self) -> bool {
        self.co_sig.is_some()
    }

    /// Signs a fresh entry authored by `secret`.
    pub(crate) fn signed(
        seq: u64,
        prev_hash: [u8; 32],
        payload: LogPayload,
        secret: &SigningKey,
    ) -> Self {
        let mover = PeerId::of(secret);
        let hash = entry_hash(seq, &prev_hash, &payload, &mover);
        let mover_sig = secret.sign(&hash).to_bytes();
        Self {
            seq,
            prev_hash,
            payload,
            mover,
            mover_sig,
            co_sig: None,
        }
    }

    /// Verifies author signature (and co-signature, if present).
    pub(crate) fn verify_sigs(&self, other: PeerId) -> Result<(), super::SessionError> {
        let hash = self.hash();
        self.mover.verify(&hash, &self.mover_sig)?;
        if let Some(co) = &self.co_sig {
            other.verify(&hash, co)?;
        }
        Ok(())
    }
}

/// Hash over canonical entry bytes.
pub(crate) fn entry_hash(
    seq: u64,
    prev_hash: &[u8; 32],
    payload: &LogPayload,
    mover: &PeerId,
) -> [u8; 32] {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(seq.to_le_bytes());
    hasher.update(prev_hash);
    hasher.update(payload_bytes(payload));
    hasher.update(mover.bytes());
    hasher.finalize().into()
}

fn payload_bytes(payload: &LogPayload) -> Vec<u8> {
    let mut bytes = Vec::new();
    match payload {
        LogPayload::Genesis {
            version,
            white,
            black,
            host,
        } => {
            bytes.push(0);
            bytes.extend_from_slice(&version.to_le_bytes());
            bytes.extend_from_slice(&white.bytes());
            bytes.extend_from_slice(&black.bytes());
            bytes.extend_from_slice(&host.bytes());
        }
        LogPayload::Move { mv } => {
            bytes.push(1);
            bytes.push(mv.from.index());
            bytes.push(mv.to.index());
            bytes.push(match mv.promotion {
                None => 0,
                Some(Role::Pawn) => 1,
                Some(Role::Knight) => 2,
                Some(Role::Bishop) => 3,
                Some(Role::Rook) => 4,
                Some(Role::Queen) => 5,
                Some(Role::King) => 6,
            });
        }
        LogPayload::DrawOffer => bytes.push(2),
        LogPayload::DrawAccept { offer_seq } => {
            bytes.push(3);
            bytes.extend_from_slice(&offer_seq.to_le_bytes());
        }
        LogPayload::Resign => bytes.push(4),
        LogPayload::Abort => bytes.push(5),
    }
    bytes
}

/// Side alias so session code reads in match terms.
pub(crate) fn side_peer(white: PeerId, black: PeerId, side: Color) -> PeerId {
    match side {
        Color::White => white,
        Color::Black => black,
    }
}
