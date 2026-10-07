//! Chess Relay application core.
//!
//! Rust owns correctness (rules, session, log, contract).
//! Godot owns presentation. See `docs/architecture/application_core.md`.
//!
//! Layout starts flat per the doc ("split only when a real boundary
//! forces it"). Each module is currently an empty boundary with no logic.

pub mod app;
pub mod bridge;
pub mod chess_core;
pub mod protocol;
pub mod session;
pub mod transport;
pub(crate) mod transport_iroh;
pub(crate) mod transport_rendezvous;

#[doc(inline)]
pub use transport_iroh::{GAME_ALPN, IrohConnection, IrohEndpoint, VOICE_ALPN, ticket_peer_id};
#[doc(inline)]
pub use transport_rendezvous::{
    derive_keypair, publish_loop, publish_once, resolve_ticket, unpublish,
};
