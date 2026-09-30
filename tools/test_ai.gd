extends SceneTree

## Headless checks for the AI move source.
##
## The AI is a placeholder opponent, so nothing here asserts strength — only
## that its moves are well-formed, deterministic under a seed, and flow
## through the same funnel as every other move.
##
##     godot-headless --headless --script res://tools/test_ai.gd

var _failures := 0


func _init() -> void:
	var game := ChessGame.new()
	game.reset()

	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var move := AiPlayer.choose_move(game, BoardState.DARK, rng)
	_check("AI produces a move", move != null, "")
	if move != null:
		var code := game.state.at(move.from_square.x, move.from_square.y)
		_check("AI moves its own piece",
			code != BoardState.EMPTY and BoardState.decode(code).y == BoardState.DARK,
			"move=%s" % move)
		_check("AI destination is on the board",
			BoardState.is_inside(move.to_square.x, move.to_square.y)
				and move.to_square != move.from_square,
			"move=%s" % move)

	# Same seed, same game, same move: P2P peers must agree exactly.
	var replay := ChessGame.new()
	replay.reset()
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 99
	var move2 := AiPlayer.choose_move(replay, BoardState.DARK, rng2)
	_check("seeded AI is deterministic", move != null and move2 != null and move.equals(move2),
		"%s vs %s" % [move, move2])

	# A full AI turn through the funnel leaves state and history consistent.
	# The funnel is turn-agnostic (no rules yet), so hand it dark's turn first.
	game.state.side_to_move = BoardState.DARK
	if move != null:
		_check("AI move applies", game.apply_move(move), "move=%s" % move)
		_check("history records it", game.history.size() == 1
			and game.history[0].equals(move), "")
		_check("side toggles after AI", game.state.side_to_move == BoardState.LIGHT, "")

	# Empty of own pieces means no move rather than a crash.
	var lone := ChessGame.new()
	lone.reset()
	for rank in 8:
		for file in 8:
			var code := lone.state.at(file, rank)
			if code != BoardState.EMPTY and BoardState.decode(code).y == BoardState.DARK:
				lone.state.set_square(file, rank, BoardState.EMPTY)
	_check("AI with no pieces returns null",
		AiPlayer.choose_move(lone, BoardState.DARK) == null, "")
	_check("null game returns null", AiPlayer.choose_move(null, BoardState.DARK) == null, "")

	if _failures == 0:
		print("ai: all checks passed")
	else:
		printerr("ai: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		print("  ok   %s  %s" % [label, detail])
	else:
		_failures += 1
		printerr("  FAIL %s  %s" % [label, detail])
