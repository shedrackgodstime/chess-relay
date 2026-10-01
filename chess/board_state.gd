class_name BoardState
extends RefCounted

## The board as pure data: 64 squares, no nodes.
##
## Each square holds an int code: EMPTY for vacant, otherwise
## piece_type * 2 + side + 1 (so code 0 is the only falsy value and every
## real piece decodes unambiguously). Sides match PieceProfiles' palette:
## 0 is light, 1 is dark.
##
## Deliberately symmetric and deterministic — no authority, no randomness —
## so two P2P peers applying the same moves converge on the same state.

const EMPTY := 0
const LIGHT := 0
const DARK := 1

## Squares per side. The single source of truth for board size: the rules, the
## state encoding and the scene geometry all read this rather than repeating 8,
## so the logic and the visuals cannot drift apart.
const BOARD_SIZE := 8

## Castling rights, as a bitmask so clearing one is a single AND. Rights are
## position state, not move history: they are lost when a king or a rook moves,
## or when one is captured on its home square, and two peers that agree on the
## squares can still disagree about them. That is why they live here rather than
## being tracked alongside the move list.
const CASTLE_WHITE_KINGSIDE := 1
const CASTLE_WHITE_QUEENSIDE := 2
const CASTLE_DARK_KINGSIDE := 4
const CASTLE_DARK_QUEENSIDE := 8
const ALL_CASTLING := 15

## Home squares, indexed by side then by king/rook side. Fixed by the rules, not
## derived: castling is only ever from these squares.
const KING_HOME := {BoardState.LIGHT: Vector2i(4, 0), BoardState.DARK: Vector2i(4, 7)}
const ROOK_HOME := {
	BoardState.LIGHT: {true: Vector2i(7, 0), false: Vector2i(0, 0)},
	BoardState.DARK: {true: Vector2i(7, 7), false: Vector2i(0, 7)},
}

## Where a side's king ends up when it castles: g or c for White, g or c for
## Black, with the file mirroring because White castles toward rank 8's letters
## only by accident. Both sides use g1/c1 or g8/c8 in their own coordinates.
const CASTLE_KING_TO := {true: Vector2i(6, -1), false: Vector2i(2, -1)}

## Back-rank order from White's left, shared with the scene generator so the
## visual layout and the logical layout can never disagree on setup.
const BACK_RANK := [
	PieceProfiles.Type.ROOK,
	PieceProfiles.Type.KNIGHT,
	PieceProfiles.Type.BISHOP,
	PieceProfiles.Type.QUEEN,
	PieceProfiles.Type.KING,
	PieceProfiles.Type.BISHOP,
	PieceProfiles.Type.KNIGHT,
	PieceProfiles.Type.ROOK,
]

var squares := PackedInt32Array()
var side_to_move := LIGHT

## Remaining castling rights as a mask of the CASTLE_* bits above.
var castling_rights := ALL_CASTLING

## The square behind a pawn that has just made a two-square move, where an
## enemy pawn may capture it by stepping diagonally onto an empty square. The
## only reason en passant needs a recorded square rather than being inferred
## from the previous move: the board looks identical before and after the
## capturing pawn has moved. Vector2i(-1, -1) when there is none.
var en_passant_square := Vector2i(-1, -1)


func _init() -> void:
	squares.resize(64)
	standard_setup()


static func encode(piece_type: int, side: int) -> int:
	return piece_type * 2 + side + 1


## Decodes to Vector2i(piece_type, side), or (-1, -1) for EMPTY.
static func decode(code: int) -> Vector2i:
	if code == EMPTY:
		return Vector2i(-1, -1)
	return Vector2i(int((code - 1) / 2.0), (code - 1) % 2)


static func index_of(file: int, rank: int) -> int:
	return rank * 8 + file


static func is_inside(file: int, rank: int) -> bool:
	return file >= 0 and file < 8 and rank >= 0 and rank < 8


func at(file: int, rank: int) -> int:
	if not is_inside(file, rank):
		return EMPTY
	return squares[index_of(file, rank)]


func set_square(file: int, rank: int, code: int) -> void:
	if is_inside(file, rank):
		squares[index_of(file, rank)] = code


## Standard chess setup: White back rank on rank 0 with pawns on rank 1,
## Black mirrored on ranks 7 and 6. Light to move.
func standard_setup() -> void:
	squares.fill(EMPTY)
	castling_rights = ALL_CASTLING
	en_passant_square = Vector2i(-1, -1)
	for file in 8:
		set_square(file, 0, encode(BACK_RANK[file], LIGHT))
		set_square(file, 1, encode(PieceProfiles.Type.PAWN, LIGHT))
		set_square(file, 6, encode(PieceProfiles.Type.PAWN, DARK))
		set_square(file, 7, encode(BACK_RANK[file], DARK))
	side_to_move = LIGHT


func piece_count() -> int:
	var count := 0
	for code in squares:
		if code != EMPTY:
			count += 1
	return count


func count_side(side: int) -> int:
	var count := 0
	for code in squares:
		if code != EMPTY and decode(code).y == side:
			count += 1
	return count


## A stable fingerprint of the full position.
##
## Squares, side to move, castling rights and the en-passant square. All four,
## because two peers can agree on every square and still be in different games:
## the same board with Black's kingside right already lost is a different
## position, and so is the same board one move after a double pawn push.
##
## Integer-only and order-fixed, so the same position always produces the same
## number on every device, which is the whole point of a hash for peer sync.
func hash() -> int:
	var accumulator := 1469598103
	for code in squares:
		accumulator = (accumulator ^ code) * 16777619
	accumulator = (accumulator ^ side_to_move) * 16777619
	accumulator = (accumulator ^ castling_rights) * 16777619
	accumulator = (accumulator ^ (en_passant_square.x + 1)) * 16777619
	return (accumulator ^ (en_passant_square.y + 1)) * 16777619


## The position as a compact list, for a full resync. Cheap to send (about 64
## small ints) and trivial to verify, so a desynced peer can be repaired
## without replaying history.
func to_array() -> Array:
	var out := squares.duplicate()
	out.resize(68)
	out[64] = side_to_move
	out[65] = castling_rights
	# Plus one, so a cleared en-passant square is 0 rather than -1 and the payload
	# is all non-negative integers.
	out[66] = en_passant_square.x + 1
	out[67] = en_passant_square.y + 1
	return Array(out)


## Restores a position produced by to_array. Returns false (changing nothing)
## if the payload is not exactly 65 values or is otherwise unusable.
func from_array(data: Array) -> bool:
	if data.size() != 68:
		return false
	for i in 68:
		if typeof(data[i]) != TYPE_INT:
			return false
	squares = PackedInt32Array()
	for i in 64:
		squares.append(int(data[i]))
	side_to_move = int(data[64])
	castling_rights = int(data[65]) & ALL_CASTLING
	var ep_x := int(data[66]) - 1
	var ep_y := int(data[67]) - 1
	en_passant_square = Vector2i(ep_x, ep_y)
	if not (ep_x < 0 or BoardState.is_inside(ep_x, ep_y)):
		en_passant_square = Vector2i(-1, -1)
	return true


## Reads a position from a FEN string, the standard interchange format.
##
## Two reasons it is here rather than only in a test. It is how a lobby or a
## network peer will agree on a starting position, and it is what makes the
## published perft positions usable as verification, which matters because every
## hand-built chess fixture written during this project has been wrong at least
## once.
##
## Accepts the first four FEN fields and ignores the clocks, which this game does
## not keep on the position.
func from_fen(fen: String) -> bool:
	var fields := fen.strip_edges().split(" ", false)
	if fields.size() < 2:
		return false
	var ranks := fields[0].split("/", false)
	if ranks.size() != BOARD_SIZE:
		return false

	var fresh := BoardState.new()
	fresh.squares.fill(EMPTY)
	# FEN lists rank 8 first and a1 last, which is the reverse of our indexing.
	for i in BOARD_SIZE:
		var file := 0
		for letter in ranks[i]:
			var c := letter.to_lower()
			if c == "/":
				continue
			if c.is_valid_int():
				file += int(c)
				continue
			var type := -1
			match c:
				"p": type = PieceProfiles.Type.PAWN
				"n": type = PieceProfiles.Type.KNIGHT
				"b": type = PieceProfiles.Type.BISHOP
				"r": type = PieceProfiles.Type.ROOK
				"q": type = PieceProfiles.Type.QUEEN
				"k": type = PieceProfiles.Type.KING
			if type < 0 or file >= BOARD_SIZE:
				return false
			# Uppercase is White in FEN, so an uppercase letter means Light.
			var side := LIGHT if letter == letter.to_upper() else DARK
			fresh.set_square(file, BOARD_SIZE - 1 - i, encode(type, side))
			file += 1

	fresh.side_to_move = DARK if fields[1].to_lower().begins_with("b") else LIGHT

	fresh.castling_rights = 0
	if fields.size() > 2 and fields[2] != "-":
		for c in fields[2]:
			match c:
				"K": fresh.castling_rights |= CASTLE_WHITE_KINGSIDE
				"Q": fresh.castling_rights |= CASTLE_WHITE_QUEENSIDE
				"k": fresh.castling_rights |= CASTLE_DARK_KINGSIDE
				"q": fresh.castling_rights |= CASTLE_DARK_QUEENSIDE

	fresh.en_passant_square = Vector2i(-1, -1)
	if fields.size() > 3 and fields[3] != "-":
		var ep := fields[3].strip_edges()
		if ep.length() >= 2:
			var ep_file := int(ep[0].to_lower().unicode_at(0)) - 97
			var ep_rank := int(ep[1]) - 1
			if BoardState.is_inside(ep_file, ep_rank):
				fresh.en_passant_square = Vector2i(ep_file, ep_rank)

	squares = fresh.squares
	side_to_move = fresh.side_to_move
	castling_rights = fresh.castling_rights
	en_passant_square = fresh.en_passant_square
	return true


## The position as a FEN string. Round-trips through from_fen.
func to_fen() -> String:
	var ranks: Array[String] = []
	for i in BOARD_SIZE:
		var rank := BOARD_SIZE - 1 - i
		var run := 0
		var line := ""
		for file in BOARD_SIZE:
			var code := at(file, rank)
			if code == EMPTY:
				run += 1
				continue
			if run > 0:
				line += str(run)
				run = 0
			var piece := decode(code)
			var letter := TYPE_LETTERS[piece.x].to_lower()
			line += letter.to_upper() if piece.y == LIGHT else letter
		if run > 0:
			line += str(run)
		ranks.append(line)
	var rights := ""
	if (castling_rights & CASTLE_WHITE_KINGSIDE) != 0:
		rights += "K"
	if (castling_rights & CASTLE_WHITE_QUEENSIDE) != 0:
		rights += "Q"
	if (castling_rights & CASTLE_DARK_KINGSIDE) != 0:
		rights += "k"
	if (castling_rights & CASTLE_DARK_QUEENSIDE) != 0:
		rights += "q"
	if rights == "":
		rights = "-"
	var ep := "-"
	if en_passant_square.x >= 0:
		ep = "%s%d" % [char(97 + en_passant_square.x), en_passant_square.y + 1]
	return "%s %s %s %s" % [
		"/".join(ranks), "b" if side_to_move == DARK else "w", rights, ep
	]


## Piece letter by type, for FEN output.
const TYPE_LETTERS := "pnbrqk"
