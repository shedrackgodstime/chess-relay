extends Control

signal invite_created(code: String)
signal invite_cancelled
signal join_requested(code: String)
signal join_cancelled(code: String)

const HOME_SCREEN: PackedScene = preload("res://src/ui/screens/home/home_screen.tscn")
const GAME_SETUP_SCREEN: PackedScene = preload(
	"res://src/ui/screens/game_setup/game_setup_screen.tscn")
const MULTIPLAYER_HUB_SCREEN: PackedScene = preload(
	"res://src/ui/screens/multiplayer_hub/multiplayer_hub_screen.tscn")
const MOCK_MULTIPLAYER_SERVICE_SCRIPT: Script = preload(
	"res://src/ui/multiplayer/mock_multiplayer_service.gd")

@onready var _screen_host: Control = %ScreenHost

var _current_screen: Control
var _mock_multiplayer: Node


func _ready() -> void:
	_mock_multiplayer = MOCK_MULTIPLAYER_SERVICE_SCRIPT.new() as Node
	add_child(_mock_multiplayer)
	_mock_multiplayer.connect(&"hosted_opponent_joined", notify_invite_opponent_connected)
	_mock_multiplayer.connect(&"join_succeeded", notify_join_connected)
	_mock_multiplayer.connect(&"join_failed", notify_join_failed)
	_mock_multiplayer.connect(&"player_invite_accepted", _on_player_invite_accepted)
	_mock_multiplayer.connect(&"player_invite_declined", _on_player_invite_declined)
	_mock_multiplayer.connect(&"opponent_ready", _on_opponent_ready)
	_show_home_screen()


func _show_home_screen() -> void:
	var home_screen: Control = HOME_SCREEN.instantiate() as Control
	home_screen.connect(&"play_computer_requested", _on_play_computer_requested)
	home_screen.connect(&"p2p_requested", _on_p2p_requested)
	_show_screen(home_screen)


func _on_play_computer_requested() -> void:
	_show_screen(GAME_SETUP_SCREEN.instantiate() as Control)


func _on_p2p_requested() -> void:
	var hub: Control = MULTIPLAYER_HUB_SCREEN.instantiate() as Control
	hub.connect(&"back_requested", _show_home_screen)
	hub.connect(&"create_requested", _on_invite_created)
	hub.connect(&"create_cancelled", _on_invite_cancelled)
	hub.connect(&"join_requested", _on_join_requested)
	hub.connect(&"join_cancelled", _on_join_cancelled)
	hub.connect(&"player_invite_requested", _on_player_invite_requested)
	hub.connect(&"player_invite_cancelled", _on_player_invite_cancelled)
	hub.connect(&"game_setup_requested", _on_peer_setup_requested)
	_show_screen(hub)


func _on_invite_created(code: String) -> void:
	invite_created.emit(code)
	_mock_multiplayer.call("start_hosting", code)


func _on_invite_cancelled() -> void:
	_mock_multiplayer.call("cancel_hosting")
	invite_cancelled.emit()


func _on_join_requested(code: String) -> void:
	join_requested.emit(code)
	_mock_multiplayer.call("join", code)


func _on_join_cancelled(code: String) -> void:
	_mock_multiplayer.call("cancel_join")
	join_cancelled.emit(code)


func _on_player_invite_requested(player_name: String) -> void:
	_mock_multiplayer.call("invite_player", player_name)


func _on_player_invite_cancelled() -> void:
	_mock_multiplayer.call("cancel_player_invite")


func _on_peer_setup_requested(opponent_name: String, setup_kind: String) -> void:
	var setup := GAME_SETUP_SCREEN.instantiate() as GameSetupScreen
	setup.configure_peer(opponent_name, setup_kind)
	setup.play_requested.connect(func(): _mock_multiplayer.call("request_player_ready"))
	_show_screen(setup)


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
		_mock_multiplayer.call("cancel_pending_requests")
		_screen_host.remove_child(_current_screen)
		_current_screen.queue_free()

	_current_screen = screen
	_screen_host.add_child(_current_screen)
	_current_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
