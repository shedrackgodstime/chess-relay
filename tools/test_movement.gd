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
## The last-move marker, and that choosing a side is the lobby's job.
func _last_move_and_side_checks() -> void:
	print("Last move and side")
	var scene := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var main: Main = scene
	main.ai_opponent = false

	# Nothing may sit over the board at start. A full-screen overlay that stops
	# mouse input makes the game unplayable while it is up, and an earlier version
	# of this did exactly that by asking for a side in the wrong place.
	_check("nothing blocks the board at start", not _has_blocking_overlay(main.hud), "")

	# And a tap has to actually select.
	_tap_square(main, Vector2i(0, 1))
	_check("a piece can be selected on the opening board",
		main.selected == Vector2i(0, 1), "selected=%s" % main.selected)
	main._deselect()

	_check("no marker before anything has been played",
		_last_move_shown(main) == 0, "shown=%d" % _last_move_shown(main))
	# The a-file, not the e-file: at this pitch the king on e1 swallows taps on
	# e2, which is a separate problem with its own test.
	_tap_square(main, Vector2i(0, 1))
	_tap_square(main, Vector2i(0, 3))
	_check("the move marks both ends",
		_last_move_shown(main) > 0
			and main.last_move_from.marked_square() == Vector2i(0, 1)
			and main.last_move_to.marked_square() == Vector2i(0, 3),
		"from=%s to=%s" % [main.last_move_from.marked_square(),
			main.last_move_to.marked_square()])
	_check("both last-move frames have geometry",
		main.last_move_from.mesh != null and main.last_move_to.mesh != null, "")
	# Four colours in use on the board, so no two may collide.
	var hues := [SquareHighlight.LAST_MOVE_FROM, SquareHighlight.LAST_MOVE_TO,
		SquareHighlight.GOLD, SquareHighlight.RED]
	var distinct := 0
	for i in hues.size():
		var clash := false
		for j in range(i + 1, hues.size()):
			if (hues[i] as Color).is_equal_approx(hues[j]):
				clash = true
		if not clash:
			distinct += 1
	_check("the four highlight colours are all different", distinct == 4,
		"distinct=%d" % distinct)
	_check("the last move's two ends differ from each other",
		not SquareHighlight.LAST_MOVE_FROM.is_equal_approx(SquareHighlight.LAST_MOVE_TO)
			and not SquareHighlight.LAST_MOVE_FROM.is_equal_approx(SquareHighlight.GOLD)
			and not SquareHighlight.LAST_MOVE_TO.is_equal_approx(SquareHighlight.GOLD),
		"from=%s to=%s" % [SquareHighlight.LAST_MOVE_FROM, SquareHighlight.LAST_MOVE_TO])
	# Brightness carries the hierarchy, so hue is not the only channel.
	_check("brightness ranks the four from loudest to quietest",
		SquareHighlight.GOLD.get_luminance() > SquareHighlight.RED.get_luminance()
			and SquareHighlight.LAST_MOVE_TO.get_luminance()
				> SquareHighlight.LAST_MOVE_FROM.get_luminance(),
		"gold=%.2f red=%.2f to=%.2f from=%.2f" % [
			SquareHighlight.GOLD.get_luminance(), SquareHighlight.RED.get_luminance(),
			SquareHighlight.LAST_MOVE_TO.get_luminance(),
			SquareHighlight.LAST_MOVE_FROM.get_luminance()])
	_check("the frame is thinner than it was",
		SquareHighlight.BAR <= 0.08, "bar=%.2f" % SquareHighlight.BAR)

	_tap_square(main, Vector2i(1, 1))
	_tap_square(main, Vector2i(1, 3))
	_check("the frames follow the newest move",
		main.last_move_from.marked_square() == Vector2i(1, 1)
			and main.last_move_to.marked_square() == Vector2i(1, 3),
		"from=%s to=%s" % [main.last_move_from.marked_square(),
			main.last_move_to.marked_square()])

	# Ownership follows the chosen side. player_side is set by the lobby later;
	# it already has to work, so it is exercised here.
	main.player_side = BoardState.DARK
	await process_frame
	_check("the board turns to face the side the player took",
		is_equal_approx(main.camera.yaw_degrees, Main.yaw_for_side(BoardState.DARK)),
		"yaw=%.1f" % main.camera.yaw_degrees)
	_check("the opponent is then the light side",
		main.opponent_side() == BoardState.LIGHT, "")

	main.ai_opponent = true
	# Black to move. It is White's turn after the moves above, and a Black player
	# may not touch anything then, which the side-ownership checks already cover.
	main.game.state.side_to_move = BoardState.DARK
	main._deselect()
	_tap_square(main, Vector2i(0, 6))
	_check("a Black player picks up their own pieces",
		main.selected == Vector2i(0, 6), "selected=%s" % main.selected)
	main._deselect()
	_tap_square(main, Vector2i(1, 0))
	_check("a Black player cannot pick up a white piece",
		main.selected == Vector2i(-1, -1), "selected=%s" % main.selected)

	# Flip must still alternate correctly after a side change.
	main.camera.reset_view(Vector3.ZERO, Main.yaw_for_side(BoardState.DARK), 41.9, 10.81)
	main._on_flip_requested()
	await process_frame
	_check("flip turns to the other side from a changed side",
		is_equal_approx(main.camera.yaw_degrees, Main.yaw_for_side(BoardState.LIGHT)),
		"yaw=%.1f" % main.camera.yaw_degrees)

	await _check_marker_checks()
	scene.queue_free()
	await process_frame


## The king-in-check highlight: the same frame the selection uses, in red.
## A pawn in hand plus a tap at the opponent's end of the board must not open the
## promotion overlay, and choosing from it must never leave a pawn that looks
## like a queen but still moves like a pawn.
## The legal-destination hints, which are a lobby setting rather than part of
## playing a game. Off by default, and when on they must agree with the rules
## exactly, since a hint that marks an illegal square is worse than none.
## Castling moves two pieces, and the board state and the views have to agree
## about both of them. This checks the whole registry against the position rather
## than one square, so a rook left behind is caught wherever it ends up.
func _castling_view_checks() -> void:
	print("Castling view")
	var scene := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var main: Main = scene
	main.ai_opponent = false
	main.game.load_position(_position_with({
		Vector2i(4, 0): BoardState.encode(PieceProfiles.Type.KING, BoardState.LIGHT),
		Vector2i(7, 0): BoardState.encode(PieceProfiles.Type.ROOK, BoardState.LIGHT),
		Vector2i(4, 7): BoardState.encode(PieceProfiles.Type.KING, BoardState.DARK),
		Vector2i(0, 5): BoardState.encode(PieceProfiles.Type.ROOK, BoardState.DARK)}))
	await _populate_views(main)

	# Castled the way a player does it: pick the king up, then tap where it lands.
	# Going through the tap handler rather than apply_move is the point, because
	# that is the only path a player has.
	_tap_square(main, Vector2i(4, 0))
	_check("the king is in hand", main.selected == Vector2i(4, 0),
		"selected=%s" % str(main.selected))
	_tap_square(main, Vector2i(6, 0))
	await _settle(main.pieces.get(Vector2i(6, 0)), Vector3.ZERO)
	await process_frame
	_check("the king has moved in the position",
		main.game.state.at(6, 0)
			== BoardState.encode(PieceProfiles.Type.KING, BoardState.LIGHT), "")
	_check("the rook has moved in the position",
		main.game.state.at(5, 0)
			== BoardState.encode(PieceProfiles.Type.ROOK, BoardState.LIGHT), "")
	_check("the rook has moved in the views too", main.pieces.has(Vector2i(5, 0))
		and not main.pieces.has(Vector2i(7, 0)),
		"pieces=%s" % str(main.pieces.keys()))
	_check("the view and the position agree square for square",
		_views_match_state(main), "")

	# And the other side, queenside, where the destination is on the other side of
	# the king, so the rook crosses towards it rather than away.
	var other := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(other)
	await process_frame
	await process_frame
	var mirror: Main = other
	mirror.ai_opponent = false
	mirror.game.load_position(_position_with({
		Vector2i(4, 0): BoardState.encode(PieceProfiles.Type.KING, BoardState.LIGHT),
		Vector2i(0, 0): BoardState.encode(PieceProfiles.Type.ROOK, BoardState.LIGHT),
		Vector2i(4, 7): BoardState.encode(PieceProfiles.Type.KING, BoardState.DARK),
		Vector2i(0, 5): BoardState.encode(PieceProfiles.Type.ROOK, BoardState.DARK)}))
	await _populate_views(mirror)
	_tap_square(mirror, Vector2i(4, 0))
	print("    diag legal=%s rights=%d selected=%s pick=%s" % [
		str(mirror.game.is_legal(ChessMove.new(Vector2i(4, 0), Vector2i(2, 0)))),
		mirror.game.state.castling_rights, str(mirror.selected),
		str(mirror._pick_square(mirror.camera.unproject_position(
			BoardMesh.square_position(2, 0))))])
	_tap_square(mirror, Vector2i(2, 0))
	await process_frame
	_check("queenside puts the king on c1",
		mirror.game.state.at(2, 0)
			== BoardState.encode(PieceProfiles.Type.KING, BoardState.LIGHT), "")
	_check("and the rook on d1",
		mirror.game.state.at(3, 0)
			== BoardState.encode(PieceProfiles.Type.ROOK, BoardState.LIGHT), "")
	_check("and the views agree there as well",
		_views_match_state(mirror), "")
	other.queue_free()
	await process_frame

	scene.queue_free()
	await process_frame


## Replaces the scene's pieces with exactly the ones the position holds.
##
## Built directly rather than through _collect_pieces, which reads the existing
## nodes and so would report the generated full set rather than the position under
## test. Leaving a stale set in place is its own trap: the opening has a bishop on
## c1, so a tap meant for a queenside castle would land on it and be read as
## picking the bishop up instead.
func _populate_views(main: Main) -> void:
	main.pieces.clear()
	for child in main.get_node("World/Pieces").get_children():
		child.queue_free()
	for rank in BoardState.BOARD_SIZE:
		for file in BoardState.BOARD_SIZE:
			var code := main.game.state.at(file, rank)
			if code == BoardState.EMPTY:
				continue
			var view := PieceView.new()
			view.piece_type = BoardState.decode(code).x
			view.side = BoardState.decode(code).y
			main.get_node("World/Pieces").add_child(view)
			view.position = BoardMesh.square_position(file, rank)
			main.pieces[Vector2i(file, rank)] = view
	await process_frame


## Whether every piece the board state holds is on the square the view registry
## says it is, and nothing is on a square the state has emptied.
func _views_match_state(main: Main) -> bool:
	var want := {}
	for rank in BoardState.BOARD_SIZE:
		for file in BoardState.BOARD_SIZE:
			var code := main.game.state.at(file, rank)
			if code != BoardState.EMPTY:
				want[Vector2i(file, rank)] = code
	if want.size() != main.pieces.size():
		return false
	for square: Vector2i in want:
		var view := main.pieces.get(square) as PieceView
		if view == null:
			return false
		if view.side != BoardState.decode(want[square]).y \
				or view.piece_type != BoardState.decode(want[square]).x:
			return false
	return true


func _legal_marker_checks() -> void:
	print("Legal markers")
	var scene := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var main: Main = scene
	main.ai_opponent = false
	# Pinned rather than asserted from the default: this test is about what the
	# setting does, and the default is currently a temporary development value that
	# will change. A test that asserts it would fail when that value is corrected,
	# for no reason connected to what it checks.
	Indicators.set_show_legal_moves(false)
	_tap_square(main, Vector2i(6, 1))
	_check("selecting with the setting off marks nothing",
		main.legal_marked.is_empty(), "")

	Indicators.set_show_legal_moves(true)
	_tap_square(main, Vector2i(1, 1))
	# b2 is a pawn in the opening, so it reaches b3 and b4 and nothing else.
	_check("selecting with it on marks both of a pawn's squares",
		main.legal_marked.size() == 2, "marked=%s" % str(main.legal_marked))
	_check("including the one it can reach",
		main.legal_marked.has(Vector2i(1, 2)), "marked=%s" % str(main.legal_marked))
	_check("and nothing it cannot",
		not main.legal_marked.has(Vector2i(2, 3)), "")
	_check("and not its own square", not main.legal_marked.has(Vector2i(1, 1)), "")
	_check("and it agrees with the rules",
		main.legal_marked == _destinations(main, Vector2i(1, 1)), "")
	_check("with as many frames showing as squares marked",
		_shown_hints(main).call().size() == main.legal_marked.size(), "")

	# A knight has the same number of moves everywhere, which makes it the piece a
	# wrong answer is easiest to see on. This one stands on the a-file, where all
	# four of its moves are on the board, and a fresh scene so that nothing marked
	# for the position above is still showing and counted as its own.
	scene.queue_free()
	await process_frame
	scene = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	main = scene
	main.ai_opponent = false
	main.game.load_position(_position_with({
		Vector2i(4, 0): BoardState.encode(PieceProfiles.Type.KING, BoardState.LIGHT),
		Vector2i(4, 7): BoardState.encode(PieceProfiles.Type.KING, BoardState.DARK),
		Vector2i(0, 4): BoardState.encode(PieceProfiles.Type.KNIGHT, BoardState.LIGHT)}))
	main.selected = Vector2i(0, 4)
	main.highlight.show_at(0, 4)
	main._update_legal_markers()
	_check("a knight on the a-file is offered all four of its moves",
		main.legal_marked.size() == 4, "marked=%s" % str(main.legal_marked))
	for expected: Vector2i in [Vector2i(1, 6), Vector2i(2, 5),
			Vector2i(2, 3), Vector2i(1, 2)]:
		_check("including %s" % str(expected), main.legal_marked.has(expected), "")
	_check("and it matches the rules there too",
		main.legal_marked == _destinations(main, Vector2i(0, 4)), "")

	# Selecting nothing must clear them, or they outlive the piece that caused
	# them and sit on squares the next piece cannot reach.
	main._deselect()
	_check("deselecting clears every hint", main.legal_marked.is_empty(), "")
	_check("and leaves no frame showing", _shown_hints(main).call().is_empty(), "")

	# Left off rather than restored to whatever the default is, so a test cannot
	# quietly leave a setting on for whatever runs after it.
	Indicators.set_show_legal_moves(false)
	scene.queue_free()
	await process_frame


## The squares the rules say a piece on this square may reach, for comparison.
func _destinations(main: Main, from: Vector2i) -> Array:
	var out: Array = []
	var side := BoardState.decode(main.game.state.at(from.x, from.y)).y
	for move in Rules.legal_moves(main.game.state, side):
		if move.from_square == from:
			out.append(move.to_square)
	return out


## The hint frames that are currently showing.
func _shown_hints(main: Main) -> Callable:
	return func() -> Array:
		var out: Array = []
		for child in main.get_node("World/LegalHighlights").get_children():
			var hint := child as SquareHighlight
			if hint != null and hint.visible:
				out.append(hint)
		return out


## Which squares the visible hints are marking.
## A position holding only the given pieces, and nothing else.
func _position_with(setup: Dictionary) -> BoardState:
	var state := BoardState.new()
	state.squares.fill(BoardState.EMPTY)
	for square: Vector2i in setup:
		state.set_square(square.x, square.y, setup[square])
	return state


func _promotion_refusal_checks() -> void:
	print("Promotion refused")
	var scene := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var main: Main = scene
	main.ai_opponent = false

	main.game.state.squares.fill(BoardState.EMPTY)
	main.game.state.set_square(4, 1,
		BoardState.encode(PieceProfiles.Type.PAWN, BoardState.LIGHT))
	# Rank index 7 is the promotion rank. The piece on it is not a pawn, so a
	# pawn cannot push onto it and cannot capture straight ahead either: the move
	# is impossible, which is exactly the case that used to open the overlay.
	main.game.state.set_square(4, 7,
		BoardState.encode(PieceProfiles.Type.ROOK, BoardState.DARK))
	main.game.state.set_square(0, 0,
		BoardState.encode(PieceProfiles.Type.KING, BoardState.LIGHT))
	main.game.state.set_square(7, 7,
		BoardState.encode(PieceProfiles.Type.KING, BoardState.DARK))
	main.game.state.side_to_move = BoardState.LIGHT

	# The generated scene has all thirty-two pieces in it; they are not on the
	# board any more and would swallow taps.
	var keep := [Vector2i(4, 1), Vector2i(4, 7), Vector2i(0, 0), Vector2i(7, 7)]
	for square: Vector2i in main.pieces.keys():
		if keep.has(square):
			continue
		var extra: Node = main.pieces[square]
		main.pieces.erase(square)
		extra.queue_free()
	(main.pieces[Vector2i(4, 1)] as PieceView).side = BoardState.LIGHT
	(main.pieces[Vector2i(4, 7)] as PieceView).side = BoardState.DARK
	await process_frame
	main._collect_pieces()
	await process_frame

	# A move no pawn could make, which still points at the promotion rank.
	var impossible := ChessMove.new(Vector2i(4, 1), Vector2i(4, 7))
	_check("a pawn move onto the far rank is a promotion by rank but not by law",
		Rules.is_promotion(main.game.state, impossible)
			and not main.game.is_legal(impossible), "")

	main.selected = Vector2i(4, 1)
	main._tap(main.camera.unproject_position(
		BoardMesh.square_position(4, 7)))
	_check("no overlay for an impossible pawn move",
		main._pending_promotion == null and not main.hud.promotion_picker.visible,
		"pending=%s" % main._pending_promotion)
	_check("and nothing moved", main.pieces.has(Vector2i(4, 1)), "")

	# Choosing anyway, if something else ever opens it, must leave the view
	# agreeing with the board.
	main._pending_promotion = ChessMove.new(Vector2i(4, 1), Vector2i(4, 7))
	var pawn: PieceView = main.pieces[Vector2i(4, 1)]
	main._on_promotion_chosen(PieceProfiles.Type.QUEEN)
	await process_frame
	_check("a refused promotion leaves the piece a pawn",
		pawn.piece_type == PieceProfiles.Type.PAWN,
		"piece=%s" % PieceProfiles.type_name(pawn.piece_type))
	_check("the board still holds the pawn",
		BoardState.decode(main.game.state.at(4, 1))
			== Vector2i(PieceProfiles.Type.PAWN, BoardState.LIGHT), "")
	_check("the rook is still on the square it stood on",
		BoardState.decode(main.game.state.at(4, 7))
			== Vector2i(PieceProfiles.Type.ROOK, BoardState.DARK), "")

	scene.queue_free()
	await process_frame


func _check_marker_checks() -> void:
	print("Check highlight")
	var scene := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var main: Main = scene
	var check: SquareHighlight = main.check_highlight
	var selection: SquareHighlight = main.highlight

	_check("no check highlight on the opening board", not check.visible, "")
	_check("it is red, unlike the gold selection frame",
		check.colour.is_equal_approx(SquareHighlight.RED)
			and selection.colour.is_equal_approx(SquareHighlight.GOLD)
			and not check.colour.is_equal_approx(selection.colour),
		"check=%s selection=%s" % [check.colour, selection.colour])
	# Same shape, so there is one marker to recognise and colour is the message.
	_check("it uses the same frame geometry as the selection",
		check.mesh != null and check.mesh.get_aabb().size.is_equal_approx(
			(selection.mesh as ArrayMesh).get_aabb().size),
		"check=%s selection=%s" % [
			check.mesh.get_aabb().size if check.mesh else Vector3.ZERO,
			(selection.mesh as ArrayMesh).get_aabb().size if selection.mesh else Vector3.ZERO])

	# A real position: the black king on e8 checked by a rook on e1. The rook has
	# to share the file or it is not check at all.
	main.game.state.squares.fill(BoardState.EMPTY)
	main.game.state.set_square(4, 7,
		BoardState.encode(PieceProfiles.Type.KING, BoardState.DARK))
	main.game.state.set_square(4, 0,
		BoardState.encode(PieceProfiles.Type.ROOK, BoardState.LIGHT))
	main.game.state.side_to_move = BoardState.DARK
	main._update_check_marker()
	await process_frame
	_check("the highlight comes up when a king is in check", check.visible, "")
	_check("it frames the king's square, not the attacker's",
		check.marked_square() == Vector2i(4, 7),
		"marked=%s" % check.marked_square())
	_check("it sits at the same height as the selection frame",
		is_equal_approx(check.position.y, SquareHighlight.LIFT),
		"y=%.4f" % check.position.y)

	# Answer the check by stepping off the file, and it goes away. e7 would still
	# be on the rook's file and still in check.
	main.game.state.set_square(4, 6, BoardState.EMPTY)
	main.game.state.set_square(5, 6,
		BoardState.encode(PieceProfiles.Type.KING, BoardState.DARK))
	main._update_check_marker()
	await process_frame
	_check("the highlight clears once the check is answered",
		not check.visible and check.marked_square() == Vector2i(-1, -1), "")

	# Checkmate still shows it: the player has to be told why there is no move.
	main.game.state.squares.fill(BoardState.EMPTY)
	main.game.state.set_square(6, 6, BoardState.encode(PieceProfiles.Type.QUEEN, BoardState.LIGHT))
	main.game.state.set_square(5, 5, BoardState.encode(PieceProfiles.Type.KING, BoardState.LIGHT))
	main.game.state.set_square(7, 7, BoardState.encode(PieceProfiles.Type.KING, BoardState.DARK))
	main.game.state.side_to_move = BoardState.DARK
	main._update_check_marker()
	await process_frame
	_check("a check with no legal reply still shows it",
		check.visible and check.marked_square() == Vector2i(7, 7),
		"marked=%s" % check.marked_square())

	scene.queue_free()
	await process_frame


## How many last-move frames are showing.
func _last_move_shown(main: Main) -> int:
	var shown := 0
	for frame in [main.last_move_from, main.last_move_to]:
		if frame != null and frame.visible:
			shown += 1
	return shown


## Any visible full-screen child of the HUD that would swallow taps.
func _has_blocking_overlay(hud: Hud) -> bool:
	for child in hud.get_children():
		var control := child as Control
		if control != null and control.visible \
				and control.mouse_filter == Control.MOUSE_FILTER_STOP \
				and control.size.x > 100.0 and control.size.y > 100.0:
			return true
	return false


## Promotion end to end## Promotion end to end: a held move, a choice, and the pawn becoming it.
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

	await _promotion_refusal_checks()
	await _legal_marker_checks()
	await _castling_view_checks()
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
