class_name ChessCoreBridge
extends Node

## Typed facade over the Rust `ChessRelayBridge` GDExtension node.
##
## Why this exists: a GDExtension class has no GDScript type, so every call to
## one is statically `Variant` or bare `Node`. Reaching for it directly from a
## screen produces a file the type checker cannot check and the escalating
## warning gate correctly refuses -- which is how `game_screen.gd` ended up with
## twenty-four findings in one file, most of them "the method is not present on
## the inferred type".
##
## So the untyped surface is confined to this one file, where each call is
## checked once, and screens talk to a typed object. This is the client half of
## the boundary `application_core.md` describes: Godot sends intent and gets
## facts back, and owns no rules of its own.
##
## What is deliberately not here: any chess decision. Legality comes from
## `legal_moves_from`; the move string is sent as given; the position comes back
## as FEN and is rendered. The promotion suffix travels in the submitted UCI
## (the core validates but does not choose the piece); until the picker UI
## exists the screen defaults it to queen, marked at the call site.

## Emitted when the core accepted and applied a move.
signal move_applied(sequence: int, uci: String, by: String, agreed: bool)
## Emitted when the core has assigned both sides for a session.
signal session_created(white: String, black: String, host: String)
## Emitted when a host setup snapshot arrives during the lobby.
signal setup_changed(side: String, time: String, variant: String)
## Emitted when play begins.
signal game_started
## Emitted when either side changed readiness.
signal ready_changed(peer: String)
## Emitted when the session ended. `reason` is a human-readable string.
signal game_ended(reason: String)
## Emitted when a draw is offered. `seq` is the offer entry sequence.
signal draw_offered(by: String, seq: int)
## Emitted when the open offer is answered.
signal draw_answered(by: String, accept: bool)
## Emitted for anything the core refused or could not do. Also the only way a
## screen learns the bridge failed to load at all.
signal bridge_error(message: String)
## Emitted when the session driver links a peer. `peer` is its identity.
signal peer_connected(peer: String)
## Emitted when the peer link drops.
signal peer_disconnected
## Emitted when the link fails without dropping (bad ticket, lost code).
signal network_error(message: String)

const BRIDGE_CLASS := &"ChessRelayBridge"
const UNAVAILABLE_MESSAGE := "Chess engine unavailable"

## The live GDExtension node, or null when the extension did not load.
var _core: Node = null


func _ready() -> void:
	if not ClassDB.class_exists(BRIDGE_CLASS):
		bridge_error.emit(UNAVAILABLE_MESSAGE)
		return
	_core = ClassDB.instantiate(BRIDGE_CLASS)
	add_child(_core)
	# Re-emitted rather than forwarded so screens connect to typed signals.
	# `connect` is checked through Callable.bind on a Node, which is the one
	# untyped call left, and it is checked once, here.
	_core.connect(&"move_applied",
		func(sequence: int, uci: String, by: String, agreed: bool) -> void:
			move_applied.emit(sequence, uci, by, agreed))
	_core.connect(&"session_created",
		func(white: String, black: String, host: String) -> void:
			session_created.emit(white, black, host))
	_core.connect(&"setup_changed",
		func(side: String, time: String, variant: String) -> void:
			setup_changed.emit(side, time, variant))
	_core.connect(&"game_started", func() -> void: game_started.emit())
	_core.connect(&"ready_changed", func(peer: String) -> void: ready_changed.emit(peer))
	_core.connect(&"game_ended", func(reason: String) -> void: game_ended.emit(reason))
	_core.connect(&"draw_offered", func(by: String, seq: int) -> void: draw_offered.emit(by, seq))
	_core.connect(&"draw_answered", func(by: String, accept: bool) -> void: draw_answered.emit(by, accept))
	_core.connect(&"bridge_error", func(message: String) -> void: bridge_error.emit(message))
	_core.connect(&"peer_connected", func(peer: String) -> void: peer_connected.emit(peer))
	_core.connect(&"peer_disconnected", func() -> void: peer_disconnected.emit())
	_core.connect(&"network_error", func(message: String) -> void: network_error.emit(message))


## Starts a fresh ephemeral session (tests and spike flows).
func start() -> void:
	if _core != null:
		_core.call(&"start")


## Starts with a persistent identity, resuming the saved game unless `fresh`
## explicitly requests a new match.
## Returns true when a saved game resumed. Paths are absolute platform
## paths (Godot resolves `user://` before calling).
func start_resumable(identity_path: String, save_path: String, fresh: bool = false) -> bool:
	if _core == null:
		return false
	var restored: bool = _core.call(&"start_resumable", identity_path, save_path, fresh)
	return restored


## Starts a local Rust-AI game. Search runs off the scene thread and the AI
## move returns through the same move_applied signal as human input.
func start_ai(
	identity_path: String,
	save_path: String,
	side: String,
	difficulty: String,
	fresh: bool = false,
) -> bool:
	if _core == null:
		return false
	var started: bool = _core.call(
		&"start_ai", identity_path, save_path, side, difficulty, fresh)
	return started


## Cancels a local AI search and retires its worker.
func stop_ai() -> void:
	if _core != null:
		_core.call(&"stop_ai")


## Persists the current move log. Returns false with no session.
func save_game() -> bool:
	if _core == null:
		return false
	var saved: bool = _core.call(&"save_game")
	return saved


## Returns the Rust-owned recent network-peer index, newest first.
func recent_players(identity_path: String) -> PackedStringArray:
	if _core == null:
		return PackedStringArray()
	return _core.call(&"recent_players", identity_path)


## Returns "ready" or "unavailable" for the recent-peer index.
func recent_players_status(identity_path: String) -> String:
	if _core == null:
		return "unavailable"
	return str(_core.call(&"recent_players_status", identity_path))


## Whether the Rust core is loaded and holding a session.
func is_available() -> bool:
	return _core != null


## Current position in FEN, or "" before play starts.
##
## Observation, never authority: this is the core's position, read for
## rendering. Nothing in Godot derives rules from it.
func fen() -> String:
	if _core == null:
		return ""
	return str(_core.call(&"fen"))


## Side to move as "white", "black", or "" before play starts.
func turn() -> String:
	if _core == null:
		return ""
	return str(_core.call(&"turn"))


## Target squares for legal moves leaving `square` (for example "e2").
##
## Empty when the square is unparseable, vacant, or play has not started.
## Legality itself stays in the core.
func legal_moves_from(square: String) -> Array[String]:
	var targets: Array[String] = []
	if _core == null:
		return targets
	var raw: Array = _core.call(&"legal_moves_from", square)
	for target: Variant in raw:
		targets.append(str(target))
	return targets


## King square of the side to move while in check, else "".
func check_square() -> String:
	if _core == null:
		return ""
	return str(_core.call(&"check_square"))


## Fullmove number derived from the signed log, not a client counter.
func move_number() -> int:
	if _core == null:
		return 1
	var number: int = _core.call(&"move_number")
	return number


## Whether the authoritative session is terminal, including after restore.
func session_finished() -> bool:
	if _core == null:
		return false
	var finished: bool = _core.call(&"session_finished")
	return finished


## Resigns the side to move. Returns false when refused.
func resign() -> bool:
	if _core == null:
		return false
	var accepted: bool = _core.call(&"resign")
	return accepted


## Offers a draw for the side to move. Returns false when refused.
func offer_draw() -> bool:
	if _core == null:
		return false
	var accepted: bool = _core.call(&"offer_draw")
	return accepted


## Answers the open offer as the other side. Returns false when refused.
func answer_draw(accept: bool) -> bool:
	if _core == null:
		return false
	var accepted: bool = _core.call(&"answer_draw", accept)
	return accepted


## Plays `uci` for whichever side owns the turn.
##
## Returns false when the core refused the move, having already emitted
## `bridge_error`. The caller does not need to distinguish "illegal" from "the
## engine is gone"; both mean "nothing happened".
func submit_move(uci: String) -> bool:
	if _core == null:
		return false
	var accepted: bool = _core.call(&"submit_move", uci)
	return accepted


## Marks a side ready ("white" or "black"); the second one starts play.
func set_ready(side: String) -> void:
	if _core != null:
		_core.call(&"set_ready", side)


## Starts a host session after the transport peer is connected.
func start_network_game(side: String, time: String, variant: String) -> bool:
	if _core == null:
		return false
	var accepted: bool = _core.call(&"start_network_game", side, time, variant)
	return accepted


## Publishes the host-owned setup preview to the connected guest.
## Time remains display metadata until authoritative clocks are implemented.
func update_network_setup(side: String, time: String, variant: String) -> bool:
	if _core == null:
		return false
	return _core.call(&"update_network_setup", side, time, variant)


## Returns the last Rust-owned network setup snapshot as [side, time, variant].
func network_setup() -> PackedStringArray:
	if _core == null:
		return PackedStringArray()
	return _core.call(&"network_setup")


## This device's side ("white"/"black"), or "" before the session has sides.
## Networked input gates on this; hotseat play ignores it.
func my_side() -> String:
	if _core == null:
		return ""
	return str(_core.call(&"my_side"))


## This device's peer ID string, or "" before initialized.
func my_peer() -> String:
	if _core == null:
		return ""
	return str(_core.call(&"my_peer"))


## Side of the given peer ("white", "black", or "" if unknown).
func side_of_peer(peer: String) -> String:
	if _core == null:
		return ""
	return str(_core.call(&"side_of_peer", peer))


## Hosts a networked game using the persistent installation identity. Returns
## the short invite code the guest enters, or ""
## when hosting failed (see `bridge_error`). Linking runs in the
## background; `peer_connected` reports the guest.
func host_game(identity_path: String) -> String:
	if _core == null:
		return ""
	return str(_core.call(&"host_game", identity_path))


## Joins a networked game over a generated rendezvous code.
## Returns false only when setup failed outright; dial success or
## failure reports through `peer_connected` / `network_error`.
func join_game(code: String, identity_path: String) -> bool:
	if _core == null:
		return false
	var accepted: bool = _core.call(&"join_game", code, identity_path)
	return accepted


## Leaves the networked game, closing the endpoint and retiring the
## session driver. Safe with no network up.
func leave_network() -> void:
	if _core != null:
		_core.call(&"leave_network")
