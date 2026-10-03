extends SceneTree

## Headless checks for square selection.
##
## The tap gesture itself (press/release timing) lives behind input events and
## is exercised on device; what is asserted here is everything around it: the
## screen-to-square ray mapping, the selection toggle, and the highlight mesh.
##
##     godot-headless --headless --script res://tools/test_selection.gd

var _failures := 0


func _init() -> void:
	Quality.set_preset(Quality.Preset.MEDIUM)
	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		printerr("  FAIL main.tscn did not load")
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	# Let _ready run so the camera frames and the highlight builds.
	await process_frame

	var main: Main = scene
	main.ai_opponent = false
	_check("nothing selected at start", main.selected == Vector2i(-1, -1),
		"selected=%s" % main.selected)
	_check("highlight hidden at start", not main.highlight.visible, "")

	# Input positions live in viewport space, which headlessly differs from
	# Window.size, so the centre comes from the camera's own viewport.
	var view_size := main.camera.get_viewport().get_visible_rect().size
	var center := view_size * 0.5
	var middle := main.screen_to_square(center)
	_check("screen centre hits a middle square",
		middle == Vector2i(3, 3) or middle == Vector2i(3, 4)
			or middle == Vector2i(4, 3) or middle == Vector2i(4, 4),
		"square=%s" % middle)

	# The middle is empty: tapping it with nothing selected selects nothing.
	main._tap(center)
	_check("empty square does not select", main.selected == Vector2i(-1, -1),
		"selected=%s" % main.selected)
	_check("highlight stays hidden", not main.highlight.visible, "")

	# Tapping a piece selects it; tapping it again deselects.
	_tap_square(main, Vector2i(0, 1))
	_check("tap selects the piece square", main.selected == Vector2i(0, 1),
		"selected=%s" % main.selected)
	_check("highlight shows on select", main.highlight.visible, "")
	_check("highlight sits on the square",
		main.highlight.position.distance_to(BoardMesh.square_position(0, 1)) < 0.05,
		"pos=%s" % main.highlight.position)
	_tap_square(main, Vector2i(0, 1))
	_check("second tap deselects", main.selected == Vector2i(-1, -1),
		"selected=%s" % main.selected)
	_check("highlight hides on deselect", not main.highlight.visible, "")

	# Tapping empty space clears the selection.
	_tap_square(main, Vector2i(0, 1))
	_check("reselect works", main.selected == Vector2i(0, 1), "")
	main._tap(Vector2(-50.0, -50.0))
	_check("off-screen tap deselects", main.selected == Vector2i(-1, -1),
		"selected=%s" % main.selected)

	# Corners of the viewport either hit an edge square or miss the board;
	# neither may crash or produce an out-of-range square.
	for corner in [Vector2.ZERO, Vector2(view_size.x, 0.0),
			Vector2(0.0, view_size.y), view_size]:
		var square := main.screen_to_square(corner)
		_check("corner %s maps sanely" % corner,
			(square.x == -1 and square.y == -1)
				or (square.x >= 0 and square.x < 8 and square.y >= 0 and square.y < 8),
			"square=%s" % square)

	var 	mesh := SquareHighlight.build_mesh()
	_check("highlight builds one surface", mesh.get_surface_count() == 1, "")
	var arrays := mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	_check("highlight is four thin boxes", int(indices.size() / 3.0) == 4 * 12,
		"tris=%d" % int(indices.size() / 3.0))
	var aabb := mesh.get_aabb()
	_check("highlight spans one square",
		aabb.size.x > 0.8 and aabb.size.x <= 1.0 and aabb.size.z > 0.8 and aabb.size.z <= 1.0,
		"size=%s" % aabb.size)

	_picking_checks(main, view_size)

	scene.queue_free()
	if _failures == 0:
		if failures > 0:
			print("selection: %d check(s) failed" % failures)
		else:
			print("selection: all checks passed")
	else:
		printerr("selection: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


## Picking must hit the piece itself, not the board under it. A ray tested
## only against the y = 0 plane sails over anything tall, so a tap on a king's
## head used to miss entirely and return no square at all.
func _picking_checks(main: Main, view_size: Vector2) -> void:
	print("Picking")
	var king: PieceView = main.pieces[Vector2i(4, 0)]
	var height: float = king.mesh.get_aabb().size.y
	# The near base can legitimately hit the pawn in front of it from this
	# camera, so only the upper body is asserted here.
	for fraction in [0.45, 0.7, 0.9]:
		var point := king.position + Vector3(0.0, height * float(fraction), 0.0)
		var square := main._pick_square(main.camera.unproject_position(point))
		_check("king body at %d%% is pickable" % int(fraction * 100.0),
			square == Vector2i(4, 0), "square=%s" % square)

	var pawn: PieceView = main.pieces[Vector2i(0, 1)]
	var pawn_mid: Vector3 = pawn.position + Vector3(0.0, pawn.mesh.get_aabb().size.y * 0.5, 0.0)
	_check("pawn body is pickable",
		main._pick_square(main.camera.unproject_position(pawn_mid)) == Vector2i(0, 1), "")

	_check("empty square still picks through the board",
		main._pick_square(
			main.camera.unproject_position(BoardMesh.square_position(4, 4))
		) == Vector2i(4, 4), "")
	_check("off-board picks nothing",
		main._pick_square(Vector2(-50.0, -50.0)) == Vector2i(-1, -1), "")
	# Which exact square the screen centre lands on depends on the pitch, and
	# pinning it here only breaks every time the framing is retuned. The
	# requirement is that it is somewhere central and empty, and the check above
	# already covers a known square exactly.
	var centre_pick := main._pick_square(view_size * 0.5)
	_check("board centre picks a middle square",
		centre_pick.x >= 3 and centre_pick.x <= 4 and centre_pick.y >= 3 and centre_pick.y <= 4,
		"got %s" % centre_pick)


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


## Taps the screen position of a square's centre.
func _tap_square(main: Main, square: Vector2i) -> void:
	var screen := main.camera.unproject_position(
		BoardMesh.square_position(square.x, square.y))
	main._tap(screen)
