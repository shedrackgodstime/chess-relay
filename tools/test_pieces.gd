extends SceneTree

## Headless checks for the procedural pieces.
##
## Verifies that every piece produces one closed, outward-facing mesh and that
## the set is proportioned sanely. It cannot tell you the knight looks like a
## horse; use tools/render_preview.gd for that.

var _failures := 0


func _init() -> void:
	Quality.set_preset(Quality.Preset.MEDIUM)
	var heights := {}
	for type in [
		PieceProfiles.Type.PAWN,
		PieceProfiles.Type.KNIGHT,
		PieceProfiles.Type.BISHOP,
		PieceProfiles.Type.ROOK,
		PieceProfiles.Type.QUEEN,
		PieceProfiles.Type.KING,
	]:
		var mesh := PieceMesh.build(type, PieceMesh.LIGHT_SIDE)
		var name := PieceProfiles.type_name(type)
		heights[type] = mesh.get_aabb().size.y

		_check("%s builds a single surface" % name, mesh.get_surface_count() == 1,
			"surfaces=%d" % mesh.get_surface_count())
		_check("%s has triangles" % name, mesh.get_surface_count() > 0, "")

		for side in [PieceMesh.LIGHT_SIDE, PieceMesh.DARK_SIDE]:
			var sided := PieceMesh.build(type, side)
			_check("%s side %d builds" % [name, side], sided.get_surface_count() == 1, "")

		var arrays := mesh.surface_get_arrays(0)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		_check("%s index count is a multiple of 3" % name, indices.size() % 3 == 0,
			"indices=%d" % indices.size())
		_check("%s has no degenerate triangles" % name,
			_degenerate_count(vertices, indices) == 0,
			"tris=%d" % (int(indices.size() / 3.0)))
		# Godot winds front faces so the right-hand normal opposes the stored
		# normals. See the note in geometry/lathe.gd.
		_check("%s winding matches the Godot convention" % name,
			_winding_score(vertices, normals, indices) < -0.5,
			"mean dot(right-hand, stored) = %+.3f" % _winding_score(vertices, normals, indices))
		_check("%s is a closed solid" % name, absf(_volume(vertices, indices)) > 0.0,
			"|volume|=%.4f" % absf(_volume(vertices, indices)))
		_check("%s sits on the board plane" % name,
			is_equal_approx(mesh.get_aabb().position.y, 0.0),
			"min_y=%.4f" % mesh.get_aabb().position.y)

		var aabb := mesh.get_aabb()
		_check("%s fits inside its square" % name,
			aabb.size.x <= 1.0 and aabb.size.z <= 1.0,
			"x=%.3f z=%.3f" % [aabb.size.x, aabb.size.z])

	# The tier lever actually moves geometry density.
	Quality.set_preset(Quality.Preset.LOW)
	BoardMaterials.clear_cache()
	PieceMaterials.clear_cache()
	var low_tris := (PieceMesh.build(PieceProfiles.Type.QUEEN, 0).surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
	Quality.set_preset(Quality.Preset.HIGH)
	BoardMaterials.clear_cache()
	PieceMaterials.clear_cache()
	var high_tris := (PieceMesh.build(PieceProfiles.Type.QUEEN, 0).surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
	Quality.set_preset(Quality.Preset.MEDIUM)
	BoardMaterials.clear_cache()
	PieceMaterials.clear_cache()
	_check("quality tiers scale geometry density", low_tris > 0 and high_tris > low_tris * 2,
		"low=%d high=%d" % [low_tris, high_tris])

	_check("unknown type builds nothing",
		PieceMesh.build(99, 0).get_surface_count() == 0, "")
	_check("bad side still builds", PieceMesh.build(PieceProfiles.Type.PAWN, 7).get_surface_count() == 1, "")

	# A Staunton set ranks king > queen > bishop > rook > knight > pawn.
	var order := [
		PieceProfiles.Type.KING, PieceProfiles.Type.QUEEN, PieceProfiles.Type.BISHOP,
		PieceProfiles.Type.ROOK, PieceProfiles.Type.KNIGHT, PieceProfiles.Type.PAWN,
	]
	for i in order.size() - 1:
		var taller: float = heights[order[i]]
		var shorter: float = heights[order[i + 1]]
		_check("%s is taller than %s" % [
				PieceProfiles.type_name(order[i]),
				PieceProfiles.type_name(order[i + 1])],
			taller > shorter,
			"%.3f vs %.3f" % [taller, shorter])

	var summary: PackedStringArray = []
	for type in heights:
		summary.append("%s=%.2f" % [PieceProfiles.type_name(type), heights[type]])
	print("heights: " + ", ".join(summary))

	if _failures == 0:
		print("pieces: all checks passed")
	else:
		printerr("pieces: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _volume(vertices: PackedVector3Array, indices: PackedInt32Array) -> float:
	var total := 0.0
	for i in range(0, indices.size(), 3):
		total += vertices[indices[i]].dot(
			vertices[indices[i + 1]].cross(vertices[indices[i + 2]]))
	return total / 6.0


## Mean dot(right-hand triangle normal, stored vertex normals). Godot's own
## built-in meshes score -1.000.
func _winding_score(
	vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array
) -> float:
	var total := 0.0
	var count := 0
	for i in range(0, indices.size(), 3):
		var a: Vector3 = vertices[indices[i]]
		var b: Vector3 = vertices[indices[i + 1]]
		var c: Vector3 = vertices[indices[i + 2]]
		var right_hand := (b - a).cross(c - a)
		if right_hand.length_squared() < 1e-16:
			continue
		var stored := (
			normals[indices[i]] + normals[indices[i + 1]] + normals[indices[i + 2]]
		).normalized()
		total += right_hand.normalized().dot(stored)
		count += 1
	return total / maxf(count, 1)


func _degenerate_count(vertices: PackedVector3Array, indices: PackedInt32Array) -> int:
	var count := 0
	for i in range(0, indices.size(), 3):
		var a: Vector3 = vertices[indices[i]]
		var b: Vector3 = vertices[indices[i + 1]]
		var c: Vector3 = vertices[indices[i + 2]]
		if (b - a).cross(c - a).length_squared() < 1e-14:
			count += 1
	return count


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		print("  ok   %s  %s" % [label, detail])
	else:
		_failures += 1
		printerr("  FAIL %s  %s" % [label, detail])
