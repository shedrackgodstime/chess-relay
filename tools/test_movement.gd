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

	await _capture_and_knight_checks()

	await _promotion_checks()
	await _selection_checks()
	await _last_move_and_side_checks()

	scene.queue_free()
	await _side_ownership_checks()

	if _failures == 0:
		print("movement: all checks passed")
	else:
		printerr("movement: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


## Capture and the knight, on their own scene.
##
## Separate because picking resolves to whatever is actually under the finger,
## and the pawn left standing on a4 from the slide test sits in front of the
## empty squares this needs. Sharing a board meant the e-pawn tried to move onto
## a4 and was correctly refused.
func _capture_and_knight_checks() -> void:
	print("Capture and knight")
	var scene := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var main: Main = scene
	main.ai_opponent = false

	# A capture the opening allows: a2-a4, b7-b5, then axb5. The black pawn has
	# to step into reach first, because a pawn captures diagonally.
	#
	# The a- and b-files, not the e-file: from the default camera the player's
	# own back rank is nearest, so the king on e1 stands in front of the e2 pawn
	# and swallows the tap entirely. The e-file is unusable at this pitch.
	_tap_square(main, Vector2i(0, 1))
	_tap_square(main, Vector2i(0, 3))
	_tap_square(main, Vector2i(1, 6))
	_tap_square(main, Vector2i(1, 4))
	_check("the opening reaches a capture position",
		main.pieces.has(Vector2i(0, 3)) and main.pieces.has(Vector2i(1, 4)),
		"a4=%s b5=%s" % [main.pieces.has(Vector2i(0, 3)),
			main.pieces.has(Vector2i(1, 4))])
	var taker: PieceView = main.pieces[Vector2i(0, 3)]
	var victim: PieceView = main.pieces[Vector2i(1, 4)]
	_tap_square(main, Vector2i(0, 3))
	_tap_square(main, Vector2i(1, 4))
	_check("capture leaves the taker on the victim square",
		main.pieces.has(Vector2i(1, 4))
			and (main.pieces[Vector2i(1, 4)] as PieceView).home_square == Vector2i(1, 4),
		"")
	await _settle(taker, BoardMesh.square_position(1, 4))
	_check("attacker lands on the victim square",
		taker.position.distance_to(BoardMesh.square_position(1, 4)) < 0.01,
		"pos=%s" % taker.position)
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
	await process_frame


## Selection switching, on its own scene.
##
## The pawn on a4 from the slide test is not reusable here: tapping another of
## your own pieces to re-select needs the held piece to stay put, and a move in
## between would change what is on the board.
func _selection_checks() -> void:
	print("Selection")
	var scene := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var main: Main = scene
	main.ai_opponent = false

	# b2 and c2, because a2 is moved later in this sequence and these two are
	# not touched by it.
	_tap_square(main, Vector2i(1, 1))
	_check("the first piece selects", main.selected == Vector2i(1, 1),
		"selected=%s" % main.selected)

	# A different piece of your own: the selection should move, not attempt a
	# move from the held piece and refuse.
	_tap_square(main, Vector2i(2, 1))
	_check("tapping another of your own pieces re-selects it",
		main.selected == Vector2i(2, 1), "selected=%s" % main.selected)
	_check("the first piece did not move", main.pieces.has(Vector2i(1, 1)), "")

	# Tapping the held piece again is still how you deselect.
	_tap_square(main, Vector2i(2, 1))
	_check("tapping the selected piece deselects it",
		main.selected == Vector2i(-1, -1), "selected=%s" % main.selected)

	# An empty square is a destination, not a change of mind.
	_tap_square(main, Vector2i(2, 1))
	_tap_square(main, Vector2i(2, 2))
	_check("an empty square is still moved to",
		main.selected == Vector2i(-1, -1) and main.pieces.has(Vector2i(2, 2)),
		"selected=%s" % main.selected)

	# Re-selection must not swallow a capture either. The capture check above
	# covers the taking; what matters here is that holding one piece and tapping
	# another side's piece is read as a move and not as a change of mind.
	_tap_square(main, Vector2i(1, 1))
	_tap_square(main, Vector2i(1, 2))
	_check("a held piece still moves to an empty square with another held first",
		main.pieces.has(Vector2i(1, 2)), "selected=%s" % main.selected)

	scene.queue_free()
	await process_frame


## The last-move marker and choosing a side.
##
## Both matter beyond their own feature: a Black player opening on White's side
## of the board is the whole point of the choice, so the camera has to follow it.
func _last_move_and_side_checks() -> void:
	print("Last move and side choice")
	var scene := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var main: Main = scene
	main.ai_opponent = false

	# The side chooser first, while the game is still unstarted. Playing a move
	# closes it, correctly, so checking it afterwards proves nothing.
	var picker: SidePicker = main.hud.side_picker
	_check("the side chooser is offered at the start", picker != null and picker.visible, "")
	_check("it offers both sides", picker.card_count() == 2, "cards=%d" % picker.card_count())
	_check("the board starts facing White",
		is_equal_approx(main.camera.yaw_degrees, Main.yaw_for_side(BoardState.LIGHT)),
		"yaw=%.1f" % main.camera.yaw_degrees)

	main._on_side_chosen(BoardState.DARK)
	await process_frame
	_check("choosing Black takes the dark side",
		main.player_side == BoardState.DARK, "side=%d" % main.player_side)
	_check("the opponent is then the light side",
		main.opponent_side() == BoardState.LIGHT, "")
	_check("the board turns to face the new side",
		is_equal_approx(main.camera.yaw_degrees, Main.yaw_for_side(BoardState.DARK)),
		"yaw=%.1f" % main.camera.yaw_degrees)
	_check("the chooser closes once a side is taken", not picker.visible, "")

	# The marker, on the a-file rather than the e-file: at this pitch the king on
	# e1 swallows taps on e2, which is a separate problem and its own test.
	_check("no marker before anything has been played", not main.last_move.is_marked(), "")
	_tap_square(main, Vector2i(0, 1))
	_tap_square(main, Vector2i(0, 3))
	_check("the move marks both ends",
		main.last_move.is_marked()
			and main.last_move.marked_from() == Vector2i(0, 1)
			and main.last_move.marked_to() == Vector2i(0, 3),
		"from=%s to=%s" % [main.last_move.marked_from(), main.last_move.marked_to()])
	_check("the marker has geometry",
		main.last_move.mesh != null
			and main.last_move.mesh.get_surface_count() >= 1, "")
	_check("the side chooser is not offered again once play starts",
		not main.hud.side_picker.visible, "")

	_tap_square(main, Vector2i(1, 1))
	_tap_square(main, Vector2i(1, 3))
	_check("the marker follows the newest move",
		main.last_move.marked_from() == Vector2i(1, 1)
			and main.last_move.marked_to() == Vector2i(1, 3),
		"from=%s to=%s" % [main.last_move.marked_from(), main.last_move.marked_to()])
	_check("the side chooser knows the game has started",
		not picker.should_offer(main.game), "")

	# Ownership follows the chosen side. With an opponent on, a Black player must
	# be able to pick up black pieces and must not be able to pick up white ones.
	main.ai_opponent = true
	# Black to move. After the two moves above it is White's turn, and a Black
	# player may not touch anything then, which is a different rule and is
	# already covered by the side-ownership checks.
	main.game.state.side_to_move = BoardState.DARK
	main._deselect()
	_tap_square(main, Vector2i(0, 6))
	_check("a Black player picks up their own pieces",
		main.selected == Vector2i(0, 6), "selected=%s" % main.selected)
	main._deselect()
	_tap_square(main, Vector2i(1, 0))
	_check("a Black player cannot pick up a white piece",
		main.selected == Vector2i(-1, -1), "selected=%s" % main.selected)

	scene.queue_free()
	await process_frame


## Promotion end to end: a held move, a choice, and the pawn becoming it.
##
## Runs on its own scene and sets the board up directly, because the promotion
## move itself is chosen by the player rather than arrived at by tapping, so
## there is no pair of squares to reach it from the opening.
func _promotion_checks() -> void:
	print("Promotion")
	var scene := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var main: Main = scene
	main.ai_opponent = false

	# A white pawn on b7, a white king somewhere harmless, black to be mated by.
	main.game.state.squares.fill(BoardState.EMPTY)
	main.game.state.set_square(1, 6,
		BoardState.encode(PieceProfiles.Type.PAWN, BoardState.LIGHT))
	main.game.state.set_square(4, 0,
		BoardState.encode(PieceProfiles.Type.KING, BoardState.LIGHT))
	main.game.state.set_square(7, 7,
		BoardState.encode(PieceProfiles.Type.KING, BoardState.DARK))
	main.game.state.side_to_move = BoardState.LIGHT

	# The generated scene has all thirty-two pieces in it. Clearing the board
	# state does not remove them, and they matter: the black pawn node still on
	# b7 would swallow a tap aimed at b8, so the move would never be offered.
	# Freed here so the scene and the state agree.
	var keep := [Vector2i(1, 6), Vector2i(4, 0), Vector2i(7, 7)]
	for square: Vector2i in main.pieces.keys():
		if keep.has(square):
			continue
		var extra: Node = main.pieces[square]
		main.pieces.erase(square)
		extra.queue_free()
	# The node on b7 is the black pawn the generator put there, so recolour it
	# rather than building a second one.
	(main.pieces[Vector2i(1, 6)] as PieceView).side = BoardState.LIGHT
	# A frame before re-collecting: queue_free is deferred, so the nodes are
	# still in the tree for now and the scan would find every one of them again.
	await process_frame
	main._collect_pieces()
	await process_frame

	var pawn: PieceView = main.pieces[Vector2i(1, 6)]
	_check("the pawn on b7 is the light one", pawn.side == BoardState.LIGHT, "")
	_check("the pawn is on the board to promote", pawn != null
		and pawn.piece_type == PieceProfiles.Type.PAWN, "")

	# Put it through the input path, so the move is held rather than applied.
	main.selected = Vector2i(1, 6)
	# Aimed near the far edge of b8 rather than its centre. From this camera the
	# ray to the exact centre passes at almost precisely the height of the pawn
	# on b7 behind it, and colliders are fitted flush to their meshes, so a
	# graze is caught. Stepping further away lifts the ray clear.
	main._tap(main.camera.unproject_position(
		BoardMesh.square_position(1, 7) + Vector3(0.0, 0.0, 0.35)))
	_check("the promotion is not applied while the choice is open",
		main.game.state.at(1, 7) == BoardState.EMPTY
			and main.pieces.has(Vector2i(1, 6)), "")
	_check("the picker is shown", main.hud.promotion_picker != null
		and main.hud.promotion_picker.visible, "")
	_check("the picker covers the screen, so it can actually be seen",
		main.hud.promotion_picker.size.x > 100.0
			and main.hud.promotion_picker.size.y > 100.0,
		"size=%s" % main.hud.promotion_picker.size)
	_check("the picker offers one tappable option per promotion piece",
		main.hud.promotion_picker.option_count() == Rules.PROMOTION_CHOICES.size(),
		"options=%d" % main.hud.promotion_picker.option_count())

	# Underpromote on purpose: a knight is the choice that proves the pawn
	# actually changed rather than quietly becoming a queen.
	main._on_promotion_chosen(PieceProfiles.Type.KNIGHT)
	await process_frame
	_check("the move lands once a piece is chosen",
		main.game.state.at(1, 7) != BoardState.EMPTY, "")
	_check("the board records the chosen piece",
		BoardState.decode(main.game.state.at(1, 7))
			== Vector2i(PieceProfiles.Type.KNIGHT, BoardState.LIGHT),
		PieceProfiles.type_name(BoardState.decode(main.game.state.at(1, 7)).x))
	var promoted: PieceView = main.pieces[Vector2i(1, 7)]
	_check("the same node is reused and now looks like a knight",
		promoted != null and promoted.piece_type == PieceProfiles.Type.KNIGHT
			and promoted == pawn, "rebuilt in place=%s" % (promoted == pawn))
	_check("the picker closes after choosing",
		not main.hud.promotion_picker.visible, "")
	_check("no promotion is left pending", main._pending_promotion == null, "")

	scene.queue_free()
	await process_frame


## A world point for a square, projected to screen, for driving _tap directly.
func _screen(main: Main, square: Vector2i) -> Vector2:
	return main.camera.unproject_position(BoardMesh.square_position(square.x, square.y))


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

	# Orientation: the player's own pieces belong at the bottom of the screen,
	# the opponent's at the top. Measured from the camera rather than from the
	# yaw number, so the assertion describes what the player sees.
	main.frame_board()
	await process_frame
	var cam_z: float = main.camera.global_position.z
	var mine: float = _mean_square_z(main, main.player_side)
	var theirs: float = _mean_square_z(main, main.opponent_side())
	_check("player sits on the near side of the board", cam_z < 0.0, "cam z=%.2f" % cam_z)
	_check("own pieces are nearer the camera than the opponent's",
		mine < theirs, "own=%.2f theirs=%.2f" % [mine, theirs])
	_check("own pieces are on the lower half of the board", mine < 0.0,
		"own z=%.2f" % mine)
	_check("opponent pieces are on the upper half", theirs > 0.0,
		"theirs z=%.2f" % theirs)

	# Flip should put the far side nearest, and must not move ownership.
	main.camera.reset_view(Vector3.ZERO, 0.0, 41.9, 10.81)
	await process_frame
	# Distance, not board position: flipping moves the camera, not the pieces, so
	# only distance from the camera can say which side is now nearest.
	_check("flipping brings the other side nearest",
		_mean_camera_distance(main, main.opponent_side())
			< _mean_camera_distance(main, main.player_side),
		"own=%.2f theirs=%.2f" % [_mean_camera_distance(main, main.player_side),
			_mean_camera_distance(main, main.opponent_side())])
	_check("flipping still does not change your side",
		main.player_side == BoardState.LIGHT, "")
	main.frame_board()
	await process_frame

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


## Mean world Z of a side's pieces, which is what decides whether they read as
## the bottom or the top of the screen.
func _mean_square_z(main: Main, side: int) -> float:
	var total := 0.0
	var count := 0
	for square: Vector2i in main.pieces:
		if main.pieces[square].side != side:
			continue
		var world: Vector3 = BoardMesh.square_position(square.x, square.y)
		total += world.z
		count += 1
	return total / float(count) if count > 0 else 0.0


## Mean distance from the camera to a side's pieces, which is what decides which
## side reads as nearest and therefore as the bottom of the screen.
func _mean_camera_distance(main: Main, side: int) -> float:
	var eye := main.camera.global_position
	var total := 0.0
	var count := 0
	for square: Vector2i in main.pieces:
		if main.pieces[square].side != side:
			continue
		total += eye.distance_to(BoardMesh.square_position(square.x, square.y))
		count += 1
	return total / float(count) if count > 0 else 0.0
