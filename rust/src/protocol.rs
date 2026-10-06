//! Wire boundary: application commands/events <-> bytes.
//!
//! Covers what crosses a process/device boundary (log entries,
//! offers, handshake, versions). Never decides move legality.
//! Protocol version goes in the very first message.
