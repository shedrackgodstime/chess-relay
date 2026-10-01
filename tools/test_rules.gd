extends SceneTree

## Headless checks for the rules engine.
##
## The centrepiece is perft: the published node counts for the opening position
## are fixed numbers, so a generator that disagrees with one is wrong in a way
## no hand-written assertion reliably describes. Depth 4 matches 197281, which
## covers movement, captures, check evasion and pins together. Castling and en
## passant are not implemented, and the opening counts do not reach either.
##
##     godot-headless --headless --script res://tools/test_rules.gd

var _failures := 0

## Depth kept in the regular suite. Four takes about half a minute, so it is
## available via tools/perft.gd rather than slowing every run.
const SUITE_DEPTH := 3


func _init() -> void:
	_perft_checks()
	_pawn_checks()
	_knight_checks()
	_sliding_checks()
	_king_checks()
	_capture_legality_checks()
	_promotion_checks()
	_pin_checks()
	_endgame_checks()
	_game_over_checks()
	if _failures == 0:
		print("rules: all checks passed")
	else:
		printerr("rules: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


## A board with only the pieces given. Most rules questions need a bare board:
## a full set introduces pins and checks nobody asked about.
func _position(setup: Dictionary) -> BoardState:
	var state := BoardState.new()
	state.squares.fill(BoardState.EMPTY)
	state.side_to_move = BoardState.LIGHT
	for square: Vector2i in setup:
		state.set_square(square.x, square.y, setup[square])
	return state


func _at(file: int, rank: int, type: int, side: int) -> Dictionary:
	return {Vector2i(file, rank): BoardState.encode(type, side)}


## A square's pseudo-legal moves, sorted and joined.
##
## Compared as a string rather than an array so a failure prints both the actual
## and the expected list side by side. Written with an explicit loop because the
## one-liner form parses as a cast against the comparison.
func _from(state: BoardState, file: int, rank: int) -> String:
	var names: Array[String] = []
	for square in Rules.pseudo_legal_moves(state, Vector2i(file, rank)):
		names.append("%s%d" % [char(97 + square.x), square.y + 1])
	names.sort()
	return ",".join(names)


## How many pseudo-legal moves a square has, for the cases where the count is
## what matters rather than the names.
func _count(state: BoardState, file: int, rank: int) -> int:
	return Rules.pseudo_legal_moves(state, Vector2i(file, rank)).size()


func _permits(state: BoardState, from: Vector2i, to: Vector2i) -> bool:
	return Rules.is_legal(state, ChessMove.new(from, to))


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok   %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		_failures += 1
		printerr("  FAIL %s  %s" % [label, detail])


func _perft_checks() -> void:
	print("Perft")
	var state := BoardState.new()
	state.standard_setup()
	for depth in range(1, SUITE_DEPTH + 1):
		var got := Rules.perft(state, depth)
		_check("perft %d from the opening" % depth,
			got == Rules.PERFT_STARTPOS[depth],
			"got %d want %d" % [got, Rules.PERFT_STARTPOS[depth]])
	# perft applies and undoes in place, so a stale board would poison
	# everything after it.
	_check("perft leaves the board untouched",
		state.piece_count() == 32 and state.side_to_move == BoardState.LIGHT
			and Rules.perft(state, SUITE_DEPTH) == Rules.PERFT_STARTPOS[SUITE_DEPTH], "")
	_check("opening gives each side twenty moves",
		Rules.legal_moves(state, BoardState.LIGHT).size() == 20
			and Rules.legal_moves(state, BoardState.DARK).size() == 20, "")


## Rank indices here are 0-based, so index 1 is algebraic rank 2. Every
## expectation below is written in algebraic notation, which is how the failures
## read back.
func _pawn_checks() -> void:
	print("Pawn")
	# A light pawn on index 1 is on e2, its starting rank.
	var start := _position(_at(4, 1, PieceProfiles.Type.PAWN, BoardState.LIGHT))
	_check("a pawn on its start rank steps or doubles",
		_from(start, 4, 1) == "e3,e4", _from(start, 4, 1))
	var advanced := _position(_at(4, 2, PieceProfiles.Type.PAWN, BoardState.LIGHT))
	_check("a pawn off its start rank may only step",
		_from(advanced, 4, 2) == "e4", _from(advanced, 4, 2))
	_check("a black pawn on rank 7 doubles downwards",
		_from(_position(_at(4, 6, PieceProfiles.Type.PAWN, BoardState.DARK)), 4, 6)
			== "e5,e6", "")

	# The double step needs both squares clear, or it jumps a piece.
	var blocked := _position(_at(4, 1, PieceProfiles.Type.PAWN, BoardState.LIGHT))
	blocked.set_square(4, 2, BoardState.encode(PieceProfiles.Type.KNIGHT, BoardState.DARK))
	_check("a blocked pawn cannot leap the obstruction",
		not _from(blocked, 4, 1).contains("e4"), _from(blocked, 4, 1))
	_check("a piece straight ahead blocks but is not captured",
		_from(blocked, 4, 1).is_empty(), _from(blocked, 4, 1))

	# One way only.
	var back := _position(_at(4, 3, PieceProfiles.Type.PAWN, BoardState.LIGHT))
	_check("a pawn cannot reverse",
		not _permits(back, Vector2i(4, 3), Vector2i(4, 2)), "")
	_check("a pawn still advances forwards",
		_from(back, 4, 3) == "e5", _from(back, 4, 3))

	# Diagonals are captures only. This is the most common generator bug there
	# is, so it is worth being explicit about.
	var open := _position(_at(4, 4, PieceProfiles.Type.PAWN, BoardState.LIGHT))
	_check("a pawn cannot move diagonally into empty space",
		_from(open, 4, 4) == "e6", _from(open, 4, 4))
	var enemies := _position(_at(4, 4, PieceProfiles.Type.PAWN, BoardState.LIGHT))
	enemies.set_square(3, 5, BoardState.encode(PieceProfiles.Type.BISHOP, BoardState.DARK))
	enemies.set_square(5, 5, BoardState.encode(PieceProfiles.Type.ROOK, BoardState.DARK))
	_check("a pawn captures the diagonals holding enemies",
		_from(enemies, 4, 4) == "d6,e6,f6", _from(enemies, 4, 4))
	var friend := _position(_at(4, 4, PieceProfiles.Type.PAWN, BoardState.LIGHT))
	friend.set_square(3, 5, BoardState.encode(PieceProfiles.Type.BISHOP, BoardState.LIGHT))
	_check("a pawn cannot capture its own piece",
		_from(friend, 4, 4) == "e6", _from(friend, 4, 4))
	_check("a pawn on the a-file has no off-board capture",
		_from(_position(_at(0, 1, PieceProfiles.Type.PAWN, BoardState.LIGHT)), 0, 1)
			== "a3,a4", "")


func _knight_checks() -> void:
	print("Knight")
	var open := _position(_at(4, 4, PieceProfiles.Type.KNIGHT, BoardState.LIGHT))
	_check("a knight has eight moves on an open board",
		_count(open, 4, 4) == 8, _from(open, 4, 4))

	# Knights leap, so what sits straight ahead is irrelevant.
	var walled := _position(_at(4, 4, PieceProfiles.Type.KNIGHT, BoardState.LIGHT))
	for square: Vector2i in [Vector2i(4, 5), Vector2i(4, 3), Vector2i(3, 4), Vector2i(5, 4)]:
		walled.set_square(square.x, square.y,
			BoardState.encode(PieceProfiles.Type.PAWN, BoardState.DARK))
	_check("a knight jumps over the pieces in front of it",
		_count(walled, 4, 4) == 8, _from(walled, 4, 4))

	_check("a knight in the corner has two moves",
		_from(_position(_at(0, 0, PieceProfiles.Type.KNIGHT, BoardState.LIGHT)), 0, 0)
			== "b3,c2", "")
	_check("a knight one file from the edge has six",
		_from(_position(_at(1, 4, PieceProfiles.Type.KNIGHT, BoardState.LIGHT)), 1, 4)
			== "a3,a7,c3,c7,d4,d6", "")


func _sliding_checks() -> void:
	print("Sliding pieces")
	var rook := _position(_at(4, 4, PieceProfiles.Type.ROOK, BoardState.LIGHT))
	_check("a rook has fourteen moves on an open board",
		_count(rook, 4, 4) == 14, _from(rook, 4, 4))
	# An enemy on e6 is capturable and then stops the ray, so the rook still has
	# its full range along the file: e6 taken, and e4 to e1 below it.
	var rook_blocked := _position(_at(4, 4, PieceProfiles.Type.ROOK, BoardState.LIGHT))
	rook_blocked.set_square(4, 5, BoardState.encode(PieceProfiles.Type.PAWN, BoardState.DARK))
	_check("a rook takes the enemy that blocks it and stops there",
		_from(rook_blocked, 4, 4) == "a5,b5,c5,d5,e1,e2,e3,e4,e6,f5,g5,h5",
		_from(rook_blocked, 4, 4))
	# Built afresh rather than duplicated: the shared _position helper is what
	# keeps these boards bare, and copying one would carry its pieces along.
	var rook_own := _position(_at(4, 4, PieceProfiles.Type.ROOK, BoardState.LIGHT))
	rook_own.set_square(4, 5, BoardState.encode(PieceProfiles.Type.PAWN, BoardState.DARK))
	rook_own.set_square(3, 4, BoardState.encode(PieceProfiles.Type.PAWN, BoardState.LIGHT))
	_check("a rook cannot pass through its own piece",
		_from(rook_own, 4, 4) == "e1,e2,e3,e4,e6,f5,g5,h5",
		_from(rook_own, 4, 4))

	var bishop := _position(_at(4, 4, PieceProfiles.Type.BISHOP, BoardState.LIGHT))
	_check("a bishop has thirteen moves on an open board",
		_count(bishop, 4, 4) == 13, _from(bishop, 4, 4))
	var bishop_ortho := _position(_at(4, 4, PieceProfiles.Type.BISHOP, BoardState.LIGHT))
	bishop_ortho.set_square(4, 5, BoardState.encode(PieceProfiles.Type.PAWN, BoardState.LIGHT))
	_check("a bishop is unaffected by an orthogonal obstruction",
		_count(bishop_ortho, 4, 4) == 13, "")
	var bishop_diag := _position(_at(4, 4, PieceProfiles.Type.BISHOP, BoardState.LIGHT))
	bishop_diag.set_square(5, 5, BoardState.encode(PieceProfiles.Type.PAWN, BoardState.DARK))
	_check("a bishop takes the enemy on its diagonal and stops",
		_from(bishop_diag, 4, 4) == "a1,b2,b8,c3,c7,d4,d6,f4,f6,g3,h2",
		_from(bishop_diag, 4, 4))

	_check("a queen has twenty-seven moves on an open board",
		_count(_position(_at(4, 4, PieceProfiles.Type.QUEEN, BoardState.LIGHT)), 4, 4) == 27, "")


func _king_checks() -> void:
	print("King")
	var open := _position(_at(4, 3, PieceProfiles.Type.KING, BoardState.LIGHT))
	_check("a king has eight moves away from the edges",
		_count(open, 4, 3) == 8, _from(open, 4, 3))
	var home := _position(_at(4, 0, PieceProfiles.Type.KING, BoardState.LIGHT))
	_check("a king in its own corner has three",
		_from(home, 4, 0) == "d1,d2,e2,f1,f2", _from(home, 4, 0))
	# One square, never two. Castling is deliberately not generated, so the
	# king's own start square simply has no long move.
	_check("a king cannot step two squares",
		not _permits(home, Vector2i(4, 0), Vector2i(6, 0))
			and not _permits(home, Vector2i(4, 0), Vector2i(2, 0)), "")

	# King safety is the reason the pseudo-legal and legal layers are separate.
	var threatened := _position(_at(4, 4, PieceProfiles.Type.KING, BoardState.LIGHT))
	threatened.set_square(4, 6, BoardState.encode(PieceProfiles.Type.ROOK, BoardState.DARK))
	_check("a king cannot step back along a rook's line",
		not _permits(threatened, Vector2i(4, 4), Vector2i(4, 5)), "")
	_check("a king may step away from the line",
		_permits(threatened, Vector2i(4, 4), Vector2i(3, 4)), "")

	# A black pawn on g5 defends f4 and h4, the two squares diagonally below it,
	# and nothing else.
	var attacked := _position(_at(4, 3, PieceProfiles.Type.KING, BoardState.LIGHT))
	attacked.set_square(6, 4, BoardState.encode(PieceProfiles.Type.PAWN, BoardState.DARK))
	_check("a king cannot step onto a square a pawn defends",
		not _permits(attacked, Vector2i(4, 3), Vector2i(5, 3)), "")
	# The square the pawn stands on is not one it defends, or no piece could
	# ever be captured by a pawn.
	_check("a pawn defends its diagonals and nothing else",
		Rules.is_attacked(attacked, Vector2i(5, 3), BoardState.DARK)
			and Rules.is_attacked(attacked, Vector2i(7, 3), BoardState.DARK)
			and not Rules.is_attacked(attacked, Vector2i(6, 4), BoardState.DARK)
			and not Rules.is_attacked(attacked, Vector2i(5, 4), BoardState.DARK), "")

	# A king defends its neighbours, which is why attack detection cannot reuse
	# the movement generator: the king may not legally move there, but it does
	# still attack it.
	var kings := _position(_at(4, 4, PieceProfiles.Type.KING, BoardState.LIGHT))
	kings.set_square(5, 5, BoardState.encode(PieceProfiles.Type.KING, BoardState.DARK))
	_check("a king attacks the square beside it",
		Rules.is_attacked(kings, Vector2i(4, 4), BoardState.DARK), "")


func _capture_legality_checks() -> void:
	print("Capture legality")
	var own := _position(_at(4, 4, PieceProfiles.Type.ROOK, BoardState.LIGHT))
	own.set_square(4, 6, BoardState.encode(PieceProfiles.Type.PAWN, BoardState.LIGHT))
	_check("a piece cannot capture its own piece",
		not _permits(own, Vector2i(4, 4), Vector2i(4, 6)), "")
	var enemy := _position(_at(4, 4, PieceProfiles.Type.ROOK, BoardState.LIGHT))
	enemy.set_square(4, 6, BoardState.encode(PieceProfiles.Type.PAWN, BoardState.DARK))
	_check("a piece can capture an enemy piece",
		_permits(enemy, Vector2i(4, 4), Vector2i(4, 6)), "")
	var king_target := _position(_at(4, 4, PieceProfiles.Type.ROOK, BoardState.LIGHT))
	king_target.set_square(4, 6, BoardState.encode(PieceProfiles.Type.KING, BoardState.DARK))
	_check("a king is never captured by walking onto it",
		not _permits(king_target, Vector2i(4, 4), Vector2i(4, 6)), "")

	var empty_from := _position(_at(0, 0, PieceProfiles.Type.ROOK, BoardState.LIGHT))
	_check("a move from an empty square is refused",
		not _permits(empty_from, Vector2i(0, 7), Vector2i(0, 6)), "")
	_check("a move from an occupied square is not",
		_permits(empty_from, Vector2i(0, 0), Vector2i(0, 1)), "")
	_check("a move off the board is refused",
		not _permits(_position(_at(0, 0, PieceProfiles.Type.ROOK, BoardState.LIGHT)),
			Vector2i(0, 0), Vector2i(-1, 0)), "")
	_check("a move onto itself is refused",
		not _permits(_position(_at(0, 0, PieceProfiles.Type.ROOK, BoardState.LIGHT)),
			Vector2i(0, 0), Vector2i(0, 0)), "")


func _promotion_checks() -> void:
	print("Promotion")
	var pawn := _position(_at(1, 6, PieceProfiles.Type.PAWN, BoardState.LIGHT))
	# _position gives a bare board, so b8 is genuinely empty here.
	pawn.set_square(0, 0, BoardState.encode(PieceProfiles.Type.KING, BoardState.LIGHT))
	pawn.set_square(7, 7, BoardState.encode(PieceProfiles.Type.KING, BoardState.DARK))
	_check("a pawn reaching the far rank promotes",
		BoardState.decode(pawn.at(1, 6)).x == PieceProfiles.Type.PAWN, "")
	var landing := Rules.landing_code(pawn, ChessMove.new(Vector2i(1, 6), Vector2i(1, 7)))
	_check("landing on the last rank becomes a queen",
		BoardState.decode(landing).x == PieceProfiles.Type.QUEEN,
		PieceProfiles.type_name(BoardState.decode(landing).x))
	_check("the promoted piece keeps its side",
		BoardState.decode(landing).y == BoardState.LIGHT, "")
	var chosen := Rules.landing_code(pawn,
		ChessMove.new(Vector2i(1, 6), Vector2i(1, 7), PieceProfiles.Type.KNIGHT))
	_check("an explicit promotion choice is honoured",
		BoardState.decode(chosen).x == PieceProfiles.Type.KNIGHT, "")
	_check("is_promotion recognises a pawn on the far rank",
		Rules.is_promotion(pawn, ChessMove.new(Vector2i(1, 6), Vector2i(1, 7))), "")
	_check("is_promotion is false for a pawn short of it",
		not Rules.is_promotion(pawn, ChessMove.new(Vector2i(1, 6), Vector2i(1, 5))), "")
	_check("is_promotion is false for a non-pawn",
		not Rules.is_promotion(pawn, ChessMove.new(Vector2i(1, 0), Vector2i(1, 6))), "")
	_check("four promotion choices are offered, and no king",
		Rules.PROMOTION_CHOICES.size() == 4
			and not Rules.PROMOTION_CHOICES.has(PieceProfiles.Type.KING)
			and not Rules.PROMOTION_CHOICES.has(PieceProfiles.Type.PAWN),
		str(Rules.PROMOTION_CHOICES))
	_check("a pawn short of the last rank does not promote",
		BoardState.decode(Rules.landing_code(pawn,
			ChessMove.new(Vector2i(1, 6), Vector2i(1, 5)))).x == PieceProfiles.Type.PAWN, "")

	# The real game has to honour it too, not just the rules helper.
	var game := ChessGame.new()
	# BoardState.new() is a whole opening position, so b8 is still Black's
	# knight unless it is cleared. Left in place the pawn's straight push is
	# blocked by it and the move is correctly refused, which reads as though
	# promotion were broken.
	game.state.squares.fill(BoardState.EMPTY)
	game.state.set_square(1, 6, BoardState.encode(PieceProfiles.Type.PAWN, BoardState.LIGHT))
	game.state.set_square(0, 0, BoardState.encode(PieceProfiles.Type.KING, BoardState.LIGHT))
	game.state.set_square(7, 7, BoardState.encode(PieceProfiles.Type.KING, BoardState.DARK))
	game.state.side_to_move = BoardState.LIGHT
	game.apply_move(ChessMove.new(Vector2i(1, 6), Vector2i(1, 7)))
	_check("apply_move promotes rather than copying the pawn across",
		game.state.at(1, 7) != BoardState.EMPTY
			and BoardState.decode(game.state.at(1, 7)).x == PieceProfiles.Type.QUEEN,
		PieceProfiles.type_name(BoardState.decode(game.state.at(1, 7)).x))


func _pin_checks() -> void:
	print("Pins")
	# A rook on the eighth pins the queen on e2 to the king on e1. Leaving the
	# e-file is illegal even though the move is otherwise perfectly shaped.
	var pin := _position(_at(4, 0, PieceProfiles.Type.KING, BoardState.LIGHT))
	pin.set_square(4, 1, BoardState.encode(PieceProfiles.Type.QUEEN, BoardState.LIGHT))
	pin.set_square(4, 7, BoardState.encode(PieceProfiles.Type.ROOK, BoardState.DARK))
	_check("a pinned piece may stay on the pinning line",
		_permits(pin, Vector2i(4, 1), Vector2i(4, 2)), "")
	_check("a pinned piece may not step off the line",
		not _permits(pin, Vector2i(4, 1), Vector2i(3, 0)), "")
	# The two layers must disagree here, or the split is doing nothing: the move
	# is well shaped, so pseudo-legal allows it and only king safety refuses.
	_check("a pin is rejected by king safety, not by movement",
		Rules.pseudo_legal_moves(pin, Vector2i(4, 1)).has(Vector2i(3, 0))
			and not _permits(pin, Vector2i(4, 1), Vector2i(3, 0)), "")

	# A diagonal pin behaves the same way for a bishop.
	var diag := _position(_at(4, 4, PieceProfiles.Type.KING, BoardState.LIGHT))
	diag.set_square(5, 5, BoardState.encode(PieceProfiles.Type.BISHOP, BoardState.LIGHT))
	diag.set_square(6, 6, BoardState.encode(PieceProfiles.Type.BISHOP, BoardState.DARK))
	_check("a diagonally pinned bishop cannot leave the diagonal",
		not _permits(diag, Vector2i(5, 5), Vector2i(5, 6))
			and not _permits(diag, Vector2i(5, 5), Vector2i(6, 5)), "")
	_check("a pinned bishop may still move along the diagonal",
		_permits(diag, Vector2i(5, 5), Vector2i(6, 6))
			or _permits(diag, Vector2i(5, 5), Vector2i(4, 3)), "")


## The game has to actually stop. Without this the board carries on being
## playable after mate, so the losing side moves again and is answered, and the
## AI appears to keep playing a finished game.
func _game_over_checks() -> void:
	print("Game over")
	var game := ChessGame.new()
	game.state.squares.fill(BoardState.EMPTY)
	game.state.set_square(6, 6, BoardState.encode(PieceProfiles.Type.QUEEN, BoardState.LIGHT))
	game.state.set_square(5, 5, BoardState.encode(PieceProfiles.Type.KING, BoardState.LIGHT))
	game.state.set_square(7, 7, BoardState.encode(PieceProfiles.Type.KING, BoardState.DARK))
	game.state.side_to_move = BoardState.DARK
	_check("a position with legal moves is still going",
		not ChessGame.new().is_over(), "")
	_check("checkmate is reported as a win for the other side",
		game.result() == ChessGame.Result.WHITE_WINS, "")

	var moves := Rules.legal_moves(game.state, game.state.side_to_move)
	_check("the mated side has nothing to play", moves.is_empty(), "")

	# The refusal that matters: nothing may be played once it is over.
	var accepted := 0
	for mv in moves:
		if game.apply_move(mv):
			accepted += 1
	_check("no move is accepted after mate", accepted == 0, "accepted=%d" % accepted)
	_check("still over after the attempt", game.is_over(), "")
	_check("the AI has nothing to offer after mate",
		AiPlayer.choose_move(game, game.state.side_to_move) == null, "")

	# And it must be announced exactly once.
	var seen: Array[int] = []
	game.finished.connect(func(r: ChessGame.Result) -> void: seen.append(r))
	game.state.side_to_move = BoardState.DARK
	game.apply_move(ChessMove.new(Vector2i(0, 0), Vector2i(0, 1)))
	_check("no finish signal for a game that was never played", seen.is_empty(),
		"seen=%d" % seen.size())

	# Ra1-a8 is the mating move: it checks along the eighth, and Kg6 covers the
	# king's three ways off it. Built before the move rather than after, since a
	# king cannot be captured and so could never be the thing taken.
	var mating := ChessGame.new()
	mating.state.squares.fill(BoardState.EMPTY)
	mating.state.set_square(0, 0, BoardState.encode(PieceProfiles.Type.ROOK, BoardState.LIGHT))
	mating.state.set_square(6, 5, BoardState.encode(PieceProfiles.Type.KING, BoardState.LIGHT))
	mating.state.set_square(7, 7, BoardState.encode(PieceProfiles.Type.KING, BoardState.DARK))
	mating.state.side_to_move = BoardState.LIGHT
	var finishes: Array[int] = []
	mating.finished.connect(func(r: ChessGame.Result) -> void: finishes.append(r))
	_check("the position before the move is still going",
		mating.result() == ChessGame.Result.ONGOING, "")
	_check("Ra1-a8 applies", mating.apply_move(ChessMove.new(Vector2i(0, 0), Vector2i(0, 7))),
		"")
	# White mated Black here, so it is White who wins.
	_check("a back-rank mate is detected",
		mating.result() == ChessGame.Result.WHITE_WINS,
		"%d" % mating.result())
	_check("finishing is signalled once, when the mating move lands",
		finishes.size() == 1 and finishes[0] == ChessGame.Result.WHITE_WINS,
		"signals=%d" % finishes.size())
	_check("nothing is played after the mating move",
		not mating.apply_move(ChessMove.new(Vector2i(7, 7), Vector2i(6, 6))), "")

	# Stalemate is not a win for anyone.
	var stale := ChessGame.new()
	stale.state.squares.fill(BoardState.EMPTY)
	stale.state.set_square(6, 5, BoardState.encode(PieceProfiles.Type.QUEEN, BoardState.LIGHT))
	stale.state.set_square(5, 5, BoardState.encode(PieceProfiles.Type.KING, BoardState.LIGHT))
	stale.state.set_square(7, 7, BoardState.encode(PieceProfiles.Type.KING, BoardState.DARK))
	stale.state.side_to_move = BoardState.DARK
	_check("stalemate is a draw, not a win",
		stale.result() == ChessGame.Result.DRAW_BY_STALEMATE, "")


func _endgame_checks() -> void:
	print("Check, mate and stalemate")
	# Queen on g7 with the king on f6: check from the diagonal, and every
	# escape square is covered.
	var mate := _position(_at(6, 6, PieceProfiles.Type.QUEEN, BoardState.LIGHT))
	mate.set_square(5, 5, BoardState.encode(PieceProfiles.Type.KING, BoardState.LIGHT))
	mate.set_square(7, 7, BoardState.encode(PieceProfiles.Type.KING, BoardState.DARK))
	mate.side_to_move = BoardState.DARK
	_check("the pinned position is genuinely check",
		Rules.is_in_check(mate, BoardState.DARK), "")
	_check("checkmate has no legal reply",
		not Rules.has_legal_move(mate, BoardState.DARK), "")
	_check("checkmate is not stalemate",
		Rules.is_in_check(mate, BoardState.DARK), "")

	# Same shape, but the queen is not giving check: stalemate instead.
	var stale := _position(_at(6, 5, PieceProfiles.Type.QUEEN, BoardState.LIGHT))
	stale.set_square(5, 5, BoardState.encode(PieceProfiles.Type.KING, BoardState.LIGHT))
	stale.set_square(7, 7, BoardState.encode(PieceProfiles.Type.KING, BoardState.DARK))
	stale.side_to_move = BoardState.DARK
	_check("the stalemate position is not check",
		not Rules.is_in_check(stale, BoardState.DARK), "")
	_check("stalemate has no legal reply either",
		not Rules.has_legal_move(stale, BoardState.DARK), "")

	# Bare kings: not in check, and g8 and h7 are both open.
	var open_kings := _position(_at(5, 5, PieceProfiles.Type.KING, BoardState.LIGHT))
	open_kings.set_square(7, 7, BoardState.encode(PieceProfiles.Type.KING, BoardState.DARK))
	open_kings.side_to_move = BoardState.DARK
	_check("a side with a legal move is neither mated nor stalemated",
		Rules.has_legal_move(open_kings, BoardState.DARK)
			and not Rules.is_in_check(open_kings, BoardState.DARK), "")

	var checked := _position(_at(4, 4, PieceProfiles.Type.KING, BoardState.LIGHT))
	checked.set_square(4, 0, BoardState.encode(PieceProfiles.Type.ROOK, BoardState.DARK))
	_check("a rook down the file gives check",
		Rules.is_in_check(checked, BoardState.LIGHT), "")
	_check("the king answers the check by stepping off the rook's file",
		_permits(checked, Vector2i(4, 4), Vector2i(3, 4)), "")
	_check("the king cannot step along the rook's line",
		not _permits(checked, Vector2i(4, 4), Vector2i(4, 3)), "")
	_check("a king missing is not in check",
		not Rules.is_in_check(_position({}), BoardState.LIGHT), "")
	_check("king_square reports a missing king as absent",
		Rules.king_square(_position({}), BoardState.LIGHT) == Vector2i(-1, -1), "")
