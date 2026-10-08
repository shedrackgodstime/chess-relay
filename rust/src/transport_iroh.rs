//! Iroh transport: the [`super::transport`] trait over QUIC endpoints.
//!
//! Proven shapes from the Phase 4 spike, moved here unchanged in
//! behavior: N0 preset, game ALPN, ticket dial strings, one uni stream
//! per framed message, tip compare plus replay for resume. What the
//! spike framed by hand now flows through [`super::transport`] framing
//! and [`super::protocol`] messages.
//!
//! Identity follows the arch doc: one 32-byte seed builds both the Iroh
//! endpoint key and the session signing key, so the endpoint identity
//! IS the peer identity. The CLI asserts the bytes match.

use super::protocol::Msg;
use super::transport::{Connection, Endpoint, TransportError, TransportQuality, encode_frame};
use iroh::{EndpointId, endpoint::presets};
use iroh_tickets::endpoint::EndpointTicket;
use std::str::FromStr;

/// ALPN identifying chess-relay game traffic.
pub const GAME_ALPN: &[u8] = b"chess-relay/1";

/// Reserved voice ALPN: served on the same endpoint, unused in v1.
pub const VOICE_ALPN: &[u8] = b"chess-relay-voice/1";

/// Iroh-backed endpoint. Clone shares the underlying endpoint, so a
/// link task can accept on its own handle while the bridge keeps one
/// for closing: no mutex ever spans an accept.
#[derive(Clone)]
pub struct IrohEndpoint {
    endpoint: iroh::Endpoint,
}

impl IrohEndpoint {
    /// Binds with the game (and reserved voice) ALPNs.
    ///
    /// # Errors
    ///
    /// Returns [`TransportError`] when binding fails.
    pub async fn bind() -> Result<Self, TransportError> {
        Self::bind_with(GAME_ALPN, VOICE_ALPN).await
    }

    /// Binds with explicit ALPNs (tests and future protocols).
    ///
    /// # Errors
    ///
    /// Returns [`TransportError`] when binding fails.
    pub async fn bind_with(game_alpn: &[u8], voice_alpn: &[u8]) -> Result<Self, TransportError> {
        let endpoint = iroh::Endpoint::builder(presets::N0)
            .alpns(vec![game_alpn.to_vec(), voice_alpn.to_vec()])
            .bind()
            .await
            .map_err(|err| TransportError::unavailable_with_detail(err.to_string()))?;
        Ok(Self { endpoint })
    }

    /// Binds with a fixed identity seed. The same seed builds the session
    /// signing key, so endpoint identity equals peer identity.
    ///
    /// # Errors
    ///
    /// Returns [`TransportError`] when binding fails.
    pub async fn bind_with_seed(seed: [u8; 32]) -> Result<Self, TransportError> {
        let secret = iroh::SecretKey::from_bytes(&seed);
        let endpoint = iroh::Endpoint::builder(presets::N0)
            .secret_key(secret)
            .alpns(vec![GAME_ALPN.to_vec(), VOICE_ALPN.to_vec()])
            .bind()
            .await
            .map_err(|err| TransportError::unavailable_with_detail(err.to_string()))?;
        Ok(Self { endpoint })
    }

    /// Local endpoint identity bytes (the peer identity).
    #[must_use]
    pub fn id_bytes(&self) -> [u8; 32] {
        *self.endpoint.id().as_bytes()
    }

    /// Waits until the endpoint reaches its home relay. Best effort:
    /// direct paths work without it.
    pub async fn wait_online(&self) {
        self.endpoint.online().await;
    }

    /// Closes the endpoint.
    pub async fn close(&self) {
        self.endpoint.close().await;
    }
}

impl Endpoint for IrohEndpoint {
    type Connection = IrohConnection;

    fn ticket(&self) -> String {
        EndpointTicket::new(self.endpoint.addr()).to_string()
    }

    async fn connect(&mut self, ticket: &str) -> Result<Self::Connection, TransportError> {
        let parsed: EndpointTicket =
            EndpointTicket::from_str(ticket).map_err(|_| TransportError::unavailable())?;
        let connection = self
            .endpoint
            .connect(parsed.endpoint_addr().clone(), GAME_ALPN)
            .await
            .map_err(|err| TransportError::unavailable_with_detail(err.to_string()))?;
        Ok(IrohConnection { connection })
    }

    async fn accept(&mut self) -> Result<Self::Connection, TransportError> {
        let incoming = self
            .endpoint
            .accept()
            .await
            .ok_or_else(TransportError::closed)?;
        let connection = incoming.await.map_err(|_| TransportError::closed())?;
        Ok(IrohConnection { connection })
    }
}

/// One Iroh connection: a framed message per uni stream.
pub struct IrohConnection {
    connection: iroh::endpoint::Connection,
}

impl IrohConnection {
    /// Remote endpoint identity bytes.
    #[must_use]
    pub fn peer_id_bytes(&self) -> [u8; 32] {
        *self.connection.remote_id().as_bytes()
    }
}

impl Connection for IrohConnection {
    async fn send(&mut self, msg: &Msg) -> Result<(), TransportError> {
        let frame = encode_frame(msg);
        let mut send = self
            .connection
            .open_uni()
            .await
            .map_err(|_| TransportError::closed())?;
        send.write_all(&frame)
            .await
            .map_err(|_| TransportError::closed())?;
        send.finish().map_err(|_| TransportError::closed())?;
        Ok(())
    }

    async fn recv(&mut self) -> Result<Msg, TransportError> {
        let mut recv = self
            .connection
            .accept_uni()
            .await
            .map_err(|_| TransportError::closed())?;
        let mut prefix = [0u8; super::transport::FRAME_PREFIX_LEN];
        recv.read_exact(&mut prefix)
            .await
            .map_err(|_| TransportError::closed())?;
        let len = u32::from_le_bytes(prefix) as usize;
        if len == 0 || len > super::transport::MAX_FRAME_LEN {
            return Err(TransportError::wire());
        }
        let mut body = vec![0u8; len];
        recv.read_exact(&mut body)
            .await
            .map_err(|_| TransportError::closed())?;
        Msg::decode(&body).map_err(TransportError::from)
    }

    async fn close(&mut self) -> Result<(), TransportError> {
        self.connection.close(0u32.into(), b"done");
        Ok(())
    }

    fn quality(&self) -> Option<TransportQuality> {
        let paths = self.connection.paths();
        let path = paths
            .iter()
            .find(|path| path.is_selected())
            .or_else(|| paths.iter().next())?;
        let stats = path.stats();
        let sent = stats.udp_tx.datagrams.max(1);
        let loss_percent = ((stats.lost_packets.saturating_mul(100)) / sent).min(100) as u8;
        Some(TransportQuality {
            rtt_ms: stats.rtt.as_millis().min(u32::MAX as u128) as u32,
            loss_percent,
            direct: path.is_ip(),
        })
    }
}

/// Parses a ticket string to its endpoint identity, for logging.
#[must_use]
pub fn ticket_peer_id(ticket: &str) -> Option<EndpointId> {
    EndpointTicket::from_str(ticket)
        .ok()
        .map(|t| t.endpoint_addr().id)
}
