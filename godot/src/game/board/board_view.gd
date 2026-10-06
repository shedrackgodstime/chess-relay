class_name ChessBoardView
extends Node3D

signal square_pressed(square: String)

const BOARD_SIZE := 8
const SQUARE_SIZE := 1.0
const SQUARE_GAP := 0.035
const SQUARE_THICKNESS := 0.07
const BOARD_SURFACE_Y := 0.0
const FRAME_MARGIN := 0.38
const FRAME_LIP := 0.025
const FRAME_DEPTH := 0.16
const PLINTH_DEPTH := 0.26
const PLINTH_INSET := 0.12

const FRAME_COLOR := Color(0.12, 0.08, 0.05, 1.0)
const HIGHLIGHT_COLOR := Color(0.95, 0.72, 0.24, 0.72)
const LAST_MOVE_COLOR := Color(0.92, 0.74, 0.28, 0.34)
const LEGAL_MOVE_COLOR := Color(0.32, 0.86, 0.55, 0.72)
const CHECK_COLOR := Color(0.92, 0.24, 0.2, 0.68)

var _highlights_root: Node3D
var _last_move_root: Node3D
var _legal_moves_root: Node3D
var _check_root: Node3D
var _coordinates_root: Node3D
var _highlighted_square := ""


func _ready() -> void:
	# The board itself is authored: 64 instances of square.tscn and square_dark.tscn
	# under Board/Squares, plus the frame and plinth. It used to be built here in
	# _ready(), which meant none of it could be seen or adjusted in the editor. The
	# tool that writes the scene is tools/build_board_scene.py; the scene is the
	# artefact and this file no longer constructs it.
	# The frame and the plinth are still made here. The generator writes the squares
	# only, because the frame is four raised rails and a slab would not be the same
	# silhouette; they move when they move as rails.
	_build_overlay_roots()
	_build_frame()
	_build_coordinates()
	_build_input_surface()


func square_to_world(square: String, height := 0.2) -> Vector3:
	if square.length() != 2:
		return Vector3.ZERO
	var file := square.unicode_at(0) - "a".unicode_at(0)
	var rank := square.unicode_at(1) - "1".unicode_at(0)
	return Vector3(
		(file - 3.5) * SQUARE_SIZE,
		height,
		(3.5 - rank) * SQUARE_SIZE
	)


func world_to_square(world_position: Vector3) -> String:
	var local := to_local(world_position)
	var file := floori(local.x / SQUARE_SIZE + 4.0)
	var rank_from_camera := floori(4.0 - local.z / SQUARE_SIZE)
	if file < 0 or file >= BOARD_SIZE or rank_from_camera < 0 or rank_from_camera >= BOARD_SIZE:
		return ""
	return "%s%d" % [char("a".unicode_at(0) + file), rank_from_camera + 1]


func set_highlight(square: String, color := HIGHLIGHT_COLOR) -> void:
	_clear_highlights()
	if square.is_empty():
		return
	_highlighted_square = square
	var highlight := _make_box(
		Vector3(SQUARE_SIZE * 0.86, 0.025, SQUARE_SIZE * 0.86),
		color,
		Vector3(square_to_world(square, BOARD_SURFACE_Y + 0.012))
	)
	highlight.name = "SelectedSquare"
	_highlights_root.add_child(highlight)


func get_highlighted_square() -> String:
	return _highlighted_square


func set_last_move(from_square: String, to_square: String) -> void:
	_clear_root(_last_move_root)
	for square in [from_square, to_square]:
		if not square.is_empty():
			_last_move_root.add_child(_square_overlay(square, LAST_MOVE_COLOR, "LastMove"))


func set_legal_moves(squares: Array[String]) -> void:
	_clear_root(_legal_moves_root)
	for square in squares:
		if not square.is_empty():
			_legal_moves_root.add_child(_square_overlay(square, LEGAL_MOVE_COLOR, "LegalMove"))


func set_check_square(square: String) -> void:
	_clear_root(_check_root)
	if not square.is_empty():
		_check_root.add_child(_square_overlay(square, CHECK_COLOR, "CheckSquare"))


func _build_input_surface() -> void:
	var area := Area3D.new()
	area.name = "BoardInputSurface"
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(BOARD_SIZE * SQUARE_SIZE, SQUARE_THICKNESS, BOARD_SIZE * SQUARE_SIZE)
	area.position.y = BOARD_SURFACE_Y - SQUARE_THICKNESS * 0.5
	collision.shape = shape
	area.add_child(collision)
	area.input_event.connect(_on_board_input)
	add_child(area)


func _add_coordinate(text: String, position: Vector3, node_name: String) -> void:
	var marking := MeshInstance3D.new()
	marking.name = node_name
	marking.position = position
	marking.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	var text_mesh := TextMesh.new()
	text_mesh.text = text
	text_mesh.font_size = 16
	text_mesh.depth = 0.002
	text_mesh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_mesh.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	marking.mesh = text_mesh
	marking.material_override = _material(Color(0.68, 0.6, 0.49, 0.9))
	_coordinates_root.add_child(marking)


func _on_board_input(_camera: Node, event: InputEvent, event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var square := world_to_square(event_position)
		if not square.is_empty():
			set_highlight(square)
			square_pressed.emit(square)


func _clear_highlights() -> void:
	_highlighted_square = ""
	_clear_root(_highlights_root)


## The four overlay groups the board draws on top of the squares.
##
## They were made inside the old _build_board, which built the squares as well, so
## removing the squares had to bring these out into their own method rather than
## take them with it.
func _build_overlay_roots() -> void:
	_highlights_root = Node3D.new()
	_highlights_root.name = "Highlights"
	add_child(_highlights_root)
	_last_move_root = _new_overlay_root("LastMove")
	_legal_moves_root = _new_overlay_root("LegalMoves")
	_check_root = _new_overlay_root("Check")


func _new_overlay_root(root_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = root_name
	add_child(root)
	return root


func _clear_root(root: Node3D) -> void:
	if root == null:
		return
	for child in root.get_children():
		child.free()


func _build_coordinates() -> void:
	_coordinates_root = Node3D.new()
	_coordinates_root.name = "Coordinates"
	add_child(_coordinates_root)
	var board_half := BOARD_SIZE * SQUARE_SIZE * 0.5
	var frame_half := board_half + FRAME_MARGIN
	var frame_label_offset := (board_half + frame_half) * 0.5
	var frame_top := FRAME_LIP
	var label_height := frame_top + 0.004
	for file in BOARD_SIZE:
		var file_name := char("a".unicode_at(0) + file)
		var file_position := (file - 3.5) * SQUARE_SIZE
		_add_coordinate(file_name, Vector3(file_position, label_height, frame_label_offset),
			"FileFront_%s" % file_name)
		_add_coordinate(file_name, Vector3(file_position, label_height, -frame_label_offset),
			"FileBack_%s" % file_name)
	for rank in BOARD_SIZE:
		var rank_name := str(rank + 1)
		var rank_position := (3.5 - rank) * SQUARE_SIZE
		_add_coordinate(rank_name, Vector3(-frame_label_offset, label_height, rank_position),
			"RankLeft_%s" % rank_name)
		_add_coordinate(rank_name, Vector3(frame_label_offset, label_height, rank_position),
			"RankRight_%s" % rank_name)


func _build_frame() -> void:
	var inner := BOARD_SIZE * SQUARE_SIZE * 0.5
	var outer := inner + FRAME_MARGIN
	var centre_offset := (outer + inner) * 0.5
	var rail_y := FRAME_LIP - FRAME_DEPTH * 0.5
	var front_back_size := Vector3(outer * 2.0, FRAME_DEPTH, FRAME_MARGIN)
	var left_right_size := Vector3(FRAME_MARGIN, FRAME_DEPTH, inner * 2.0)
	for side in [-1.0, 1.0]:
		var rail := _make_box(front_back_size, FRAME_COLOR,
			Vector3(0.0, rail_y, side * centre_offset))
		rail.name = "FrameRail_%s" % ("Front" if side > 0.0 else "Back")
		add_child(rail)
		rail = _make_box(left_right_size, FRAME_COLOR,
			Vector3(side * centre_offset, rail_y, 0.0))
		rail.name = "FrameRail_%s" % ("Right" if side > 0.0 else "Left")
		add_child(rail)
	var plinth_half := outer - PLINTH_INSET
	var plinth := _make_box(
		Vector3(plinth_half * 2.0, PLINTH_DEPTH, plinth_half * 2.0),
		FRAME_COLOR,
		Vector3(0.0, -SQUARE_THICKNESS - PLINTH_DEPTH * 0.5, 0.0)
	)
	plinth.name = "BoardPlinth"
	add_child(plinth)


func _square_overlay(square: String, color: Color, prefix: String) -> MeshInstance3D:
	var overlay := _make_box(
		Vector3(SQUARE_SIZE * 0.84, 0.026, SQUARE_SIZE * 0.84),
		color,
		Vector3(square_to_world(square, BOARD_SURFACE_Y + 0.012))
	)
	overlay.name = "%s_%s" % [prefix, square]
	return overlay


func _make_box(dimensions: Vector3, color: Color, position: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	mesh.mesh = box
	mesh.material_override = _material(color)
	mesh.position = position
	return mesh


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.78
	return material
