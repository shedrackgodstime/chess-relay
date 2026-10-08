# Multiplayer UI lifecycle

The multiplayer hub is a UI-only flow. `MultiplayerHubScreen` owns the
presentation of invite choices, code entry, player rows, and incoming or
outgoing invite status. `app_root.gd` owns screen changes. The current
`MockMultiplayerService` supplies delayed outcomes so these states can be
reviewed without a connection implementation.

Keep this separation when backend work begins: the backend should report
events and receive user intent through the app layer. It should not own screen
controls or require the hub to know how a connection is established.

## Current lifecycle

```text
Multiplayer hub
├── Create invite -> show code and wait -> peer connected -> Game Setup
├── Join by code -> connecting -> failed/retry or connected -> Game Setup
├── Invite listed player -> wait -> declined/retry or accepted -> Game Setup
└── Receive invite -> accept -> Game Setup or decline -> return to hub

Peer Game Setup -> local Ready -> wait for peer Ready -> both ready
```

Create, join, direct player invitations, and incoming invitations all use the
hub's shared full-width invite card. The small Create and Join cards are hidden
while a flow is active, as are the player-list Invite buttons. An incoming
invitation received during another flow is queued and shown when that flow
ends. Accepting any peer invitation reuses `GameSetupScreen`; reaching the
ready state is the end of this UI preview and does not start a chess game.

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

The app routes results back to the hub through `opponent_connected`,
`opponent_left`, `join_connected`, `join_failed`, `receive_incoming_invite`,
`player_invite_accepted`, and `player_invite_declined`. Game Setup exposes
`configure_peer` and `opponent_ready` for peer-specific presentation and
readiness updates. Preserve these screen-facing responsibilities when
replacing the mock event source.

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
- A peer setup receives the opponent's Ready response after the local player
  marks Ready.

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

The player rows are static UI fixtures today. Their names, presence labels,
and Recent markers are not an account or identity model. A later UI pass can
cover loading and empty-list presentation when those states are ready to
review; no connection behavior is specified here.
