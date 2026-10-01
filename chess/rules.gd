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
			_step_moves(state, square, piece.y, ROOK_DIRS + BISHOP_DIRS, moves)
			_castling_moves(state, square, piece.y, moves)
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


## Whether this side may still castle kingside, ignoring where the king currently
## is. Rights plus the pieces being home.
##
## Separated from the full test on purpose: the castling indicator needs to know
## whether castling is available at all, which is this, while legality also
## depends on the board in front of the king.
static func can_castle_kingside(state: BoardState, side: int) -> bool:
	return _has_castling_right(state, side, true)


static func can_castle_queenside(state: BoardState, side: int) -> bool:
	return _has_castling_right(state, side, false)


static func _has_castling_right(state: BoardState, side: int, kingside: bool) -> bool:
	var bit := (BoardState.CASTLE_DARK_KINGSIDE if side == BoardState.DARK
		else BoardState.CASTLE_WHITE_KINGSIDE) if kingside else \
		(BoardState.CASTLE_DARK_QUEENSIDE if side == BoardState.DARK
		else BoardState.CASTLE_WHITE_QUEENSIDE)
	if (state.castling_rights & bit) == 0:
		return false
	# The king must still be home and the rook must still be beside it. A rook
	# captured on its home square loses the right through ChessGame, but a state
	# built by hand may not have gone through that.
	if state.at(BoardState.KING_HOME[side].x, BoardState.KING_HOME[side].y) \
			!= BoardState.encode(PieceProfiles.Type.KING, side):
		return false
	var rook_square: Vector2i = BoardState.ROOK_HOME[side][kingside]
	return state.at(rook_square.x, rook_square.y) \
		== BoardState.encode(PieceProfiles.Type.ROOK, side)


## Castling destinations, when the whole thing is actually available.
##
## Every condition is checked here rather than left to is_legal, because is_legal
## only evaluates the square the king ends on. The squares it passes through are
## the ones it would miss, and a king that may not cross an attacked square must
## not be able to.
static func _castling_moves(state: BoardState, from: Vector2i, side: int,
		moves: Array[Vector2i]) -> void:
	if from != BoardState.KING_HOME[side]:
		return
	if Rules.is_in_check(state, side):
		return
	for kingside in [true, false]:
		if not _has_castling_right(state, side, kingside):
			continue
		var rook_square: Vector2i = BoardState.ROOK_HOME[side][kingside]
		var destination := Vector2i(BoardState.CASTLE_KING_TO[kingside].x, from.y)
		# Nothing between the king and its rook, and nothing where the king lands.
		if not _span_is_clear(state, from, rook_square, destination):
			continue
		# The king crosses every square it passes, and each must be safe. The
		# board still has the king on its home square here, which is correct:
		# what matters is whether that square attacked, not whether the king could
		# legally stand on it.
		var step := 1 if kingside else -1
		var transit := from
		while transit.x != destination.x:
			transit.x += step
			if transit == destination:
				continue
			if is_attacked(state, transit, 1 - side):
				transit = Vector2i(-1, -1)
				break
		if transit.x < 0:
			continue
		moves.append(destination)


static func _span_is_clear(state: BoardState, from: Vector2i, rook: Vector2i,
		destination: Vector2i) -> bool:
	# Starting one square along, not at the king: the king's own square is
	# occupied by the king, so testing it would always fail and castling would
	# never be generated at all.
	var step := signi(rook.x - from.x)
	var x := from.x + step
	while x != rook.x:
		if state.at(x, from.y) != BoardState.EMPTY:
			return false
		x += step
	# The square the king lands on is between it and the rook, so the loop above
	# already covers it; kept explicit here because it is the square that
	# matters most and relying on the loop's path to reach it is too subtle.
	return state.at(destination.x, from.y) == BoardState.EMPTY


## Whether neither side has the material to deliver mate, so the game cannot end
## however long it is played.
##
## The cases are the ones the rules recognise: bare kings, and a single minor
## piece against a bare king. Two knights against a bare king is included, since
## although mate exists it cannot be forced, which is the same situation as far as
## a game is concerned. Two bishops, a knight with a bishop, or anything with a
## pawn, rook or queen is enough.
static func has_insufficient_material(state: BoardState) -> bool:
	if state == null:
		return true
	var knights := {BoardState.LIGHT: 0, BoardState.DARK: 0}
	var bishops := {BoardState.LIGHT: 0, BoardState.DARK: 0}
	var other := 0
	for rank in BoardState.BOARD_SIZE:
		for file in BoardState.BOARD_SIZE:
			var code := state.at(file, rank)
			if code == BoardState.EMPTY:
				continue
			var piece := BoardState.decode(code)
			match piece.x:
				PieceProfiles.Type.PAWN, PieceProfiles.Type.ROOK, PieceProfiles.Type.QUEEN:
					other += 1
				PieceProfiles.Type.KNIGHT:
					knights[piece.y] += 1
				PieceProfiles.Type.BISHOP:
					bishops[piece.y] += 1
	if other > 0:
		return false
	var total_knights: int = knights[BoardState.LIGHT] + knights[BoardState.DARK]
	var total_bishops: int = bishops[BoardState.LIGHT] + bishops[BoardState.DARK]
	if total_knights + total_bishops <= 1:
		return true
	# Two bishops only deaden the position when they cannot help each other, which
	# means both stand on squares of the same colour.
	if total_knights == 0 and total_bishops == 2 \
			and bishops[BoardState.LIGHT] == 1 and bishops[BoardState.DARK] == 1:
		return _bishops_share_colour(state)
	# Two knights against a bare king cannot be forced to mate, though mate exists.
	# A knight on each side is a different matter and can be won, so the test is
	# that one side is left with nothing but its king.
	if total_knights == 2 and total_bishops == 0 \
			and (knights[BoardState.LIGHT] == 0 or knights[BoardState.DARK] == 0):
		return true
	return false


## Whether every bishop on the board stands on the same colour of square.
static func _bishops_share_colour(state: BoardState) -> bool:
	var colour := -1
	for rank in BoardState.BOARD_SIZE:
		for file in BoardState.BOARD_SIZE:
			var code := state.at(file, rank)
			if code == BoardState.EMPTY:
				continue
			var piece := BoardState.decode(code)
			if piece.x != PieceProfiles.Type.BISHOP:
				continue
			var square_colour := (file + rank) % 2
			if colour == -1:
				colour = square_colour
			elif colour != square_colour:
				return false
	return true


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
	# An en passant capture also vacates the square beside the mover, and that
	# square may be the only thing shielding the king. Leaving it occupied here
	# made a discovered check look covered, so the capture was allowed when the
	# capturing pawn and the captured one together were the only obstacles.
	if _is_en_passant(state, move):
		squares[move.from_square.y * BoardState.BOARD_SIZE + move.to_square.x] = BoardState.EMPTY
	var king := _find_king(squares, side)
	if king.x < 0:
		return false
	return _is_attacked_on(squares, king, 1 - side)


## Whether this move captures en passant: a pawn landing on the square behind a
## pawn that has just gone two squares, which is empty by definition.
##
## Derived here rather than passed in, because both the legality check and the
## board mutation need it and neither should depend on the other being right.
static func _is_en_passant(state: BoardState, move: ChessMove) -> bool:
	if state.at(move.to_square.x, move.to_square.y) != BoardState.EMPTY:
		return false
	if BoardState.decode(state.at(move.from_square.x, move.from_square.y)).x \
			!= PieceProfiles.Type.PAWN:
		return false
	return move.to_square == state.en_passant_square


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
	# Captures are diagonal only, and onto an occupied enemy square. This is why
	# pawns cannot move diagonally into empty space.
	for step in [-1, 1]:
		var capture := Vector2i(from.x + step, next_rank)
		if not BoardState.is_inside(capture.x, capture.y):
			continue
		# En passant: the one diagonal move onto an empty square a pawn has,
		# landing behind a pawn that has just gone two squares. The sole exception
		# to the rule below, so it is checked before the occupied-square test
		# rather than folded into it.
		if state.en_passant_square == capture:
			moves.append(capture)
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
## Whether this move is fully legal, king safety included.
