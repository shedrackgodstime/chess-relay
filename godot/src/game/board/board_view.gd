class_name ChessBoardView
extends Node3D

const BOARD_MESH_SCRIPT := preload("res://src/game/board/board_mesh.gd")
const SQUARE_MARKER_SCRIPT := preload("res://src/game/board/square_marker.gd")

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

const LIGHT_SQUARE := Color(0.76, 0.67, 0.52, 1.0)
const DARK_SQUARE := Color(0.28, 0.20, 0.14, 1.0)
const FRAME_COLOR := Color(0.12, 0.08, 0.05, 1.0)
const HIGHLIGHT_COLOR := Color(0.95, 0.72, 0.24, 0.72)
const LAST_MOVE_COLOR := Color(0.92, 0.74, 0.28, 0.34)
const LEGAL_MOVE_COLOR := Color(0.32, 0.86, 0.55, 0.72)
const CHECK_COLOR := Color(0.92, 0.24, 0.2, 0.68)

var _squares_root: Node3D
var _highlights_root: Node3D
var _last_move_root: Node3D
var _legal_moves_root: Node3D
var _check_root: Node3D
var _coordinates_root: Node3D
var _highlighted_square := ""
var _square_colors: Array[Color] = []


func _ready() -> void:
	_build_board()
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
	var highlight := SQUARE_MARKER_SCRIPT.create_square(
		color,
		"SelectedSquare",
		square_to_world(square, BOARD_SURFACE_Y + 0.012)
	)
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
			_legal_moves_root.add_child(_legal_move_marker(square))


func set_check_square(square: String) -> void:
	_clear_root(_check_root)
	if not square.is_empty():
		_check_root.add_child(_square_overlay(square, CHECK_COLOR, "CheckSquare"))


func _build_board() -> void:
	_squares_root = Node3D.new()
	_squares_root.name = "Squares"
	add_child(_squares_root)
	_highlights_root = Node3D.new()
	_highlights_root.name = "Highlights"
	add_child(_highlights_root)
	_last_move_root = _new_overlay_root("LastMove")
	_legal_moves_root = _new_overlay_root("LegalMoves")
	_check_root = _new_overlay_root("Check")
	_square_colors = [LIGHT_SQUARE, DARK_SQUARE]
	_build_render_mesh()
	for rank in BOARD_SIZE:
		for file in BOARD_SIZE:
			var square := Node3D.new()
			square.name = "Square_%s%d" % [char("a".unicode_at(0) + file), rank + 1]
			square.position = square_to_world(
				"%s%d" % [char("a".unicode_at(0) + file), rank + 1],
				BOARD_SURFACE_Y - SQUARE_THICKNESS * 0.5)
			_squares_root.add_child(square)


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
	var pressed: bool = event is InputEventMouseButton and event.pressed \
		and event.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventScreenTouch:
		pressed = event.pressed
	if pressed:
		var square := world_to_square(event_position)
		if not square.is_empty():
			set_highlight(square)
			square_pressed.emit(square)
			get_viewport().set_input_as_handled()


func _clear_highlights() -> void:
	_highlighted_square = ""
	_clear_root(_highlights_root)


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


func _build_render_mesh() -> void:
	var board_surface := MeshInstance3D.new()
	board_surface.name = "BoardSurface"
	board_surface.mesh = BOARD_MESH_SCRIPT.build(
		BOARD_SIZE,
		SQUARE_SIZE,
		SQUARE_GAP,
		SQUARE_THICKNESS,
		FRAME_MARGIN,
		FRAME_LIP,
		FRAME_DEPTH,
		PLINTH_DEPTH,
		PLINTH_INSET,
		_material(LIGHT_SQUARE),
		_material(DARK_SQUARE),
		_material(FRAME_COLOR)
	)
	add_child(board_surface)


func _square_overlay(square: String, color: Color, prefix: String) -> MeshInstance3D:
	return SQUARE_MARKER_SCRIPT.create_square(
		color,
		"%s_%s" % [prefix, square],
		square_to_world(square, BOARD_SURFACE_Y + 0.012)
	)


func _legal_move_marker(square: String) -> MeshInstance3D:
	return SQUARE_MARKER_SCRIPT.create_dot(
		LEGAL_MOVE_COLOR,
		"LegalMove_%s" % square,
		square_to_world(square, BOARD_SURFACE_Y + 0.018)
	)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.78
	return material
