class_name MultiplayerHubScreen
extends Control

const FLOW_ACTION_SIZE := Vector2(144.0, 48.0)

signal back_requested
signal create_requested
signal create_cancelled
signal join_requested(code: String)
signal join_cancelled(code: String)
signal player_invite_requested(player_name: String)
signal player_invite_cancelled
signal incoming_invite_responded(player_name: String, accepted: bool)
signal game_setup_requested(opponent_name: String, setup_kind: String)

## The list row, loaded here rather than referred to by path at runtime so that a
## scene which has gone missing is a load error at startup instead of a null in the
## middle of filling the list.
## The discovery dialog, built once and reused.
const DISCOVERY_DIALOG_SCENE: PackedScene = preload(
	"res://src/ui/components/discovery_dialog/discovery_dialog.tscn")

const PLAYER_ROW_SCENE: PackedScene = preload(
	"res://src/ui/components/player_row/player_row.tscn")

const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 6

@onready var _invite_grid: GridContainer = %InviteGrid
## The card the running flow fills. A component rather than a panel built here,
## because five flows in this screen want the same card and none of them want a
## different kind of one.
@onready var _flow: InviteFlowCard = %InviteFlowCard
@onready var _player_rows: VBoxContainer = %PlayerRows
@onready var _profile_status: Label = %ProfileStatus
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
## Kept as rows rather than as the rows' Invite buttons, so turning the list off
## asks each row to do it and the row stays the thing that knows how.
var _player_rows_added: Array[PlayerRow] = []
var _active_invite_flow := ""
var _current_player_invite := ""
var _queued_incoming_invite := ""
var _discoverable_nearby := true
var _discoverable_online := false
var _discovery_dialog: DiscoverySettingsDialog = null


func _ready() -> void:
	_back_button.pressed.connect(func() -> void: back_requested.emit())
	_create_invite_button.pressed.connect(_on_create_invite)
	_join_game_button.pressed.connect(_begin_join_flow)
	(_discovery_settings_button).pressed.connect(_show_discovery_settings)
	_build_discovery_dialog()
	_populate_mock_players()
	get_viewport().size_changed.connect(_update_responsive_layout)
	_update_responsive_layout()


func _populate_mock_players() -> void:
	_player_rows.add_child(_build_mock_player_row("Ayo", "Nearby", false))
	_player_rows.add_child(_build_mock_player_row("KnightOwl", "Online", false))
	_player_rows.add_child(_build_mock_player_row("Kemi", "Nearby", true))
	_player_rows.add_child(_build_mock_player_row("RookRunner", "Online", true))


## A person in the list. The row is a scene and this only says who it is.
##
## The row used to be built here, out of seven nodes, in a loop over mock names.
## That put a reusable piece of interface inside one screen's script, where it
## could not be seen or edited in the editor and could not be used anywhere else.
func _build_mock_player_row(player_name: String, presence: String, is_recent: bool) -> PlayerRow:
	var row := PLAYER_ROW_SCENE.instantiate() as PlayerRow
	row.invite_pressed.connect(_show_mock_invite.bind(player_name))
	row.configure(player_name, presence, is_recent)
	_player_rows_added.append(row)
	return row


func _show_mock_invite(player_name: String) -> void:
	_active_invite_flow = "player-invite"
	_current_player_invite = player_name
	_invite_grid.hide()
	_flow.show()
	_set_player_invites_enabled(false)
	_flow.show_flow("Invite %s" % player_name, "")
	_flow.add_status("Invitation sent · waiting for response...")
	_flow_cancel_button(_cancel_player_invite)
	player_invite_requested.emit(player_name)


## Mock or backend response: the invited player accepted.
func player_invite_accepted(player_name: String) -> void:
	if _active_invite_flow != "player-invite":
		return
	game_setup_requested.emit(player_name, "player")


## Mock or backend response: keep the flow inline and let the user retry or leave.
func player_invite_declined(player_name: String) -> void:
	if _active_invite_flow != "player-invite":
		return
	_flow.show_flow("Invite %s" % player_name, "")
	_flow.add_status("Invitation declined.")
	_flow.add_action("Invite again").pressed.connect(_retry_player_invite)
	_flow.add_action("Done", &"QuietButton").pressed.connect(_cancel_player_invite)


func _retry_player_invite() -> void:
	_show_mock_invite(_current_player_invite)


func _cancel_player_invite() -> void:
	_reset_invite_flow()
	player_invite_cancelled.emit()


## An incoming request uses the same inline card. Queue it if another flow is active.
func receive_incoming_invite(player_name: String) -> void:
	if not _active_invite_flow.is_empty():
		_queued_incoming_invite = player_name
		return
	_show_incoming_invite(player_name)


func _show_incoming_invite(player_name: String) -> void:
	_active_invite_flow = "incoming-invite"
	_current_player_invite = player_name
	_invite_grid.hide()
	_flow.show()
	_set_player_invites_enabled(false)
	_flow.show_flow("Game invitation", "%s invited you to play." % player_name)
	_flow.add_action("Accept").pressed.connect(_accept_incoming_invite)
	_flow.add_action("Decline", &"QuietButton").pressed.connect(_decline_incoming_invite)


func _accept_incoming_invite() -> void:
	if _active_invite_flow != "incoming-invite":
		return
	var player_name := _current_player_invite
	incoming_invite_responded.emit(player_name, true)
	game_setup_requested.emit(player_name, "incoming")


func _decline_incoming_invite() -> void:
	if _active_invite_flow != "incoming-invite":
		return
	var player_name := _current_player_invite
	incoming_invite_responded.emit(player_name, false)
	_flow.show_flow("", "")
	_flow.add_status("Invitation declined.")
	_flow_cancel_button(_reset_invite_flow)


## Opens the dialog, with the answers that are currently in force.
##
## One dialog for the life of the screen rather than one per opening. It used to be
## built here each time and freed on close, which meant the two answers had to be
## copied in each time and could drift from the profile line beside the button.
func _show_discovery_settings() -> void:
	_discovery_dialog.discoverable_nearby = _discoverable_nearby
	_discovery_dialog.discoverable_online = _discoverable_online
	_discovery_dialog.show_dialog()


## One dialog, made once.
func _build_discovery_dialog() -> void:
	_discovery_dialog = DISCOVERY_DIALOG_SCENE.instantiate() as DiscoverySettingsDialog
	add_child(_discovery_dialog)
	_discovery_dialog.discovery_changed.connect(_on_discovery_changed)


func _on_discovery_changed(nearby: bool, online: bool) -> void:
	_discoverable_nearby = nearby
	_discoverable_online = online
	_update_profile_status()


func _update_profile_status() -> void:
	if _discoverable_nearby and _discoverable_online:
		_profile_status.text = "Discoverable nearby and online"
	elif _discoverable_nearby:
		_profile_status.text = "Discoverable nearby"
	elif _discoverable_online:
		_profile_status.text = "Discoverable online"
	else:
		_profile_status.text = "Not discoverable"


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


## Backend calls this when the link is up but the session handshake is
## still running. The flow stays put: advancing to setup happens in
## `opponent_connected`, which now means the session is ready, not
## just the transport. (Advancing on link-up sent the host to setup
## while the guest was still handshaking — and the guest's failure
## then looked like a mystery instead of a failed handshake.)
func peer_linked() -> void:
	if _active_invite_flow == "create" and _create_waiting and _create_status != null:
		_create_status.text = "Opponent connected · starting game..."
	elif _active_invite_flow == "join-connecting" and _join_status != null:
		_join_status.text = "Connected · starting game..."


## Backend calls this when the session is ready (game started), not
## when the transport merely linked. Only this advances out of the hub.
## Both flows advance here: the host from its create card, the guest
## from its join card. (Gating this on the create flow alone stranded
## every guest on "starting game" with a live session underneath —
## found via the NET-TRACE handshake log, not guessed.)
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
	_flow.show_flow("Join a game", "Enter the six-character code someone shared with you.")
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


func _reset_invite_flow() -> void:
	_active_invite_flow = ""
	_create_waiting = false
	_join_is_connecting = false
	_current_player_invite = ""
	_flow.hide()
	_invite_grid.show()
	_clear_invite_flow()
	_set_player_invites_enabled(true)
	if not _queued_incoming_invite.is_empty():
		var queued_player := _queued_incoming_invite
		_queued_incoming_invite = ""
		_show_incoming_invite(queued_player)


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
	field.placeholder_text = "ABC-123"
	field.max_length = CODE_LENGTH + 1
	field.custom_minimum_size.y = 48
	return field
