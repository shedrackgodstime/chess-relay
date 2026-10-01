class_name Rules
extends RefCounted

## Chess movement, attacks and king safety.
##
## Pure functions over BoardState. No nodes, no randomness, no game state — which
## is what lets both P2P peers run identical rules and reach identical results
## from the same move sequence.
##
## Layered in two steps, because the split matters everywhere else:
##
##   pseudo_legal  — the piece's own movement rules, ignoring whether it would
##                   leave its own king exposed.
##   legal         — pseudo-legal, and the mover's king is still safe afterwards.
##
## Anything that answers "can this piece attack that square" must use the
## *attack* form, not the move form: a pawn attacks the diagonals ahead of it
## whether or not anything stands there, and a king attacks its neighbours even
## though it may never move onto an attacked one. Reusing the move generator for
## attacks is the classic way to get check detection subtly wrong.
##
## Not implemented: castling, en passant and the drawn-game rules. Those moves
## are simply not generated, so they are rejected rather than mishandled.

## Where each side starts, and where it promotes. White is on the low ranks.
const START_RANK := {BoardState.LIGHT: 1, BoardState.DARK: 6}
const PROMOTION_RANK := {BoardState.LIGHT: 7, BoardState.DARK: 0}

## The direction a side's pawns travel, in rank steps.
const PAWN_DIRECTION := {BoardState.LIGHT: 1, BoardState.DARK: -1}

const KNIGHT_STEPS := [
	Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, -1), Vector2i(1, -2),
	Vector2i(-1, -2), Vector2i(-2, -1), Vector2i(-2, 1), Vector2i(-1, 2),
]

const ROOK_DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const BISHOP_DIRS := [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]


static func direction_for(side: int) -> int:
	return PAWN_DIRECTION.get(side, 1)


## Squares this piece could move to if its own king's safety did not matter.
static func pseudo_legal_moves(state: BoardState, square: Vector2i) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	if state == null or not BoardState.is_inside(square.x, square.y):
		return moves
	var code := state.at(square.x, square.y)
	if code == BoardState.EMPTY:
		return moves
	var piece := BoardState.decode(code)
	match piece.x:
		PieceProfiles.Type.PAWN:
			_pawn_moves(state, square, piece.y, moves)
		PieceProfiles.Type.KNIGHT:
			_step_moves(state, square, piece.y, KNIGHT_STEPS, moves)
		PieceProfiles.Type.KING:
			_step_moves(state, square, piece.y,
				ROOK_DIRS + BISHOP_DIRS, moves)
		PieceProfiles.Type.ROOK:
			_slide_moves(state, square, piece.y, ROOK_DIRS, moves)
		PieceProfiles.Type.BISHOP:
			_slide_moves(state, square, piece.y, BISHOP_DIRS, moves)
		PieceProfiles.Type.QUEEN:
			_slide_moves(state, square, piece.y, ROOK_DIRS + BISHOP_DIRS, moves)
	return moves


static func is_pseudo_legal(state: BoardState, move: ChessMove) -> bool:
	if state == null or move == null:
		return false
	if not BoardState.is_inside(move.from_square.x, move.from_square.y):
		return false
	if not BoardState.is_inside(move.to_square.x, move.to_square.y):
		return false
	if move.from_square == move.to_square:
		return false
	var code := state.at(move.from_square.x, move.from_square.y)
	if code == BoardState.EMPTY:
		return false
	# Never capture your own piece, and never capture the king: a king is taken
	# by leaving check unanswered, not by walking onto it.
	var target := state.at(move.to_square.x, move.to_square.y)
	if target != BoardState.EMPTY:
		var target_piece := BoardState.decode(target)
		if target_piece.y == BoardState.decode(code).y:
			return false
		if target_piece.x == PieceProfiles.Type.KING:
			return false
	return pseudo_legal_moves(state, move.from_square).has(move.to_square)


## Whether this move would promote: a pawn arriving on its far rank.
##
## Asked separately from is_legal because a promotion is the one move the player
## does not get to specify fully on their own, so the input layer has to ask
## before submitting rather than after.
static func is_promotion(state: BoardState, move: ChessMove) -> bool:
	if state == null or move == null:
		return false
	var code := state.at(move.from_square.x, move.from_square.y)
	if code == BoardState.EMPTY:
		return false
	var piece := BoardState.decode(code)
	return piece.x == PieceProfiles.Type.PAWN \
		and move.to_square.y == PROMOTION_RANK.get(piece.y, -1)


## The pieces a pawn may promote to. No king: that is not a promotion, it is an
## illegal move, and offering it would invite confusion.
const PROMOTION_CHOICES := [
	PieceProfiles.Type.QUEEN, PieceProfiles.Type.ROOK,
	PieceProfiles.Type.BISHOP, PieceProfiles.Type.KNIGHT,
]


## Whether this move is fully legal, king safety included.
static func is_legal(state: BoardState, move: ChessMove) -> bool:
	if not is_pseudo_legal(state, move):
		return false
	return not _leaves_own_king_exposed(state, move)


## Every legal move available to a side. Used by the AI to choose from, and by
## the game to tell checkmate from stalemate.
static func legal_moves(state: BoardState, side: int) -> Array[ChessMove]:
	var moves: Array[ChessMove] = []
	if state == null:
		return moves
	for rank in BoardState.BOARD_SIZE:
		for file in BoardState.BOARD_SIZE:
			var code := state.at(file, rank)
			if code == BoardState.EMPTY or BoardState.decode(code).y != side:
				continue
			var from := Vector2i(file, rank)
			for to in pseudo_legal_moves(state, from):
				var move := ChessMove.new(from, to)
				if is_legal(state, move):
					moves.append(move)
	return moves


static func has_legal_move(state: BoardState, side: int) -> bool:
	return not legal_moves(state, side).is_empty()


## Square holding a side's king, or (-1, -1) if it has none. Tests build partial
## positions, so a missing king is normal rather than an error.
static func king_square(state: BoardState, side: int) -> Vector2i:
	if state == null:
		return Vector2i(-1, -1)
	for rank in BoardState.BOARD_SIZE:
		for file in BoardState.BOARD_SIZE:
			var code := state.at(file, rank)
			if code == BoardState.EMPTY:
				continue
			var piece := BoardState.decode(code)
			if piece.x == PieceProfiles.Type.KING and piece.y == side:
				return Vector2i(file, rank)
	return Vector2i(-1, -1)


static func is_in_check(state: BoardState, side: int) -> bool:
	var king := king_square(state, side)
	if king.x < 0:
		return false
	return is_attacked(state, king, 1 - side)


## Whether `by_side` attacks `square`, ignoring whether the move is legal. This
## is the primitive check detection is built from, so it must be the attack form
## rather than the movement form.
static func is_attacked(state: BoardState, square: Vector2i, by_side: int) -> bool:
	if state == null or not BoardState.is_inside(square.x, square.y):
		return false
	return _is_attacked_on(state.squares, square, by_side)


## Applies a move to a copy of the squares and reports whether the mover's king
## would be attacked afterwards. Works on a duplicated PackedInt32Array rather
## than a whole BoardState, because this runs once per candidate move and
## copying the full state each time is wasted work.
static func _leaves_own_king_exposed(state: BoardState, move: ChessMove) -> bool:
	var squares := state.squares.duplicate()
	var side := BoardState.decode(state.at(move.from_square.x, move.from_square.y)).y
	# Move first, so a king stepping away from a checking piece is judged from
	# its new square.
	squares[move.from_square.y * BoardState.BOARD_SIZE + move.from_square.x] = BoardState.EMPTY
	var landing := landing_code(state, move)
	squares[move.to_square.y * BoardState.BOARD_SIZE + move.to_square.x] = landing
	var king := _find_king(squares, side)
	if king.x < 0:
		return false
	return _is_attacked_on(squares, king, 1 - side)


## What ends up on the destination square. A pawn reaching the far rank with no
## promotion chosen becomes a queen, rather than sitting there as a pawn that
## can never move again.
static func landing_code(state: BoardState, move: ChessMove) -> int:
	var moving := BoardState.decode(state.at(move.from_square.x, move.from_square.y))
	if move.promotion >= 0:
		return BoardState.encode(move.promotion, moving.y)
	if moving.x == PieceProfiles.Type.PAWN \
			and move.to_square.y == PROMOTION_RANK.get(moving.y, -1):
		return BoardState.encode(PieceProfiles.Type.QUEEN, moving.y)
	return state.at(move.from_square.x, move.from_square.y)


static func _pawn_moves(state: BoardState, from: Vector2i, side: int,
		moves: Array[Vector2i]) -> void:
	var forward := direction_for(side)
	var next_rank := from.y + forward
	if not BoardState.is_inside(from.x, next_rank):
		return
	var one := Vector2i(from.x, next_rank)
	if state.at(one.x, one.y) == BoardState.EMPTY:
		moves.append(one)
		# The double step needs both squares clear, or it can jump a piece.
		var two_rank := from.y + forward * 2
		if from.y == START_RANK.get(side, -1) \
				and BoardState.is_inside(from.x, two_rank) \
				and state.at(from.x, two_rank) == BoardState.EMPTY:
			moves.append(Vector2i(from.x, two_rank))
	# Captures are diagonal only, and only onto an occupied enemy square. This
	# is why pawns cannot move diagonally into empty space.
	for step in [-1, 1]:
		var capture := Vector2i(from.x + step, next_rank)
		if not BoardState.is_inside(capture.x, capture.y):
			continue
		var code := state.at(capture.x, capture.y)
		if code == BoardState.EMPTY:
			continue
		if BoardState.decode(code).y != side:
			moves.append(capture)


static func _step_moves(state: BoardState, from: Vector2i, side: int,
		steps: Array, moves: Array[Vector2i]) -> void:
	for step: Vector2i in steps:
		var to := from + step
		if not BoardState.is_inside(to.x, to.y):
			continue
		var code := state.at(to.x, to.y)
		if code == BoardState.EMPTY:
			moves.append(to)
		elif BoardState.decode(code).y != side:
			moves.append(to)


## Slides along each direction until something blocks it. Own pieces stop the
## ray and are not capturable; an enemy piece is capturable and also stops it,
## because a bishop cannot leap past a rook.
static func _slide_moves(state: BoardState, from: Vector2i, side: int,
		directions: Array, moves: Array[Vector2i]) -> void:
	for direction: Vector2i in directions:
		var to := from + direction
		while BoardState.is_inside(to.x, to.y):
			var code := state.at(to.x, to.y)
			if code == BoardState.EMPTY:
				moves.append(to)
			else:
				if BoardState.decode(code).y != side:
					moves.append(to)
				break
			to += direction


static func _is_attacked_on(squares: PackedInt32Array, square: Vector2i,
		by_side: int) -> bool:
	# Pawns: look back along the direction the attacker would have come from.
	var pawn_rank := square.y - direction_for(by_side)
	for step in [-1, 1]:
		var origin := Vector2i(square.x + step, pawn_rank)
		if not BoardState.is_inside(origin.x, origin.y):
			continue
		var code := _at(squares, origin)
		if code == BoardState.EMPTY:
			continue
		var piece := BoardState.decode(code)
		if piece.x == PieceProfiles.Type.PAWN and piece.y == by_side:
			return true

	for step: Vector2i in KNIGHT_STEPS:
		var origin := square + step
		if not BoardState.is_inside(origin.x, origin.y):
			continue
		var code := _at(squares, origin)
		if code != BoardState.EMPTY:
			var piece := BoardState.decode(code)
			if piece.x == PieceProfiles.Type.KNIGHT and piece.y == by_side:
				return true

	# The king attacks its neighbours even though it may not legally move there,
	# which is exactly why this cannot reuse the movement generator.
	for direction: Vector2i in ROOK_DIRS + BISHOP_DIRS:
		var origin := square + direction
		if not BoardState.is_inside(origin.x, origin.y):
			continue
		var code := _at(squares, origin)
		if code != BoardState.EMPTY:
			var piece := BoardState.decode(code)
			if piece.x == PieceProfiles.Type.KING and piece.y == by_side:
				return true

	return _ray_attacked(squares, square, ROOK_DIRS, by_side,
		[PieceProfiles.Type.ROOK, PieceProfiles.Type.QUEEN]) \
		or _ray_attacked(squares, square, BISHOP_DIRS, by_side,
		[PieceProfiles.Type.BISHOP, PieceProfiles.Type.QUEEN])


## Walks outwards and asks whether the first thing met is a slider of the right
## kind. Anything at all blocks, so a slider behind a pawn is not attacking.
static func _ray_attacked(squares: PackedInt32Array, square: Vector2i,
		directions: Array, by_side: int, attackers: Array) -> bool:
	for direction: Vector2i in directions:
		var to := square + direction
		while BoardState.is_inside(to.x, to.y):
			var code := _at(squares, to)
			if code != BoardState.EMPTY:
				var piece := BoardState.decode(code)
				if piece.y == by_side and attackers.has(piece.x):
					return true
				break
			to += direction
	return false


static func _find_king(squares: PackedInt32Array, side: int) -> Vector2i:
	for rank in BoardState.BOARD_SIZE:
		for file in BoardState.BOARD_SIZE:
			var code := _at(squares, Vector2i(file, rank))
			if code == BoardState.EMPTY:
				continue
			var piece := BoardState.decode(code)
			if piece.x == PieceProfiles.Type.KING and piece.y == side:
				return Vector2i(file, rank)
	return Vector2i(-1, -1)


static func _at(squares: PackedInt32Array, square: Vector2i) -> int:
	if not BoardState.is_inside(square.x, square.y):
		return BoardState.EMPTY
	return squares[square.y * BoardState.BOARD_SIZE + square.x]


## Counts the leaf nodes reachable in exactly `depth` plies.
##
## The standard correctness check for a move generator, and the reason this
## exists as a method rather than living in a test file: the published node
## counts are fixed, well known numbers, so a generator that disagrees with one
## is wrong in a way no hand-written assertion will reliably describe. A single
## wrong castling or en-passant case shifts the count and every other count with
## it.
##
## Applies and undoes moves in place rather than copying the board each ply,
## because a copy per node is most of the cost at depth five.
##
## Castling and en passant are not implemented, so counts for positions that
## depend on them will not match. The opening counts below do not reach either,
## which is why they can be trusted as they stand.
static func perft(state: BoardState, depth: int) -> int:
	if state == null or depth <= 0:
		return 1
	var moves := legal_moves(state, state.side_to_move)
	if depth == 1:
		return moves.size()
	var nodes := 0
	for move in moves:
		var from := move.from_square.y * BoardState.BOARD_SIZE + move.from_square.x
		var to := move.to_square.y * BoardState.BOARD_SIZE + move.to_square.x
		var moved := state.squares[from]
		var captured := state.squares[to]
		# Read before clearing: landing_code inspects the origin square to know
		# what is moving, and clearing first made every move land a light pawn.
		# Depth 2 still matched by luck because leaf counting never looks at the
		# piece that arrived.
		var landing := landing_code(state, move)
		state.squares[from] = BoardState.EMPTY
		state.squares[to] = landing
		state.side_to_move = 1 - state.side_to_move

		nodes += perft(state, depth - 1)

		state.side_to_move = 1 - state.side_to_move
		state.squares[from] = moved
		state.squares[to] = captured
	return nodes


## Node counts for the opening position, which are published constants rather
## than anything this code chose.
const PERFT_STARTPOS := {1: 20, 2: 400, 3: 8902, 4: 197281, 5: 4865609}
