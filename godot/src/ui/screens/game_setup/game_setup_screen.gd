class_name GameSetupScreen
extends Control

signal play_requested
signal settings_requested
signal leave_requested(is_peer_setup: bool)

@onready var _players_grid: GridContainer = %Players
@onready var _settings_grid: GridContainer = %Settings
@onready var _side_choice: ChoiceGroup = %SideChoice
@onready var _time_choice: ChoiceGroup = %TimeChoice
@onready var _variant_choice: ChoiceGroup = %VariantChoice
@onready var _difficulty_choice: ChoiceGroup = %DifficultyChoice
@onready var _custom_time_controls: HBoxContainer = %CustomTimeControls
@onready var _custom_minutes: SpinBox = %CustomMinutes
@onready var _custom_increment: SpinBox = %CustomIncrement
@onready var _player_card: ParticipantCard = %PlayerCard
@onready var _opponent_card: ParticipantCard = %OpponentCard
@onready var _settings_summary: Label = %SettingsSummary
@onready var _ready_label: Label = %ReadyLabel
@onready var _play_button: Button = %PlayButton
@onready var _header: GameHeader = $GameHeader

var _peer_setup := false
var _peer_name := "Opponent"
var _peer_kind := "peer"
var _local_ready := false
var _opponent_is_ready := false
var _header_menu_layer: Control
## The live networked session, when this setup fronts one. Set for
## ticket/host flows only; mock invite flows have no session and keep
## the old local behavior.
var _net_bridge: ChessCoreBridge = null


func _ready() -> void:
	_side_choice.selection_changed.connect(_on_side_changed)
	_time_choice.selection_changed.connect(_on_time_changed)
	_variant_choice.selection_changed.connect(_on_settings_changed)
	_difficulty_choice.selection_changed.connect(_on_settings_changed)
	_custom_minutes.value_changed.connect(_on_custom_time_changed)
	_custom_increment.value_changed.connect(_on_custom_time_changed)
	_play_button.pressed.connect(_on_play_pressed)
	_header.menu_requested.connect(_toggle_header_menu)
	_configure_choices()
	_update_header_visibility()
	_update_screen_columns()
	call_deferred("_update_screen_columns")
	_update_side_cards()
	_update_custom_time_visibility()
	_update_summary()
	if _peer_setup:
		_apply_peer_setup()


## Choice content owned here in code (see ChoiceGroup.configure): the
## option arrays live outside scene overrides so export conversion
## cannot drop them.
func _configure_choices() -> void:
	_side_choice.configure("Choose Color", ["White", "Black", "Random"], 3, 0)
	_time_choice.configure("Time Control", ["1 | 0", "3 | 2", "5 | 3", "10 | 0", "15 | 10", "Custom"], 3, 2)
	_variant_choice.configure("Variant", ["Standard", "Chess960"], 2, 0)
	_difficulty_choice.configure("Difficulty", ["Easy", "Medium", "Hard"], 3, 1)


## Configures this shared screen after a peer has joined or accepted an invite.
func configure_peer(opponent_name: String, setup_kind: String) -> void:
	_peer_setup = true
	_peer_name = opponent_name
	_peer_kind = setup_kind
	if is_node_ready():
		_update_header_visibility()
		_apply_peer_setup()


func selected_ai_side() -> String:
	return _side_choice.get_selected_choice()


func selected_ai_difficulty() -> String:
	return _difficulty_choice.get_selected_choice()


## Attaches the live networked session. The lobby then shows the
## session instead of offering choices: sides were fixed when the
## handshake completed, and color/time/variant/difficulty pickers
## change nothing on the wire, so they hide instead of lying.
func configure_net_bridge(bridge: ChessCoreBridge) -> void:
	_net_bridge = bridge
	if is_node_ready() and _peer_setup:
		_apply_peer_setup()


func _apply_peer_setup() -> void:
	_difficulty_choice.hide()
	_play_button.text = "Ready   ✓"
	_play_button.tooltip_text = "Mark yourself ready for this match"
	_ready_label.text = "Choose your settings, then mark yourself ready"
	var detail := "Connected player"
	if _peer_kind == "create" or _peer_kind == "join":
		# Tickets today; short codes arrive with rendezvous publishing.
		detail = "Connected via ticket"
	_opponent_card.configure(_peer_name, "PLAYER", detail)
	if _net_bridge != null:
		_apply_net_lobby()
	_update_summary()


## Read-only lobby for a live session: real sides on the cards,
## theater controls hidden, one honest button. Entering only opens
## the board of the game that started underneath; it never starts
## anything, so an early host sees the live game, not a second one.
func _apply_net_lobby() -> void:
	_side_choice.hide()
	_time_choice.hide()
	_variant_choice.hide()
	_custom_time_controls.hide()
	var mine := _net_bridge.my_side()
	var mine_shown := mine.capitalize() if not mine.is_empty() else "…"
	var theirs := "Black" if mine == "white" else "White" if mine == "black" else "…"
	_player_card.set_side(mine_shown)
	_opponent_card.set_side(theirs)
	_play_button.text = "Enter game"
	_play_button.tooltip_text = "Open the live game"
	_play_button.disabled = false
	_ready_label.text = "Connected · game is live · enter when ready"
	_settings_summary.text = "You play %s · Standard · game is live" % mine_shown


func _update_header_visibility() -> void:
	_header.set_visibility(_peer_setup, _peer_setup, true, true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_update_screen_columns()


func _update_screen_columns(width: float = -1.0) -> void:
	var screen_width := size.x if width < 0.0 else width
	_players_grid.columns = 2 if screen_width >= 760.0 else 1
	if screen_width >= 1080.0:
		_settings_grid.columns = 3
	elif screen_width >= 680.0:
		_settings_grid.columns = 2
	else:
		_settings_grid.columns = 1


func _on_side_changed(_choice: String, _index: int) -> void:
	_update_side_cards()
	_update_summary()


func _on_time_changed(_choice: String, _index: int) -> void:
	_update_custom_time_visibility()
	_update_summary()


func _on_settings_changed(_choice: String, _index: int) -> void:
	_update_summary()


func _on_custom_time_changed(_value: float) -> void:
	_update_summary()


func _on_play_pressed() -> void:
	if _net_bridge != null:
		# Live session underneath; entering only opens its board.
		play_requested.emit()
		return
	if _peer_setup:
		_local_ready = true
		_play_button.disabled = true
		_ready_label.text = (
			"Both players ready · UI preview complete"
			if _opponent_is_ready else "You’re ready · waiting for opponent"
		)
	play_requested.emit()


## Mock or backend response for the other player's ready state.
## Ignored on a live session: both sides are past ready there, and the
## lobby shows the session instead of a ready dance.
func opponent_ready() -> void:
	if not _peer_setup or _net_bridge != null:
		return
	_opponent_is_ready = true
	if _local_ready:
		_ready_label.text = "Both players ready · UI preview complete"
	else:
		_ready_label.text = "Opponent is ready · choose settings and mark yourself ready"


## Backend reports the link died after setup opened (the host's final
## send can fail after its own game-started fired). The session is
## gone; say so where the user is looking instead of stranding them on
## a ready screen for a dead game.
func notify_net_issue(message: String) -> void:
	if not _peer_setup:
		return
	_ready_label.text = message
	_play_button.disabled = true


func _toggle_header_menu() -> void:
	if _header_menu_layer != null:
		_close_header_menu()
		return
	_open_header_menu()


func _open_header_menu() -> void:
	_header_menu_layer = Control.new()
	_header_menu_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_header_menu_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_header_menu_layer)

	# A Panel rather than a ColorRect so the wash is a theme item. A ColorRect takes
	# its colour from the node and nowhere else, which would put one more value in this
	# script that a re-theme could not reach.
	var backdrop := Panel.new()
	backdrop.theme_type_variation = &"ModalBackdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_header_menu_backdrop_input)
	_header_menu_layer.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_menu_layer.add_child(center)

	var menu_card := PanelContainer.new()
	menu_card.custom_minimum_size = Vector2(300.0, 0.0)
	menu_card.theme_type_variation = &"Card"
	menu_card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(menu_card)
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	menu_card.add_child(actions)
	actions.add_child(_header_menu_item("Settings", _on_header_settings_pressed))
	var leave_label := "Leave game" if _peer_setup else "Return to Home"
	actions.add_child(_header_menu_item(leave_label, _on_leave_setup_pressed))


func _header_menu_item(label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.accessibility_name = label
	button.custom_minimum_size.y = 48.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.theme_type_variation = &"QuietButton"
	button.pressed.connect(action)
	return button


func _on_header_menu_backdrop_input(event: InputEvent) -> void:
	if not ChessBoardView.is_selecting_press(event):
		return
	_close_header_menu()
	get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and _header_menu_layer != null:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE:
			_close_header_menu()
			get_viewport().set_input_as_handled()


func _close_header_menu() -> void:
	if _header_menu_layer == null:
		return
	_header_menu_layer.queue_free()
	_header_menu_layer = null


func _on_header_settings_pressed() -> void:
	_close_header_menu()
	settings_requested.emit()


func _on_leave_setup_pressed() -> void:
	_close_header_menu()
	if not _peer_setup:
		leave_requested.emit(false)
		return
	var confirmation := ConfirmationDialog.new()
	confirmation.theme_type_variation = &"ModalDialog"
	confirmation.title = "Leave game?"
	confirmation.dialog_text = "You’ll disconnect from %s and return to Multiplayer." % _peer_name
	confirmation.dialog_autowrap = true
	confirmation.ok_button_text = "Leave game"
	confirmation.cancel_button_text = "Stay"
	confirmation.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirmation.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var leave_button := confirmation.get_ok_button()
	leave_button.accessibility_name = "Leave the game"
	leave_button.theme_type_variation = &"ModalDangerButton"
	var stay_button := confirmation.get_cancel_button()
	stay_button.accessibility_name = "Stay in the game"
	stay_button.theme_type_variation = &"ModalSecondaryButton"
	confirmation.confirmed.connect(func() -> void:
		leave_requested.emit(true)
		confirmation.queue_free()
	)
	confirmation.canceled.connect(confirmation.queue_free)
	add_child(confirmation)
	confirmation.popup_centered(Vector2i(460, 220))


func _update_side_cards() -> void:
	if _net_bridge != null:
		return
	match _side_choice.get_selected_choice():
		"Black":
			_player_card.set_side("Black")
			_opponent_card.set_side("White")
		"Random":
			_player_card.set_side("Random")
			_opponent_card.set_side("Auto assigned")
		_:
			_player_card.set_side("White")
			_opponent_card.set_side("Black")


func _update_custom_time_visibility() -> void:
	_custom_time_controls.visible = _time_choice.get_selected_choice() == "Custom"


func _update_summary() -> void:
	if _net_bridge != null:
		return
	var time_summary := _format_time_summary()
	var variant := _variant_choice.get_selected_choice()
	if _peer_setup:
		_settings_summary.text = "%s  ·  %s" % [time_summary, variant]
		return
	var difficulty := _difficulty_choice.get_selected_choice()
	_settings_summary.text = "%s  ·  %s  ·  %s" % [time_summary, variant, difficulty]


func _format_time_summary() -> String:
	if _time_choice.get_selected_choice() == "Custom":
		return "%d min + %d sec" % [
			int(_custom_minutes.value), int(_custom_increment.value)
		]
	var parts := _time_choice.get_selected_choice().split(" | ")
	if parts.size() != 2:
		return _time_choice.get_selected_choice()
	return "%s min + %s sec" % [parts[0], parts[1]]
