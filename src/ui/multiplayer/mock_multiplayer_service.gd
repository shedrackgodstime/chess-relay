class_name MockMultiplayerService
extends Node

## Local-only event source for exercising the multiplayer UI without a transport.
signal hosted_opponent_joined(opponent_name: String)
signal join_succeeded(opponent_name: String)
signal join_failed
signal player_invite_accepted(player_name: String)
signal player_invite_declined(player_name: String)
signal incoming_invite_received(player_name: String)
signal incoming_invite_answered(player_name: String, accepted: bool)
signal opponent_ready

const MOCK_DELAY := 2.0

var active_code := ""
var _host_generation := 0
var _join_generation := 0
var _invite_generation := 0
var _incoming_invite_generation := 0
var _ready_generation := 0


func cancel_pending_requests() -> void:
	_host_generation += 1
	_join_generation += 1
	_invite_generation += 1
	_incoming_invite_generation += 1
	_ready_generation += 1
	active_code = ""


func start_hosting(code: String) -> void:
	active_code = _normalize(code)
	_host_generation += 1
	_finish_hosting_after_delay(_host_generation)


func cancel_hosting() -> void:
	_host_generation += 1
	active_code = ""


func join(code: String) -> void:
	_join_generation += 1
	_finish_join_after_delay(_normalize(code), _join_generation)


func cancel_join() -> void:
	_join_generation += 1


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


func _finish_hosting_after_delay(generation: int) -> void:
	await get_tree().create_timer(MOCK_DELAY).timeout
	if generation == _host_generation and not active_code.is_empty():
		hosted_opponent_joined.emit("Morgan")


func _finish_join_after_delay(code: String, generation: int) -> void:
	await get_tree().create_timer(MOCK_DELAY).timeout
	if generation != _join_generation:
		return
	if code == "ABC123" or (not active_code.is_empty() and code == active_code):
		join_succeeded.emit("Morgan")
	else:
		join_failed.emit()


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


func _normalize(code: String) -> String:
	return code.replace("-", "").replace(" ", "").to_upper()
