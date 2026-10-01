class_name ChessGame
extends RefCounted

## The authoritative game: owns the board state and every move ever applied.
##
## This is THE funnel. Taps, the AI and (later) network peers all submit
## ChessMoves here; views and replication only ever react to the `moved`
## signal. Because state is plain data and application is deterministic, two
## P2P peers applying the same move sequence converge — neither side is
## special, which a server-authoritative design would not guarantee.
##
## No legality yet, by project order: apply_move currently accepts any
## well-formed move. is_legal() is the seam where the rules engine plugs in
## without touching callers.

signal moved(move: ChessMove, captured: int)

## Emitted once, when the game stops being playable.
signal finished(result: Result)

## Why the game is or is not still going. Stalemate is the only draw recognised
## so far; threefold, fifty-move and insufficient material are still owed.
enum Result {
	ONGOING,
	WHITE_WINS,
	BLACK_WINS,
	DRAW_BY_STALEMATE,
}

var state := BoardState.new()
var history: Array[ChessMove] = []

## Piece codes taken by each side, in the order they fell. Tracked as data
## derived from the move sequence rather than pushed in by the view, so two
## P2P peers applying the same moves build identical trays without any extra
## replication.
##
## Two explicitly typed arrays rather than a Dictionary keyed by side: a
## Dictionary lookup yields an untyped Array, which cannot satisfy an
## Array[int] return and fails at runtime instead of at parse time.
var captured_by_light: Array[int] = []
var captured_by_dark: Array[int] = []


func reset() -> void:
	state = BoardState.new()
	history.clear()
	captured_by_light = []
	captured_by_dark = []
	_finished = false


## Pieces this side has taken, oldest first.
func captures_by(side: int) -> Array[int]:
	return captured_by_light if side == BoardState.LIGHT else captured_by_dark


## Total material captured by a side, counting pawns as 1 and the rest as 3.
## Chess does not score this way, but the number a player expects to compare
## is the simple sum, and the rules engine can revise it later.
func material_captured_by(side: int) -> int:
	var total := 0
	for code in captures_by(side):
		total += 1 if BoardState.decode(code).x == PieceProfiles.Type.PAWN else 3
	return total


## Applies a move: validates shape, delegates legality, mutates state,
## records history, notifies. Returns false for anything it refuses, in
## which case nothing changes and nothing emits.
func apply_move(move: ChessMove) -> bool:
	if move == null:
		return false
	if not BoardState.is_inside(move.from_square.x, move.from_square.y):
		return false
	if not BoardState.is_inside(move.to_square.x, move.to_square.y):
		return false
	if move.from_square == move.to_square:
		return false
	if state.at(move.from_square.x, move.from_square.y) == BoardState.EMPTY:
		return false
	# A finished game accepts nothing further. Without this the board carries on
	# being playable after mate, so the losing side could move again and be
	# answered, and nothing ever looked like an ending.
	if result() != Result.ONGOING:
		return false
	if not is_legal(move):
		return false

	# Read before anything is written. The castling bookkeeping below needs to know
	# what was moving, and by then the origin square has been cleared.
	var moving := BoardState.decode(state.at(move.from_square.x, move.from_square.y))

	# En passant is the one capture that does not land on the victim. The square
	# being moved onto is empty; the pawn is beside it.
	var captured := state.at(move.to_square.x, move.to_square.y)
	var is_en_passant := captured == BoardState.EMPTY \
		and moving.x == PieceProfiles.Type.PAWN \
		and move.to_square == state.en_passant_square
	if is_en_passant:
		captured = state.at(move.to_square.x, move.from_square.y)
	# Recorded before the side flip, since captures_by is keyed by the taker.
	if captured != BoardState.EMPTY:
		# Before the side flip below, so this is still the capturing side.
		if state.side_to_move == BoardState.LIGHT:
			captured_by_light.append(captured)
		else:
			captured_by_dark.append(captured)
	# Through the rules rather than copied across, so a pawn reaching the far
	# rank actually promotes instead of arriving as a pawn that can never move
	# again.
	var landing := Rules.landing_code(state, move)
	state.set_square(move.from_square.x, move.from_square.y, BoardState.EMPTY)
	state.set_square(move.to_square.x, move.to_square.y, landing)

	if is_en_passant:
		# The captured pawn is beside the mover, on the mover's own rank.
		state.set_square(move.to_square.x, move.from_square.y, BoardState.EMPTY)

	_update_castling_rights(move, captured, moving)
	if _is_castling(move, moving):
		# Castling moves a rook too. Missing this leaves the board with a king on
		# g1 and a rook still on h1, which looks like a legal position and is not
		# one.
		var side := moving.y
		var kingside: bool = move.to_square.x > move.from_square.x
		var rook_from: Vector2i = BoardState.ROOK_HOME[side][kingside]
		var rook_to := Vector2i(move.to_square.x - 1 if kingside else move.to_square.x + 1,
			move.from_square.y)
		var rook_code := state.at(rook_from.x, rook_from.y)
		state.set_square(rook_from.x, rook_from.y, BoardState.EMPTY)
		state.set_square(rook_to.x, rook_to.y, rook_code)

	# The en-passant square is set by a two-square pawn push and cleared by
	# everything else. Set on every double push rather than only when a capture is
	# actually available: the extra square is harmless, and testing availability
	# would mean generating moves to answer a question the board does not ask.
	if moving.x == PieceProfiles.Type.PAWN \
			and absi(move.to_square.y - move.from_square.y) == 2:
		state.en_passant_square = Vector2i(move.from_square.x,
			(move.from_square.y + move.to_square.y) / 2)
	else:
		state.en_passant_square = Vector2i(-1, -1)
	state.side_to_move = BoardState.DARK if state.side_to_move == BoardState.LIGHT else BoardState.LIGHT
	history.append(move)
	moved.emit(move, captured)
	if result() != Result.ONGOING and not _finished:
		_finished = true
		finished.emit(result())
	return true


var _finished := false


## Legality, delegated to the rules engine.
##
## This stayed a stub returning true until now so the visual prototype could
## move pieces freely while the view was being built. Everything that needs to
## know whether a move is allowed — apply_move, the AI's choice, and later a
## network peer's validation — comes through here, so there is one place that
## decides.
func is_legal(move: ChessMove) -> bool:
	return Rules.is_legal(state, move)


## Whether the game is still playable, and if not, how it ended.
##
## Decided on demand from the position rather than recorded as events, so it
## cannot fall out of step with the board the way an incrementally tracked flag
## would. The side to move having nothing left is the end of it: in check is
## checkmate, not in check is stalemate.
func result() -> Result:
	if Rules.has_legal_move(state, state.side_to_move):
		return Result.ONGOING
	if not Rules.is_in_check(state, state.side_to_move):
		return Result.DRAW_BY_STALEMATE
	return Result.WHITE_WINS if state.side_to_move == BoardState.DARK \
		else Result.BLACK_WINS


func is_over() -> bool:
	return result() != Result.ONGOING


## A king moving exactly two files from its home square, which is the only way a
## castle can be expressed. Derived from the move rather than carried as a flag,
## so the network format does not have to agree on an extra field.
func _is_castling(move: ChessMove, moving: Vector2i) -> bool:
	return moving.x == PieceProfiles.Type.KING \
		and absi(move.to_square.x - move.from_square.x) == 2


## The two castling bits belonging to a side.
static func king_rights(side: int) -> int:
	if side == BoardState.LIGHT:
		return BoardState.CASTLE_WHITE_KINGSIDE | BoardState.CASTLE_WHITE_QUEENSIDE
	return BoardState.CASTLE_DARK_KINGSIDE | BoardState.CASTLE_DARK_QUEENSIDE


## The one castling bit for a side and a rook.
static func rook_right(side: int, kingside: bool) -> int:
	if side == BoardState.LIGHT:
		if kingside:
			return BoardState.CASTLE_WHITE_KINGSIDE
		return BoardState.CASTLE_WHITE_QUEENSIDE
	if kingside:
		return BoardState.CASTLE_DARK_KINGSIDE
	return BoardState.CASTLE_DARK_QUEENSIDE


## Castling rights are lost when the king moves, when a rook leaves its home
## square, or when one is captured there. Any of the three loses the right for
## good, which is why this clears bits rather than counting them.
func _update_castling_rights(move: ChessMove, captured: int, moving: Vector2i) -> void:
	if moving.x == PieceProfiles.Type.KING:
		state.castling_rights &= ~king_rights(moving.y)
	for kingside in [true, false]:
		var home: Vector2i = BoardState.ROOK_HOME[moving.y][kingside]
		var rook_left := move.from_square == home
		var rook_taken := captured != BoardState.EMPTY and move.to_square == home
		if rook_left or rook_taken:
			state.castling_rights &= ~rook_right(moving.y, kingside)


## Node counts for the opening position, which are published constants rather
## than anything this code chose.
const PERFT_STARTPOS := {1: 20, 2: 400, 3: 8902, 4: 197281, 5: 4865609}


## Counts the leaf nodes reachable in exactly `depth` plies.
##
## The standard correctness check for a move generator, and the reason it lives
## here rather than in a test file: the published node counts are fixed numbers,
## so a generator that disagrees with one is wrong in a way no hand-written
## assertion will reliably describe.
##
## It goes through apply_move rather than writing to the board directly, which is
## the whole point. An earlier version had its own applier and reported 2038 on
## Kiwipete against a true 2039, because it never moved the rook on a castling
## move. A check that shares no code with the thing it checks will happily pass
## while the game is broken.
func perft(depth: int) -> int:
	if depth <= 0:
		return 1
	var moves := legal_moves()
	if depth == 1:
		return moves.size()
	var saved := _snapshot()
	var nodes := 0
	for move in moves:
		if apply_move(move):
			nodes += perft(depth - 1)
		_restore(saved)
	return nodes


## Everything apply_move touches, so perft can put it all back.
func _snapshot() -> Dictionary:
	return {
		"squares": state.squares.duplicate(),
		"side": state.side_to_move,
		"rights": state.castling_rights,
		"en_passant": state.en_passant_square,
		"history": history.size(),
		"light": captured_by_light.size(),
		"dark": captured_by_dark.size(),
		"finished": _finished,
	}


## Undoes to a snapshot by truncation: the lists only ever grow, so their old
## sizes are enough to put them back.
func _restore(saved: Dictionary) -> void:
	# Duplicated on the way back in. Assigning the saved array itself lets the
	# next apply_move write through into the snapshot, which silently corrupted
	# the board and made every depth past one wrong.
	state.squares = (saved["squares"] as PackedInt32Array).duplicate()
	state.side_to_move = saved["side"]
	state.castling_rights = saved["rights"]
	state.en_passant_square = saved["en_passant"]
	history.resize(int(saved["history"]))
	captured_by_light.resize(int(saved["light"]))
	captured_by_dark.resize(int(saved["dark"]))
	_finished = saved["finished"]


## Every legal move for the side to move. The AI chooses from this rather than
## inventing squares and hoping one is accepted.
func legal_moves() -> Array[ChessMove]:
	return Rules.legal_moves(state, state.side_to_move)
