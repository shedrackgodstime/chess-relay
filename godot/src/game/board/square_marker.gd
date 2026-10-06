extends MeshInstance3D

## Reusable, unshaded frame placed just above a board square.
##
## The marker is deliberately a frame rather than a filled transparent box:
## the board grain and piece remain visible underneath it at every camera angle.

const OUTER := 0.86
const BAR := 0.055
const HEIGHT := 0.018

static func create(tint: Color) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.mesh = _build_mesh(tint)
	return marker


static func _build_mesh(tint: Color) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := OUTER * 0.5
	var pieces := [
		[Vector3(OUTER, HEIGHT, BAR), Vector3(0.0, 0.0, -half + BAR * 0.5)],
		[Vector3(OUTER, HEIGHT, BAR), Vector3(0.0, 0.0, half - BAR * 0.5)],
		[Vector3(BAR, HEIGHT, OUTER), Vector3(-half + BAR * 0.5, 0.0, 0.0)],
		[Vector3(BAR, HEIGHT, OUTER), Vector3(half - BAR * 0.5, 0.0, 0.0)]
	]
	for piece in pieces:
		var box := BoxMesh.new()
		box.size = piece[0]
		tool.append_from(box, 0, Transform3D(Basis.IDENTITY, piece[1]))
	var mesh := tool.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = Color(tint.r, tint.g, tint.b, 1.0)
	material.emission_energy_multiplier = 1.35
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.surface_set_material(0, material)
	return mesh
