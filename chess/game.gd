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

var state := BoardState.new()
var history: Array[ChessMove] = []


func reset() -> void:
	state = BoardState.new()
	history.clear()


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
	if not is_legal(move):
		return false

	var captured := state.at(move.to_square.x, move.to_square.y)
	state.set_square(move.to_square.x, move.to_square.y,
		state.at(move.from_square.x, move.from_square.y))
	state.set_square(move.from_square.x, move.from_square.y, BoardState.EMPTY)
	state.side_to_move = BoardState.DARK if state.side_to_move == BoardState.LIGHT else BoardState.LIGHT
	history.append(move)
	moved.emit(move, captured)
	return true


## Legality hook for the rules engine. True until then, so the visual
## prototype keeps moving freely; callers already go through it.
func is_legal(_move: ChessMove) -> bool:
	return true
