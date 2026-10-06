extends RefCounted

## Builds the board's render mesh as three material surfaces.
##
## SurfaceTool is used here in the same way described by the Godot procedural
## geometry documentation: primitives are appended to a surface and committed
## to one ArrayMesh. The board keeps its square marker nodes separately for
## interaction and diagnostics; those nodes do not carry render geometry.

static func build(
	board_size: int,
	square_size: float,
	square_gap: float,
	square_bevel: float,
	square_thickness: float,
	frame_margin: float,
	frame_lip: float,
	frame_depth: float,
	plinth_depth: float,
	plinth_inset: float,
	light_material: Material,
	dark_material: Material,
	frame_material: Material
) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var light := SurfaceTool.new()
	var dark := SurfaceTool.new()
	var frame := SurfaceTool.new()
	light.begin(Mesh.PRIMITIVE_TRIANGLES)
	dark.begin(Mesh.PRIMITIVE_TRIANGLES)
	frame.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half := board_size * square_size * 0.5
	var tile_size := square_size - square_gap
	for rank in board_size:
		for file in board_size:
			var centre := Vector3(
				(file - (board_size - 1) * 0.5) * square_size,
				-square_thickness * 0.5,
				(rank - (board_size - 1) * 0.5) * square_size
			)
			var target := light if (file + rank) % 2 == 0 else dark
			_append_beveled_box(
				target,
				Vector3(tile_size, square_thickness, tile_size),
				square_bevel,
				centre)

	var outer := half + frame_margin
	var centre_offset := (outer + half) * 0.5
	var rail_y := frame_lip - frame_depth * 0.5
	for side in [-1.0, 1.0]:
		var along_x := BoxMesh.new()
		along_x.size = Vector3(outer * 2.0, frame_depth, frame_margin)
		frame.append_from(along_x, 0,
			Transform3D(Basis.IDENTITY, Vector3(0.0, rail_y, side * centre_offset)))
		var along_z := BoxMesh.new()
		along_z.size = Vector3(frame_margin, frame_depth, half * 2.0)
		frame.append_from(along_z, 0,
			Transform3D(Basis.IDENTITY, Vector3(side * centre_offset, rail_y, 0.0)))

	var plinth_half := outer - plinth_inset
	var plinth := BoxMesh.new()
	plinth.size = Vector3(plinth_half * 2.0, plinth_depth, plinth_half * 2.0)
	frame.append_from(plinth, 0,
		Transform3D(Basis.IDENTITY,
			Vector3(0.0, -square_thickness - plinth_depth * 0.5, 0.0)))

	light.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, light_material)
	dark.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, dark_material)
	frame.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, frame_material)
	return mesh


## Emits a box with a chamfered top edge. The bottom remains flat so every tile
## keeps a precise playing surface while the bevel gives the light a controlled
## edge to catch. Faces are emitted with their own vertices and normals, which
## keeps the top, sides, and chamfer visually crisp under directional light.
static func _append_beveled_box(
	tool: SurfaceTool, size: Vector3, bevel: float, centre: Vector3
) -> void:
	var half := size * 0.5
	var amount := clampf(bevel, 0.0, minf(half.x, minf(half.y, half.z)) * 0.5)
	var top_side := half.y - amount
	var local_faces := [
		[Vector3(0.0, 0.0, 1.0), [
			Vector3(-half.x, -half.y, half.z), Vector3(half.x, -half.y, half.z),
			Vector3(half.x, top_side, half.z), Vector3(-half.x, top_side, half.z)]],
		[Vector3(0.0, 0.0, -1.0), [
			Vector3(half.x, -half.y, -half.z), Vector3(-half.x, -half.y, -half.z),
			Vector3(-half.x, top_side, -half.z), Vector3(half.x, top_side, -half.z)]],
		[Vector3(1.0, 0.0, 0.0), [
			Vector3(half.x, -half.y, half.z), Vector3(half.x, -half.y, -half.z),
			Vector3(half.x, top_side, -half.z), Vector3(half.x, top_side, half.z)]],
		[Vector3(-1.0, 0.0, 0.0), [
			Vector3(-half.x, -half.y, -half.z), Vector3(-half.x, -half.y, half.z),
			Vector3(-half.x, top_side, half.z), Vector3(-half.x, top_side, -half.z)]]
	]
	for face in local_faces:
		_append_quad(tool, face[0], face[1], centre)

	if amount <= 0.0:
		_append_quad(tool, Vector3.UP, [
			Vector3(-half.x, half.y, half.z), Vector3(half.x, half.y, half.z),
			Vector3(half.x, half.y, -half.z), Vector3(-half.x, half.y, -half.z)], centre)
	else:
		var chamfers := [
			[Vector3(0.0, 1.0, 1.0).normalized(), [
				Vector3(-half.x, top_side, half.z), Vector3(half.x, top_side, half.z),
				Vector3(half.x - amount, half.y, half.z - amount),
				Vector3(-half.x + amount, half.y, half.z - amount)]],
			[Vector3(0.0, 1.0, -1.0).normalized(), [
				Vector3(half.x, top_side, -half.z), Vector3(-half.x, top_side, -half.z),
				Vector3(-half.x + amount, half.y, -half.z + amount),
				Vector3(half.x - amount, half.y, -half.z + amount)]],
			[Vector3(1.0, 1.0, 0.0).normalized(), [
				Vector3(half.x, top_side, half.z), Vector3(half.x, top_side, -half.z),
				Vector3(half.x - amount, half.y, -half.z + amount),
				Vector3(half.x - amount, half.y, half.z - amount)]],
			[Vector3(-1.0, 1.0, 0.0).normalized(), [
				Vector3(-half.x, top_side, -half.z), Vector3(-half.x, top_side, half.z),
				Vector3(-half.x + amount, half.y, half.z - amount),
				Vector3(-half.x + amount, half.y, -half.z + amount)]]
		]
		for chamfer in chamfers:
			_append_quad(tool, chamfer[0], chamfer[1], centre)
		_append_quad(tool, Vector3.UP, [
			Vector3(-half.x + amount, half.y, half.z - amount),
			Vector3(half.x - amount, half.y, half.z - amount),
			Vector3(half.x - amount, half.y, -half.z + amount),
			Vector3(-half.x + amount, half.y, -half.z + amount)], centre)

	_append_quad(tool, Vector3.DOWN, [
		Vector3(-half.x, -half.y, -half.z), Vector3(half.x, -half.y, -half.z),
		Vector3(half.x, -half.y, half.z), Vector3(-half.x, -half.y, half.z)], centre)


static func _append_quad(
	tool: SurfaceTool, normal: Vector3, corners: Array, centre: Vector3
) -> void:
	for triangle in [[0, 2, 1], [0, 3, 2]]:
		for corner_index in triangle:
			tool.set_normal(normal)
			tool.add_vertex(centre + corners[corner_index])
