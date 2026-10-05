class_name GameSetupScreen
extends Control

signal play_requested

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

var _peer_setup := false
var _peer_name := "Opponent"
var _peer_kind := "peer"
var _local_ready := false
var _opponent_is_ready := false


func _ready() -> void:
	_side_choice.selection_changed.connect(_on_side_changed)
	_time_choice.selection_changed.connect(_on_time_changed)
	_variant_choice.selection_changed.connect(_on_settings_changed)
	_difficulty_choice.selection_changed.connect(_on_settings_changed)
	_custom_minutes.value_changed.connect(_on_custom_time_changed)
	_custom_increment.value_changed.connect(_on_custom_time_changed)
	_play_button.pressed.connect(_on_play_pressed)
	_update_screen_columns()
	call_deferred("_update_screen_columns")
	_update_side_cards()
	_update_custom_time_visibility()
	_update_summary()
	if _peer_setup:
		_apply_peer_setup()


## Configures this shared screen after a peer has joined or accepted an invite.
func configure_peer(opponent_name: String, setup_kind: String) -> void:
	_peer_setup = true
	_peer_name = opponent_name
	_peer_kind = setup_kind
	if is_node_ready():
		_apply_peer_setup()


func _apply_peer_setup() -> void:
	_difficulty_choice.hide()
	_play_button.text = "Ready   ✓"
	_play_button.tooltip_text = "Mark yourself ready for this match"
	_ready_label.text = "Choose your settings, then mark yourself ready"
	var detail := "Connected player"
	if _peer_kind == "create" or _peer_kind == "join":
		detail = "Connected via invite code"
	_opponent_card.configure(_peer_name, "PLAYER", detail)
	_update_summary()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_update_screen_columns()


func _update_screen_columns() -> void:
	var screen_width := size.x
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
	if _peer_setup:
		_local_ready = true
		_play_button.disabled = true
		_ready_label.text = (
			"Both players ready · UI preview complete"
			if _opponent_is_ready else "You’re ready · waiting for opponent"
		)
	play_requested.emit()


## Mock or backend response for the other player's ready state.
func opponent_ready() -> void:
	if not _peer_setup:
		return
	_opponent_is_ready = true
	if _local_ready:
		_ready_label.text = "Both players ready · UI preview complete"
	else:
		_ready_label.text = "Opponent is ready · choose settings and mark yourself ready"


func _update_side_cards() -> void:
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
