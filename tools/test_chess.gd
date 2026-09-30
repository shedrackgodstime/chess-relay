extends SceneTree

## Headless checks for the game core: state, moves, and the apply funnel.
##
## Everything here is plain data — no nodes — which is exactly the property
## the P2P design needs: both peers run this same code over the same moves.
##
##     godot-headless --headless --script res://tools/test_chess.gd

var _failures := 0


func _init() -> void:
	_encoding_checks()
	_setup_checks()
	_move_data_checks()
	_funnel_checks()
	if _failures == 0:
		print("chess: all checks passed")
	else:
		printerr("chess: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _encoding_checks() -> void:
	print("Encoding")
	for type in [PieceProfiles.Type.PAWN, PieceProfiles.Type.KNIGHT,
			PieceProfiles.Type.BISHOP, PieceProfiles.Type.ROOK,
			PieceProfiles.Type.QUEEN, PieceProfiles.Type.KING]:
		for side in [BoardState.LIGHT, BoardState.DARK]:
			var code := BoardState.encode(type, side)
			var decoded := BoardState.decode(code)
			_check("encode/decode round-trips %s side %d" % [PieceProfiles.type_name(type), side],
				decoded == Vector2i(type, side), "code=%d" % code)
	_check("empty decodes to nothing", BoardState.decode(BoardState.EMPTY) == Vector2i(-1, -1), "")
	_check("out-of-range reads empty",
		BoardState.new().at(-1, 0) == BoardState.EMPTY
			and BoardState.new().at(8, 8) == BoardState.EMPTY, "")


func _setup_checks() -> void:
	print("Setup")
	var state := BoardState.new()
	_check("standard setup has 32 pieces", state.piece_count() == 32,
		"count=%d" % state.piece_count())
	_check("each side has 16", state.count_side(0) == 16 and state.count_side(1) == 16, "")
	_check("light to move first", state.side_to_move == BoardState.LIGHT, "")

	var e2 := BoardState.decode(state.at(4, 1))
	_check("white king pawn on e2", e2 == Vector2i(PieceProfiles.Type.PAWN, 0),
		"code=%s" % e2)
	var e8 := BoardState.decode(state.at(4, 7))
	_check("black king on e8", e8 == Vector2i(PieceProfiles.Type.KING, 1),
		"code=%s" % e8)
	_check("middle is empty", state.at(3, 3) == BoardState.EMPTY
		and state.at(4, 4) == BoardState.EMPTY, "")


func _move_data_checks() -> void:
	print("Move data")
	var move := ChessMove.new(Vector2i(4, 1), Vector2i(4, 3))
	var restored := ChessMove.from_dict(move.to_dict())
	_check("move survives a dict round-trip", move.equals(restored),
		"dict=%s" % move.to_dict())
	_check("dict is JSON-safe primitives",
		(restored.to_dict()["from"] as Array).size() == 2
			and restored.to_dict()["promotion"] is int, "")
	var other := ChessMove.new(Vector2i(4, 1), Vector2i(4, 2))
	_check("different moves compare unequal", not move.equals(other), "")
	_check("move prints readably", str(move) == "ChessMove((4, 1) -> (4, 3))",
		"str=%s" % move)


func _funnel_checks() -> void:
	print("Apply funnel")
	var game := ChessGame.new()
	game.reset()
	var emitted: Array = []
	game.moved.connect(func(m: ChessMove, c: int) -> void: emitted.append([m, c]))

	_check("e2-e4 applies", game.apply_move(ChessMove.new(Vector2i(4, 1), Vector2i(4, 3))),
		"")
	_check("pawn leaves e2",
		game.state.at(4, 1) == BoardState.EMPTY, "")
	_check("pawn arrives on e4",
		BoardState.decode(game.state.at(4, 3)) == Vector2i(PieceProfiles.Type.PAWN, 0),
		"")
	_check("side toggles to dark", game.state.side_to_move == BoardState.DARK, "")
	_check("history records the move", game.history.size() == 1
		and game.history[0].equals(ChessMove.new(Vector2i(4, 1), Vector2i(4, 3))), "")
	_check("signal fires once with no capture", emitted.size() == 1
		and (emitted[0][0] as ChessMove).equals(ChessMove.new(Vector2i(4, 1), Vector2i(4, 3)))
		and int(emitted[0][1]) == BoardState.EMPTY,
		"emitted=%d" % emitted.size())

	# Queen takes the pawn that just advanced to e4.
	game.apply_move(ChessMove.new(Vector2i(3, 7), Vector2i(4, 3)))
	_check("capture reports the victim code",
		int(emitted[1][1]) == BoardState.encode(PieceProfiles.Type.PAWN, 0),
		"captured=%d" % int(emitted[1][1]))
	_check("queen stands on the victim square",
		BoardState.decode(game.state.at(4, 3)) == Vector2i(PieceProfiles.Type.QUEEN, 1),
		"")

	# Refusals change nothing and emit nothing.
	var before := emitted.size()
	_check("empty origin refused", not game.apply_move(ChessMove.new(Vector2i(3, 3), Vector2i(3, 4))),
		"(d4 is vacant after the queen left d8 for e4)")
	_check("same square refused", not game.apply_move(ChessMove.new(Vector2i(3, 3), Vector2i(3, 3))),
		"")
	_check("off-board refused", not game.apply_move(ChessMove.new(Vector2i(0, 0), Vector2i(-1, 0))),
		"")
	_check("null refused", not game.apply_move(null), "")
	_check("refusals stay silent", emitted.size() == before, "")

	game.reset()
	_check("reset restores the setup", game.state.piece_count() == 32
		and game.history.is_empty() and game.state.side_to_move == BoardState.LIGHT, "")


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		print("  ok   %s  %s" % [label, detail])
	else:
		_failures += 1
		printerr("  FAIL %s  %s" % [label, detail])
