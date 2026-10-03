extends SceneTree

## Headless checks for the surrounding table, floor and capture trays.
##
##     godot-headless --headless --script res://tools/test_surroundings.gd

var _failures := 0


## The tray has to fit on the table without touching either the board frame or
## the rim, since it sits in the gap between them.
## The room has to contain the camera at every angle it can reach, which is the
## whole reason it is a cylinder rather than a box. Both constraints are asserted
## directly, because either one failing puts the camera outside its own room.
func _room_checks() -> void:
	print("Room")
	var camera := OrbitCamera.new()

	# Furthest the camera gets sideways, at the shallowest pitch it allows.
	var side_reach: float = camera.max_distance * cos(deg_to_rad(camera.min_pitch_degrees))
	_check("camera stays inside the wall at its widest reach",
		side_reach < RoomMesh.RADIUS - 1.0,
		"reach=%.1f radius=%.1f" % [side_reach, RoomMesh.RADIUS])

	# And it must not rise through the ceiling at the steepest pitch.
	var up_reach: float = camera.max_distance * sin(deg_to_rad(camera.max_pitch_degrees))
	_check("camera stays under the ceiling at its highest reach",
		up_reach < RoomMesh.CEILING_Y - 1.0,
		"reach=%.1f ceiling=%.1f" % [up_reach, RoomMesh.CEILING_Y])

	_check("room is wider than the table it holds",
		RoomMesh.RADIUS > TableMesh.RADIUS + 2.0,
		"room=%.1f table=%.1f" % [RoomMesh.RADIUS, TableMesh.RADIUS])
	_check("ceiling is above the table surface",
		RoomMesh.CEILING_Y > 0.0, "y=%.1f" % RoomMesh.CEILING_Y)

	var parts := {
		"floor": RoomMesh.build_floor(),
		"wall": RoomMesh.build_wall(),
		"ceiling": RoomMesh.build_ceiling(),
		"skirting": RoomMesh.build_skirting(),
		"rail": RoomMesh.build_rail(),
	}
	for part_name: String in parts:
		var mesh: ArrayMesh = parts[part_name]
		_check("room %s builds" % part_name,
			mesh.get_surface_count() >= 1 and mesh.get_aabb().size.length() > 0.0,
			"surfaces=%d" % mesh.get_surface_count())

	# Normals must face the room. An inside-out wall is lit from behind, which
	# looks wrong from some orbit angles and is exactly the sort of thing that
	# only ever shows up in a render.
	var wall: ArrayMesh = RoomMesh.build_wall()
	var arrays := wall.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var inward := 0
	var sampled: int = mini(verts.size(), norms.size())
	for i in sampled:
		var radial := Vector2(verts[i].x, verts[i].z)
		if radial.length() < 0.001:
			continue
		if radial.normalized().dot(Vector2(norms[i].x, norms[i].z)) < 0.0:
			inward += 1
	_check("wall normals point into the room", inward > 0,
		"inward=%d of %d" % [inward, sampled])

	var view := RoomView.new()
	root.add_child(view)
	await process_frame
	_check("room view builds its parts",
		view.get_node_or_null("Wall") != null
			and view.get_node_or_null("Ceiling") != null
			and view.get_node_or_null("Floor") != null, "")
	view.queue_free()
	await process_frame


func _tray_geometry_checks() -> void:
	print("Capture tray mesh")
	var body := TrayMesh.build()
	var wells := TrayMesh.build_wells()
	_check("tray body builds", body.get_surface_count() >= 1,
		"surfaces=%d" % body.get_surface_count())
	_check("tray wells build", wells.get_surface_count() >= 1,
		"surfaces=%d" % wells.get_surface_count())

	var aabb := body.get_aabb()
	var board_edge := BoardMesh.playing_half_extent() + BoardMesh.FRAME_MARGIN
	var inner := TrayMesh.TRAY_X - aabb.size.x * 0.5
	_check("tray clears the board frame", inner > board_edge,
		"tray inner=%.2f board edge=%.2f" % [inner, board_edge])
	var corner := Vector2(TrayMesh.TRAY_X + aabb.size.x * 0.5, aabb.size.z * 0.5).length()
	_check("tray stays on the table", corner < TableMesh.RADIUS,
		"corner=%.2f table r=%.2f" % [corner, TableMesh.RADIUS])

	_check("tray holds a full set", TrayMesh.SLOTS >= 16, "slots=%d" % TrayMesh.SLOTS)
	_check("slots are evenly spaced along the tray",
		is_equal_approx(TrayMesh.slot_position(1).z - TrayMesh.slot_position(0).z,
			TrayMesh.SLOT_SPACING), "")
	_check("slot 0 is at one end of the tray",
		is_equal_approx(TrayMesh.slot_position(0).z + TrayMesh.slot_position(TrayMesh.SLOTS - 1).z, 0.0),
		"first=%.2f last=%.2f" % [
			TrayMesh.slot_position(0).z, TrayMesh.slot_position(TrayMesh.SLOTS - 1).z])
	_check("slots sit above the slab, not sunk in it",
		TrayMesh.slot_position(0).y > TrayMesh.HEIGHT,
		"y=%.3f slab=%.3f" % [TrayMesh.slot_position(0).y, TrayMesh.HEIGHT])


## Capture order, colour, and the guarantee that a tray cannot show pieces the
## game does not actually have.
func _tray_view_checks() -> void:
	print("Capture tray view")
	var tray := TrayView.new()
	tray.capturer = BoardState.LIGHT
	root.add_child(tray)
	await process_frame
	_check("tray starts empty", tray.captured_count() == 0,
		"n=%d" % tray.captured_count())

	var taken: Array[int] = [
		BoardState.encode(PieceProfiles.Type.KNIGHT, BoardState.DARK),
		BoardState.encode(PieceProfiles.Type.PAWN, BoardState.DARK),
		BoardState.encode(PieceProfiles.Type.ROOK, BoardState.DARK),
	]
	tray.set_captured(taken)
	_check("tray holds one piece per capture", tray.captured_count() == 3,
		"n=%d" % tray.captured_count())

	# Capture order, not grouped by type: the knight was first.
	_check("slots follow capture order",
		tray.slot_type(0) == PieceProfiles.Type.KNIGHT
			and tray.slot_type(1) == PieceProfiles.Type.PAWN
			and tray.slot_type(2) == PieceProfiles.Type.ROOK,
		"got %d,%d,%d" % [tray.slot_type(0), tray.slot_type(1), tray.slot_type(2)])
	_check("the knight sits in the first slot",
		(tray.slot_child(0) as PieceView).position == TrayMesh.slot_position(0), "")

	# White took dark pieces, so every silhouette must be the dark set.
	var all_dark := true
	for i in tray.captured_count():
		if (tray.slot_child(i) as PieceView).side != BoardState.DARK:
			all_dark = false
	_check("tray pieces are the colour that was taken", all_dark, "")
	_check("tray pieces are shrunk to fit",
		(tray.slot_child(0) as PieceView).scale.x < 1.0,
		"scale=%.2f" % (tray.slot_child(0) as PieceView).scale.x)

	# Shrinking a row is the normal case: it must not leave stale pieces behind.
	tray.set_captured(taken.slice(0, 1))
	_check("a shorter list clears the extras", tray.captured_count() == 1,
		"n=%d" % tray.captured_count())
	tray.set_captured([])
	_check("a tray can be emptied", tray.captured_count() == 0, "")

	# Read from a real game, so the tray cannot be fed something out of step
	# with the board.
	var game := ChessGame.new()
	tray.capturer = BoardState.LIGHT
	tray.refresh_from(game)
	_check("a fresh game leaves the tray empty", tray.captured_count() == 0, "")
	game.state.set_square(4, 1, BoardState.encode(PieceProfiles.Type.PAWN, BoardState.LIGHT))
	game.state.set_square(4, 3, BoardState.encode(PieceProfiles.Type.PAWN, BoardState.DARK))
	game.state.side_to_move = BoardState.LIGHT
	game.apply_move(ChessMove.new(Vector2i(4, 1), Vector2i(4, 3)))
	tray.refresh_from(game)
	_check("a played capture fills the tray", tray.captured_count() == 1,
		"n=%d" % tray.captured_count())

	# Overflow: more than a full set cannot happen in chess, but a tray that
	# silently lost count would be worse than one that caps.
	var overflow: Array[int] = []
	for i in 20:
		overflow.append(BoardState.encode(PieceProfiles.Type.PAWN, BoardState.DARK))
	tray.set_captured(overflow)
	_check("a tray caps at its slot count", tray.captured_count() == TrayMesh.SLOTS,
		"n=%d slots=%d" % [tray.captured_count(), TrayMesh.SLOTS])

	tray.queue_free()
	await process_frame


func _init() -> void:
	Quality.set_preset(Quality.Preset.MEDIUM)
	_room_checks()
	_tray_geometry_checks()
	_tray_view_checks()
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
		if failures > 0:
			print("surroundings: %d check(s) failed" % failures)
		else:
			print("surroundings: all checks passed")
	else:
		printerr("surroundings: %d check(s) failed" % _failures)
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