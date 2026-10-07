class_name ChessPieceView
extends Node3D

signal piece_pressed(piece: ChessPieceView)

const PIECE_SCALE := 16.0
const KNIGHT_FACING_OFFSET := deg_to_rad(60.0)
const WHITE_MATERIAL := preload("res://src/game/pieces/piece_white_material.tres")
const BLACK_MATERIAL := preload("res://src/game/pieces/piece_black_material.tres")

## Which shape to draw, as an identity that arrived over the bridge.
##
## Deliberately a plain String rather than `@export_enum`. An enum would be a
## second list of piece types in GDScript, beside the one in Rust's
## `chess_core`, and it would show an editor dropdown implying this project is
## the authority on which pieces exist. `board_build_order.md` argues this at
## length ("No piece enum in GDScript"); this is that decision, made. The
## identity is whatever the core sends, and an identity with no shape here is
## refused by `configure` rather than approximated.
var piece_type := "pawn"
var side := "white"

## The square this piece stands on, set when the position is built from the
## core's FEN.
##
## Carried as data rather than parsed back out of the node name, which is what
## `_on_piece_pressed` used to do and which broke the moment a piece name was
## formatted differently.
var square := ""


func _ready() -> void:
	if get_child_count() == 0:
		configure(piece_type, side)

func configure(type: String, piece_side: String, at_square := "") -> void:
	if not ChessPieceCatalog.contains(type):
		push_error("Unknown chess piece type: %s" % type)
		return
	if piece_side != "white" and piece_side != "black":
		push_error("Unknown chess piece side: %s" % piece_side)
		return
	piece_type = type
	side = piece_side
	square = at_square
	for child in get_children():
		child.free()
	var source: Node = ChessPieceCatalog.scene_for(piece_type).instantiate()
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
	if ChessBoardView.is_selecting_press(event):
		piece_pressed.emit(self)
		# The tap can rebuild the board synchronously, detaching this node
		# mid-emission; only mark handled while still inside the tree.
		if is_inside_tree():
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
