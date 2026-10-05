extends Control

const MIN_WINDOW_SIZE := Vector2i(960, 640)

signal invite_created(code: String)
signal invite_cancelled
signal join_requested(code: String)
signal join_cancelled(code: String)
signal settings_requested

const HOME_SCREEN: PackedScene = preload("res://src/ui/screens/home/home_screen.tscn")
const GAME_SETUP_SCREEN: PackedScene = preload(
	"res://src/ui/screens/game_setup/game_setup_screen.tscn")
const MULTIPLAYER_HUB_SCREEN: PackedScene = preload(
	"res://src/ui/screens/multiplayer_hub/multiplayer_hub_screen.tscn")
const GAME_SCREEN: PackedScene = preload("res://src/ui/screens/game/game_screen.tscn")
const MOCK_MULTIPLAYER_SERVICE_SCRIPT: Script = preload(
	"res://src/ui/multiplayer/mock_multiplayer_service.gd")

@onready var _screen_host: Control = %ScreenHost

var _current_screen: Control
var _mock_multiplayer: MockMultiplayerService


func _ready() -> void:
	get_window().min_size = MIN_WINDOW_SIZE
	_mock_multiplayer = MOCK_MULTIPLAYER_SERVICE_SCRIPT.new() as MockMultiplayerService
	add_child(_mock_multiplayer)
	_mock_multiplayer.hosted_opponent_joined.connect(notify_invite_opponent_connected)
	_mock_multiplayer.join_succeeded.connect(notify_join_connected)
	_mock_multiplayer.join_failed.connect(notify_join_failed)
	_mock_multiplayer.player_invite_accepted.connect(_on_player_invite_accepted)
	_mock_multiplayer.player_invite_declined.connect(_on_player_invite_declined)
	_mock_multiplayer.incoming_invite_received.connect(_on_incoming_invite_received)
	_mock_multiplayer.opponent_ready.connect(_on_opponent_ready)
	_show_home_screen()


func _show_home_screen() -> void:
	var home_screen := HOME_SCREEN.instantiate() as HomeScreen
	home_screen.play_computer_requested.connect(_on_play_computer_requested)
	home_screen.p2p_requested.connect(_on_p2p_requested)
	home_screen.settings_requested.connect(_on_settings_requested)
	_show_screen(home_screen)


func _on_play_computer_requested() -> void:
	var setup := GAME_SETUP_SCREEN.instantiate() as GameSetupScreen
	setup.settings_requested.connect(_on_settings_requested)
	setup.leave_requested.connect(_on_game_setup_leave_requested)
	setup.play_requested.connect(_show_game_screen)
	_show_screen(setup)


func _on_p2p_requested() -> void:
	var hub := MULTIPLAYER_HUB_SCREEN.instantiate() as MultiplayerHubScreen
	hub.back_requested.connect(_show_home_screen)
	hub.create_requested.connect(_on_invite_created)
	hub.create_cancelled.connect(_on_invite_cancelled)
	hub.join_requested.connect(_on_join_requested)
	hub.join_cancelled.connect(_on_join_cancelled)
	hub.player_invite_requested.connect(_on_player_invite_requested)
	hub.player_invite_cancelled.connect(_on_player_invite_cancelled)
	hub.incoming_invite_responded.connect(_on_incoming_invite_responded)
	hub.game_setup_requested.connect(_on_peer_setup_requested)
	_show_screen(hub)
	_mock_multiplayer.start_hub_session()


func _on_invite_created(code: String) -> void:
	invite_created.emit(code)
	_mock_multiplayer.start_hosting(code)


func _on_invite_cancelled() -> void:
	_mock_multiplayer.cancel_hosting()
	invite_cancelled.emit()


func _on_join_requested(code: String) -> void:
	join_requested.emit(code)
	_mock_multiplayer.join(code)


func _on_join_cancelled(code: String) -> void:
	_mock_multiplayer.cancel_join()
	join_cancelled.emit(code)


func _on_player_invite_requested(player_name: String) -> void:
	_mock_multiplayer.invite_player(player_name)


func _on_player_invite_cancelled() -> void:
	_mock_multiplayer.cancel_player_invite()


func _on_incoming_invite_received(player_name: String) -> void:
	if _current_screen is MultiplayerHubScreen:
		(_current_screen as MultiplayerHubScreen).receive_incoming_invite(player_name)


func _on_incoming_invite_responded(player_name: String, accepted: bool) -> void:
	_mock_multiplayer.answer_incoming_invite(player_name, accepted)


func _on_peer_setup_requested(opponent_name: String, setup_kind: String) -> void:
	var setup := GAME_SETUP_SCREEN.instantiate() as GameSetupScreen
	setup.configure_peer(opponent_name, setup_kind)
	setup.settings_requested.connect(_on_settings_requested)
	setup.leave_requested.connect(_on_game_setup_leave_requested)
	setup.play_requested.connect(_show_game_screen)
	_show_screen(setup)


func _show_game_screen() -> void:
	var game := GAME_SCREEN.instantiate() as GameScreen
	game.leave_requested.connect(_show_home_screen)
	_show_screen(game)


func _on_game_setup_leave_requested(is_peer_setup: bool) -> void:
	if is_peer_setup:
		_on_p2p_requested()
	else:
		_show_home_screen()


func _on_settings_requested() -> void:
	settings_requested.emit()


func _on_player_invite_accepted(player_name: String) -> void:
	if _current_screen is MultiplayerHubScreen:
		(_current_screen as MultiplayerHubScreen).player_invite_accepted(player_name)


func _on_player_invite_declined(player_name: String) -> void:
	if _current_screen is MultiplayerHubScreen:
		(_current_screen as MultiplayerHubScreen).player_invite_declined(player_name)


func _on_opponent_ready() -> void:
	if _current_screen is GameSetupScreen:
		(_current_screen as GameSetupScreen).opponent_ready()


## UI outcome hooks for the future multiplayer service.
func notify_invite_opponent_connected(opponent_name: String = "Opponent") -> void:
	if _current_screen is MultiplayerHubScreen:
		(_current_screen as MultiplayerHubScreen).opponent_connected(opponent_name)


func notify_invite_opponent_left() -> void:
	if _current_screen is MultiplayerHubScreen:
		(_current_screen as MultiplayerHubScreen).opponent_left()


func notify_join_failed() -> void:
	if _current_screen is MultiplayerHubScreen:
		(_current_screen as MultiplayerHubScreen).join_failed()


func notify_join_connected(opponent_name: String = "Opponent") -> void:
	if _current_screen is MultiplayerHubScreen:
		(_current_screen as MultiplayerHubScreen).join_connected(opponent_name)


func _show_screen(screen: Control) -> void:
	if _current_screen != null:
		_mock_multiplayer.cancel_pending_requests()
		_screen_host.remove_child(_current_screen)
		_current_screen.queue_free()

	_current_screen = screen
	_screen_host.add_child(_current_screen)
	_current_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
