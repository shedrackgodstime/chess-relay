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


## A stable fingerprint of the full position: squares plus side to move.
## Two peers comparing hashes can detect divergence without shipping their
## whole boards. Integer-only and order-fixed, so the same position always
## produces the same number on every device.
func hash() -> int:
	var accumulator := 1469598103
	for code in squares:
		accumulator = (accumulator ^ code) * 16777619
	return (accumulator ^ side_to_move) * 16777619


## The position as a compact list, for a full resync. Cheap to send (about 64
## small ints) and trivial to verify, so a desynced peer can be repaired
## without replaying history.
func to_array() -> Array:
	var out := squares.duplicate()
	out.resize(65)
	out[64] = side_to_move
	return Array(out)


## Restores a position produced by to_array. Returns false (changing nothing)
## if the payload is not exactly 65 values or is otherwise unusable.
func from_array(data: Array) -> bool:
	if data.size() != 65:
		return false
	for i in 64:
		if typeof(data[i]) != TYPE_INT:
			return false
	squares = PackedInt32Array()
	for i in 64:
		squares.append(int(data[i]))
	side_to_move = int(data[64])
	return true
