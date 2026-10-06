class_name ChessPieceView
extends Node3D

signal piece_pressed(piece: ChessPieceView)

const PIECE_SCALE := 16.0
const KNIGHT_FACING_OFFSET := deg_to_rad(60.0)
const CATALOG_SCRIPT := preload("res://src/game/pieces/piece_catalog.gd")
const WHITE_MATERIAL := preload("res://src/game/pieces/piece_white_material.tres")
const BLACK_MATERIAL := preload("res://src/game/pieces/piece_black_material.tres")

@export_enum("pawn", "rook", "knight", "bishop", "queen", "king") var piece_type := "pawn"
@export_enum("white", "black") var side := "white"

func _ready() -> void:
	if get_child_count() == 0:
		configure(piece_type, side)

func configure(type: String, piece_side: String) -> void:
	if not CATALOG_SCRIPT.contains(type):
		push_error("Unknown chess piece type: %s" % type)
		return
	if piece_side != "white" and piece_side != "black":
		push_error("Unknown chess piece side: %s" % piece_side)
		return
	piece_type = type
	side = piece_side
	for child in get_children():
		child.free()
	var source = CATALOG_SCRIPT.scene_for(piece_type).instantiate()
	var mesh := _find_mesh(source)
	if mesh == null:
		push_error("Piece scene has no mesh: %s" % piece_type)
		source.free()
		return
	source.remove_child(mesh)
	source.free()
	mesh.name = "Mesh"
	mesh.scale = Vector3.ONE * PIECE_SCALE
	mesh.position.y = -_mesh_min_y(mesh) * PIECE_SCALE
	mesh.material_override = WHITE_MATERIAL if side == "white" else BLACK_MATERIAL
	add_child(mesh)
	_build_input_surface(mesh)
	if piece_type == "knight":
		rotation.y = PI + KNIGHT_FACING_OFFSET if side == "white" else -KNIGHT_FACING_OFFSET
	else:
		rotation.y = PI if side == "black" else 0.0


func _build_input_surface(mesh: MeshInstance3D) -> void:
	var area := Area3D.new()
	area.name = "PieceInputSurface"
	area.collision_layer = 2
	area.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var bounds := mesh.get_aabb()
	shape.size = bounds.size * PIECE_SCALE
	collision.shape = shape
	area.position = mesh.position + bounds.get_center() * PIECE_SCALE
	area.input_event.connect(_on_piece_input)
	area.add_child(collision)
	add_child(area)


func _on_piece_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3,
		_shape_idx: int) -> void:
	var pressed: bool = event is InputEventMouseButton and event.pressed \
		and event.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventScreenTouch:
		pressed = event.pressed
	if pressed:
		piece_pressed.emit(self)
		get_viewport().set_input_as_handled()

func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null

func _mesh_min_y(mesh: MeshInstance3D) -> float:
	return mesh.get_aabb().position.y
