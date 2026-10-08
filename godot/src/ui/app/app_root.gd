class_name AppRoot
extends Control

## Application UI root: owns screen transitions and shared UI coordination.
##
## Named so the checks can hold a typed reference. It had no `class_name`, so
## every `APP_SCENE.instantiate()` in the suite was a Variant and reaching a
## method on it produced eight findings in the test file alone.

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
const IDENTITY_FILE := "user://chess_relay_identity.key"
const MockMultiplayerServiceScript := preload(
	"res://src/ui/multiplayer/mock_multiplayer_service.gd")

@onready var _screen_host: Control = %ScreenHost

var _current_screen: Control
var _mock_multiplayer: MockMultiplayerService
## The networked session owner. Created on demand for the multiplayer
## flow and handed to the game screen, so host/join outlive the hub and
## the setup screen. Null until first use and after a full leave.
var _net_bridge: ChessCoreBridge = null
## True while the shown game screen plays on `_net_bridge`.
var _net_game_active := false
## Last linked peer identity, for naming the setup screen once the
## session (not just the transport) is ready.
var _net_peer := ""


func _ready() -> void:
	get_window().min_size = MIN_WINDOW_SIZE
	_mock_multiplayer = MockMultiplayerServiceScript.new()
	add_child(_mock_multiplayer)
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
	setup.play_requested.connect(_on_computer_setup_play.bind(setup))
	_show_screen(setup)


func _on_computer_setup_play(setup: GameSetupScreen) -> void:
	_show_game_screen(false, setup.selected_ai_side(), setup.selected_ai_difficulty())


func _on_p2p_requested() -> void:
	var hub := MULTIPLAYER_HUB_SCREEN.instantiate() as MultiplayerHubScreen
	hub.back_requested.connect(_on_hub_back_requested)
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


## Hands the live network bridge to whoever needs it, wiring its
## link signals once. Screens use the node; they never own it.
func _net() -> ChessCoreBridge:
	if _net_bridge == null:
		_net_bridge = ChessCoreBridge.new()
		add_child(_net_bridge)
		_net_bridge.peer_connected.connect(_on_net_peer_connected)
		_net_bridge.network_error.connect(_on_net_network_error)
		_net_bridge.peer_disconnected.connect(_on_net_peer_disconnected)
		_net_bridge.game_started.connect(_on_net_game_started)
	return _net_bridge


func _on_hub_back_requested() -> void:
	_leave_network()
	_show_home_screen()


func _on_invite_created() -> void:
	invite_created.emit("")
	var code := _net().host_game(_identity_path())
	if code.is_empty():
		_leave_network()
		if _current_screen is MultiplayerHubScreen:
			(_current_screen as MultiplayerHubScreen).host_failed()
		return
	if _current_screen is MultiplayerHubScreen:
		(_current_screen as MultiplayerHubScreen).show_host_code(code)


func _on_invite_cancelled() -> void:
	_leave_network()
	invite_cancelled.emit()


func _on_join_requested(code: String) -> void:
	join_requested.emit(code)
	if not _net().join_game(code, _identity_path()):
		_leave_network()
		if _current_screen is MultiplayerHubScreen:
			(_current_screen as MultiplayerHubScreen).join_failed()


func _on_join_cancelled(code: String) -> void:
	_leave_network()
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
	if (setup_kind == "create" or setup_kind == "join") and _net_if_live() != null:
		setup.configure_net_bridge(_net_if_live())
	setup.settings_requested.connect(_on_settings_requested)
	setup.leave_requested.connect(_on_game_setup_leave_requested)
	setup.play_requested.connect(_show_game_screen.bind(true))
	_show_screen(setup)


func _show_game_screen(
	is_multiplayer: bool = false,
	ai_side: String = "White",
	ai_difficulty: String = "Medium",
) -> void:
	var game := GAME_SCREEN.instantiate() as GameScreen
	_net_game_active = false
	if is_multiplayer:
		game.configure_peer(_net_if_live())
		_net_game_active = _net_bridge != null
	else:
		game.configure_ai(ai_side, ai_difficulty)
	game.leave_requested.connect(_on_game_leave_requested)
	_show_screen(game)


## Leaving a networked game retires its session; leaving a local game
## changes nothing but the screen.
func _on_game_leave_requested() -> void:
	if _net_game_active:
		_net_game_active = false
		_leave_network()
	_show_home_screen()


## Routes link signals to the hub when it is showing; the game screen
## hears the same bridge directly for in-game display.
##
## Link-up only rewords the hub's status. The hub advances to setup on
## `game_started`: the handshake (ready + genesis agreement both ways)
## must complete first, otherwise one side sits in setup while the
## other is still failing to join.
## TEMP-DIAG screen tag for the trace lines below. Removed with them.
func _trace_screen() -> String:
	if _current_screen is MultiplayerHubScreen:
		return "hub"
	if _current_screen is GameSetupScreen:
		return "setup"
	if _current_screen is GameScreen:
		return "game"
	if _current_screen is HomeScreen:
		return "home"
	return "none"


func _on_net_peer_connected(peer: String) -> void:
	print("NET-TRACE app: peer_connected peer=%s screen=%s" % [peer.left(8), _trace_screen()]) # TEMP-DIAG
	_net_peer = peer
	if _current_screen is MultiplayerHubScreen:
		(_current_screen as MultiplayerHubScreen).peer_linked()


func _on_net_game_started() -> void:
	print("NET-TRACE app: game_started screen=%s" % _trace_screen()) # TEMP-DIAG
	if _current_screen is MultiplayerHubScreen:
		var opponent := _net_peer if not _net_peer.is_empty() else "Opponent"
		(_current_screen as MultiplayerHubScreen).opponent_connected(opponent)


func _on_net_network_error(message: String) -> void:
	print("NET-TRACE app: network_error %s" % message) # TEMP-DIAG
	if _current_screen is MultiplayerHubScreen:
		(_current_screen as MultiplayerHubScreen).notify_network_error(message)
	elif _current_screen is GameSetupScreen:
		(_current_screen as GameSetupScreen).notify_net_issue(message)


func _on_net_peer_disconnected() -> void:
	print("NET-TRACE app: peer_disconnected") # TEMP-DIAG
	if _current_screen is MultiplayerHubScreen:
		(_current_screen as MultiplayerHubScreen).notify_network_error("Opponent disconnected.")
	elif _current_screen is GameSetupScreen:
		(_current_screen as GameSetupScreen).notify_net_issue("Opponent disconnected.")


## The live bridge, if any. Null when no networked session exists, so
## mock flows (player invites) fall back to local boards instead of
## binding a real endpoint for nothing.
func _net_if_live() -> ChessCoreBridge:
	return _net_bridge


func _identity_path() -> String:
	return ProjectSettings.globalize_path(IDENTITY_FILE)


## Retires the networked session, if any, and drops its bridge so a
## retired session can never be adopted later. Safe to call with none
## up: leaving the hub, cancelling a flow, and leaving a game all
## funnel here so a half-open link never outlives its screen.
func _leave_network() -> void:
	if _net_bridge != null:
		_net_bridge.leave_network()
		_net_bridge.queue_free()
		_net_bridge = null
	_net_peer = ""


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


func _show_screen(screen: Control) -> void:
	if _current_screen != null:
		_mock_multiplayer.cancel_pending_requests()
		_screen_host.remove_child(_current_screen)
		_current_screen.queue_free()

	_current_screen = screen
	_screen_host.add_child(_current_screen)
	_current_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
