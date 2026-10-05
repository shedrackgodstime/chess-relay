class_name ChessBoardView
extends Node3D

signal square_pressed(square: String)

const BOARD_SIZE := 8
const SQUARE_SIZE := 1.0
const BOARD_HEIGHT := 0.16
const FRAME_MARGIN := 0.42

const LIGHT_SQUARE := Color(0.76, 0.67, 0.52, 1.0)
const DARK_SQUARE := Color(0.28, 0.20, 0.14, 1.0)
const FRAME_COLOR := Color(0.12, 0.08, 0.05, 1.0)
const HIGHLIGHT_COLOR := Color(0.95, 0.72, 0.24, 0.72)

var _squares_root: Node3D
var _highlights_root: Node3D
var _highlighted_square := ""
var _square_colors: Array[Color] = []


func _ready() -> void:
	_build_board()
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
		Vector3(square_to_world(square, BOARD_HEIGHT + 0.04))
	)
	highlight.name = "SelectedSquare"
	_highlights_root.add_child(highlight)


func get_highlighted_square() -> String:
	return _highlighted_square


func _build_board() -> void:
	_squares_root = Node3D.new()
	_squares_root.name = "Squares"
	add_child(_squares_root)
	_highlights_root = Node3D.new()
	_highlights_root.name = "Highlights"
	add_child(_highlights_root)
	_square_colors = [LIGHT_SQUARE, DARK_SQUARE]
	var footprint := BOARD_SIZE * SQUARE_SIZE + FRAME_MARGIN * 2.0
	var frame := _make_box(
		Vector3(footprint, 0.34, footprint), FRAME_COLOR, Vector3(0, -0.12, 0)
	)
	frame.name = "BoardFrame"
	add_child(frame)
	for rank in BOARD_SIZE:
		for file in BOARD_SIZE:
			var square := _make_box(
				Vector3(SQUARE_SIZE, BOARD_HEIGHT, SQUARE_SIZE),
					_square_colors[(file + rank) % 2],
				square_to_world("%s%d" % [char("a".unicode_at(0) + file), rank + 1], BOARD_HEIGHT * 0.5)
			)
			square.name = "Square_%s%d" % [char("a".unicode_at(0) + file), rank + 1]
			_squares_root.add_child(square)


func _build_input_surface() -> void:
	var area := Area3D.new()
	area.name = "BoardInputSurface"
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(BOARD_SIZE * SQUARE_SIZE, BOARD_HEIGHT, BOARD_SIZE * SQUARE_SIZE)
	collision.shape = shape
	area.add_child(collision)
	area.input_event.connect(_on_board_input)
	add_child(area)


func _on_board_input(_camera: Node, event: InputEvent, event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var square := world_to_square(event_position)
		if not square.is_empty():
			set_highlight(square)
			square_pressed.emit(square)


func _clear_highlights() -> void:
	_highlighted_square = ""
	for child in _highlights_root.get_children():
		child.queue_free()


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
