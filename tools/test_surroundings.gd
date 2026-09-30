extends SceneTree

## Headless checks for the surrounding table and floor.
##
##     godot-headless --headless --script res://tools/test_surroundings.gd

var _failures := 0


func _init() -> void:
	Quality.set_preset(Quality.Preset.MEDIUM)
	var mesh := TableMesh.build()
	_check("table builds one surface", mesh.get_surface_count() == 1,
		"surfaces=%d" % mesh.get_surface_count())

	var arrays := mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	_check("table has triangles", indices.size() >= 3, "tris=%d" % int(indices.size() / 3.0))

	var aabb := mesh.get_aabb()
	_check("table is round", is_equal_approx(aabb.size.x, aabb.size.z),
		"x=%.2f z=%.2f" % [aabb.size.x, aabb.size.z])
	_check("table radius is a little wider than the board",
		aabb.size.x * 0.5 > BoardMesh.playing_half_extent() + BoardMesh.FRAME_MARGIN,
		"table r=%.2f board edge=%.2f" % [
			aabb.size.x * 0.5, BoardMesh.playing_half_extent() + BoardMesh.FRAME_MARGIN])

	# The board's plinth bottom must clear the table top, otherwise the table
	# pushes up through the board when thicknesses are retuned.
	var plinth_bottom := -BoardMesh.SQUARE_THICKNESS - BoardMesh.PLINTH_DEPTH
	_check("table top sits below the board plinth",
		aabb.end.y <= plinth_bottom,
		"table top=%.3f plinth bottom=%.3f" % [aabb.end.y, plinth_bottom])
	_check("table has thickness", aabb.size.y > 0.1, "thickness=%.3f" % aabb.size.y)

	# Closed solid: the lathe profile has poles at both ends, so the mesh has
	# no boundary edges and the volume is outward-facing.
	var degen := 0
	for i in range(0, indices.size(), 3):
		var a: Vector3 = vertices[indices[i]]
		var b: Vector3 = vertices[indices[i + 1]]
		var c: Vector3 = vertices[indices[i + 2]]
		if (b - a).cross(c - a).length_squared() < 1e-14:
			degen += 1
	_check("table has no degenerate triangles", degen == 0, "degen=%d" % degen)

	var material := TableMesh.material()
	_check("table has a wood texture", material.albedo_texture != null, "")
	_check("floor has a material", TableMesh.floor_material().albedo_color != Color.BLACK, "")

	# The floor must be far below the table so it only reads as a horizon.
	_check("floor is well below the table",
		TableMesh.FLOOR_Y < TableMesh.TOP_Y - 1.0,
		"floor=%.2f table top=%.2f" % [TableMesh.FLOOR_Y, TableMesh.TOP_Y])

	if _failures == 0:
		print("surroundings: all checks passed")
	else:
		printerr("surroundings: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		print("  ok   %s  %s" % [label, detail])
	else:
		_failures += 1
		printerr("  FAIL %s  %s" % [label, detail])