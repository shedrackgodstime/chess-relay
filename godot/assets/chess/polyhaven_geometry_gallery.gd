extends Node3D

func _ready() -> void:
	$Camera3D.look_at(Vector3(0.0, 0.55, 0.0), Vector3.UP)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.86, 0.82, 0.73, 1.0)
	white.metallic = 0.18
	white.roughness = 0.28
	for piece in $Pieces.get_children():
		_apply_material(piece, white)

func _apply_material(node: Node, material: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		node.material_override = material
	for child in node.get_children():
		_apply_material(child, material)
