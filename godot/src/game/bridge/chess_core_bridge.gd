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
## Emitted when play begins.
signal game_started
## Emitted when either side changed readiness.
signal ready_changed(peer: String)
## Emitted when the session ended. `reason` is a human-readable string.
signal game_ended(reason: String)
## Emitted for anything the core refused or could not do. Also the only way a
## screen learns the bridge failed to load at all.
signal bridge_error(message: String)

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
	_core.connect(&"game_started", func() -> void: game_started.emit())
	_core.connect(&"ready_changed", func(peer: String) -> void: ready_changed.emit(peer))
	_core.connect(&"game_ended", func(reason: String) -> void: game_ended.emit(reason))
	_core.connect(&"bridge_error", func(message: String) -> void: bridge_error.emit(message))
	_core.call(&"start")


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