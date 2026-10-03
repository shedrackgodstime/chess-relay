extends SceneTree

## Headless checks for the procedural board.
##
##     godot-headless --headless --script res://tools/test_board.gd

var _failures := 0


func _init() -> void:
	Quality.set_preset(Quality.Preset.MEDIUM)
	var mesh := BoardMesh.build()
	_check("board builds", mesh.get_surface_count() == 3,
		"surfaces=%d (expect light, dark, frame)" % mesh.get_surface_count())

	# Light squares, dark squares, then the frame and plinth. Tiles are
	# bevelled boxes at 20 triangles each; rails and plinth are plain boxes.
	var expected := [32 * 20, 32 * 20, 4 * 12 + 12]
	for surface in mesh.get_surface_count():
		var indices: PackedInt32Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
		var tris := int(indices.size() / 3.0)
		_check("surface %d triangle count" % surface, tris == expected[surface],
			"tris=%d expected=%d" % [tris, expected[surface]])

	var total := 0
	for surface in mesh.get_surface_count():
		total += int((mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3.0)
	_check("board is 64 tiles plus frame", total == 64 * 20 + 5 * 12,
		"tris=%d" % total)

	var aabb := mesh.get_aabb()
	var outer := (BoardMesh.playing_half_extent() + BoardMesh.FRAME_MARGIN) * 2.0
	_check("board is square", is_equal_approx(aabb.size.x, aabb.size.z),
		"x=%.3f z=%.3f" % [aabb.size.x, aabb.size.z])
	_check("board footprint matches the frame", is_equal_approx(aabb.size.x, outer),
		"x=%.3f expected=%.3f" % [aabb.size.x, outer])

	# Pieces are authored with their base at y = 0, so the playing surface has
	# to be flush with the origin.
	_check("playing surface is at y = 0",
		aabb.position.y < 0.0 and aabb.end.y > 0.0 and aabb.end.y < 0.1,
		"y range %.3f..%.3f" % [aabb.position.y, aabb.end.y])

	# An even-sized board has no centre square: the origin is the shared corner
	# of the four middle squares.
	_check("board centre is the shared corner of the middle squares",
		BoardMesh.square_position(3, 3) == Vector3(-0.5, 0.0, -0.5)
			and BoardMesh.square_position(4, 4) == Vector3(0.5, 0.0, 0.5),
		"(3,3) -> %s  (4,4) -> %s" % [
			BoardMesh.square_position(3, 3), BoardMesh.square_position(4, 4)
		])
	_check("a1 is the near-left corner",
		BoardMesh.square_position(0, 0) == Vector3(-3.5, 0.0, -3.5),
		"(0,0) -> %s" % BoardMesh.square_position(0, 0))
	_check("h8 is the far-right corner",
		BoardMesh.square_position(7, 7) == Vector3(3.5, 0.0, 3.5),
		"(7,7) -> %s" % BoardMesh.square_position(7, 7))
	_check("squares are one unit apart",
		BoardMesh.square_position(1, 0).distance_to(BoardMesh.square_position(0, 0)) == 1.0,
		"")
	_check("square gap leaves each tile visible", BoardMesh.SQUARE_GAP > 0.0,
		"gap=%.3f" % BoardMesh.SQUARE_GAP)

	# Every material should be opaque and non-default, or the board renders flat.
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface) as StandardMaterial3D
		_check("surface %d has a material" % surface, material != null, "")
		if material != null:
			_check("surface %d colour is set" % surface,
				material.albedo_color != Color.BLACK, str(material.albedo_color))

	if _failures == 0:
		if failures > 0:
			print("board: %d check(s) failed" % failures)
		else:
			print("board: all checks passed")
	else:
		printerr("board: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


## Failed checks, counted. The summary line is printed from this rather than
## printed regardless, because a suite that says it passed while printing failures is
## worse than no suite at all: it is believed.
var failures := 0


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		print("  ok   %s  %s" % [label, detail])
	else:
		failures += 1
		_failures += 1
		printerr("  FAIL %s  %s" % [label, detail])
