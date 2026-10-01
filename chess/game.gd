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

## Piece codes taken by each side, in the order they fell. Tracked as data
## derived from the move sequence rather than pushed in by the view, so two
## P2P peers applying the same moves build identical trays without any extra
## replication. Keyed by BoardState.LIGHT / DARK.
var captured_by := {BoardState.LIGHT: [] as Array[int], BoardState.DARK: [] as Array[int]}


func reset() -> void:
	state = BoardState.new()
	history.clear()
	captured_by[BoardState.LIGHT] = []
	captured_by[BoardState.DARK] = []


## Pieces this side has taken, oldest first.
func captures_by(side: int) -> Array[int]:
	return captured_by.get(side, [] as Array[int])


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
	if not is_legal(move):
		return false

	var captured := state.at(move.to_square.x, move.to_square.y)
	# Recorded before the side flip, since captures_by is keyed by the taker.
	if captured != BoardState.EMPTY:
		(captured_by[state.side_to_move] as Array).append(captured)
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
