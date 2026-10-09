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
var _remote_setup_received := false
## Every peer setup role the hub can produce. Comparisons go through the
## helpers below, never bare strings at each call site: a typo in a bare
## string silently changes which branch runs and nothing fails.
const SETUP_KINDS: Array[String] = [
	"create", "join", "invite-host", "invite-guest", "rematch-host", "rematch-guest",
]
const HOST_SETUP_KINDS: Array[String] = ["create", "invite-host", "rematch-host"]
const GUEST_SETUP_KINDS: Array[String] = ["join", "invite-guest", "rematch-guest"]


static func is_network_setup(kind: String) -> bool:
	return kind in SETUP_KINDS


static func is_host_setup(kind: String) -> bool:
	return kind in HOST_SETUP_KINDS


static func is_guest_setup(kind: String) -> bool:
	return kind in GUEST_SETUP_KINDS
## The live networked session, when this setup fronts one. Set for
## code/host flows only; mock invite flows have no session and keep
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
	_header.set_peer_context(_peer_setup)
	_update_screen_columns()
	call_deferred("_update_screen_columns")
	_update_side_cards()
	_update_custom_time_visibility()
	_update_summary()
	if _peer_setup:
		if _net_bridge != null:
			# configure_net_bridge can run before this scene enters the tree;
			# @onready controls are valid only after this point.
			_header.bind_net_bridge(_net_bridge)
		_apply_peer_setup()
		# The host snapshot may have arrived before this screen subscribed.
		# Re-read the bridge-owned value after all @onready controls exist.
		if is_guest_setup(_peer_kind):
			call_deferred("_apply_saved_net_setup")


## Choice content owned here in code (see ChoiceGroup.configure): the
## option arrays live outside scene overrides so export conversion
## cannot drop them.
func _configure_choices() -> void:
	_side_choice.configure("Choose Color", ["White", "Black", "Random"], 3, 0)
	# Clock is out of v1: the core starts untimed games, so the label must
	# not promise a rule. The choice still syncs as lobby preview metadata.
	_time_choice.configure("Time Control (preview · untimed)", ["1 | 0", "3 | 2", "5 | 3", "10 | 0", "15 | 10", "Custom"], 3, 2)
	# The Rust core currently has one authoritative starting position. Do not
	# offer a Chess960 choice that would render as selected but start standard
	# chess underneath.
	_variant_choice.configure("Variant", ["Standard"], 1, 0)
	_difficulty_choice.configure("Difficulty", ["Easy", "Medium", "Hard"], 3, 1)


## Configures this shared screen after a peer has joined or accepted an invite.
func configure_peer(opponent_name: String, setup_kind: String) -> void:
	_peer_setup = true
	_peer_name = opponent_name
	_peer_kind = setup_kind
	if is_node_ready():
		_header.set_peer_context(_peer_setup)
		_apply_peer_setup()


func selected_ai_side() -> String:
	return _side_choice.get_selected_choice()


func selected_ai_difficulty() -> String:
	return _difficulty_choice.get_selected_choice()


## Attaches the live network bridge. Only choices supported by the current
## application contract remain interactive; unsupported settings are hidden.
func configure_net_bridge(bridge: ChessCoreBridge) -> void:
	_net_bridge = bridge
	if not _net_bridge.session_created.is_connected(_on_net_session_created):
		_net_bridge.session_created.connect(_on_net_session_created)
	if not _net_bridge.setup_changed.is_connected(_on_net_setup_changed):
		_net_bridge.setup_changed.connect(_on_net_setup_changed)
	if is_node_ready() and _peer_setup:
		_header.bind_net_bridge(bridge)
		_apply_peer_setup()


func _apply_peer_setup() -> void:
	_difficulty_choice.hide()
	_play_button.text = "Ready   ✓"
	_play_button.tooltip_text = "Mark yourself ready for this match"
	_ready_label.text = "Choose your settings, then mark yourself ready"
	var detail := "Connected player"
	if is_network_setup(_peer_kind):
		detail = "Connected via invite code"
	_opponent_card.configure(_peer_name, "PLAYER", detail)
	if _net_bridge != null:
		_apply_net_setup()
	_update_summary()
	if _peer_setup and not is_network_setup(_peer_kind):
		_ready_label.text = "Unknown setup mode · waiting for host"


## Network setup owns the user-visible transition into the session. The host
## chooses a side and starts; the guest observes and waits for that one action.
func _apply_net_setup() -> void:
	_custom_time_controls.hide()
	_difficulty_choice.hide()
	_side_choice.show()
	_time_choice.show()
	_variant_choice.show()
	var mine := _net_bridge.my_side()
	var mine_shown := mine.capitalize() if not mine.is_empty() else "…"
	var theirs := "Black" if mine == "white" else "White" if mine == "black" else "…"
	_player_card.set_side(mine_shown)
	_opponent_card.set_side(theirs)
	if is_host_setup(_peer_kind):
		_side_choice.set_read_only(false)
		_time_choice.set_read_only(false)
		_variant_choice.set_read_only(false)
		_side_choice.set_enabled(true)
		_time_choice.set_enabled(true)
		_variant_choice.set_enabled(true)
		_play_button.text = "Start game"
		_play_button.tooltip_text = "Choose your side and start the session"
		_ready_label.text = "Choose your side, then start the game"
		_play_button.disabled = false
		_publish_net_setup()
	else:
		_side_choice.set_read_only(true)
		_time_choice.set_read_only(true)
		_variant_choice.set_read_only(true)
		_play_button.text = "Waiting for host"
		_play_button.tooltip_text = "The host controls the lobby"
		_ready_label.text = "Waiting for the host to choose settings"
		_play_button.disabled = true
		_apply_saved_net_setup()


func _on_net_setup_changed(side: String, time: String, variant: String) -> void:
	if _net_bridge == null or not is_guest_setup(_peer_kind):
		return
	_remote_setup_received = true
	_apply_remote_side(side)
	for index in range(_time_choice.choices.size()):
		if _time_choice.choices[index] == time:
			_time_choice.set_selection(index)
			break
	for index in range(_variant_choice.choices.size()):
		if _variant_choice.choices[index] == variant:
			_variant_choice.set_selection(index)
			break
	_update_custom_time_visibility()
	_update_summary()
	_ready_label.text = "Host is readying the match · waiting to start"
	_play_button.disabled = true


func _apply_remote_side(side: String) -> void:
	for index in range(_side_choice.choices.size()):
		if _side_choice.choices[index] == side:
			_side_choice.set_selection(index)
			break
	match side:
		"Black":
			_player_card.set_side("White")
			_opponent_card.set_side("Black")
		"Random":
			_player_card.set_side("Auto assigned")
			_opponent_card.set_side("Auto assigned")
		_:
			_player_card.set_side("Black")
			_opponent_card.set_side("White")


func _apply_saved_net_setup() -> void:
	if _net_bridge == null or not is_guest_setup(_peer_kind):
		return
	var snapshot := _net_bridge.network_setup()
	if snapshot.size() != 3:
		return
	_on_net_setup_changed(snapshot[0], snapshot[1], snapshot[2])


func _publish_net_setup() -> void:
	if _net_bridge == null or not is_host_setup(_peer_kind):
		return
	_net_bridge.update_network_setup(
		_side_choice.get_selected_choice(),
		_time_choice.get_selected_choice(),
		_variant_choice.get_selected_choice(),
	)


func _on_net_session_created(_white: String, _black: String, _host: String) -> void:
	if _net_bridge == null:
		return
	var mine := _net_bridge.my_side()
	var theirs := "Black" if mine == "white" else "White" if mine == "black" else "…"
	_player_card.set_side(mine.capitalize() if not mine.is_empty() else "…")
	_opponent_card.set_side(theirs)
	if is_host_setup(_peer_kind):
		_ready_label.text = "Game created · waiting for opponent to be ready"
	else:
		_ready_label.text = "Game created · waiting for host to start"
		_play_button.text = "Waiting for host"
		_play_button.disabled = true


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
	_publish_net_setup()


func _on_time_changed(_choice: String, _index: int) -> void:
	_update_custom_time_visibility()
	_update_summary()
	_publish_net_setup()


func _on_settings_changed(_choice: String, _index: int) -> void:
	_update_summary()
	_publish_net_setup()


func _on_custom_time_changed(_value: float) -> void:
	_update_summary()


func _on_play_pressed() -> void:
	if _net_bridge != null:
		if is_host_setup(_peer_kind):
			if _net_bridge.start_network_game(
				selected_ai_side(),
				_time_choice.get_selected_choice(),
				_variant_choice.get_selected_choice(),
			):
				_play_button.disabled = true
				_ready_label.text = "Starting game · waiting for opponent"
		else:
			return
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
	var leave_label := "Leave game" if _peer_setup else "Return to Home"
	HeaderMenu.toggle_in(
		self,
		["Settings", leave_label],
		[_on_header_settings_pressed, _on_leave_setup_pressed]
	)


func _on_header_settings_pressed() -> void:
	settings_requested.emit()


func _on_leave_setup_pressed() -> void:
	if not _peer_setup:
		leave_requested.emit(false)
		return
	HeaderMenu.confirm_in(
		self,
		"Leave game?",
		"You’ll disconnect from %s and return to Multiplayer." % _peer_name,
		"Leave game",
		"Stay",
		func() -> void: leave_requested.emit(true)
	)


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
