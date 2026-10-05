class_name MultiplayerHubScreen
extends Control

const FLOW_ACTION_SIZE := Vector2(144.0, 48.0)

signal back_requested
signal create_requested(code: String)
signal create_cancelled
signal join_requested(code: String)
signal join_cancelled(code: String)
signal player_invite_requested(player_name: String)
signal player_invite_cancelled
signal incoming_invite_responded(player_name: String, accepted: bool)
signal game_setup_requested(opponent_name: String, setup_kind: String)

const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 6
const TEXT := Color(1.0, 0.9, 0.72, 1.0)

@onready var _invite_grid: GridContainer = %InviteGrid
@onready var _invite_flow_card: PanelContainer = %InviteFlowCard
@onready var _invite_flow_content: VBoxContainer = %InviteFlowContent
@onready var _player_list: ScrollContainer = %PlayerList
@onready var _player_rows: VBoxContainer = %PlayerRows
@onready var _profile_status: Label = %ProfileStatus
@onready var _create_invite_button: Button = %CreateInviteButton
@onready var _join_game_button: Button = %JoinGameButton
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
var _player_invite_buttons: Array[Button] = []
var _active_invite_flow := ""
var _current_player_invite := ""
var _queued_incoming_invite := ""
var _discoverable_nearby := true
var _discoverable_online := false


func _ready() -> void:
	_back_button.pressed.connect(func(): back_requested.emit())
	_create_invite_button.pressed.connect(_on_create_invite)
	_join_game_button.pressed.connect(_begin_join_flow)
	%DiscoverySettingsButton.pressed.connect(_show_discovery_settings)
	_populate_mock_players()
	get_viewport().size_changed.connect(_update_responsive_layout)
	_update_responsive_layout()


func _populate_mock_players() -> void:
	_player_rows.add_child(_build_mock_player_row("Ayo", "Nearby", false))
	_player_rows.add_child(_build_mock_player_row("KnightOwl", "Online", false))
	_player_rows.add_child(_build_mock_player_row("Kemi", "Nearby", true))
	_player_rows.add_child(_build_mock_player_row("RookRunner", "Online", true))


func _build_mock_player_row(player_name: String, presence: String, is_recent: bool) -> PanelContainer:
	var row := PanelContainer.new()
	row.theme_type_variation = &"PlayerListRow"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size.y = 56
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	row.add_child(layout)
	var avatar := Label.new()
	avatar.text = player_name.substr(0, 1).to_upper()
	avatar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avatar.custom_minimum_size = Vector2(34, 34)
	avatar.theme_type_variation = &"PlayerRowAvatar"
	layout.add_child(avatar)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.alignment = BoxContainer.ALIGNMENT_CENTER
	identity.add_child(_label(player_name, "SetupParticipantName"))
	var details := HBoxContainer.new()
	details.add_theme_constant_override("separation", 10)
	details.add_child(_label("●  " + presence, "QuietLabel"))
	if is_recent:
		var recent := _label("Recent", "Caption")
		details.add_child(recent)
	identity.add_child(details)
	layout.add_child(identity)
	var invite := Button.new()
	invite.text = "Invite"
	invite.custom_minimum_size = Vector2(88, 44)
	invite.theme_type_variation = &"SetupOptionButton"
	invite.pressed.connect(_show_mock_invite.bind(player_name))
	layout.add_child(invite)
	_player_invite_buttons.append(invite)
	return row


func _show_mock_invite(player_name: String) -> void:
	_active_invite_flow = "player-invite"
	_current_player_invite = player_name
	_invite_grid.hide()
	_invite_flow_card.show()
	_set_player_invites_enabled(false)
	_clear_invite_flow()
	_invite_flow_content.add_child(_label("Invite %s" % player_name, "SetupParticipantName"))
	_invite_flow_content.add_child(_label("Invitation sent · waiting for response...", "SetupStatusText"))
	_invite_flow_content.add_child(_flow_cancel_button(_cancel_player_invite))
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
	_clear_invite_flow()
	_invite_flow_content.add_child(_label("Invite %s" % player_name, "SetupParticipantName"))
	_invite_flow_content.add_child(_label("Invitation declined.", "SetupStatusText"))
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	_invite_flow_content.add_child(actions)
	actions.add_child(_action_button("Invite again", _retry_player_invite))
	var done := Button.new()
	done.text = "Done"
	done.theme_type_variation = &"QuietButton"
	done.custom_minimum_size = FLOW_ACTION_SIZE
	done.pressed.connect(_cancel_player_invite)
	actions.add_child(done)


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
	_invite_flow_card.show()
	_set_player_invites_enabled(false)
	_clear_invite_flow()
	_invite_flow_content.add_child(_label("Game invitation", "SetupParticipantName"))
	_invite_flow_content.add_child(_label("%s invited you to play." % player_name, "QuietLabel"))
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	_invite_flow_content.add_child(actions)
	actions.add_child(_action_button("Accept", _accept_incoming_invite))
	var decline := Button.new()
	decline.text = "Decline"
	decline.custom_minimum_size = FLOW_ACTION_SIZE
	decline.theme_type_variation = &"QuietButton"
	decline.pressed.connect(_decline_incoming_invite)
	actions.add_child(decline)


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
	_clear_invite_flow()
	_invite_flow_content.add_child(_label("Invitation declined.", "SetupStatusText"))
	_invite_flow_content.add_child(_flow_cancel_button(_reset_invite_flow))


func _show_discovery_settings() -> void:
	var dialog := AcceptDialog.new()
	dialog.theme_type_variation = &"ModalDialog"
	dialog.title = "Discovery settings"
	dialog.dialog_text = "Choose where other players can discover you."
	dialog.dialog_autowrap = true
	dialog.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	var nearby := CheckButton.new()
	nearby.text = "Discoverable on this local network"
	nearby.button_pressed = _discoverable_nearby
	nearby.toggled.connect(func(enabled: bool):
		_discoverable_nearby = enabled
		_update_profile_status()
	)
	content.add_child(nearby)
	var online := CheckButton.new()
	online.text = "Discoverable by online players"
	online.button_pressed = _discoverable_online
	online.toggled.connect(func(enabled: bool):
		_discoverable_online = enabled
		_update_profile_status()
	)
	content.add_child(online)
	dialog.add_child(content)
	add_child(dialog)
	dialog.popup_centered(Vector2i(460, 240))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


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
	_invite_flow_card.show()
	_set_player_invites_enabled(false)
	_clear_invite_flow()
	_invite_flow_content.add_child(_label("YOUR GAME CODE", "Caption"))
	_create_code_label = _label(_generate_invite_code(), "CodeDisplay")
	_create_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_invite_flow_content.add_child(_create_code_label)
	var copy_row := HBoxContainer.new()
	copy_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_invite_flow_content.add_child(copy_row)
	_copy_button = _action_button("Copy code", _on_copy_code)
	_copy_button.custom_minimum_size = Vector2(170, 48)
	copy_row.add_child(_copy_button)
	_create_status = _label("Waiting for opponent...", "SetupStatusText")
	_create_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_invite_flow_content.add_child(_create_status)
	_invite_flow_content.add_child(_flow_cancel_button(_cancel_create_wait))
	create_requested.emit(_create_code_label.text)


## Backend calls this when the room reports that an opponent has joined.
func opponent_connected(opponent_name: String = "Opponent") -> void:
	if not _create_waiting or _active_invite_flow != "create":
		return
	_create_status.text = "Opponent connected."
	_copy_button.hide()
	_create_waiting = false
	game_setup_requested.emit(opponent_name, "create")


## Backend calls this if the opponent leaves before setup begins.
func opponent_left() -> void:
	if not _create_waiting or _active_invite_flow != "create":
		return
	_create_status.text = "Waiting for opponent..."
	_copy_button.show()


func _on_copy_code() -> void:
	DisplayServer.clipboard_set(_create_code_label.text)
	_copy_button.text = "Copied"
	_create_status.text = "Waiting for opponent..."
	get_tree().create_timer(1.6).timeout.connect(func():
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
	_invite_flow_card.show()
	_set_player_invites_enabled(false)
	_clear_invite_flow()
	_invite_flow_content.add_child(_label("Join with a code", "SetupParticipantName"))
	_invite_flow_content.add_child(_label("Enter the code someone shared with you.", "QuietLabel"))
	_join_field = LineEdit.new()
	_join_field.placeholder_text = "ABC-123"
	_join_field.max_length = 9
	_join_field.custom_minimum_size.y = 48
	_join_field.text_changed.connect(_on_join_code_changed)
	_invite_flow_content.add_child(_join_field)
	_join_echo = _label("", "Caption")
	_join_echo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join_echo.hide()
	_invite_flow_content.add_child(_join_echo)
	_join_status = _label("", "SetupStatusText")
	_join_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join_status.hide()
	_invite_flow_content.add_child(_join_status)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	_invite_flow_content.add_child(actions)
	_join_button = _action_button("Join game", _on_join_pressed)
	_join_button.disabled = true
	_join_button.custom_minimum_size = FLOW_ACTION_SIZE
	actions.add_child(_join_button)
	_join_retry_button = _action_button("Retry", _retry_join)
	_join_retry_button.custom_minimum_size = FLOW_ACTION_SIZE
	_join_retry_button.hide()
	actions.add_child(_join_retry_button)
	_join_cancel_button = Button.new()
	_join_cancel_button.text = "Cancel"
	_join_cancel_button.custom_minimum_size = FLOW_ACTION_SIZE
	_join_cancel_button.theme_type_variation = &"QuietButton"
	_join_cancel_button.pressed.connect(_cancel_join)
	actions.add_child(_join_cancel_button)
	call_deferred("_focus_join_field")


func _focus_join_field() -> void:
	if is_instance_valid(_join_field) and _join_field.is_inside_tree():
		_join_field.grab_focus()


func _on_join_code_changed(value: String) -> void:
	_current_join_code = _normalize_invite_code(value)
	var readable := _format_invite_code(_current_join_code)
	_join_echo.text = readable
	_join_echo.visible = not readable.is_empty()
	_join_button.disabled = not _is_valid_invite_code(_current_join_code)


func _on_join_pressed() -> void:
	if not _is_valid_invite_code(_current_join_code):
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


## Backend calls this when the entered code cannot be reached.
func join_failed() -> void:
	if not _join_is_connecting or _active_invite_flow != "join-connecting":
		return
	_join_is_connecting = false
	_active_invite_flow = "join-failed"
	_join_status.text = "Check the game code and try again."
	_join_echo.text = "Couldn't connect."
	_join_retry_button.show()
	_join_cancel_button.show()


## Backend calls this when the invite code has connected successfully.
func join_connected(opponent_name: String = "Opponent") -> void:
	if not _join_is_connecting or _active_invite_flow != "join-connecting":
		return
	_join_is_connecting = false
	game_setup_requested.emit(opponent_name, "join")


func _retry_join() -> void:
	_active_invite_flow = "join-entry"
	_join_status.hide()
	_join_echo.text = _format_invite_code(_current_join_code)
	_join_field.show()
	_join_button.show()
	_join_button.disabled = not _is_valid_invite_code(_current_join_code)
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
	_invite_flow_card.hide()
	_invite_grid.show()
	_clear_invite_flow()
	_set_player_invites_enabled(true)
	if not _queued_incoming_invite.is_empty():
		var queued_player := _queued_incoming_invite
		_queued_incoming_invite = ""
		_show_incoming_invite(queued_player)


func _clear_invite_flow() -> void:
	for child in _invite_flow_content.get_children():
		_invite_flow_content.remove_child(child)
		child.queue_free()


func _set_player_invites_enabled(enabled: bool) -> void:
	for button in _player_invite_buttons:
		if is_instance_valid(button):
			button.disabled = not enabled


func _flow_cancel_button(action: Callable) -> Button:
	var button := Button.new()
	button.text = "Cancel"
	button.custom_minimum_size = FLOW_ACTION_SIZE
	button.theme_type_variation = &"QuietButton"
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(action)
	return button


func _generate_invite_code() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var result := ""
	for index in CODE_LENGTH:
		if index == 3:
			result += "-"
		result += CODE_ALPHABET[rng.randi_range(0, CODE_ALPHABET.length() - 1)]
	return result


func _normalize_invite_code(value: String) -> String:
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


func _action_button(title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = FLOW_ACTION_SIZE
	button.theme_type_variation = &"SetupPrimaryButton"
	button.pressed.connect(action)
	return button


func _label(value: String, variation: StringName = &"") -> Label:
	var label := Label.new()
	label.text = value
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	if variation != &"":
		label.theme_type_variation = variation
	else:
		label.add_theme_color_override("font_color", TEXT)
	return label
