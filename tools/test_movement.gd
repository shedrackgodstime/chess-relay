extends SceneTree

## Headless checks for piece movement, captures and side ownership.
##
## No legality is asserted — there is none yet, by design. What is asserted is
## the machinery: the registry tracks every piece, taps move the selection,
## captures remove the victim, and glides land exactly on the square.
##
##     godot-headless --headless --script res://tools/test_movement.gd

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
	await process_frame
	await process_frame

	var main: Main = scene
	main.ai_opponent = false
	_check("registry holds the full set", main.pieces.size() == 32,
		"pieces=%d" % main.pieces.size())

	_check("world origin maps to a middle square",
		Main.world_to_square(Vector3.ZERO) == Vector2i(4, 4),
		"square=%s" % Main.world_to_square(Vector3.ZERO))
	_check("far outside maps invalid",
		Main.world_to_square(Vector3(20.0, 0.0, 0.0)) == Vector2i(-1, -1), "")

	# White pawn A2 -> A4: select, move, land exactly.
	_tap_square(main, Vector2i(0, 1))
	_check("pawn selects", main.selected == Vector2i(0, 1),
		"selected=%s" % main.selected)
	var pawn: PieceView = main.pieces[Vector2i(0, 1)]
	_tap_square(main, Vector2i(0, 3))
	_check("registry moves with the piece",
		main.pieces.has(Vector2i(0, 3)) and not main.pieces.has(Vector2i(0, 1)), "")
	_check("home square follows", pawn.home_square == Vector2i(0, 3),
		"home=%s" % pawn.home_square)
	_check("tap deselects after moving", main.selected == Vector2i(-1, -1), "")
	await _settle(pawn, BoardMesh.square_position(0, 3))
	_check("glide lands exactly on the square",
		pawn.position.distance_to(BoardMesh.square_position(0, 3)) < 0.01,
		"pos=%s" % pawn.position)

	# Pawn takes pawn: white A4 x black A7-pawn standing on A6... use the black
	# pawn's real square instead of inventing one.
	_tap_square(main, Vector2i(0, 3))
	var victim: PieceView = main.pieces[Vector2i(0, 6)]
	_tap_square(main, Vector2i(0, 6))
	_check("capture clears the victim square",
		main.pieces.has(Vector2i(0, 6))
			and (main.pieces[Vector2i(0, 6)] as PieceView).home_square == Vector2i(0, 6),
		"")
	await _settle(pawn, BoardMesh.square_position(0, 6))
	_check("attacker lands on the victim square",
		pawn.position.distance_to(BoardMesh.square_position(0, 6)) < 0.01,
		"pos=%s" % pawn.position)
	for i in 30:
		await process_frame
		if not is_instance_valid(victim):
			break
	_check("victim is freed after its capture animation", not is_instance_valid(victim), "")

	# Knight B1 -> C3: hops instead of sliding, lands the same way.
	_tap_square(main, Vector2i(1, 0))
	var knight: PieceView = main.pieces[Vector2i(1, 0)]
	_tap_square(main, Vector2i(2, 2))
	await _settle(knight, BoardMesh.square_position(2, 2))
	_check("knight lands exactly",
		knight.position.distance_to(BoardMesh.square_position(2, 2)) < 0.01,
		"pos=%s" % knight.position)
	_check("knight registry follows", knight.home_square == Vector2i(2, 2), "")

	scene.queue_free()
	await _side_ownership_checks()

	if _failures == 0:
		print("movement: all checks passed")
	else:
		printerr("movement: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


## Taps a square the way a finger would: on the piece's body when one is
## there. Tapping the bare square centre is not equivalent, because from the
## default camera a piece in front can legitimately occlude it, and picking
## now resolves to what is actually visible at that pixel.
func _tap_square(main: Main, square: Vector2i) -> void:
	var point: Vector3 = BoardMesh.square_position(square.x, square.y)
	if main.pieces.has(square):
		var piece: PieceView = main.pieces[square]
		point.y = piece.mesh.get_aabb().size.y * 0.6
	main._tap(main.camera.unproject_position(point))


## Waits until a piece settles near its target, up to ~2 seconds of frames.
func _settle(piece: PieceView, target: Vector3) -> void:
	for i in 120:
		await process_frame
		if not is_instance_valid(piece):
			return
		if piece.position.distance_to(target) < 0.01 and not piece.is_moving():
			return


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		print("  ok   %s  %s" % [label, detail])
	else:
		_failures += 1
		printerr("  FAIL %s  %s" % [label, detail])


## The opponent is always the other side. Flipping the board is a camera move and
## must never change who you control, and neither side's pieces may be picked up
## on the other's turn.
##
## Runs on its own scene: it turns the AI on, which starts replying, and that
## would fight with the shared scene's state.
func _side_ownership_checks() -> void:
	print("Side ownership")
	var scene := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var main: Main = scene
	main.ai_opponent = true
	main.player_side = BoardState.LIGHT

	_check("player starts on the light side", main.player_side == BoardState.LIGHT, "")
	_check("opponent is the other side", main.opponent_side() == BoardState.DARK,
		"opponent=%d" % main.opponent_side())

	# Flipping is a camera move and must not reassign sides. Checked while it is
	# still the player's turn, since that is the only time a piece is pickable.
	main.camera.reset_view(Vector3.ZERO, 180.0, 41.9, 10.81)
	_check("flipping does not change your side",
		main.player_side == BoardState.LIGHT
			and main.opponent_side() == BoardState.DARK,
		"player=%d opponent=%d" % [main.player_side, main.opponent_side()])
	_tap_square(main, Vector2i(1, 1))
	_check("you still play the same pieces when the board is flipped",
		main.selected == Vector2i(1, 1), "selected=%s" % main.selected)
	main._deselect()

	# The opponent's pieces are not yours to touch, even on your own turn.
	_tap_square(main, Vector2i(0, 6))
	_check("opponent piece cannot be picked up",
		main.selected == Vector2i(-1, -1), "selected=%s" % main.selected)

	# Yours are.
	_tap_square(main, Vector2i(0, 1))
	_check("own piece picks up", main.selected == Vector2i(0, 1),
		"selected=%s" % main.selected)
	_tap_square(main, Vector2i(0, 3))
	_check("own piece moves",
		main.selected == Vector2i(-1, -1)
			and main.game.state.side_to_move == BoardState.DARK,
		"to move=%d" % main.game.state.side_to_move)

	# Now it is the opponent's turn, so your pieces are inert until it replies.
	_tap_square(main, Vector2i(1, 1))
	_check("own piece is inert on the opponent's turn",
		main.selected == Vector2i(-1, -1), "selected=%s" % main.selected)

	# Without an opponent both sides are playable, so the rules engine can be
	# driven from one device.
	main.ai_opponent = false
	main._deselect()
	_tap_square(main, Vector2i(1, 6))
	_check("with no opponent either side can be played",
		main.selected == Vector2i(1, 6), "selected=%s" % main.selected)

	scene.queue_free()
	await process_frame
