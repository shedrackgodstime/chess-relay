class_name ChessPieceView
extends Node3D

@export_enum("pawn", "rook", "knight", "bishop", "queen", "king") var piece_type := "pawn"
@export_enum("white", "black") var side := "white"

const WHITE_PIECE := Color(0.92, 0.86, 0.74, 1.0)
const BLACK_PIECE := Color(0.10, 0.07, 0.05, 1.0)


func _ready() -> void:
	_build_visual()


func configure(type: String, piece_side: String) -> void:
	piece_type = type
	side = piece_side
	if is_node_ready():
		_build_visual()


func _build_visual() -> void:
	for child in get_children():
		child.queue_free()
	var root_material := StandardMaterial3D.new()
	root_material.albedo_color = WHITE_PIECE if side == "white" else BLACK_PIECE
	root_material.roughness = 0.5
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.28
	base_mesh.bottom_radius = 0.36
	base_mesh.height = 0.16
	base.mesh = base_mesh
	base.material_override = root_material
	base.position.y = 0.1
	add_child(base)
	var body := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.16 if piece_type == "pawn" else 0.24
	body_mesh.bottom_radius = 0.25
	body_mesh.height = 0.5 if piece_type == "pawn" else 0.72
	body.mesh = body_mesh
	body.material_override = root_material
	body.position.y = 0.42
	add_child(body)
	if piece_type != "pawn":
		var crown := MeshInstance3D.new()
		var crown_mesh := SphereMesh.new()
		crown_mesh.radius = 0.2 if piece_type == "king" else 0.16
		crown_mesh.height = crown_mesh.radius * 2.0
		crown.mesh = crown_mesh
		crown.material_override = root_material
		crown.position.y = 0.86
		add_child(crown)
