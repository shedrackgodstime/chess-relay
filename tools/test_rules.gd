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
	_special_rules_checks()
	_pawn_checks()
	_knight_checks()
	_sliding_checks()
	_king_checks()
	_capture_legality_checks()
	_promotion_checks()
	_pin_checks()
	_endgame_checks()
	_game_over_checks()
	_draw_checks()
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


## The three draw rules, which are three different kinds of thing: a dead
## position is about material and is automatic, while repetition and the
## fifty-move rule are about history and are claims in the real rules that a
## player has to make. This game treats all three as automatic.
func _draw_checks() -> void:
	print("Draw rules")

	# --- dead positions ---
	_check("bare kings cannot mate", _dead({
		Vector2i(0, 0): _dp(PieceProfiles.Type.KING, BoardState.LIGHT),
		Vector2i(7, 7): _dp(PieceProfiles.Type.KING, BoardState.DARK)}), "")
	_check("king and knight cannot mate", _dead({
		Vector2i(0, 0): _dp(PieceProfiles.Type.KING, BoardState.LIGHT),
		Vector2i(7, 7): _dp(PieceProfiles.Type.KING, BoardState.DARK),
		Vector2i(1, 1): _dp(PieceProfiles.Type.KNIGHT, BoardState.LIGHT)}), "")
	_check("king and bishop cannot mate", _dead({
		Vector2i(0, 0): _dp(PieceProfiles.Type.KING, BoardState.LIGHT),
		Vector2i(7, 7): _dp(PieceProfiles.Type.KING, BoardState.DARK),
		Vector2i(1, 1): _dp(PieceProfiles.Type.BISHOP, BoardState.LIGHT)}), "")
	_check("two knights against a bare king cannot force mate", _dead({
		Vector2i(0, 0): _dp(PieceProfiles.Type.KING, BoardState.LIGHT),
		Vector2i(7, 7): _dp(PieceProfiles.Type.KING, BoardState.DARK),
		Vector2i(1, 1): _dp(PieceProfiles.Type.KNIGHT, BoardState.LIGHT),
		Vector2i(2, 1): _dp(PieceProfiles.Type.KNIGHT, BoardState.LIGHT)}), "")
	_check("a knight on each side can be won", not _dead({
		Vector2i(0, 0): _dp(PieceProfiles.Type.KING, BoardState.LIGHT),
		Vector2i(7, 7): _dp(PieceProfiles.Type.KING, BoardState.DARK),
		Vector2i(1, 1): _dp(PieceProfiles.Type.KNIGHT, BoardState.LIGHT),
		Vector2i(6, 5): _dp(PieceProfiles.Type.KNIGHT, BoardState.DARK)}), "")
	# Two bishops of the same colour are the classic dead pair. Of opposite
	# colours they can cross-check and mate.
	_check("bishops on the same colour of square are dead", _dead({
		Vector2i(0, 0): _dp(PieceProfiles.Type.KING, BoardState.LIGHT),
		Vector2i(7, 7): _dp(PieceProfiles.Type.KING, BoardState.DARK),
		Vector2i(1, 1): _dp(PieceProfiles.Type.BISHOP, BoardState.LIGHT),
		Vector2i(2, 2): _dp(PieceProfiles.Type.BISHOP, BoardState.DARK)}), "")
	_check("bishops on opposite colours can mate", not _dead({
		Vector2i(0, 0): _dp(PieceProfiles.Type.KING, BoardState.LIGHT),
		Vector2i(7, 7): _dp(PieceProfiles.Type.KING, BoardState.DARK),
		Vector2i(1, 1): _dp(PieceProfiles.Type.BISHOP, BoardState.LIGHT),
		Vector2i(2, 1): _dp(PieceProfiles.Type.BISHOP, BoardState.DARK)}), "")
	_check("a rook is enough material", not _dead({
		Vector2i(0, 0): _dp(PieceProfiles.Type.KING, BoardState.LIGHT),
		Vector2i(7, 7): _dp(PieceProfiles.Type.KING, BoardState.DARK),
		Vector2i(1, 1): _dp(PieceProfiles.Type.ROOK, BoardState.LIGHT)}), "")
	_check("knight and bishop together can mate", not _dead({
		Vector2i(0, 0): _dp(PieceProfiles.Type.KING, BoardState.LIGHT),
		Vector2i(7, 7): _dp(PieceProfiles.Type.KING, BoardState.DARK),
		Vector2i(1, 1): _dp(PieceProfiles.Type.KNIGHT, BoardState.LIGHT),
		Vector2i(2, 1): _dp(PieceProfiles.Type.BISHOP, BoardState.LIGHT)}), "")

	var dead_game := ChessGame.new()
	dead_game.load_position(_position({
		Vector2i(0, 0): _dp(PieceProfiles.Type.KING, BoardState.LIGHT),
		Vector2i(7, 7): _dp(PieceProfiles.Type.KING, BoardState.DARK)}))
	_check("a dead position ends the game whatever else is true",
		dead_game.result() == ChessGame.Result.DRAW_BY_INSUFFICIENT_MATERIAL,
		"result=%d" % dead_game.result())

	# --- repetition ---
	# Shuffling both knights out and back twice brings the opening position round
	# for a third time.
	var game := ChessGame.new()
	var opening := BoardState.new()
	opening.standard_setup()
	game.load_position(opening)
	var key: int = game.state.repetition_key()
	_check("the opening is counted once",
		game.position_counts.size() == 1 and int(game.position_counts.get(key, 0)) == 1,
		"size=%d" % game.position_counts.size())
	# One out-and-back for both knights, which is four moves and returns the board
	# to the opening.
	var cycle := [
		Vector2i(6, 0), Vector2i(5, 2), Vector2i(6, 7), Vector2i(5, 5),
		Vector2i(5, 2), Vector2i(6, 0), Vector2i(5, 5), Vector2i(6, 7)]
	var all_applied := _shuffle_cycle(game, cycle)
	_check("the knight shuffle applies", all_applied, "")
	_check("not yet a draw after the first cycle",
		game.result() == ChessGame.Result.ONGOING, "result=%d" % game.result())
	_check("the opening has been seen twice",
		int(game.position_counts.get(key, 0)) == 2,
		"seen=%d" % int(game.position_counts.get(key, 0)))
	_shuffle_cycle(game, cycle)
	_check("the opening has been seen three times",
		int(game.position_counts.get(key, 0)) == 3,
		"seen=%d" % int(game.position_counts.get(key, 0)))
	_check("threefold repetition is a draw",
		game.result() == ChessGame.Result.DRAW_BY_REPETITION,
		"result=%d" % game.result())
	_check("and nothing more may be played",
		not game.apply_move(ChessMove.new(Vector2i(6, 0), Vector2i(5, 2))), "")

	# Two positions differing only by an en passant square nothing can use are the
	# same position and must not count as different. With an enemy pawn beside it
	# the capture exists, and they differ.
	var plain := _position({
		Vector2i(0, 0): _dp(PieceProfiles.Type.KING, BoardState.LIGHT),
		Vector2i(7, 7): _dp(PieceProfiles.Type.KING, BoardState.DARK),
		Vector2i(1, 1): _dp(PieceProfiles.Type.PAWN, BoardState.LIGHT),
		Vector2i(2, 1): _dp(PieceProfiles.Type.PAWN, BoardState.DARK)})
	var unusable := plain.duplicate() as BoardState
	unusable.en_passant_square = Vector2i(1, 3)
	_check("an en passant square nothing can use is ignored for repetition",
		unusable.repetition_key() == plain.repetition_key(), "")
	var usable := plain.duplicate() as BoardState
	usable.set_square(2, 2, _dp(PieceProfiles.Type.PAWN, BoardState.DARK))
	usable.en_passant_square = Vector2i(1, 3)
	_check("one that can be used is not ignored",
		usable.repetition_key() != plain.repetition_key(), "")

	# --- fifty-move rule ---
	var quiet := ChessGame.new()
	quiet.load_position(_position({
		Vector2i(0, 0): _dp(PieceProfiles.Type.KING, BoardState.LIGHT),
		Vector2i(7, 7): _dp(PieceProfiles.Type.KING, BoardState.DARK),
		Vector2i(0, 1): _dp(PieceProfiles.Type.ROOK, BoardState.LIGHT),
		Vector2i(7, 6): _dp(PieceProfiles.Type.ROOK, BoardState.DARK)}))
	_check("no draw with plenty of material on the board",
		quiet.result() == ChessGame.Result.ONGOING, "")
	quiet.halfmove_clock = 99
	_check("not yet at a hundred half-moves",
		quiet.result() == ChessGame.Result.ONGOING, "clock=%d" % quiet.halfmove_clock)
	quiet.halfmove_clock = 100
	_check("a hundred half-moves without progress is a draw",
		quiet.result() == ChessGame.Result.DRAW_BY_FIFTY_MOVE,
		"result=%d" % quiet.result())
	# Checkmate outranks it: a mating move that also completes fifty moves is a mate.
	var mating := ChessGame.new()
	mating.load_position(_back_rank_mate())
	mating.halfmove_clock = 200
	_check("checkmate outranks the fifty-move rule",
		mating.result() == ChessGame.Result.WHITE_WINS,
		"result=%d" % mating.result())

	var clock := ChessGame.new()
	clock.load_position(opening)
	_check("the clock starts at zero", clock.halfmove_clock == 0, "")
	clock.apply_move(ChessMove.new(Vector2i(4, 1), Vector2i(4, 3)))
	_check("a pawn move resets it", clock.halfmove_clock == 0,
		"clock=%d" % clock.halfmove_clock)
	clock.apply_move(ChessMove.new(Vector2i(4, 7), Vector2i(4, 5)))
	_check("a quiet move counts one", clock.halfmove_clock == 1,
		"clock=%d" % clock.halfmove_clock)
	clock.apply_move(ChessMove.new(Vector2i(6, 0), Vector2i(5, 2)))
	clock.apply_move(ChessMove.new(Vector2i(5, 7), Vector2i(6, 5)))
	_check("and keeps counting", clock.halfmove_clock == 3,
		"clock=%d" % clock.halfmove_clock)
	clock.apply_move(ChessMove.new(Vector2i(4, 5), Vector2i(5, 5)))
	_check("a capture resets it", clock.halfmove_clock == 0,
		"clock=%d" % clock.halfmove_clock)


## Plays a flat list of squares as from/to pairs, reporting whether they all
## applied so one refusal does not cascade into a wall of failures.
func _shuffle_cycle(game: ChessGame, squares: Array) -> bool:
	var all_applied := true
	for i in range(0, squares.size(), 2):
		if not game.apply_move(ChessMove.new(squares[i], squares[i + 1])):
			all_applied = false
	return all_applied


## Whether the position has too little material to mate.
func _dead(setup: Dictionary) -> bool:
	return Rules.has_insufficient_material(_position(setup))


## One encoded piece, since the bare-board helper takes plain integers.
func _dp(type: int, side: int) -> int:
	return BoardState.encode(type, side)


## White king e1 and rook a1, black king e8 and rook h8, white to move, so that
## Ra1xa8 is mate. The same rook is the piece whose capture resets the clock.
func _back_rank_mate() -> BoardState:
	return _position({
		Vector2i(4, 0): _dp(PieceProfiles.Type.KING, BoardState.LIGHT),
		Vector2i(0, 0): _dp(PieceProfiles.Type.ROOK, BoardState.LIGHT),
		Vector2i(4, 7): _dp(PieceProfiles.Type.KING, BoardState.DARK),
		Vector2i(7, 7): _dp(PieceProfiles.Type.ROOK, BoardState.DARK)})

func _perft_checks() -> void:
	print("Perft")
	var state := BoardState.new()
	state.standard_setup()
	for depth in range(1, SUITE_DEPTH + 1):
		var got: int = kiwipete_perft(state, depth)
		_check("perft %d from the opening" % depth,
			got == ChessGame.PERFT_STARTPOS[depth],
			"got %d want %d" % [got, ChessGame.PERFT_STARTPOS[depth]])
	# perft applies and undoes in place, so a stale board would poison
	# everything after it.
	_check("perft leaves the board untouched",
		state.piece_count() == 32 and state.side_to_move == BoardState.LIGHT
			and kiwipete_perft(state, SUITE_DEPTH)
				== ChessGame.PERFT_STARTPOS[SUITE_DEPTH], "")
	_check("opening gives each side twenty moves",
		Rules.legal_moves(state, BoardState.LIGHT).size() == 20
			and Rules.legal_moves(state, BoardState.DARK).size() == 20, "")


## Rank indices here are 0-based, so index 1 is algebraic rank 2. Every
## expectation below is written in algebraic notation, which is how the failures
## read back.
## Castling and en passant, checked against the published perft positions for
## them rather than against hand-built positions. Every hand-written chess
## fixture in this project has been wrong at least once.
func _special_rules_checks() -> void:
	print("Castling and en passant")
	# Kiwipete: castling both ways, pins, and pieces that must not be.
	var kiwipete := BoardState.new()
	_check("Kiwipete parses",
		kiwipete.from_fen(
			"r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"), "")
	_check("FEN round-trips", kiwipete.to_fen().begins_with(
		"r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq"), kiwipete.to_fen())
	_check("castling rights come back from FEN",
		kiwipete.castling_rights == BoardState.ALL_CASTLING,
		"rights=%d" % kiwipete.castling_rights)
	_check("both sides can castle from Kiwipete",
		Rules.can_castle_kingside(kiwipete, BoardState.LIGHT)
			and Rules.can_castle_queenside(kiwipete, BoardState.LIGHT)
			and Rules.can_castle_kingside(kiwipete, BoardState.DARK)
			and Rules.can_castle_queenside(kiwipete, BoardState.DARK), "")
	_check("Kiwipete perft 1 is 48", kiwipete_perft(kiwipete, 1) == 48,
		"got=%d" % kiwipete_perft(kiwipete, 1))
	_check("Kiwipete perft 2 is 2039", kiwipete_perft(kiwipete, 2) == 2039,
		"got=%d" % kiwipete_perft(kiwipete, 2))

	# Position 3: en passant, and a pin that a naive generator gets wrong.
	var ep := BoardState.new()
	_check("the en passant position parses",
		ep.from_fen("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1"), "")
	_check("en passant perft 1 is 14", kiwipete_perft(ep, 1) == 14,
		"got=%d" % kiwipete_perft(ep, 1))
	_check("en passant perft 2 is 191", kiwipete_perft(ep, 2) == 191,
		"got=%d" % kiwipete_perft(ep, 2))
	_check("en passant perft 3 is 2812", kiwipete_perft(ep, 3) == 2812,
		"got=%d" % kiwipete_perft(ep, 3))

	# The bug that position 3 exists to catch, stated on its own so the reason
	# survives. An en passant capture moves two pieces off the board: the one
	# being captured and the one doing the capturing. Simulating only the second
	# left a shield in place and let the capture through.
	var pinned := BoardState.new()
	pinned.squares.fill(BoardState.EMPTY)
	pinned.set_square(0, 4, BoardState.encode(PieceProfiles.Type.KING, BoardState.DARK))
	pinned.set_square(7, 4, BoardState.encode(PieceProfiles.Type.ROOK, BoardState.LIGHT))
	pinned.set_square(1, 4, BoardState.encode(PieceProfiles.Type.PAWN, BoardState.LIGHT))
	pinned.set_square(2, 4, BoardState.encode(PieceProfiles.Type.PAWN, BoardState.DARK))
	pinned.set_square(2, 3, BoardState.encode(PieceProfiles.Type.PAWN, BoardState.LIGHT))
	pinned.side_to_move = BoardState.DARK
	pinned.en_passant_square = Vector2i(2, 3)
	_check("an en passant capture that exposes the king along a rank is refused",
		not Rules.is_legal(pinned, ChessMove.new(Vector2i(2, 4), Vector2i(2, 3))), "")

	# Castling actually moving the rook, and costing the right.
	var game := ChessGame.new()
	game.state.squares.fill(BoardState.EMPTY)
	game.state.set_square(4, 0, BoardState.encode(PieceProfiles.Type.KING, BoardState.LIGHT))
	game.state.set_square(7, 0, BoardState.encode(PieceProfiles.Type.ROOK, BoardState.LIGHT))
	game.state.set_square(4, 7, BoardState.encode(PieceProfiles.Type.KING, BoardState.DARK))
	game.state.set_square(0, 7, BoardState.encode(PieceProfiles.Type.ROOK, BoardState.DARK))
	game.state.side_to_move = BoardState.LIGHT
	_check("O-O is offered on an empty kingside",
		Rules.is_legal(game.state, ChessMove.new(Vector2i(4, 0), Vector2i(6, 0))), "")
	_check("O-O applies", game.apply_move(ChessMove.new(Vector2i(4, 0), Vector2i(6, 0))), "")
	_check("the king lands on g1",
		BoardState.decode(game.state.at(6, 0)) == Vector2i(PieceProfiles.Type.KING, BoardState.LIGHT), "")
	_check("the rook moves to f1 too",
		BoardState.decode(game.state.at(5, 0)) == Vector2i(PieceProfiles.Type.ROOK, BoardState.LIGHT)
			and game.state.at(7, 0) == BoardState.EMPTY, "")
	_check("castling right is spent, both ways",
		game.state.castling_rights == BoardState.CASTLE_DARK_KINGSIDE
			| BoardState.CASTLE_DARK_QUEENSIDE,
		"rights=%d" % game.state.castling_rights)
	_check("the king cannot castle again",
		not Rules.can_castle_kingside(game.state, BoardState.LIGHT), "")

	# Castling through an attacked square is the case is_legal alone would miss.
	var blocked := BoardState.new()
	blocked.squares.fill(BoardState.EMPTY)
	blocked.set_square(4, 0, BoardState.encode(PieceProfiles.Type.KING, BoardState.LIGHT))
	blocked.set_square(7, 0, BoardState.encode(PieceProfiles.Type.ROOK, BoardState.LIGHT))
	blocked.set_square(4, 7, BoardState.encode(PieceProfiles.Type.KING, BoardState.DARK))
	# A rook on f8, which is the square the king crosses on the way to g1. A
	# bishop would have to sit on the diagonal to attack f1 and would not.
	blocked.set_square(5, 7, BoardState.encode(PieceProfiles.Type.ROOK, BoardState.DARK))
	blocked.side_to_move = BoardState.LIGHT
	_check("a king cannot castle through an attacked square",
		not Rules.is_legal(blocked, ChessMove.new(Vector2i(4, 0), Vector2i(6, 0))), "")
	_check("the right survives a castle that was refused",
		Rules.can_castle_kingside(blocked, BoardState.LIGHT), "")

	# En passant, from a position built so the geometry is unambiguous.
	var ep_game := ChessGame.new()
	ep_game.state.squares.fill(BoardState.EMPTY)
	ep_game.state.set_square(4, 4, BoardState.encode(PieceProfiles.Type.PAWN, BoardState.LIGHT))
	ep_game.state.set_square(3, 6, BoardState.encode(PieceProfiles.Type.PAWN, BoardState.DARK))
	ep_game.state.set_square(0, 0, BoardState.encode(PieceProfiles.Type.KING, BoardState.LIGHT))
	ep_game.state.set_square(7, 7, BoardState.encode(PieceProfiles.Type.KING, BoardState.DARK))
	ep_game.state.side_to_move = BoardState.LIGHT
	_check("no en passant before the double step",
		ep_game.state.en_passant_square == Vector2i(-1, -1)
			and not Rules.pseudo_legal_moves(ep_game.state, Vector2i(4, 4)).has(Vector2i(3, 5)), "")
	ep_game.state.side_to_move = BoardState.DARK
	ep_game.apply_move(ChessMove.new(Vector2i(3, 6), Vector2i(3, 4)))
	_check("a double step records the square behind the pawn",
		ep_game.state.en_passant_square == Vector2i(3, 5),
		"ep=%s" % ep_game.state.en_passant_square)
	_check("the enemy pawn may now take en passant",
		Rules.is_legal(ep_game.state, ChessMove.new(Vector2i(4, 4), Vector2i(3, 5))), "")
	_check("the capture applies", ep_game.apply_move(ChessMove.new(Vector2i(4, 4), Vector2i(3, 5))), "")
	_check("the pawn lands on the square it skipped to",
		BoardState.decode(ep_game.state.at(3, 5))
			== Vector2i(PieceProfiles.Type.PAWN, BoardState.LIGHT), "")
	_check("the taken pawn is removed from where it stood, not where it was taken",
		ep_game.state.at(3, 4) == BoardState.EMPTY and ep_game.state.at(4, 4) == BoardState.EMPTY, "")
	_check("it is recorded as a capture",
		ep_game.captures_by(BoardState.LIGHT).size() == 1, "")
	_check("the en passant square is cleared afterwards",
		ep_game.state.en_passant_square == Vector2i(-1, -1), "")

	# Position state has to travel, or two peers disagree about a game they both
	# think they are playing.
	var carrier := ChessGame.new()
	carrier.state.from_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	carrier.state.en_passant_square = Vector2i(4, 5)
	var payload := carrier.state.to_array()
	var restored := BoardState.new()
	_check("castling rights and the en passant square survive a snapshot",
		restored.from_array(payload)
			and restored.castling_rights == carrier.state.castling_rights
			and restored.en_passant_square == carrier.state.en_passant_square
			and restored.hash() == carrier.state.hash(),
		"rights=%d ep=%s" % [restored.castling_rights, restored.en_passant_square])


## perft for an arbitrary position, on a fresh game seeded from it.
func kiwipete_perft(state: BoardState, depth: int) -> int:
	# Seeded through the snapshot rather than duplicate(), which errors on this
	# type, and which exercises the same path a peer's resync takes.
	var game := ChessGame.new()
	game.state.from_array(state.to_array())
	var nodes: int = game.perft(depth)
	return nodes


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
