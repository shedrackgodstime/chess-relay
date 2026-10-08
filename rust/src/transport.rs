//! Transport boundary: connections, delivery, lifecycle, errors.
//!
//! Moves bytes between endpoints and exposes only what higher layers
//! need. Iroh specifics (direct vs relay, encryption, endpoint identity)
//! stay below this boundary, in the Iroh implementation that follows.
//!
//! Shape extracted from the Phase 4 spike, which proved it with real
//! endpoints: one side binds and shares a dial string, the other dials
//! it, and both exchange length-prefixed messages over reliable streams.
//! [`MemoryTransport`] fakes the same shape in-process so session and
//! application logic prove they cannot tell the difference — including
//! the drop-and-resume pattern from the arch doc (no clock: a disconnect
//! pauses, tips compare, missing entries replay).
//!
//! Framing is transport's job: [`encode_frame`] prefixes the postcard
//! bytes with their length for stream transport; message meaning stays
//! in [`crate::protocol`].
//!
//! # Examples
//!
//! ```
//! use chess_relay_core::protocol::Msg;
//! use chess_relay_core::transport::{Connection, Endpoint, MemoryTransport, TransportError};
//!
//! # #[tokio::main]
//! # async fn main() -> Result<(), TransportError> {
//! let mut hub = MemoryTransport::new();
//! let mut host = hub.endpoint();
//! let mut guest = hub.endpoint();
//! let mut to_host = guest.connect(&host.ticket()).await?;
//! let mut to_guest = host.accept().await?;
//! to_guest.send(&Msg::Done).await?;
//! assert_eq!(to_host.recv().await?, Msg::Done);
//! # Ok(())
//! # }
//! ```

use crate::protocol::{Msg, ProtocolError};
use std::backtrace::Backtrace;
use std::collections::VecDeque;
use std::fmt::{self, Display, Formatter};
use std::sync::{Arc, Mutex};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::sync::mpsc;

/// Length prefix size for framed messages.
pub const FRAME_PREFIX_LEN: usize = 4;

/// Largest single message accepted (1 MiB; a log entry is ~200 bytes).
pub const MAX_FRAME_LEN: usize = 1024 * 1024;

/// One side of a connection: framed messages both ways.
///
/// Async methods are native (Rust 1.75+), not boxed futures: readability
/// wins here because the trait already requires `Send` and carries no
/// lifetime-captured state that would need explicit auto-trait bounds.
#[allow(async_fn_in_trait)]
pub trait Connection: Send {
    /// Sends one message, framed.
    async fn send(&mut self, msg: &Msg) -> Result<(), TransportError>;
    /// Receives the next message. A closed peer surfaces as an error,
    /// never a silent end: the caller decides resume vs stop.
    async fn recv(&mut self) -> Result<Msg, TransportError>;
    /// Closes this side; the peer observes closure on receive.
    async fn close(&mut self) -> Result<(), TransportError>;
}

/// An endpoint that dials tickets and accepts peers.
///
/// See [`Connection`] on the async-method choice.
#[allow(async_fn_in_trait)]
pub trait Endpoint: Send {
    /// One side of an accepted or dialled connection.
    type Connection: Connection;

    /// Shareable dial string for this endpoint.
    fn ticket(&self) -> String;
    /// Dials a ticket. Bad tickets fail here, not later.
    async fn connect(&mut self, ticket: &str) -> Result<Self::Connection, TransportError>;
    /// Accepts the next incoming peer.
    async fn accept(&mut self) -> Result<Self::Connection, TransportError>;
}

/// Transport-layer failure: addressing, lifecycle, or wire decoding.
///
/// Sole error type of this layer (arch doc §Errors). Protocol decode
/// failures arrive as causes via `From<ProtocolError>`.
///
/// # Examples
///
/// ```
/// use chess_relay_core::transport::{Endpoint, MemoryTransport};
///
/// # #[tokio::main]
/// # async fn main() -> Result<(), chess_relay_core::transport::TransportError> {
/// let hub = MemoryTransport::new();
/// let mut ep = hub.endpoint();
/// let err = match ep.connect("").await {
///     Err(err) => err,
///     Ok(_) => unreachable!(),
/// };
/// assert!(err.is_unavailable());
/// # Ok(())
/// # }
/// ```
#[derive(Debug)]
pub struct TransportError {
    kind: TransportErrorKind,
    backtrace: Backtrace,
    cause: Option<Box<ProtocolError>>,
}

#[derive(Debug)]
enum TransportErrorKind {
    /// Dial string rejected, or no peer reachable.
    Unavailable(Option<String>),
    /// Use after close, or the peer went away.
    Closed,
    /// A received frame did not decode.
    Wire,
}

impl TransportError {
    pub(crate) fn unavailable() -> Self {
        Self::bare(TransportErrorKind::Unavailable(None))
    }

    pub(crate) fn unavailable_with_detail(detail: String) -> Self {
        Self::bare(TransportErrorKind::Unavailable(Some(detail)))
    }

    pub(crate) fn closed() -> Self {
        Self::bare(TransportErrorKind::Closed)
    }

    pub(crate) fn wire() -> Self {
        Self::bare(TransportErrorKind::Wire)
    }

    fn bare(kind: TransportErrorKind) -> Self {
        Self {
            kind,
            backtrace: Backtrace::capture(),
            cause: None,
        }
    }

    /// Whether dialling or reachability failed.
    #[must_use]
    pub fn is_unavailable(&self) -> bool {
        matches!(self.kind, TransportErrorKind::Unavailable(_))
    }

    /// Whether the connection is gone.
    #[must_use]
    pub fn is_closed(&self) -> bool {
        matches!(self.kind, TransportErrorKind::Closed)
    }

    /// Whether a received frame was undecodable.
    #[must_use]
    pub fn is_wire(&self) -> bool {
        matches!(self.kind, TransportErrorKind::Wire)
    }

    /// Underlying protocol failure, if any.
    #[must_use]
    pub fn protocol_cause(&self) -> Option<&ProtocolError> {
        self.cause.as_deref()
    }
}

impl Display for TransportError {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        let summary = match &self.kind {
            TransportErrorKind::Unavailable(detail) => {
                if let Some(detail) = detail {
                    return write!(f, "transport error: peer unavailable ({detail})");
                }
                "peer unavailable"
            }
            TransportErrorKind::Closed => "connection closed",
            TransportErrorKind::Wire => "undecodable frame",
        };
        write!(f, "transport error: {summary}")?;
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

impl std::error::Error for TransportError {}

impl From<ProtocolError> for TransportError {
    fn from(cause: ProtocolError) -> Self {
        Self {
            kind: TransportErrorKind::Wire,
            backtrace: Backtrace::capture(),
            cause: Some(Box::new(cause)),
        }
    }
}

/// Encodes one framed message: length prefix plus postcard bytes.
#[must_use]
pub fn encode_frame(msg: &Msg) -> Vec<u8> {
    let body = msg.encode();
    let mut frame = Vec::with_capacity(FRAME_PREFIX_LEN + body.len());
    frame.extend_from_slice(&(body.len() as u32).to_le_bytes());
    frame.extend_from_slice(&body);
    frame
}

/// Reads one framed message from an async byte reader.
///
/// # Errors
///
/// Returns [`TransportError`] on I/O failure, oversize length, a
/// truncated body, or undecodable content.
pub async fn read_frame<R: AsyncRead + Unpin>(reader: &mut R) -> Result<Msg, TransportError> {
    let mut prefix = [0u8; FRAME_PREFIX_LEN];
    reader
        .read_exact(&mut prefix)
        .await
        .map_err(|_| TransportError::closed())?;
    let len = u32::from_le_bytes(prefix) as usize;
    if len == 0 || len > MAX_FRAME_LEN {
        return Err(TransportError::wire());
    }
    let mut body = vec![0u8; len];
    reader
        .read_exact(&mut body)
        .await
        .map_err(|_| TransportError::closed())?;
    Msg::decode(&body).map_err(TransportError::from)
}

/// Writes one framed message to an async byte writer. Stream lifecycle
/// (finish/close per message or persistent streams) stays with the
/// transport implementation; this only frames.
///
/// # Errors
///
/// Returns [`TransportError`] when the peer is gone.
pub async fn write_frame<W: AsyncWrite + Unpin>(
    writer: &mut W,
    msg: &Msg,
) -> Result<(), TransportError> {
    writer
        .write_all(&encode_frame(msg))
        .await
        .map_err(|_| TransportError::closed())?;
    Ok(())
}

/// In-memory transport: the trait shape with channels instead of QUIC.
///
/// Endpoints come from one hub; `connect` links the caller to the waiting
/// peer and `accept` receives it. Bytes cross encoded, so framing and the
/// codec are exercised; closure propagates as errors. Same contract the
/// Iroh implementation honors, so resume logic cannot tell them apart.
pub struct MemoryTransport {
    pending: Arc<Mutex<VecDeque<PendingLink>>>,
}

struct PendingLink {
    to_acceptor: mpsc::Sender<Vec<u8>>,
    from_acceptor: mpsc::Receiver<Vec<u8>>,
}

impl MemoryTransport {
    /// Creates a hub handing out linked endpoints.
    #[must_use]
    pub fn new() -> Self {
        Self {
            pending: Arc::new(Mutex::new(VecDeque::new())),
        }
    }

    /// A fresh endpoint on this hub.
    pub fn endpoint(&self) -> MemoryEndpoint {
        MemoryEndpoint {
            pending: Arc::clone(&self.pending),
        }
    }
}

impl Default for MemoryTransport {
    fn default() -> Self {
        Self::new()
    }
}

/// One end of an in-memory link.
pub struct MemoryEndpoint {
    pending: Arc<Mutex<VecDeque<PendingLink>>>,
}

impl Endpoint for MemoryEndpoint {
    type Connection = MemoryConnection;

    fn ticket(&self) -> String {
        "memory://peer".to_string()
    }

    async fn connect(&mut self, ticket: &str) -> Result<Self::Connection, TransportError> {
        if ticket.is_empty() {
            return Err(TransportError::unavailable());
        }
        // Bytes toward the acceptor; bytes back from it.
        let (to_acceptor, from_dialler) = mpsc::channel(64);
        let (to_dialler, from_acceptor) = mpsc::channel(64);
        {
            let mut pending = self
                .pending
                .lock()
                .map_err(|_| TransportError::unavailable())?;
            pending.push_back(PendingLink {
                to_acceptor,
                from_acceptor,
            });
        }
        Ok(MemoryConnection {
            incoming: from_dialler,
            outgoing: to_dialler,
            open: true,
        })
    }

    async fn accept(&mut self) -> Result<Self::Connection, TransportError> {
        let link = {
            let mut pending = self
                .pending
                .lock()
                .map_err(|_| TransportError::unavailable())?;
            pending
                .pop_front()
                .ok_or_else(TransportError::unavailable)?
        };
        Ok(MemoryConnection {
            incoming: link.from_acceptor,
            outgoing: link.to_acceptor,
            open: true,
        })
    }
}

/// One in-memory connection: framed bytes across channels.
pub struct MemoryConnection {
    incoming: mpsc::Receiver<Vec<u8>>,
    outgoing: mpsc::Sender<Vec<u8>>,
    open: bool,
}

impl Connection for MemoryConnection {
    async fn send(&mut self, msg: &Msg) -> Result<(), TransportError> {
        if !self.open {
            return Err(TransportError::closed());
        }
        self.outgoing
            .send(encode_frame(msg))
            .await
            .map_err(|_| TransportError::closed())
    }

    async fn recv(&mut self) -> Result<Msg, TransportError> {
        if !self.open {
            return Err(TransportError::closed());
        }
        let frame = self
            .incoming
            .recv()
            .await
            .ok_or_else(TransportError::closed)?;
        if frame.len() < FRAME_PREFIX_LEN {
            return Err(TransportError::wire());
        }
        let len = u32::from_le_bytes(
            frame[..FRAME_PREFIX_LEN]
                .try_into()
                .map_err(|_| TransportError::wire())?,
        ) as usize;
        if len == 0 || len > MAX_FRAME_LEN || frame.len() != FRAME_PREFIX_LEN + len {
            return Err(TransportError::wire());
        }
        Msg::decode(&frame[FRAME_PREFIX_LEN..]).map_err(TransportError::from)
    }

    async fn close(&mut self) -> Result<(), TransportError> {
        self.open = false;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frame_prefix_carries_body_length() {
        let frame = encode_frame(&Msg::Done);
        let len = u32::from_le_bytes(frame[..FRAME_PREFIX_LEN].try_into().unwrap()) as usize;
        assert_eq!(frame.len(), FRAME_PREFIX_LEN + len);
        assert!(len > 0 && len <= MAX_FRAME_LEN);
    }

    #[test]
    fn error_kinds_report() {
        assert!(TransportError::unavailable().is_unavailable());
        assert!(TransportError::closed().is_closed());
        assert!(TransportError::wire().is_wire());
        assert!(TransportError::closed().protocol_cause().is_none());
    }

    #[tokio::test]
    async fn memory_pair_exchanges_and_closes() {
        let hub = MemoryTransport::new();
        let mut host = hub.endpoint();
        let mut guest = hub.endpoint();
        let ticket = host.ticket();
        assert!(ticket.starts_with("memory://"));
        let mut to_host = guest.connect(&ticket).await.unwrap();
        let mut to_guest = host.accept().await.unwrap();
        assert!(matches!(guest.connect("").await, Err(e) if e.is_unavailable()));
        assert!(matches!(host.accept().await, Err(e) if e.is_unavailable()));

        to_guest.send(&Msg::Done).await.unwrap();
        assert_eq!(to_host.recv().await.unwrap(), Msg::Done);
        to_host
            .send(&Msg::Tip {
                seq: 2,
                hash: [1u8; 32],
            })
            .await
            .unwrap();
        assert_eq!(
            to_guest.recv().await.unwrap(),
            Msg::Tip {
                seq: 2,
                hash: [1u8; 32]
            }
        );

        to_host.close().await.unwrap();
        assert!(matches!(to_host.send(&Msg::Done).await, Err(e) if e.is_closed()));
        assert!(matches!(to_host.recv().await, Err(e) if e.is_closed()));
    }

    #[tokio::test]
    async fn memory_drop_reads_as_closed() {
        let hub = MemoryTransport::new();
        let host = hub.endpoint();
        let mut guest = hub.endpoint();
        let ticket = host.ticket();
        let mut to_host = guest.connect(&ticket).await.unwrap();
        drop(host);
        drop(guest);
        drop(hub);
        assert!(matches!(to_host.recv().await, Err(e) if e.is_closed()));
    }

    #[tokio::test]
    async fn frame_codec_round_trips_over_duplex() {
        let (mut writer, mut reader) = tokio::io::duplex(4096);
        let msg = Msg::Fen {
            fen: "x".to_string(),
        };
        write_frame(&mut writer, &msg).await.unwrap();
        let back = read_frame(&mut reader).await.unwrap();
        assert_eq!(back, msg);
    }

    #[tokio::test]
    async fn read_frame_rejects_oversize_and_truncated() {
        let mut bad = (MAX_FRAME_LEN as u32 + 1).to_le_bytes().to_vec();
        bad.extend_from_slice(&[0u8; 4]);
        let mut cursor: &[u8] = &bad;
        assert!(read_frame(&mut cursor).await.unwrap_err().is_wire());

        let mut short: &[u8] = &[1, 2, 3];
        assert!(read_frame(&mut short).await.unwrap_err().is_closed());

        let mut truncated = encode_frame(&Msg::Done);
        truncated.truncate(truncated.len() - 1);
        let mut cursor: &[u8] = &truncated;
        assert!(read_frame(&mut cursor).await.unwrap_err().is_closed());
    }
}
