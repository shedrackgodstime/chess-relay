class_name MockMultiplayerService
extends Node

## Local-only event source for exercising the multiplayer UI without a backend.
##
## What is still faked here, and why: player invites, incoming invites,
## and the setup ready-dance have no transport backend yet (no
## discovery, no pre-game config channel), so the mock holds their UI
## shapes until one lands. Hosting and joining are NOT faked anymore:
## the app root drives those through the real bridge, and their mock
## paths were deleted so a timer can never impersonate a peer again.
signal player_invite_accepted(player_name: String)
signal player_invite_declined(player_name: String)
signal incoming_invite_received(player_name: String)
signal incoming_invite_answered(player_name: String, accepted: bool)
signal opponent_ready

const MOCK_DELAY := 2.0

var _invite_generation := 0
var _incoming_invite_generation := 0
var _ready_generation := 0


func cancel_pending_requests() -> void:
	_invite_generation += 1
	_incoming_invite_generation += 1
	_ready_generation += 1


func invite_player(player_name: String) -> void:
	_invite_generation += 1
	_finish_player_invite_after_delay(player_name, _invite_generation)


func cancel_player_invite() -> void:
	_invite_generation += 1


func start_hub_session() -> void:
	_incoming_invite_generation += 1
	_deliver_incoming_invite_after_delay(_incoming_invite_generation)


func answer_incoming_invite(player_name: String, accepted: bool) -> void:
	incoming_invite_answered.emit(player_name, accepted)


func request_player_ready() -> void:
	_ready_generation += 1
	_finish_ready_after_delay(_ready_generation)


func _finish_player_invite_after_delay(player_name: String, generation: int) -> void:
	await get_tree().create_timer(MOCK_DELAY).timeout
	if generation != _invite_generation:
		return
	if player_name == "KnightOwl" or player_name == "RookRunner":
		player_invite_declined.emit(player_name)
	else:
		player_invite_accepted.emit(player_name)


func _deliver_incoming_invite_after_delay(generation: int) -> void:
	await get_tree().create_timer(5.0).timeout
	if generation == _incoming_invite_generation:
		incoming_invite_received.emit("Morgan")


func _finish_ready_after_delay(generation: int) -> void:
	await get_tree().create_timer(MOCK_DELAY).timeout
	if generation == _ready_generation:
		opponent_ready.emit()
