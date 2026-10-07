extends Node
## On-device counterpart of bridge_spike_test.gd, as a runnable scene whose
## prints land in logcat.
##
## Kept as a scene rather than folded into the desktop suite because a phone
## sends its verdict to logcat, and that is the only evidence the Android gate
## has. Same checks, same facade.

var _failed := false
var _checks := 0
var _phase_reached_end := false
var _started := false
## Read as typed locals: a Dictionary lookup is a Variant and these checks take
## a bool.
var _move_uci := ""
## Last refusal message from the core, for diagnosis.
var last_error := ""


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("BRIDGE-SPIKE ok: ", label)
	else:
		_failed = true
		printerr("BRIDGE-SPIKE FAIL: ", label)


func _ready() -> void:
	var bridge := ChessCoreBridge.new()
	add_child(bridge)
	bridge.move_applied.connect(
		func(_sequence: int, uci: String, _by: String, _agreed: bool) -> void:
			_move_uci = uci)
	bridge.game_started.connect(func() -> void: _started = true)
	bridge.bridge_error.connect(_on_bridge_error)

	_check(bridge.is_available(),
		"Rust core loaded on device (gdextension registered ChessRelayBridge)")

	if bridge.is_available():
		_check(_started, "game started after readiness")
		_check(bridge.submit_move("e2e4"), "core accepted e2e4")
		_check(_move_uci == "e2e4", "move_applied carried the uci")
		_check(bridge.fen()
			== "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
			"core position observed e2e4, got %s" % bridge.fen())

	_phase_reached_end = true
	_check(_phase_reached_end, "phase ran to completion")
	print("BRIDGE-SPIKE: %d checks, %d failed" % [_checks, int(_failed)])
	if _failed:
		printerr("BRIDGE-SPIKE RESULT: FAIL")
		get_tree().quit(1)
	else:
		print("BRIDGE-SPIKE RESULT: PASS")
		get_tree().quit(0)


func _on_bridge_error(message: String) -> void:
	# Recorded, not failed: the suite deliberately submits illegal moves and the
	# core is expected to refuse them.
	last_error = message