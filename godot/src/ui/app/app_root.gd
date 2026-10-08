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
@onready var _screen_host: Control = %ScreenHost

var _current_screen: Control
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
	hub.game_setup_requested.connect(_on_peer_setup_requested)
	_show_screen(hub)
	hub.configure_recent_players(_net(), _identity_path())


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
		game.configure_peer(_net_if_live(), _net_peer)
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
func _on_net_peer_connected(peer: String) -> void:
	_net_peer = peer
	if _current_screen is MultiplayerHubScreen:
		var hub := _current_screen as MultiplayerHubScreen
		hub.refresh_recent_players(_net(), _identity_path())
		hub.peer_linked(peer)


func _on_net_game_started() -> void:
	if _current_screen is MultiplayerHubScreen:
		var opponent := _net_peer if not _net_peer.is_empty() else "Opponent"
		(_current_screen as MultiplayerHubScreen).opponent_connected(opponent)
	elif _current_screen is GameSetupScreen:
		_show_game_screen(true)


func _on_net_network_error(message: String) -> void:
	if _current_screen is MultiplayerHubScreen:
		(_current_screen as MultiplayerHubScreen).notify_network_error(message)
	elif _current_screen is GameSetupScreen:
		(_current_screen as GameSetupScreen).notify_net_issue(message)


func _on_net_peer_disconnected() -> void:
	if _current_screen is MultiplayerHubScreen:
		(_current_screen as MultiplayerHubScreen).notify_network_error("Opponent disconnected.")
	elif _current_screen is GameSetupScreen:
		(_current_screen as GameSetupScreen).notify_net_issue("Opponent disconnected.")


## The live bridge, if any. Null when no networked session exists; setup is
## allowed to bind it only for a real host/join flow.
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
		# Returning to the multiplayer hub is still a network leave. Keeping the
		# borrowed bridge alive here leaves the other player in a false lobby
		# state and lets a later screen reuse a dead session.
		_leave_network()
		_on_p2p_requested()
	else:
		_show_home_screen()


func _on_settings_requested() -> void:
	settings_requested.emit()


func _show_screen(screen: Control) -> void:
	if _current_screen != null:
		_screen_host.remove_child(_current_screen)
		_current_screen.queue_free()

	_current_screen = screen
	_screen_host.add_child(_current_screen)
	_current_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
