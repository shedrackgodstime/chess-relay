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
			var tile := BoxMesh.new()
			tile.size = Vector3(tile_size, square_thickness, tile_size)
			var target := light if (file + rank) % 2 == 0 else dark
			target.append_from(tile, 0, Transform3D(Basis.IDENTITY, centre))

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
