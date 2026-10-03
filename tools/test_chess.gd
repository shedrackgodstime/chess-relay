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
	_capture_checks()
	if _failures == 0:
		if failures > 0:
			print("chess: %d check(s) failed" % failures)
		else:
			print("chess: all checks passed")
	else:
		printerr("chess: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


## Captures are tracked as data derived from the move sequence, so both P2P
## peers build identical trays without extra replication.
func _capture_checks() -> void:
	print("Capture tracking")
	var game := ChessGame.new()
	_check("a fresh game has no captures",
		game.captures_by(BoardState.LIGHT).is_empty()
			and game.captures_by(BoardState.DARK).is_empty(), "")

	# A white pawn on d4 takes the dark knight on e5: a capture is diagonal,
	# so the pawn cannot be standing directly behind its target.
	#
	# The board is cleared first. ChessGame.new() is a full opening position,
	# so leaving it in place puts a black pawn on f6 and a white rook on a1, and
	# every piece below fights with the ones already there.
	game.state.squares.fill(BoardState.EMPTY)
	var knight := BoardState.encode(PieceProfiles.Type.KNIGHT, BoardState.DARK)
	game.state.set_square(3, 3, BoardState.encode(PieceProfiles.Type.PAWN, BoardState.LIGHT))
	game.state.set_square(4, 4, knight)
	game.state.set_square(0, 0, BoardState.encode(PieceProfiles.Type.KING, BoardState.LIGHT))
	game.state.set_square(7, 7, BoardState.encode(PieceProfiles.Type.KING, BoardState.DARK))
	game.state.side_to_move = BoardState.LIGHT
	game.apply_move(ChessMove.new(Vector2i(3, 3), Vector2i(4, 4)))

	_check("a capture is recorded for the capturing side",
		game.captures_by(BoardState.LIGHT) == [knight],
		str(game.captures_by(BoardState.LIGHT)))
	_check("the victim is not credited to the losing side",
		game.captures_by(BoardState.DARK).is_empty(), "")

	# Black recaptures with the pawn on f6, taking the pawn that just landed on
	# e5. Diagonally above its target, as a capturing pawn must be.
	var pawn := BoardState.encode(PieceProfiles.Type.PAWN, BoardState.DARK)
	game.state.set_square(5, 5, pawn)
	game.apply_move(ChessMove.new(Vector2i(5, 5), Vector2i(4, 4)))
	# Black took the white pawn, so it is the light piece code that lands here.
	_check("recapture lands on the other side's tray",
		game.captures_by(BoardState.DARK)
			== [BoardState.encode(PieceProfiles.Type.PAWN, BoardState.LIGHT)],
		str(game.captures_by(BoardState.DARK)))
	_check("both trays fill independently",
		game.captures_by(BoardState.LIGHT).size() == 1
			and game.captures_by(BoardState.DARK).size() == 1, "")

	# Material: a knight counts 3, a pawn 1.
	_check("material sums knights as 3 and pawns as 1",
		game.material_captured_by(BoardState.LIGHT) == 3
			and game.material_captured_by(BoardState.DARK) == 1,
		"light=%d dark=%d" % [game.material_captured_by(BoardState.LIGHT),
			game.material_captured_by(BoardState.DARK)])

	# A non-capturing move must not add anything. The knight hops two ranks.
	var before := game.captures_by(BoardState.LIGHT).size()
	game.state.set_square(4, 4, BoardState.encode(PieceProfiles.Type.KNIGHT, BoardState.LIGHT))
	game.apply_move(ChessMove.new(Vector2i(4, 4), Vector2i(5, 6)))
	_check("a quiet move adds no capture",
		game.captures_by(BoardState.LIGHT).size() == before, "")

	game.reset()
	_check("reset clears both trays",
		game.captures_by(BoardState.LIGHT).is_empty()
			and game.captures_by(BoardState.DARK).is_empty()
			and game.material_captured_by(BoardState.LIGHT) == 0, "")

	# Two independent games from the same moves must agree, or peers drift.
	var a := ChessGame.new()
	var b := ChessGame.new()
	for peer in [a, b]:
		peer.state.set_square(3, 4, BoardState.encode(PieceProfiles.Type.PAWN, BoardState.LIGHT))
		peer.state.set_square(3, 3, knight)
		peer.state.side_to_move = BoardState.LIGHT
		peer.apply_move(ChessMove.new(Vector2i(3, 4), Vector2i(3, 3)))
	_check("peers build identical trays from the same moves",
		a.captures_by(BoardState.LIGHT) == b.captures_by(BoardState.LIGHT), "")


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

	# 1... d5 2. exd5. A real capture: the black d-pawn comes down two and the
	# white pawn on e4 takes it. The queen on d8 cannot reach e4 on any line,
	# which with legality in place would have failed the whole funnel test.
	_check("d7-d5 applies", game.apply_move(ChessMove.new(Vector2i(3, 6), Vector2i(3, 4))),
		"")
	_check("the capture applies", game.apply_move(ChessMove.new(Vector2i(4, 3), Vector2i(3, 4))),
		"")
	_check("capture reports the victim code",
		int(emitted[2][1]) == BoardState.encode(PieceProfiles.Type.PAWN, 1),
		"captured=%d" % int(emitted[2][1]))
	_check("the taker stands on the victim square",
		BoardState.decode(game.state.at(3, 4)) == Vector2i(PieceProfiles.Type.PAWN, 0),
		"")

	# Refusals change nothing and emit nothing.
	var before := emitted.size()
	_check("empty origin refused", not game.apply_move(ChessMove.new(Vector2i(3, 3), Vector2i(3, 4))),
		"(d4 is vacant in the opening position)")
	_check("same square refused", not game.apply_move(ChessMove.new(Vector2i(3, 3), Vector2i(3, 3))),
		"")
	_check("off-board refused", not game.apply_move(ChessMove.new(Vector2i(0, 0), Vector2i(-1, 0))),
		"")
	_check("null refused", not game.apply_move(null), "")
	_check("refusals stay silent", emitted.size() == before, "")

	game.reset()
	_check("reset restores the setup", game.state.piece_count() == 32
		and game.history.is_empty() and game.state.side_to_move == BoardState.LIGHT, "")


## Failed checks, counted. The summary line is printed from this rather than
## printed regardless, because a suite that says it passed while printing failures is
## worse than no suite at all: it is believed.
var failures := 0


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		print("  ok   %s  %s" % [label, detail])
	else:
		failures += 1
		_failures += 1
		printerr("  FAIL %s  %s" % [label, detail])
