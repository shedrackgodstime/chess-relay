# Multiplayer UI lifecycle

The multiplayer hub owns presentation and user intent for invite choices, code
entry, player rows, and incoming or outgoing invite status. `app_root.gd` owns
screen changes and the typed bridge. Rust owns the recent-peer index and live
network outcomes. The `MockMultiplayerService` remains only a UI fixture and
is not a production source of multiplayer facts.

Keep this separation when backend work begins: the backend should report
events and receive user intent through the app layer. It should not own screen
controls or require the hub to know how a connection is established.

## Current lifecycle

```text
Multiplayer hub
├── Create invite -> show code and wait -> transport connected -> Game Setup
│   └── host live setup -> host starts -> guest auto-acknowledges -> both load -> board
├── Join by code -> resolving/connecting -> failed/retry or connected -> Setup
│   └── host setup snapshot -> wait for host start -> both load -> board
├── Invite listed player -> wait -> declined/retry or accepted -> Game Setup
└── Receive invite -> accept -> Game Setup or decline -> return to hub

Peer Game Setup -> host owns setup and Start; guest observes -> both enter only
after the host commit and the automatic readiness exchange
```

When the live link drops, the remaining game screen keeps the last Rust-owned
position visible but enters a non-interactive terminal barrier: clock, move,
promotion, draw, and selection actions stop. A later authoritative game-start
event may reopen interaction for resume. Intentional leave and unexpected
transport loss are distinct: `peer_left` is the authenticated leave result,
while `peer_disconnected` represents an unannounced transport failure.

Create, join, listed-player invitations, and incoming invitations use the live
bridge. All use the hub's shared full-width invite card. The small Create and
Join cards are hidden
while a flow is active, as are the player-list Invite buttons. An incoming
invitation is held by Rust until the Morgan card responds. Accepting it reuses
`GameSetupScreen`; declining it returns to the hub. A listed-player invite
uses the saved authenticated endpoint ticket and enters setup only after the
remote peer explicitly accepts.

## Screen and app event boundary

`MultiplayerHubScreen` emits intent signals:

| Signal | Meaning |
| --- | --- |
| `create_requested(code)` | Show the generated code and wait for a peer. |
| `create_cancelled` | Stop waiting for a peer. |
| `join_requested(code)` | Attempt to join with the entered code. |
| `join_cancelled(code)` | Cancel the pending code attempt. |
| `player_invite_requested(ticket)` | Invite the selected listed player using its Rust-owned ticket. |
| `player_invite_cancelled` | Cancel the outgoing player invitation. |
| `incoming_invite_response(invite_id, accepted)` | Send the user's accept or decline response. |
| `game_setup_requested(opponent_name, setup_kind)` | Open shared peer Game Setup after acceptance/connection. |
| `profile_name_changed(display_name)` | Persist the local display name through the Rust profile authority; the hub echoes the authoritative name back. |

The app routes results back to the hub through the live bridge for transport,
presence, and invitation events. Game Setup exposes `configure_peer` and the
live bridge setup contract for peer-specific presentation and host-owned setup
snapshots. `invite-host` and `invite-guest` are distinct setup roles: the
inviter owns choices and Start; the recipient observes the Rust snapshot.

Intentional leave is an authenticated `Leave` protocol message with bounded
shutdown acknowledgement. The receiving bridge emits `peer_left`, while an
unannounced endpoint failure emits `peer_disconnected`; screens must preserve
that distinction in their user-facing wording.

## Terminal game presentation and rematch

Rust owns the terminal fact and reason. Godot presents it as a dedicated card
while preserving the last authoritative board position:

| Authoritative event | Presentation | Available action |
| --- | --- | --- |
| Checkmate, resignation, or draw | Result card with reason | Review, Leave, and Rematch for a live peer game |
| Authenticated opponent leave | Opponent-left card | Review and Leave |
| Unrecovered transport failure | Connection-lost card | Review and Leave |

The terminal barrier stops moves, promotion, draw input, selection affordances,
and clocks. A rematch is not a local scene reset: it is an authenticated
`RematchRequest`/`RematchResponse` exchange. Both peers reset their Rust session,
advance a fresh generation, return to shared Game Setup, and only then can the
host start another game. Declining leaves the finished board available for
review.

## Mock scenarios

The `MockMultiplayerService` fixture has been removed from the production
tree; the scenarios below describe historical UI-development fixtures, not
current behavior. Live create/join/invite flows use the bridge paths above.

`src/ui/multiplayer/mock_multiplayer_service.gd` is deliberately temporary
and local to UI development:

- A created invite connects a mock opponent after two seconds unless canceled.
- `ABC-23456` is the successful join example; other well-formed eight-character codes exercise
  the failure and retry state.
- A listed-player invite is accepted for Ayo and Kemi, and declined for
  KnightOwl and RookRunner, so both outcomes can be reviewed.
- A mock incoming invite arrives five seconds after entering the hub. It can
  be accepted or declined; a declined invitation stays visible until Done.
- A peer setup renders the host's live setup snapshot; the guest has no Ready
  action and waits for the host to start.

These are test fixtures for presentation, not product rules. Replace their
outcomes with app-layer events; keep the screen states and user-intent boundary
stable where possible.

## Discovery preferences and future Settings page

The hub's Discovery settings are **visibility preferences**: whether this
device is discoverable nearby and whether it is discoverable online. They do
not control which other players appear in the list. The profile summary shows
the selected combination: nearby, online, both, or not discoverable.

The toggles currently live only in the hub instance. They are not persisted or
connected to a service. When a Settings page is designed, move ownership of
these preferences out of the hub so the page and hub read the same values. Keep
the UI preference model independent of the eventual transport or discovery
implementation. Persistence and consent wording should be settled with the
Settings UI; do not treat the current in-memory defaults as a final policy.

The player rows are observations from Rust's installation-local recent-peer
index. A row means that this installation successfully completed a network
handshake with that peer. Rust stores the stable peer identity, the latest
authenticated endpoint ticket when the transport provides one, and the last
successful-contact Unix timestamp in the versioned recent-peer record. A row
does not claim that the peer is online now; online/offline/unknown requires a
separate live presence contract. `online`, `offline`, and `unknown` are only
live observations from Rust; history and a stored ticket never imply presence.
Rust owns the records, presence state, ticket validation, and newest-first
ordering, while Godot renders those facts.

The endpoint ticket is retained after a failed dial. A failed dial is a
reachability result at that moment, not proof that the peer identity should be
deleted. Ticket replacement and record-retention policy must be explicit in
the backend; the UI must not delete records as a side effect of a failed
invite.
