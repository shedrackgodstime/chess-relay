# Irosh reference audit

Status: Observed and source-confirmed; no Irosh code was copied.

Reference inspected: `/home/kristency/Projects/irosh`.

This audit records behavior found in the reference project and the parts that
are applicable to Chess Relay. It does not treat Irosh's CLI/SSH architecture
as a direct implementation template.

## Confirmed patterns worth carrying forward

### 1. Endpoint identity and endpoint address are separate values

Irosh keeps a persistent Ed25519 identity in its state directory, derives the
Iroh endpoint identity from that key, and exposes a `ServerReady` value that
contains both `endpoint_id` and a complete `Ticket`.

Evidence:

- `irosh/src/storage/keys.rs`: persistent identity loading/generation.
- `irosh/src/transport/iroh.rs`: `ServerEndpoint` contains `endpoint`, `addr`,
  `endpoint_id`, relay URLs, and direct addresses.
- `irosh/src/transport/ticket.rs`: typed `Ticket` wraps `EndpointTicket` and
  exposes its `EndpointAddr`.
- `irosh/src/server/mod.rs`: `ServerReady` carries both endpoint identity and
  ticket.

Application to Chess Relay: the stable peer identity must identify the peer,
while the ticket/address is replaceable dial material. They must never be
collapsed into one string or regenerated independently.

### 2. Endpoint readiness precedes ticket publication

`bind_server_endpoint()` waits for `endpoint.online()` with a ten-second
timeout before reading `endpoint.addr()` and constructing the ticket.

Chess Relay already has `IrohEndpoint::wait_online()` in
`rust/src/transport_iroh.rs`, but `start_network()` in `rust/src/bridge.rs`
binds and proceeds without calling it before host ticket generation and
rendezvous publication.

Finding: `TRANSPORT-READY-001` — implemented. Chess Relay now performs the
same bounded readiness wait before ticket generation. Relay readiness is not a
hard dependency: direct paths remain allowed after the ten-second wait.

### 3. Saved peers are dial profiles, not presence

Irosh stores a named `PeerProfile` containing a human alias and a typed ticket.
It lists, loads, renames, and deletes those profiles. On a successful client
session it auto-saves the ticket, deduplicating by the endpoint ID inside the
ticket. On a failed connection it may preserve a recovered ticket for later
retry.

Evidence: `irosh/src/storage/peers.rs` and
`irosh/cli/src/commands/connect/mod.rs`.

There is no online/offline presence implementation in this peer address book.
Therefore this validates our separation:

```text
saved peer = identity + dial material + local history
online peer = live presence/discovery fact
```

A failed dial must not delete the saved peer. It is a reachability result at a
point in time, not proof that the identity is invalid.

### 4. Wormhole discovery is temporary rendezvous, not presence

Irosh derives a Pkarr key from a human pairing code, publishes a ticket with a
five-minute record lifetime, republishes while active, polls for the record,
and explicitly publishes a tombstone on close. A successful one-shot pairing
can burn the code.

Evidence: `irosh/src/transport/wormhole.rs`, `irosh/src/server/mod.rs`, and
the `Wormhole rendezvous` section in `irosh/docs/README.md`.

Application to Chess Relay: our short invite code can resolve a temporary
connection target, but it cannot by itself answer “is this saved peer online?”
or implement an incoming invite notification. Those require a separate,
authenticated presence/invitation contract.

### 5. Metadata is exchanged after transport/authentication

Irosh exchanges optional peer metadata over a separate framed control stream
after the P2P/SSH connection is established. The exchange has a magic header,
version, kind, length limit, sanitization, and timeout; metadata failure does
not silently become a transport success.

Evidence: `irosh/src/transport/metadata/{codec.rs,types.rs,mod.rs}` and
`irosh/src/client/connect.rs`.

Application to Chess Relay: display name/capabilities can be a separate
authenticated metadata snapshot. They must not be mixed into the transport
quality or online-presence state machine.

## What Irosh does not provide

- No recent-player online indicator.
- No peer-to-peer incoming game invitation UI/protocol.
- No heartbeat-based presence directory.
- No guarantee that a stored ticket remains current after the remote endpoint
  changes address data.

Therefore Irosh supports the backend direction, but it does not already solve
Morgan's online indicator or incoming invite behavior for us.

## Chess Relay implementation status

1. Bounded endpoint-online readiness is implemented before ticket generation.
2. Rust's versioned recent-peer record is the persistence authority; the UI
   reads it through `recent_peer_records`.
3. Failed dialing preserves the record and emits an explicit offline
   observation; it does not delete history or silently imply presence.
4. The bridge exposes live `online`, `offline`, and `unknown` observations.
5. Authenticated incoming/outgoing invite messages now define an explicit
   request, accept/decline response, and game-session transition.
6. Rust unit coverage is required before marking the bridge boundary verified;
   two-process Godot/device verification remains an external gate.

The UI must not infer presence from a stored ticket or timestamp. Morgan's
invite card is backed by the Rust protocol, but it is only a live fact after
the authenticated transport has delivered the invite event.
