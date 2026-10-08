//! Short-code rendezvous: join a game with eight characters, no server.
//!
//! The UI promises short invite codes while Iroh tickets are long. This
//! closes that gap the way irosh's wormhole does: both sides derive the
//! same pkarr keypair from the code alone (`SHA256(salt + code)`), the
//! host publishes its [`EndpointTicket`](iroh_tickets::endpoint::EndpointTicket)
//! as a TXT record under it, and the guest polls until the record
//! appears. Short-lived codes (TTL 5 minutes, tombstoned after pairing)
//! keep the window small.
//!
//! Security posture, stated plainly: anyone holding or guessing the code
//! derives the same keypair and can read — or overwrite — the record.
//! Eight characters are still enumerable by a determined scanner. What saves the
//! game is everything above this layer: the guest connects to *an*
//! endpoint, but the session only proceeds on signed genesis, and the UI
//! already gates joining on host accept/decline. A squatter gets a knock
//! on the door, not a seat at the board. Ticket sharing stays the fallback
//! for anyone who wants cryptographic addressing.
//!
//! This lives at the transport layer: it resolves codes to tickets, and
//! dialling stays with the endpoint.

use super::transport::TransportError;
use iroh_tickets::endpoint::EndpointTicket;
use pkarr::{
    Client, Keypair, ResolvePolicy, SignedPacket,
    dns::rdata::{RData, TXT},
};
use sha2::{Digest, Sha256};
use std::time::Duration;

/// Salt separating our rendezvous namespace from other pkarr users.
const RENDEZVOUS_SALT: &[u8] = b"chess-relay-v1";
/// DNS name holding the ticket inside the signed packet.
const RECORD_NAME: &str = "_chess-relay";
/// Ticket envelope: `chess-relay-ticket=<EndpointTicket>`.
const TICKET_PREFIX: &str = "chess-relay-ticket=";
/// Record lifetime: short-lived invites only.
const RECORD_TTL: u32 = 300;
/// Republish interval while an invite stays open.
const REPUBLISH_INTERVAL: Duration = Duration::from_secs(60);
/// Resolve poll interval for guests.
const RESOLVE_INTERVAL: Duration = Duration::from_secs(5);

/// Derives the rendezvous keypair from a human invite code.
///
/// Deterministic: both sides derive identical keys from the code alone,
/// which is what makes a server unnecessary — and what makes codes
/// enumerable, per the module docs.
#[must_use]
pub fn derive_keypair(code: &str) -> Keypair {
    let mut hasher = Sha256::new();
    hasher.update(RENDEZVOUS_SALT);
    hasher.update(code.as_bytes());
    let seed: [u8; 32] = hasher.finalize().into();
    Keypair::from_secret_key(&seed)
}

/// Builds the signed ticket packet without publishing (testable offline).
fn ticket_packet(code: &str, ticket: &EndpointTicket) -> Result<SignedPacket, TransportError> {
    let keypair = derive_keypair(code);
    let msg = format!("{TICKET_PREFIX}{ticket}");
    let txt = TXT::try_from(msg.as_str()).map_err(|_| TransportError::unavailable())?;
    SignedPacket::builder()
        .txt(
            RECORD_NAME
                .try_into()
                .map_err(|_| TransportError::unavailable())?,
            txt,
            RECORD_TTL,
        )
        .sign(&keypair)
        .map_err(|_| TransportError::unavailable())
}

/// Extracts the ticket from a resolved packet, if present and valid.
fn ticket_from_packet(packet: &SignedPacket) -> Option<EndpointTicket> {
    for record in packet.all_resource_records() {
        if let RData::TXT(txt) = &record.rdata
            && let Ok(content) = String::try_from(txt.clone())
            && let Some(ticket_str) = content.strip_prefix(TICKET_PREFIX)
            && let Ok(ticket) = ticket_str.parse::<EndpointTicket>()
        {
            return Some(ticket);
        }
    }
    None
}

/// Publishes `ticket` under `code` once.
///
/// # Errors
///
/// Returns [`TransportError`] when the pkarr client or packet fails.
pub async fn publish_once(code: &str, ticket: &EndpointTicket) -> Result<(), TransportError> {
    let client = Client::builder()
        .build()
        .map_err(|_| TransportError::unavailable())?;
    let packet = ticket_packet(code, ticket)?;
    client
        .publish(&packet)
        .await
        .map_err(|_| TransportError::unavailable())?;
    Ok(())
}

/// Keeps `ticket` published under `code` until cancelled.
///
/// Short TTL plus 60s republish keeps invites alive while open and lets
/// them die on their own. Cancel the handle (and call [`unpublish`])
/// once paired.
pub async fn publish_loop(code: String, ticket: EndpointTicket) {
    loop {
        if publish_once(&code, &ticket).await.is_err() {
            // Relays flap, especially on mobile networks; the loop is the
            // retry. The TTL bounds how stale a record can get.
        }
        tokio::time::sleep(REPUBLISH_INTERVAL).await;
    }
}

/// Resolves `code` to its ticket, polling until `timeout`.
///
/// # Errors
///
/// Returns [`TransportError`] when no record appears in time.
pub async fn resolve_ticket(
    code: &str,
    timeout: Duration,
) -> Result<EndpointTicket, TransportError> {
    let keypair = derive_keypair(code);
    let public_key = keypair.public_key();
    let client = Client::builder()
        .build()
        .map_err(|_| TransportError::unavailable())?;
    let deadline = tokio::time::Instant::now() + timeout;
    while tokio::time::Instant::now() < deadline {
        match client.resolve(&public_key, ResolvePolicy::CacheFirst).await {
            Ok(packet) => {
                if let Some(ticket) = ticket_from_packet(&packet) {
                    return Ok(ticket);
                }
            }
            Err(err) => {
                // Keep polling: transient relay/DNS failures are expected on
                // mobile. The final error must still tell the caller that
                // discovery failed, rather than looking like a hang.
                if tokio::time::Instant::now() + RESOLVE_INTERVAL >= deadline {
                    return Err(TransportError::unavailable_with_detail(format!(
                        "rendezvous lookup failed: {err}"
                    )));
                }
            }
        }
        tokio::time::sleep(RESOLVE_INTERVAL).await;
    }
    Err(TransportError::unavailable_with_detail(
        "rendezvous record not found before timeout".to_string(),
    ))
}

/// Overwrites the record with an empty tombstone so the code dies now
/// instead of at TTL expiry. Best effort by design.
pub async fn unpublish(code: &str) {
    let keypair = derive_keypair(code);
    let Ok(client) = Client::builder().build() else {
        return;
    };
    let Ok(tombstone) = SignedPacket::builder().sign(&keypair) else {
        return;
    };
    let _ = client.publish(&tombstone).await;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn derivation_is_deterministic_and_salted() {
        let a = derive_keypair("ABC123");
        let b = derive_keypair("ABC123");
        assert_eq!(a.public_key().to_string(), b.public_key().to_string());
        let c = derive_keypair("ABC124");
        assert_ne!(a.public_key().to_string(), c.public_key().to_string());
    }

    #[test]
    fn packet_round_trips_offline() {
        // Packet construction and parsing need no network.
        let keypair = derive_keypair("TEST99");
        let packet = SignedPacket::builder()
            .txt(
                RECORD_NAME.try_into().unwrap(),
                TXT::try_from("chess-relay-ticket=endpointbogus").unwrap(),
                RECORD_TTL,
            )
            .sign(&keypair)
            .unwrap();
        // Well-formed envelope, unparsable ticket: no ticket out.
        assert!(ticket_from_packet(&packet).is_none());
    }

    #[test]
    fn ticket_prefix_shapes_envelope() {
        assert!(TICKET_PREFIX.ends_with('='));
        assert_eq!(RECORD_TTL, 300);
    }

    /// Live round trip against real relays. Ignored by default: needs
    /// network and takes ~30s. Run explicitly to re-prove rendezvous.
    #[tokio::test]
    #[ignore = "live relays; run explicitly with -- --ignored"]
    async fn live_publish_resolve_round_trip() {
        use crate::IrohEndpoint;
        use crate::transport::Endpoint as _;

        let code = format!("LIVE{:04}", std::process::id() % 10000);
        let endpoint = IrohEndpoint::bind().await.expect("endpoint binds");
        let ticket: EndpointTicket = endpoint.ticket().parse().expect("own ticket parses");
        publish_once(&code, &ticket)
            .await
            .expect("publish reaches relays");
        let found = resolve_ticket(&code, Duration::from_secs(120))
            .await
            .expect("guest resolves");
        assert_eq!(found.to_string(), ticket.to_string());
        unpublish(&code).await;
        endpoint.close().await;
    }
}
