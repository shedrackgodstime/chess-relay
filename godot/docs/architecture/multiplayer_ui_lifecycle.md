# Multiplayer UI lifecycle

The multiplayer hub owns presentation and user intent for invite choices, code
entry, player rows, and incoming or outgoing invite status. `app_root.gd` owns
screen changes and the typed bridge. Rust owns the recent-peer index and live
network outcomes. The `MockMultiplayerService` supplies only the explicitly
labelled preview invite flows that do not yet have a backend contract.

Keep this separation when backend work begins: the backend should report
events and receive user intent through the app layer. It should not own screen
controls or require the hub to know how a connection is established.

## Current lifecycle

```text
Multiplayer hub
├── Create invite -> show code and wait -> transport connected -> Game Setup
│   └── host live setup -> host starts -> guest auto-acknowledges -> game -> board
├── Join by code -> resolving/connecting -> failed/retry or connected -> Setup
│   └── host setup snapshot -> wait for host start -> game -> board
├── Invite listed player -> wait -> declined/retry or accepted -> Game Setup
└── Receive invite -> accept -> Game Setup or decline -> return to hub

Peer Game Setup -> host owns setup and Start; guest observes -> both enter only
after the host commit and the automatic readiness exchange
```

Create and join use the live bridge; direct player invitations and incoming
invitations remain preview flows. All use the hub's shared full-width invite
card. The small Create and Join cards are hidden
while a flow is active, as are the player-list Invite buttons. An incoming
invitation received during another flow is queued and shown when that flow
ends. Accepting a preview peer invitation reuses `GameSetupScreen`; reaching
the ready state is the end of that UI preview and does not start a chess game.

## Screen and app event boundary

`MultiplayerHubScreen` emits intent signals:

| Signal | Meaning |
| --- | --- |
| `create_requested(code)` | Show the generated code and wait for a peer. |
| `create_cancelled` | Stop waiting for a peer. |
| `join_requested(code)` | Attempt to join with the entered code. |
| `join_cancelled(code)` | Cancel the pending code attempt. |
| `player_invite_requested(player_name)` | Invite the selected listed player. |
| `player_invite_cancelled` | Cancel the outgoing player invitation. |
| `incoming_invite_responded(player_name, accepted)` | Send the user's accept or decline response. |
| `game_setup_requested(opponent_name, setup_kind)` | Open shared peer Game Setup after acceptance/connection. |

The app routes results back to the hub through the live bridge for transport
and session events, and through `receive_incoming_invite`,
`player_invite_accepted`, and `player_invite_declined` for preview flows. Game
Setup exposes `configure_peer` and the live bridge setup contract for
peer-specific presentation and host-owned setup snapshots. Preserve these screen-facing
responsibilities when replacing the remaining mock event source.

## Mock scenarios

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
index. A row means that this installation successfully connected to that peer;
it does not claim that the peer is online now. Rust owns the index and its
newest-first ordering, while Godot renders the populated, empty, or unavailable
state.
