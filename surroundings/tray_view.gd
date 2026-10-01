@tool
class_name TrayView
extends Node3D

## One capture tray on the table: the moulded slab plus the pieces standing in
## it.
##
## Shows what the side this tray belongs to has taken, in the order the pieces
## fell. Capture order rather than grouped-by-type, because the tray answers
## "what have I taken, and in what order"; a row that reshuffles every time an
## unrelated piece dies is harder to follow than one that only ever grows from
## one end.
##
## The pieces standing here are copies for display only. They are not
## registered with Main's piece registry and cannot be picked, so a tray can
## never be mistaken for a playable piece.

## Captured pieces are shrunk so all sixteen fit beside the board, and turned to
## face inward so the row reads as a set rather than a queue.
const PIECE_SCALE := 0.52
const PIECE_FACING := PI * 0.5

## The side whose captures this tray shows, BoardState.LIGHT or DARK.
@export var capturer: int = BoardState.LIGHT:
	set(value):
		capturer = clampi(value, 0, 1)
		if is_inside_tree():
			set_captured(_codes)

var _wells: MeshInstance3D
var _slots: Node3D
var _codes: Array[int] = []


func _ready() -> void:
	_build()
	if not _codes.is_empty():
		_rebuild()


func _build() -> void:
	if _slots != null:
		return
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = TrayMesh.build()
	add_child(body)

	_wells = MeshInstance3D.new()
	_wells.name = "Wells"
	_wells.mesh = TrayMesh.build_wells()
	add_child(_wells)

	_slots = Node3D.new()
	_slots.name = "Slots"
	add_child(_slots)


## Repaints the tray from the game's authoritative capture list for `capturer`.
func set_captured(codes: Array[int]) -> void:
	_codes = codes.duplicate()
	if _slots != null:
		_rebuild()


## Re-reads from a game, so the tray cannot be fed something out of step with
## the board.
func refresh_from(game: ChessGame) -> void:
	set_captured(game.captures_by(capturer))


func captured_count() -> int:
	return _slots.get_child_count() if _slots != null else 0


func slot_child(index: int) -> Node3D:
	if _slots == null or index < 0 or index >= _slots.get_child_count():
		return null
	return _slots.get_child(index) as Node3D


## The piece type standing in a given slot, or -1.
func slot_type(index: int) -> int:
	var piece := slot_child(index) as PieceView
	return piece.piece_type if piece != null else -1


func _rebuild() -> void:
	for child in _slots.get_children():
		_slots.remove_child(child)
		child.queue_free()
	var shown := mini(_codes.size(), TrayMesh.SLOTS)
	for i in shown:
		# decode gives (type, side): the piece that was taken, which is the
		# colour the tray shows. A side can only ever capture the other side's
		# pieces, so it is the opponent's colour in every slot.
		var decoded := BoardState.decode(_codes[i])
		if decoded.x < 0:
			continue
		_slots.add_child(_make_piece(decoded.x, decoded.y, i))


func _make_piece(type: int, side: int, index: int) -> Node3D:
	var view := MeshInstance3D.new()
	view.name = "Taken%s%d" % [PieceProfiles.type_name(type), index]
	view.set_script(load("res://pieces/piece_view.gd"))
	view.set("side", side)
	view.set("piece_type", type)
	view.scale = Vector3.ONE * PIECE_SCALE
	view.rotation.y = PIECE_FACING
	view.position = TrayMesh.slot_position(index)
	return view
