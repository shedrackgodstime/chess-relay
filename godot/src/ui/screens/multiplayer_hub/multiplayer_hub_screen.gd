class_name MultiplayerHubScreen
extends Control

const FLOW_ACTION_SIZE := Vector2(144.0, 48.0)

signal back_requested
signal create_requested
signal create_cancelled
signal join_requested(code: String)
signal join_cancelled(code: String)
signal player_invite_requested(ticket: String)
signal player_invite_cancelled
signal incoming_invite_response(invite_id: int, accepted: bool)
signal game_setup_requested(opponent_name: String, setup_kind: String)
signal profile_name_changed(display_name: String)

## The list row, loaded here rather than referred to by path at runtime so that a
## scene which has gone missing is a load error at startup instead of a null in the
## middle of filling the list.
const PLAYER_ROW_SCENE: PackedScene = preload(
	"res://src/ui/components/player_row/player_row.tscn")

const CODE_ALPHABET := "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
const CODE_LENGTH := 8

@onready var _invite_grid: GridContainer = %InviteGrid
## The card the running flow fills. A component rather than a panel built here,
## because five flows in this screen want the same card and none of them want a
## different kind of one.
@onready var _flow: InviteFlowCard = %InviteFlowCard
@onready var _player_rows: VBoxContainer = %PlayerRows
@onready var _empty_players_label: Label = %EmptyPlayersLabel
@onready var _profile_status: Label = %ProfileStatus
@onready var _profile_name: Label = %ProfileName
@onready var _create_invite_button: Button = %CreateInviteButton
@onready var _join_game_button: Button = %JoinGameButton
@onready var _discovery_settings_button: Button = %DiscoverySettingsButton
@onready var _back_button: Button = %BackButton
var _create_code_label: Label
var _create_status: Label
var _copy_button: Button
var _join_field: LineEdit
var _join_echo: Label
var _join_status: Label
var _join_button: Button
var _join_retry_button: Button
var _join_cancel_button: Button
var _current_join_code := ""
var _create_waiting := false
var _join_is_connecting := false
var _profile_field: LineEdit = null
## Kept as rows rather than as the rows' Invite buttons, so turning the list off
## asks each row to do it and the row stays the thing that knows how.
var _player_rows_added: Array[PlayerRow] = []
var _active_invite_flow := ""


func _ready() -> void:
	_back_button.pressed.connect(func() -> void: back_requested.emit())
	_create_invite_button.pressed.connect(_on_create_invite)
	_join_game_button.pressed.connect(_begin_join_flow)
	_profile_status.text = "Recent peers"
	_profile_status.tooltip_text = "Recent peers are saved locally; presence is checked when an invite is sent."
	_profile_status.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65, 1.0))
	_discovery_settings_button.disabled = true
	_show_empty_players()
	get_viewport().size_changed.connect(_update_responsive_layout)
	_update_responsive_layout()


## The list is intentionally empty until an authoritative discovery/recent-data
## source is wired through the application contract. Invented player rows are
## worse than an explicit empty state because they imply real availability.
func _show_empty_players() -> void:
	_player_rows.show()
	_empty_players_label.text = "No recent players yet."
	_empty_players_label.show()


## Loads only Rust-owned observations. A peer row is not an online presence
## claim; it means this installation previously connected to that peer.
func configure_recent_players(bridge: ChessCoreBridge, identity_path: String) -> void:
	if bridge.recent_players_status(identity_path) != "ready":
		_show_recent_players_unavailable()
		return
	var records := bridge.recent_peer_records(identity_path)
	_clear_player_rows()
	if records.is_empty():
		_show_empty_players()
		return
	_empty_players_label.hide()
	_player_rows.show()
	for record: Dictionary in records:
		var peer := str(record.get("peer", ""))
		var ticket := str(record.get("ticket", ""))
		var presence := str(record.get("presence", "unknown"))
		var row := PLAYER_ROW_SCENE.instantiate() as PlayerRow
		_player_rows.add_child(row)
		row.configure("Peer %s" % peer, presence, true, ticket)
		row.invite_pressed.connect(_on_player_invite.bind(row))
		row.set_invite_enabled(not ticket.is_empty())
		_player_rows_added.append(row)


## Re-reads the same Rust-owned index after a successful connection fact.
func refresh_recent_players(bridge: ChessCoreBridge, identity_path: String) -> void:
	configure_recent_players(bridge, identity_path)


## Shows the authoritative local display name (Rust-owned profile or
## deterministic fallback) and builds the editor once. Saves route out
## through `profile_name_changed`; the backend echoes truth back here,
## so this screen never invents a name.
func configure_profile(display_name: String) -> void:
	_profile_name.text = display_name
	if _profile_field != null:
		if not _profile_field.has_focus():
			_profile_field.text = display_name
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_profile_field = LineEdit.new()
	_profile_field.custom_minimum_size = Vector2(180, 40)
	_profile_field.max_length = 24
	_profile_field.placeholder_text = "Display name"
	_profile_field.text = display_name
	_profile_field.text_submitted.connect(_submit_profile_name)
	row.add_child(_profile_field)
	var save := Button.new()
	save.text = "Save"
	save.theme_type_variation = &"QuietButton"
	save.pressed.connect(_submit_profile_name)
	row.add_child(save)
	_profile_name.get_parent().add_child(row)


func _submit_profile_name(_typed: String = "") -> void:
	if _profile_field == null:
		return
	profile_name_changed.emit(_profile_field.text.strip_edges())


func _show_recent_players_unavailable() -> void:
	_clear_player_rows()
	_player_rows.show()
	_empty_players_label.text = "Recent players unavailable."
	_empty_players_label.show()


func _clear_player_rows() -> void:
	for row in _player_rows_added:
		if is_instance_valid(row):
			row.queue_free()
	_player_rows_added.clear()


func _on_player_invite(row: PlayerRow) -> void:
	if row.ticket.is_empty() or _active_invite_flow != "":
		return
	_active_invite_flow = "player-outgoing"
	_invite_grid.hide()
	_flow.show_flow("Invite player", "Sending an invitation to %s..." % row.display_name)
	_flow.add_status("Waiting for response...")
	_flow_cancel_button(_cancel_player_invite)
	_set_player_invites_enabled(false)
	player_invite_requested.emit(row.ticket)


func player_invite_failed(reason: String = "") -> void:
	if _active_invite_flow != "player-outgoing":
		return
	_flow.show_flow("Invite failed", reason if not reason.is_empty() else "The peer could not be reached.")
	_flow_cancel_button(_reset_invite_flow)


func show_incoming_invite(invite_id: int, peer: String) -> void:
	_active_invite_flow = "player-incoming"
	_invite_grid.hide()
	_set_player_invites_enabled(false)
	_flow.show_flow("Game invitation", "Peer %s wants to play." % peer)
	var actions := _flow.add_centered_row()
	var accept := Button.new()
	accept.text = "Accept"
	accept.custom_minimum_size = FLOW_ACTION_SIZE
	actions.add_child(accept)
	accept.pressed.connect(func() -> void:
		_flow.show_flow("Game invitation", "Joining the game...")
		incoming_invite_response.emit(invite_id, true))
	var decline := Button.new()
	decline.text = "Decline"
	decline.custom_minimum_size = FLOW_ACTION_SIZE
	decline.theme_type_variation = &"QuietButton"
	actions.add_child(decline)
	decline.pressed.connect(func() -> void:
		incoming_invite_response.emit(invite_id, false)
		_reset_invite_flow())


func invite_result_received(accepted: bool, peer: String) -> void:
	if _active_invite_flow != "player-outgoing":
		return
	if accepted:
		_flow.show_flow("Invite accepted", "Peer %s is joining..." % peer)
	else:
		_flow.show_flow("Invite declined", "Peer %s declined the invitation." % peer)
		_flow_cancel_button(_reset_invite_flow)


func _on_create_invite() -> void:
	_active_invite_flow = "create"
	_create_waiting = true
	_invite_grid.hide()
	_flow.show()
	_set_player_invites_enabled(false)
	_flow.show_flow("", "")
	_create_status = _flow.add_status("Starting host...")
	_flow_cancel_button(_cancel_create_wait)
	create_requested.emit()


## Backend calls this with the generated short code once hosting is up.
func show_host_code(code: String) -> void:
	if not _create_waiting or _active_invite_flow != "create":
		return
	_flow.show_flow("", "")
	_flow.add_status("YOUR GAME CODE", &"Caption")
	_create_code_label = _flow.add_code(_format_invite_code(code))
	_copy_button = _flow.add_action("Copy code")
	_copy_button.pressed.connect(_on_copy_code)
	_create_status = _flow.add_status("Waiting for opponent...")
	_flow_cancel_button(_cancel_create_wait)


## Backend calls this when hosting failed outright.
func host_failed(reason: String = "") -> void:
	if not _create_waiting or _active_invite_flow != "create":
		return
	_create_waiting = false
	_flow.show_flow("", "")
	if reason.is_empty():
		reason = "Could not start hosting."
	_flow.add_status(reason)
	_flow_cancel_button(_reset_invite_flow)


## A network failure routes by flow, carrying the core's reason:
## a joining attempt fails, a hosting attempt reports, anything else
## is already gone.
func notify_network_error(reason: String = "") -> void:
	if _active_invite_flow == "join-connecting":
		join_failed(reason)
	elif _create_waiting and _active_invite_flow == "create":
		host_failed(reason)
	elif _active_invite_flow == "player-outgoing":
		player_invite_failed(reason)
	elif _active_invite_flow == "player-incoming":
		_flow.show_flow(
			"Invitation ended",
			reason if not reason.is_empty() else "The other player disconnected.")
		_flow_cancel_button(_reset_invite_flow)


## Backend calls this when the link is up but the session handshake is
## still running. The flow stays put: advancing to setup happens in
## `opponent_connected`, which now means the session is ready, not
## just the transport. (Advancing on link-up sent the host to setup
## while the guest was still handshaking — and the guest's failure
## then looked like a mystery instead of a failed handshake.)
func peer_linked(opponent_name: String = "Opponent") -> void:
	if _active_invite_flow == "create" and _create_waiting and _create_status != null:
		_create_status.text = "Opponent connected · configure the game..."
		game_setup_requested.emit(opponent_name, "create")
	elif _active_invite_flow == "join-connecting" and _join_status != null:
		_join_status.text = "Connected · waiting for host..."
		game_setup_requested.emit(opponent_name, "join")
	elif _active_invite_flow == "player-outgoing":
		_flow.show_flow("Peer connected", "Configure the game with %s." % opponent_name)
		game_setup_requested.emit(opponent_name, "invite-host")
	elif _active_invite_flow == "player-incoming":
		game_setup_requested.emit(opponent_name, "invite-guest")


## Backend calls this when the session is ready (game started), not
## when the transport merely linked. Only this advances out of the hub.
## Both flows remain supported for the compatibility path: the host from its
## create card and the guest from its join card.
func opponent_connected(opponent_name: String = "Opponent") -> void:
	if _active_invite_flow == "create" and _create_waiting:
		_create_status.text = "Opponent connected."
		_copy_button.hide()
		_create_waiting = false
		game_setup_requested.emit(opponent_name, "create")
		return
	if _active_invite_flow == "join-connecting" and _join_is_connecting:
		_join_is_connecting = false
		game_setup_requested.emit(opponent_name, "join")
		return


## Backend calls this if the opponent leaves before setup begins.
## No caller yet: a dropped pre-setup peer currently ends the flow
## through `host_failed`, because nothing re-accepts after the driver
## exits. Kept for the re-accept flow, which will return the card to
## waiting instead of ending it.
func opponent_left() -> void:
	if not _create_waiting or _active_invite_flow != "create":
		return
	_create_status.text = "Waiting for opponent..."
	_copy_button.show()


func _on_copy_code() -> void:
	DisplayServer.clipboard_set(_create_code_label.text)
	_copy_button.text = "Copied"
	_create_status.text = "Waiting for opponent..."
	get_tree().create_timer(1.6).timeout.connect(func() -> void:
		if is_instance_valid(_copy_button):
			_copy_button.text = "Copy code"
	)


func _cancel_create_wait() -> void:
	_reset_invite_flow()
	create_cancelled.emit()


func _begin_join_flow() -> void:
	_active_invite_flow = "join-entry"
	_current_join_code = ""
	_join_is_connecting = false
	_invite_grid.hide()
	_flow.show()
	_set_player_invites_enabled(false)
	_flow.show_flow("Join a game", "Enter the eight-character code someone shared with you.")
	_join_field = _flow.add_content(_code_field()) as LineEdit
	_join_field.text_changed.connect(_on_join_code_changed)
	_join_echo = _flow.add_status("", &"Caption")
	_join_echo.hide()
	_join_status = _flow.add_status("")
	_join_status.hide()
	_join_button = _flow.add_action("Join game")
	_join_button.disabled = true
	_join_button.pressed.connect(_on_join_pressed)
	_join_retry_button = _flow.add_action("Retry")
	_join_retry_button.hide()
	_join_retry_button.pressed.connect(_retry_join)
	_join_cancel_button = _flow.add_action("Cancel", &"QuietButton")
	_join_cancel_button.pressed.connect(_cancel_join)
	call_deferred("_focus_join_field")


func _focus_join_field() -> void:
	if is_instance_valid(_join_field) and _join_field.is_inside_tree():
		_join_field.grab_focus()


func _on_join_code_changed(value: String) -> void:
	_current_join_code = _normalize_join_target(value)
	var readable := _format_invite_code(_current_join_code)
	_join_echo.text = readable
	_join_echo.visible = not readable.is_empty()
	_join_button.disabled = not _is_valid_join_target(_current_join_code)


func _on_join_pressed() -> void:
	if not _is_valid_join_target(_current_join_code):
		return
	_join_field.hide()
	_join_button.hide()
	_join_echo.show()
	_join_status.text = "Connecting to %s..." % _format_invite_code(_current_join_code)
	_join_status.show()
	_join_retry_button.hide()
	_join_cancel_button.show()
	_join_is_connecting = true
	_active_invite_flow = "join-connecting"
	join_requested.emit(_current_join_code)


## Backend calls this when the entered code cannot be resolved or reached.
## `reason` carries the core's words; without it every failure reads
## the same and the real cause (bad ticket, lost code, dead relay) is
## undebuggable on device.
func join_failed(reason: String = "") -> void:
	if not _join_is_connecting or _active_invite_flow != "join-connecting":
		return
	_join_is_connecting = false
	_active_invite_flow = "join-failed"
	if reason.is_empty():
		reason = "Check the game code and try again."
	_join_status.text = reason
	_join_echo.text = "Couldn't connect."
	_join_retry_button.show()
	_join_cancel_button.show()


func _retry_join() -> void:
	_active_invite_flow = "join-entry"
	_join_status.hide()
	_join_echo.text = _format_invite_code(_current_join_code)
	_join_field.show()
	_join_button.show()
	_join_button.disabled = not _is_valid_join_target(_current_join_code)
	_join_retry_button.hide()
	_join_cancel_button.show()


func _cancel_join() -> void:
	var attempted_code := _current_join_code
	var cancel_pending_attempt := _join_is_connecting
	_join_is_connecting = false
	_reset_invite_flow()
	if cancel_pending_attempt:
		join_cancelled.emit(attempted_code)


func _cancel_player_invite() -> void:
	_reset_invite_flow()
	player_invite_cancelled.emit()


func _reset_invite_flow() -> void:
	_active_invite_flow = ""
	_create_waiting = false
	_join_is_connecting = false
	_flow.hide()
	_invite_grid.show()
	_clear_invite_flow()
	_set_player_invites_enabled(true)


## The card, emptied, without changing which flow is active.
func _clear_invite_flow() -> void:
	_flow.show_flow("", "")


func _set_player_invites_enabled(enabled: bool) -> void:
	for row in _player_rows_added:
		if is_instance_valid(row):
			row.set_invite_enabled(enabled)


## A Cancel in the card's own action row. Put there rather than in the body because it
## is an action on the flow, not a line of content.
func _flow_cancel_button(action: Callable) -> Button:
	var button := _flow.add_action("Cancel", &"QuietButton")
	button.pressed.connect(action)
	return button


## Where a code is typed.
##
## Its own method because the join flow is the only thing that needs one, and a
## control that exists only for one caller is not yet a component. When a second caller
## appears it should become a scene of its own, like PlayerRow did.


## What the guest typed: a short code (uppercased, separators dropped).
func _normalize_join_target(value: String) -> String:
	var result := ""
	for index in value.length():
		var character := value[index]
		if character == "-" or character == " " or character == "\t":
			continue
		result += character.to_upper()
	return result


func _format_invite_code(value: String) -> String:
	if value.length() <= 3:
		return value
	return "%s-%s" % [value.substr(0, 3), value.substr(3)]


func _is_valid_join_target(value: String) -> bool:
	return _is_valid_invite_code(value)


func _is_valid_invite_code(value: String) -> bool:
	if value.length() != CODE_LENGTH:
		return false
	for index in value.length():
		if not CODE_ALPHABET.contains(value[index]):
			return false
	return true


func _update_responsive_layout(width: float = -1.0) -> void:
	if _invite_grid != null and is_instance_valid(_invite_grid):
		var screen_width := get_viewport_rect().size.x if width < 0.0 else width
		_invite_grid.columns = 1 if screen_width < 900.0 else 2


func _code_field() -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = "ABC-23456"
	field.max_length = CODE_LENGTH + 1
	field.custom_minimum_size.y = 48
	return field
