extends SceneTree

const APP_SCENE: PackedScene = preload("res://src/ui/app/app_root.tscn")
const HOME_SCENE: PackedScene = preload("res://src/ui/screens/home/home_screen.tscn")
const SETUP_SCENE: PackedScene = preload("res://src/ui/screens/game_setup/game_setup_screen.tscn")
const HUB_SCENE: PackedScene = preload("res://src/ui/screens/multiplayer_hub/multiplayer_hub_screen.tscn")
const GAME_SCENE: PackedScene = preload("res://src/ui/screens/game/game_screen.tscn")
const HEADER_SCENE: PackedScene = preload("res://src/ui/components/game_header/game_header.tscn")
const CHOICE_SCENE: PackedScene = preload("res://src/ui/components/choice_group/choice_group.tscn")
const PARTICIPANT_SCENE: PackedScene = preload("res://src/ui/components/participant_card/participant_card.tscn")
const THEME: Theme = preload("res://src/ui/theme/chess_relay_theme.tres")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_check_scene_contracts()
	await _check_reusable_components()
	await _check_participant_and_setup_states()
	await _check_hub_interactions()
	await _check_responsive_layouts()
	await _check_game_screen()
	_check_theme_contracts()
	await _check_app_lifecycle()
	if _failures == 0:
		print("UI smoke checks passed")
	else:
		push_error("UI smoke checks failed: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _check_scene_contracts() -> void:
	_check(APP_SCENE != null, "app scene loads")
	_check(HOME_SCENE != null, "home scene loads")
	_check(SETUP_SCENE != null, "game setup scene loads")
	_check(HUB_SCENE != null, "multiplayer hub scene loads")
	_check(GAME_SCENE != null, "game scene loads")
	_check(HEADER_SCENE != null, "game header scene loads")
	_check(CHOICE_SCENE != null, "choice group scene loads")


func _check_reusable_components() -> void:
	var header := HEADER_SCENE.instantiate() as GameHeader
	root.add_child(header)
	await process_frame
	header.set_visibility(false, false, true, true)
	_check(not header.get_node("NetworkIndicator").visible, "header hides network indicator")
	_check(not header.get_node("VoiceCluster").visible, "header hides voice control")
	header.set_visibility(true, true, true, true)
	_check(header.get_node("NetworkIndicator").visible, "header shows network indicator")
	header.queue_free()

	var choices := CHOICE_SCENE.instantiate() as ChoiceGroup
	choices.choices = PackedStringArray(["White", "Black", "Random"])
	choices.selected_index = 1
	root.add_child(choices)
	await process_frame
	_check(choices.get_selected_choice() == "Black", "choice group selects configured option")
	choices.set_selection(2)
	_check(choices.get_selected_choice() == "Random", "choice group changes selection")
	choices.queue_free()


func _check_participant_and_setup_states() -> void:
	var participant := PARTICIPANT_SCENE.instantiate() as ParticipantCard
	root.add_child(participant)
	await process_frame
	participant.set_side("Black")
	_check(participant.get_node("Content/Info/SideRow/SideValue").text == "Black",
		"participant card updates black side")
	_check(participant.get_node("Content/Info/SideRow/SideValue").theme_type_variation == &"SetupDarkSideBadge",
		"participant card applies black badge style")
	participant.set_side("Random")
	_check(participant.get_node("Content/Info/SideRow/SideValue").theme_type_variation == &"SetupNeutralSideBadge",
		"participant card applies neutral badge style")
	participant.queue_free()

	var setup := SETUP_SCENE.instantiate() as GameSetupScreen
	root.add_child(setup)
	await process_frame
	setup._side_choice.get_node("Options").get_child(1).pressed.emit()
	_check(setup._player_card.side == "Black", "setup updates local participant side")
	_check(setup._opponent_card.side == "White", "setup updates opponent participant side")
	setup._time_choice.get_node("Options").get_child(5).pressed.emit()
	_check(setup._custom_time_controls.visible, "setup shows custom time controls")
	setup._custom_minutes.value = 10
	setup._custom_increment.value = 5
	_check("10 min" in setup._settings_summary.text, "setup updates custom time summary")
	setup._toggle_header_menu()
	_check(setup._header_menu_layer != null, "setup opens header menu")
	setup._close_header_menu()
	_check(setup._header_menu_layer == null, "setup closes header menu")
	setup.configure_peer("Morgan", "peer")
	await process_frame
	setup._on_leave_setup_pressed()
	var confirmation: ConfirmationDialog
	for child in setup.get_children():
		if child is ConfirmationDialog:
			confirmation = child as ConfirmationDialog
			break
	_check(confirmation != null, "peer setup opens leave confirmation")
	if confirmation != null:
		_check(confirmation.get_ok_button().text == "Leave game", "leave confirmation has leave action")
		_check(confirmation.get_cancel_button().text == "Stay", "leave confirmation has stay action")
		_check(confirmation.get_label().horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER,
			"leave confirmation centers description text")
		_check(confirmation.theme_type_variation == &"ModalDialog", "leave confirmation uses modal surface")
		_check(confirmation.get_theme_constant("buttons_min_width") == 144,
			"leave confirmation uses shared button width")
		_check(confirmation.get_theme_constant("buttons_min_height") == 48,
			"leave confirmation uses shared button height")
		_check(confirmation.get_ok_button().theme_type_variation == &"ModalDangerButton",
			"leave confirmation uses danger action style")
		_check(confirmation.get_cancel_button().theme_type_variation == &"ModalSecondaryButton",
			"leave confirmation uses secondary action style")
		confirmation.queue_free()
	setup.queue_free()


func _check_hub_interactions() -> void:
	var hub := HUB_SCENE.instantiate() as MultiplayerHubScreen
	root.add_child(hub)
	await process_frame
	_check(hub._player_invite_buttons.size() == 4, "hub populates mock player rows")
	hub._create_invite_button.pressed.emit()
	_check(hub._active_invite_flow == "create", "hub enters create invite flow")
	_check(not hub._invite_grid.visible and hub._invite_flow_card.visible,
		"hub hides invite choices during create flow")
	hub._cancel_create_wait()
	_check(hub._active_invite_flow.is_empty() and hub._invite_grid.visible,
		"hub restores invite choices after cancel")
	hub._join_game_button.pressed.emit()
	hub._on_join_code_changed("ABC234")
	_check(hub._join_button.disabled == false, "hub enables join for valid code")
	hub._on_join_pressed()
	_check(hub._active_invite_flow == "join-connecting", "hub enters join connecting state")
	hub.join_failed()
	_check(hub._active_invite_flow == "join-failed", "hub exposes join failure state")
	hub._cancel_join()
	_check(hub._active_invite_flow.is_empty(), "hub restores state after join cancel")
	await process_frame
	hub.queue_free()


func _check_responsive_layouts() -> void:
	var hub := HUB_SCENE.instantiate() as MultiplayerHubScreen
	root.add_child(hub)
	await process_frame
	hub._update_responsive_layout(800.0)
	_check(hub._invite_grid.columns == 1, "hub stacks invite cards at narrow width")
	hub._update_responsive_layout(1200.0)
	_check(hub._invite_grid.columns == 2, "hub uses two invite columns at wide width")
	hub.queue_free()

	var setup := SETUP_SCENE.instantiate() as GameSetupScreen
	root.add_child(setup)
	await process_frame
	setup._update_screen_columns(640.0)
	_check(setup._players_grid.columns == 1, "setup stacks players at narrow width")
	_check(setup._settings_grid.columns == 1, "setup stacks settings at narrow width")
	setup._update_screen_columns(1200.0)
	_check(setup._players_grid.columns == 2, "setup uses two player columns at wide width")
	_check(setup._settings_grid.columns == 3, "setup uses three setting columns at wide width")
	setup.queue_free()


func _check_game_screen() -> void:
	var game := GAME_SCENE.instantiate() as GameScreen
	root.add_child(game)
	await process_frame
	_check(game._board.get_node("Squares").get_child_count() == 64,
		"game board builds 64 reusable squares")
	_check(game._board.get_node("Coordinates").get_child_count() == 32,
		"game board builds reusable labels on all four frame sides")
	_check(game._board.get_node("Coordinates/FileFront_a").mesh.text == "a",
		"board exposes file coordinate labels")
	_check(game._board.get_node("Coordinates/RankLeft_1").mesh.text == "1",
		"board exposes rank coordinate labels")
	_check(is_equal_approx(game._board.get_node("Coordinates/FileFront_a").position.z, 4.19),
		"file labels are pinned to the frame midpoint")
	_check(is_equal_approx(game._board.get_node("Coordinates/RankLeft_1").position.x, -4.19),
		"rank labels are pinned to the frame midpoint")
	_check(is_equal_approx(game._board.get_node("Coordinates/FileFront_a").position.y, 0.029),
		"coordinate markings sit on the frame top surface")
	_check(game._pieces.get_child_count() == 32,
		"game screen renders a complete demo position")
	var key_light := game.get_node("World/KeyLight") as DirectionalLight3D
	_check(is_equal_approx(key_light.rotation_degrees.x, -90.0),
		"game key light is directly above the board")
	_check(game.get_node("World/OpponentFillLight") is OmniLight3D,
		"game has an opponent-side fill light")
	_check(game.get_node("World/PlayerFillLight") is OmniLight3D,
		"game has a player-side fill light")
	_check(game.get_node("World/LeftFillLight") is OmniLight3D,
		"game has a left-side fill light")
	_check(game.get_node("World/RightFillLight") is OmniLight3D,
		"game has a right-side fill light")
	var black_piece := game._pieces.get_child(2) as ChessPieceView
	_check(is_equal_approx(black_piece.rotation.y, PI),
		"black pieces face the opposing side")
	game._update_camera_framing(1440.0, 900.0)
	var wide_camera_height := game._camera.position.y
	game._update_camera_framing(640.0, 900.0)
	_check(game._camera.position.y > wide_camera_height,
		"game camera pulls back for a narrow viewport")
	game._update_camera_framing(1440.0, 900.0)
	_check(is_equal_approx(game._camera.position.y, wide_camera_height),
		"game camera restores framing for a wide viewport")
	var initial_camera_position := game._camera.position
	game._camera.orbit_by(90.0)
	_check(not game._camera.position.is_equal_approx(initial_camera_position),
		"game camera orbits around the board")
	var drag_yaw: float = game._camera.yaw_degrees
	var drag_start := InputEventMouseButton.new()
	drag_start.button_index = MOUSE_BUTTON_LEFT
	drag_start.pressed = true
	game._camera._unhandled_input(drag_start)
	var drag_motion := InputEventMouseMotion.new()
	drag_motion.relative = Vector2(40.0, 0.0)
	game._camera._unhandled_input(drag_motion)
	var drag_end := InputEventMouseButton.new()
	drag_end.button_index = MOUSE_BUTTON_LEFT
	drag_end.pressed = false
	game._camera._unhandled_input(drag_end)
	_check(not is_equal_approx(game._camera.yaw_degrees, drag_yaw),
		"camera drag input changes orbit yaw")
	var camera_distance: float = game._camera.distance
	game._camera.set_distance(camera_distance + 2.0)
	_check(game._camera.distance > camera_distance,
		"game camera zooms out within its distance contract")
	game._board_view_button.pressed.emit()
	_check(game.get_node_or_null("HUD/BoardViewOverlay/BoardViewMenu") != null,
		"game opens board view controls")
	game.get_node("HUD/BoardViewOverlay/BoardViewMenu").get_child(0).get_child(1).pressed.emit()
	_check(is_equal_approx(game._camera.yaw_degrees, 94.5),
		"board view controls rotate by the prototype step")
	_check(game.get_node_or_null("HUD/BoardViewOverlay/BoardViewMenu") != null,
		"board view stays open after an internal action")
	game.get_node("HUD/BoardViewOverlay/BoardViewMenu").get_child(0).get_child(2).pressed.emit()
	_check(is_equal_approx(game._camera.yaw_degrees, 274.5),
		"board view controls flip the board")
	var outside_click := InputEventMouseButton.new()
	outside_click.pressed = true
	game._on_board_view_overlay_input(outside_click,
		game.get_node("HUD/BoardViewOverlay"))
	_check(game.get_node("HUD/BoardViewOverlay").is_queued_for_deletion(),
		"board view closes from an outside click")
	for square in ["a1", "e4", "h8"]:
		_check(game._board.world_to_square(game._board.square_to_world(square)) == square,
			"board coordinate round trip works for %s" % square)
	game._board.set_highlight("e4")
	_check(game._board.get_highlighted_square() == "e4",
		"board exposes selected square state")
	_check(game._board.get_node("Highlights").get_child_count() == 1,
		"board renders selected square highlight")
	game._board.set_last_move("e2", "e4")
	_check(game._board.get_node("LastMove").get_child_count() == 2,
		"board renders last move squares")
	game._board.set_legal_moves(["e5", "f5"])
	_check(game._board.get_node("LegalMoves").get_child_count() == 2,
		"board renders legal move previews")
	game._board.set_check_square("e8")
	_check(game._board.get_node("Check").get_child_count() == 1,
		"board renders check state")
	game._on_square_pressed("e4")
	_check("E4" in game._header.center_text, "header responds to square selection")
	game.queue_free()


func _check_theme_contracts() -> void:
	_check(THEME.has_stylebox("focus", &"Button"), "theme defines shared button focus style")
	_check(THEME.has_stylebox("normal", &"SetupSideBadge"), "theme defines white side badge style")
	_check(THEME.has_stylebox("normal", &"SetupDarkSideBadge"), "theme defines black side badge style")
	_check(THEME.has_stylebox("normal", &"SetupNeutralSideBadge"), "theme defines neutral side badge style")


func _check_app_lifecycle() -> void:
	var app := APP_SCENE.instantiate()
	root.add_child(app)
	await process_frame
	_check(app.get_node("ScreenHost").get_child_count() == 1, "app starts with one screen")
	_check(app._current_screen is HomeScreen, "app starts on home screen")
	app._on_play_computer_requested()
	await process_frame
	_check(app._current_screen is GameSetupScreen, "home enters game setup")
	(app._current_screen as GameSetupScreen)._play_button.pressed.emit()
	await process_frame
	_check(app._current_screen is GameScreen, "setup enters main game")
	(app._current_screen as GameScreen).leave_requested.emit()
	await process_frame
	_check(app._current_screen is HomeScreen, "game leave returns home")
	app._on_p2p_requested()
	await process_frame
	_check(app._current_screen is MultiplayerHubScreen, "home enters multiplayer hub")
	app.queue_free()


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		_failures += 1
		push_error("FAIL: %s" % description)
