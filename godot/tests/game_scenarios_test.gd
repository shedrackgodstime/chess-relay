extends SceneTree
## End-to-end rules presentation: every chess rule the core owns must be
## visible and playable through the live game screen — captures, castling,
## en passant, promotion, checkmate, draws, resignation. The Rust suites
## prove the rules; this suite proves the player meets them.
##
## Drives the screen the way hands do (select, submit, render) against the
## real bridge, never around it.
##   godot --headless --path godot --script res://tests/game_scenarios_test.gd
## Or, with counts wired in, via run_all_checks.sh.

const GAME_SCENE: PackedScene = preload("res://src/ui/screens/game/game_screen.tscn")

var _failures := 0
var _checks_run := 0
var _phase_announced := ""
var _phase_reached_end := false
var _leave_requested := false


func _on_leave_requested() -> void:
	_leave_requested = true


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	await _phase("captures", _scenario_captures)
	await _phase("castling", _scenario_castling)
	await _phase("en_passant", _scenario_en_passant)
	await _phase("promotion", _scenario_promotion)
	await _phase("promotion_cancel", _scenario_promotion_cancel)
	await _phase("checkmate", _scenario_checkmate)
	await _phase("draw_offer", _scenario_draw_offer)
	await _phase("resign", _scenario_resign)
	_report()


func _phase(name: String, scenario: Callable) -> void:
	_phase_announced = name
	_phase_reached_end = false
	await scenario.call()
	_check(_phase_reached_end, "phase %s ran to completion" % name)


func _report() -> void:
	var expected := _expected_check_count()
	print("SCENARIOS: %d of %d checks ran, %d failed"
		% [_checks_run, expected, _failures])
	if _checks_run < expected:
		push_error("SCENARIOS: only %d of %d checks ran. %d checks never executed. "
			% [_checks_run, expected, expected - _checks_run]
				+ "A phase crashed partway; read the SCRIPT ERROR above for where.")
		_failures += 1
	if _failures == 0:
		print("Game scenario checks passed")
	else:
		push_error("Game scenario checks failed: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _expected_check_count() -> int:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--expected-checks="):
			return int(argument.split("=")[1])
	return 0


func _check(condition: bool, description: String) -> void:
	_checks_run += 1
	if condition:
		print("PASS: ", description)
	else:
		_failures += 1
		printerr("FAIL: ", description)


func _new_game() -> GameScreen:
	var game := GAME_SCENE.instantiate() as GameScreen
	root.add_child(game)
	await process_frame
	await process_frame
	return game


func _piece_at(game: GameScreen, square: String) -> ChessPieceView:
	for child in game._board.get_node("Pieces").get_children():
		if child.name.right(2).to_lower() == square:
			return child as ChessPieceView
	return null


## Side of the piece on a square, or "" when vacant. Typed Strings keep
## every `_check` argument a bool under the escalating gate (`.get()`
## returns Variant and poisons `and` chains).
func _side_at(game: GameScreen, square: String) -> String:
	var piece := _piece_at(game, square)
	return piece.side if piece != null else ""


func _type_at(game: GameScreen, square: String) -> String:
	var piece := _piece_at(game, square)
	return piece.piece_type if piece != null else ""


func _play(game: GameScreen, uci: String) -> void:
	var mover := _piece_at(game, uci.left(2))
	_check(mover != null, "piece stands on %s for %s" % [uci.left(2), uci])
	if mover == null:
		return
	game._on_piece_pressed(mover)
	game._on_square_pressed(uci.substr(2, 2))


func _fen(game: GameScreen) -> String:
	return game._bridge.fen()


func _scenario_captures() -> void:
	var game: GameScreen = await _new_game()
	_play(game, "e2e4")
	_play(game, "d7d5")
	# Taps the victim piece itself, the way hands do: the piece surface
	# fires first, and the screen must read it as a capture, not a
	# reselection.
	var attacker := _piece_at(game, "e4")
	var victim := _piece_at(game, "d5")
	_check(attacker != null and victim != null, "both pieces stand for the capture")
	game._on_piece_pressed(attacker)
	# Through the victim's surface, not the screen handler: live taps emit
	# here, and the rebuild runs mid-emission with the emitter inside it.
	# Freeing during emission used to abort the rebuild and empty the board.
	var capture := InputEventMouseButton.new()
	capture.button_index = MOUSE_BUTTON_LEFT
	capture.pressed = true
	var surface := victim.get_node("PieceInputSurface") as Area3D
	surface.input_event.emit(
		game._camera, capture, Vector3.ZERO, Vector3.UP, 0)
	_check(_side_at(game, "d5") == "white",
		"capture lands the white pawn on d5")
	_check(_side_at(game, "d5") == "white",
		"capture lands the white pawn on d5")
	_check(_piece_at(game, "e4") == null,
		"capture vacates the departure square")
	var black_pawns := 0
	for child in game._board.get_node("Pieces").get_children():
		var viewed := child as ChessPieceView
		if viewed != null and viewed.side == "black" and viewed.piece_type == "pawn":
			black_pawns += 1
	_check(black_pawns == 7, "capture removes one black pawn, got %d" % black_pawns)
	game.queue_free()
	_phase_reached_end = true


func _scenario_castling() -> void:
	var game: GameScreen = await _new_game()
	for uci: String in ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6"]:
		_play(game, uci)
	_play(game, "e1g1")
	_check(_type_at(game, "g1") == "king",
		"castling lands the king on g1")
	_check(_type_at(game, "f1") == "rook",
		"castling lands the rook on f1")
	_check(_piece_at(game, "e1") == null, "castling vacates e1")
	game.queue_free()
	_phase_reached_end = true


func _scenario_en_passant() -> void:
	var game: GameScreen = await _new_game()
	for uci: String in ["e2e4", "a7a6", "e4e5", "d7d5"]:
		_play(game, uci)
	_play(game, "e5d6")
	_check(_side_at(game, "d6") == "white",
		"en passant lands the pawn on d6")
	_check(_piece_at(game, "d5") == null,
		"en passant removes the bypassed pawn")
	game.queue_free()
	_phase_reached_end = true


func _scenario_promotion() -> void:
	var game: GameScreen = await _new_game()
	for uci: String in ["h2h4", "a7a6", "h4h5", "a6a5", "h5h6", "a5a4", "h6g7", "h7h6"]:
		_play(game, uci)
	_tap_promotion(game, "g7", "h8")
	var knight := _picker(game)
	_check(knight.visible, "promotion opens the picker")
	_check(knight.option_count() == 4, "picker offers four pieces")
	_press_picker_option(knight, 3)
	_check(_type_at(game, "h8") == "knight"
		and _side_at(game, "h8") == "white",
		"promotion crowns the chosen knight on h8")
	_check(_fen(game).begins_with("rnbqkbnN"),
		"underpromotion registers in the position, got %s" % _fen(game))
	game.queue_free()
	_phase_reached_end = true


func _scenario_promotion_cancel() -> void:
	var game: GameScreen = await _new_game()
	for uci: String in ["h2h4", "a7a6", "h4h5", "a6a5", "h5h6", "a5a4", "h6g7", "h7h6"]:
		_play(game, uci)
	_tap_promotion(game, "g7", "h8")
	var cancel := _picker(game).get_node("Centre/Panel/Column/Cancel") as Button
	cancel.pressed.emit()
	await process_frame
	_check(_type_at(game, "h8") == "queen",
		"cancel falls back to queen on h8")
	game.queue_free()
	_phase_reached_end = true


func _picker(game: GameScreen) -> PromotionPicker:
	return game.get_node("PromotionPicker") as PromotionPicker


## Taps a promotion without choosing: the move must wait for the picker.
func _tap_promotion(game: GameScreen, from_square: String, to_square: String) -> void:
	var mover := _piece_at(game, from_square)
	_check(mover != null, "pawn stands on %s" % from_square)
	if mover == null:
		return
	game._on_piece_pressed(mover)
	game._on_square_pressed(to_square)


func _press_picker_option(picker: PromotionPicker, index: int) -> void:
	var option := picker.get_node("Centre/Panel/Column/Options").get_child(index) as Button
	option.pressed.emit()
	await process_frame


func _scenario_checkmate() -> void:
	var game: GameScreen = await _new_game()
	for uci: String in ["e2e4", "e7e5", "d1h5", "b8c6", "f1c4", "g8f6", "h5f7"]:
		_play(game, uci)
	_check(game._header.center_text == "Checkmate · White wins",
		"checkmate banners the result, got '%s'" % game._header.center_text)
	_check(game._finished, "checkmate ends input")
	var before := _fen(game)
	game._on_square_pressed("e2")
	_check(_fen(game) == before, "taps after mate change nothing")
	game.queue_free()
	_phase_reached_end = true


func _scenario_draw_offer() -> void:
	var game: GameScreen = await _new_game()
	_play(game, "e2e4")
	game._open_game_menu()
	await process_frame
	var menu := game.get_node_or_null("GameMenu")
	_check(menu != null, "menu opens with an offer action")
	if menu == null:
		game.queue_free()
		return
	var offer := menu.get_child(0).get_child(0) as Button
	_check(offer.text == "Offer draw", "menu offers a draw first")
	offer.pressed.emit()
	await process_frame
	var answer: ConfirmationDialog = null
	for child in game.get_children():
		if child is ConfirmationDialog and (child as ConfirmationDialog).title == "Draw offered":
			answer = child as ConfirmationDialog
	_check(answer != null, "offer opens the answer dialog")
	if answer == null:
		game.queue_free()
		return
	answer.confirmed.emit()
	await process_frame
	_check(game._header.center_text == "Draw agreed",
		"accepted draw banners, got '%s'" % game._header.center_text)
	_check(game._finished, "agreed draw finishes the game")
	game.queue_free()
	_phase_reached_end = true


func _scenario_resign() -> void:
	var game: GameScreen = await _new_game()
	_play(game, "e2e4")
	game._open_game_menu()
	await process_frame
	var menu := game.get_node_or_null("GameMenu")
	_check(menu != null, "menu opens with a leave action")
	if menu == null:
		game.queue_free()
		return
	var leave := menu.get_child(0).get_child(1) as Button
	_check(leave.text == "Leave game", "menu offers leaving second")
	leave.pressed.emit()
	await process_frame
	var confirmation: ConfirmationDialog = null
	for child in game.get_children():
		if child is ConfirmationDialog and (child as ConfirmationDialog).title == "Leave game?":
			confirmation = child as ConfirmationDialog
	_check(confirmation != null, "leave asks for confirmation")
	if confirmation == null:
		game.queue_free()
		return
	game.leave_requested.connect(_on_leave_requested)
	confirmation.confirmed.emit()
	await process_frame
	_check(_leave_requested, "confirming leave resigns and exits")
	_check("Resignation" in game._header.center_text
		or "resign" in game._header.center_text.to_lower(),
		"resignation banners, got '%s'" % game._header.center_text)
	game.queue_free()
	_phase_reached_end = true
