extends Node
## Phase 5 on-device spike: same checks as bridge_spike_test.gd, but as a
## runnable scene whose prints land in logcat. Exits 0 on pass.

var _got := {}
var _failed := false

func _check(cond: bool, label: String) -> void:
	if cond:
		print("BRIDGE-SPIKE ok: ", label)
	else:
		_failed = true
		printerr("BRIDGE-SPIKE FAIL: ", label)

func _ready() -> void:
	if not ClassDB.class_exists("ChessRelayBridge"):
		printerr("BRIDGE-SPIKE FAIL: class missing")
		get_tree().quit(1)
		return
	var bridge: Node = ClassDB.instantiate("ChessRelayBridge")
	add_child(bridge)
	bridge.session_created.connect(func(_w: String, _b: String) -> void: _got["session"] = true)
	bridge.game_started.connect(func() -> void: _got["started"] = true)
	bridge.move_applied.connect(func(_s: int, uci: String, _b: String, _a: bool) -> void: _got["move"] = uci)
	bridge.bridge_error.connect(func(msg: String) -> void:
		_failed = true
		printerr("BRIDGE-SPIKE error signal: ", msg))
	bridge.start()
	_check(_got.get("session", false), "session_created signal")
	_check(_got.get("started", false), "game_started after both ready")
	_check(bridge.submit_move("e2e4"), "submit_move accepted")
	_check(_got.get("move", "") == "e2e4", "move_applied carries uci")
	var fen: String = bridge.fen()
	_check(fen == "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", "fen observes e2e4")
	if _failed:
		printerr("BRIDGE-SPIKE RESULT: FAIL")
		get_tree().quit(1)
	else:
		print("BRIDGE-SPIKE RESULT: PASS")
		get_tree().quit(0)
