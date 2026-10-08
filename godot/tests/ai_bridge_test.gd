extends SceneTree

## Verifies the local AI crosses the application boundary as a normal move:
## Godot requests a game, Rust searches off-frame, and the resulting move
## arrives through the existing move_applied signal.

var _failed := false
var _checks := 0
var _move_uci := ""
var _started := false


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failed = true
		printerr("FAIL: ", label)


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	var bridge := ChessCoreBridge.new()
	bridge.game_started.connect(func() -> void: _started = true)
	bridge.move_applied.connect(
		func(_sequence: int, uci: String, _by: String, _agreed: bool) -> void:
			_move_uci = uci)
	bridge.bridge_error.connect(func(message: String) -> void: printerr("AI bridge: ", message))
	root.add_child(bridge)
	await process_frame

	_check(bridge.is_available(), "Rust bridge is available for AI")
	if bridge.is_available():
		var save_path := "/tmp/chess-relay-ai-bridge-test-%s.bin" % str(Time.get_ticks_usec())
		_check(
			bridge.start_ai(
				ProjectSettings.globalize_path("user://chess_relay_identity.key"),
				save_path,
				"White",
				"Easy"),
			"AI game starts through the bridge")
		_check(bridge.submit_move("e2e4"), "human move enters the application command path")
		_move_uci = ""
		for _frame in range(180):
			if not _move_uci.is_empty():
				break
			await process_frame
		_check(_started, "AI game emits game_started")
		_check(not _move_uci.is_empty(), "AI returns a move through move_applied")
		_check(bridge.turn() == "white", "AI reply advances the authoritative turn")
		bridge.stop_ai()

	bridge.queue_free()
	print("AI BRIDGE: %d checks ran, %d failed" % [_checks, int(_failed)])
	quit(1 if _failed else 0)
