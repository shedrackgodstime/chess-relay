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

	var captured := state.at(move.to_square.x, move.to_square.y)
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


## Every legal move for the side to move. The AI chooses from this rather than
## inventing squares and hoping one is accepted.
func legal_moves() -> Array[ChessMove]:
	return Rules.legal_moves(state, state.side_to_move)
