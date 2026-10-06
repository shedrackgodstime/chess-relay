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
	rotation.y = PI if side == "black" else 0.0
	if is_node_ready():
		_build_visual()


func _build_visual() -> void:
	rotation.y = PI if side == "black" else 0.0
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
	base.position.y = 0.08
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
	_add_crown(root_material)


func _add_crown(material: StandardMaterial3D) -> void:
	var crown := MeshInstance3D.new()
	var crown_mesh: Mesh
	match piece_type:
		"pawn":
			var pawn_head := SphereMesh.new()
			pawn_head.radius = 0.16
			pawn_head.height = 0.32
			crown_mesh = pawn_head
		"rook":
			var rook_top := CylinderMesh.new()
			rook_top.top_radius = 0.24
			rook_top.bottom_radius = 0.29
			rook_top.height = 0.18
			crown_mesh = rook_top
		"bishop":
			var bishop_top := CylinderMesh.new()
			bishop_top.top_radius = 0.06
			bishop_top.bottom_radius = 0.2
			bishop_top.height = 0.3
			crown_mesh = bishop_top
		"knight":
			var knight_top := SphereMesh.new()
			knight_top.radius = 0.2
			knight_top.height = 0.42
			crown_mesh = knight_top
		"queen":
			var queen_top := SphereMesh.new()
			queen_top.radius = 0.22
			queen_top.height = 0.44
			crown_mesh = queen_top
		"king":
			var king_top := BoxMesh.new()
			king_top.size = Vector3(0.28, 0.32, 0.28)
			crown_mesh = king_top
	crown.mesh = crown_mesh
	crown.material_override = material
	crown.position.y = 0.86
	if piece_type == "knight":
		crown.rotation_degrees.x = -18.0
	if piece_type == "king":
		crown.scale = Vector3(0.75, 1.0, 0.75)
	add_child(crown)
	if piece_type == "king":
		_add_king_cross(material)


func _add_king_cross(material: StandardMaterial3D) -> void:
	var vertical := MeshInstance3D.new()
	var vertical_mesh := BoxMesh.new()
	vertical_mesh.size = Vector3(0.07, 0.26, 0.07)
	vertical.mesh = vertical_mesh
	vertical.material_override = material
	vertical.position.y = 1.17
	add_child(vertical)
	var horizontal := MeshInstance3D.new()
	var horizontal_mesh := BoxMesh.new()
	horizontal_mesh.size = Vector3(0.22, 0.07, 0.07)
	horizontal.mesh = horizontal_mesh
	horizontal.material_override = material
	horizontal.position.y = 1.12
	add_child(horizontal)
