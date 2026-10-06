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

	# A theme item name the engine does not know is ignored without complaint, so a
	# variation can be misspelled and everything still runs. Reading the resolved value
	# back is the only way to know the theme item is real. See
	# foundation_tightening item 3.
	var muted := Color(0.72, 0.66, 0.58, 1.0)
	var rival := PARTICIPANT_SCENE.instantiate() as ParticipantCard
	rival.is_opponent = true
	root.add_child(rival)
	await process_frame
	var icon := rival.get_node("Content/Avatar/PieceIcon") as TextureRect
	_check(icon.theme_type_variation == &"MutedPieceIcon",
		"opponent piece uses the muted variation")
	_check(icon.get_theme_color("modulate", "TextureRect") == muted,
		"and the theme really supplies that colour, got %s"
			% icon.get_theme_color("modulate", "TextureRect"))
	rival.queue_free()

	var backdrop := Panel.new()
	backdrop.theme_type_variation = &"ModalBackdrop"
	root.add_child(backdrop)
	await process_frame
	var wash := backdrop.get_theme_stylebox("panel") as StyleBoxFlat
	_check(wash != null and wash.bg_color == Color(0.05, 0.04, 0.03, 0.72),
		"modal backdrop wash comes from the theme, got %s"
			% ("null" if wash == null else wash.bg_color))
	backdrop.queue_free()

	# The meter draws its own bars, so its colours come from a custom theme type read by
	# the script. Checked here because a custom type that nothing reads would look
	# perfectly correct in the theme file.
	var bars := Control.new()
	root.add_child(bars)
	await process_frame
	_check(bars.get_theme_color("bar_good", &"NetworkBars") == Color(0.42, 0.92, 0.52, 1),
		"connection meter colours come from the theme, got %s"
			% bars.get_theme_color("bar_good", &"NetworkBars"))
	bars.queue_free()
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
	# Counted by scene type rather than by reaching into a list the screen keeps for
	# its own bookkeeping. The assertion is about what the player can see: four rows.
	var rows := 0
	for child in hub._player_rows.get_children():
		if child is PlayerRow:
			rows += 1
	_check(rows == 4, "hub populates mock player rows, got %d" % rows)
	_check(hub._player_rows_added.size() == 4,
		"and tracks one invite control per row, got %d" % hub._player_rows_added.size())
	hub._create_invite_button.pressed.emit()
	_check(hub._active_invite_flow == "create", "hub enters create invite flow")
	_check(not hub._invite_grid.visible and hub._flow.visible,
		"hub hides invite choices during create flow")
	_check(hub._flow.get_child_count() > 0,
		"and the flow card is instanced from a scene, not built by the screen")
	var card: String = hub._flow.get_script().resource_path
	_check(card == "res://src/ui/components/invite_flow_card/invite_flow_card.gd",
		"flow card is the shared component, got %s" % card)
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
	# The discovery dialog has to be a scene and has to keep the hub's answers, because
	# the alternative was copying two booleans in on every opening.
	var dialog := hub._discovery_dialog
	_check(dialog != null, "hub holds a discovery dialog")
	_check(dialog.get_script().resource_path
			== "res://src/ui/components/discovery_dialog/discovery_dialog.gd",
		"and it is the shared component scene")
	hub._discoverable_nearby = false
	hub._show_discovery_settings()
	await process_frame
	_check(dialog.visible, "opening the dialog shows it")
	_check(dialog.discoverable_nearby == false,
		"and it opens on the answers in force, not its own defaults")
	_check(not dialog.get_node("Options/Nearby").button_pressed,
		"with the control showing that answer")
	var changes := {"count": 0}
	dialog.discovery_changed.connect(
		func(_nearby: bool, _online: bool) -> void: changes["count"] += 1)
	dialog.get_node("Options/Online").button_pressed = true
	await process_frame
	_check(int(changes["count"]) == 1, "the dialog reports a change")
	_check(hub._discoverable_online, "and the hub takes it")
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
	var clock_strip := game.get_node("HUD/HUDRoot/ClockStrip") as PanelContainer
	_check(clock_strip != null, "game screen has a compact clock strip")
	_check(clock_strip.get_node("Content/OpponentClock").text == "MORGAN  09:58",
		"clock strip shows the opponent clock")
	_check(clock_strip.get_node("Content/PlayerClock").text == "10:00  YOU",
		"clock strip shows the local clock")
	_check(not game.get_node("HUD/HUDRoot/GameHeader/NetworkIndicator").visible,
		"computer game keeps network status hidden")
	var peer_game := GAME_SCENE.instantiate() as GameScreen
	peer_game.configure_peer()
	root.add_child(peer_game)
	await process_frame
	_check(peer_game.get_node("HUD/HUDRoot/GameHeader/NetworkIndicator").visible,
		"peer game restores network status in the header")
	_check(peer_game.get_node("HUD/HUDRoot/GameHeader/VoiceCluster").visible,
		"peer game restores voice control in the header")
	peer_game.queue_free()
	# The screen root is a full-rect Control and Control.mouse_filter defaults to
	# MOUSE_FILTER_STOP, which is why it is set to IGNORE. Without this, no mouse
	# event reaches the camera at all.
	_check(game.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"the game screen root lets input through, got %d" % game.mouse_filter)
	_check(game.get_node("HUD/HUDRoot").mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"and so does the HUD root")

	# The camera reads input before the GUI, so it must refuse a drag that began on
	# something interactive, or the board would rotate while a button was pressed.
	# The earlier checks could not catch this: they drove orbit_by directly.
	var free_press := Vector2(400.0, 520.0)
	_check(not game._camera._dragged_by_gui(free_press),
		"a press on empty board space is free to drag")
	var header_pos: Vector2 = game.get_node("HUD/HUDRoot/GameHeader").get_global_rect().get_center()
	_check(game._camera._dragged_by_gui(header_pos),
		"a press on the header is not, so the header keeps its clicks")
	var view_button := game.get_node("HUD/HUDRoot/BoardViewButton") as Button
	_check(game._camera._dragged_by_gui(view_button.get_global_rect().get_center()),
		"and neither is one on the board view button")

	# A finger rotates, on the evidence that pinch works and drag did not: the touch
	# events are delivered and the emulated mouse ones are not. Driven as touch events
	# rather than as mouse ones, because driving mouse motion would pass whether or not
	# the touch path works at all, which is the check that was wrong three times.
	# Put the camera back at the end. Three of these checks have now broken the ones
	# after them by leaving it somewhere else, which is the same mistake each time:
	# shared state that a check moves and does not put back.
	var cam := game._camera
	var saved_yaw: float = cam.yaw_degrees
	var saved_pitch: float = cam.pitch_degrees
	var touch_yaw: float = cam.yaw_degrees
	var touch_down := InputEventScreenTouch.new()
	touch_down.index = 0
	touch_down.pressed = true
	touch_down.position = Vector2(400.0, 520.0)
	cam._input(touch_down)
	var touch_drag := InputEventScreenDrag.new()
	touch_drag.index = 0
	touch_drag.position = Vector2(440.0, 520.0)
	touch_drag.relative = Vector2(40.0, 0.0)
	cam._input(touch_drag)
	_check(not is_equal_approx(cam.yaw_degrees, touch_yaw),
		"a one-finger drag rotates the board, yaw %.1f -> %.1f"
			% [touch_yaw, cam.yaw_degrees])

	# And the emulated mouse must not also rotate while that finger is down, or the
	# board would turn at twice the speed on a device where both do arrive.
	var before_double: float = cam.yaw_degrees
	var emulated := InputEventMouseMotion.new()
	emulated.relative = Vector2(40.0, 0.0)
	cam._dragging_mouse = true
	cam._input(emulated)
	_check(is_equal_approx(cam.yaw_degrees, before_double),
		"and the emulated mouse does not rotate on top of it")

	var lift := InputEventScreenTouch.new()
	lift.index = 0
	lift.pressed = false
	cam._input(lift)
	cam._dragging_mouse = true
	var mouse_yaw: float = cam.yaw_degrees
	cam._input(emulated)
	_check(not is_equal_approx(cam.yaw_degrees, mouse_yaw),
		"while a plain mouse drag still rotates once no finger is down")
	cam.yaw_degrees = saved_yaw
	cam.pitch_degrees = saved_pitch
	cam._dragging_mouse = false

	# The piece seam exists before any piece does. It is keyed by the identities that
	# arrive over the application boundary rather than by an enum declared here, so
	# there is one list of piece types and this project is not it.
	_check(game._board.get_node("Coordinates").get_child_count() == 32,
		"game board builds reusable labels on all four frame sides")
	_check(game._board.get_node("Coordinates/FileFront_a").mesh.text == "a",
		"board exposes file coordinate labels")
	var board_surface := game._board.get_node("BoardSurface") as MeshInstance3D
	_check(board_surface.mesh is ArrayMesh, "board uses one procedural ArrayMesh surface")
	_check((board_surface.mesh as ArrayMesh).get_surface_count() == 3,
		"board mesh separates light, dark, and frame materials")
	_check(game._board.get_node("Squares/Square_a1").get_child_count() == 0,
		"square markers carry no duplicate render geometry")
	var board_aabb := (board_surface.mesh as ArrayMesh).get_aabb()
	_check(board_aabb.size.x > 8.7 and board_aabb.size.z > 8.7 and board_aabb.size.y > 0.3,
		"board mesh includes the full frame and plinth bounds")
	_check(game._board.get_node("Coordinates/RankLeft_1").mesh.text == "1",
		"board exposes rank coordinate labels")
	_check(is_equal_approx(game._board.get_node("Coordinates/FileFront_a").position.z, 4.19),
		"file labels are pinned to the frame midpoint")
	_check(is_equal_approx(game._board.get_node("Coordinates/RankLeft_1").position.x, -4.19),
		"rank labels are pinned to the frame midpoint")
	_check(is_equal_approx(game._board.get_node("Coordinates/FileFront_a").position.y, 0.029),
		"coordinate markings sit on the frame top surface")
	var pieces := game._board.get_node("Pieces")
	_check(pieces.get_child_count() == 32, "game builds the reusable starting piece position")
	var white_mesh := pieces.get_node("White_Pawn_a2/Mesh") as MeshInstance3D
	var black_mesh := pieces.get_node("Black_Pawn_a7/Mesh") as MeshInstance3D
	_check(white_mesh.material_override != null and black_mesh.material_override != null,
		"pieces receive controlled side materials")
	_check(white_mesh.material_override != black_mesh.material_override,
		"white and black pieces use separate shared materials")
	_check(is_equal_approx(pieces.get_node("White_Pawn_a2/Mesh").scale.x, 16.0),
		"pieces use the approved board presentation scale")
	_check(is_equal_approx(pieces.get_node("White_Pawn_a2").position.x, -3.5),
		"white pawn is centered on the a-file square")
	_check(is_equal_approx(pieces.get_node("White_Pawn_a2").position.z, 2.5),
		"white pawn is centered on the second rank")
	var pawn_mesh := pieces.get_node("White_Pawn_a2/Mesh") as MeshInstance3D
	_check(is_equal_approx(pawn_mesh.position.y, 0.0),
		"white pawn mesh is grounded against the board surface (y=%.3f)" % pawn_mesh.position.y)
	_check(is_equal_approx(pieces.get_node("Black_Pawn_a7").rotation.y, PI),
		"black pieces face the opposing side")
	_check(is_equal_approx(pieces.get_node("White_Knight_b1").rotation.y, PI + deg_to_rad(60.0)),
		"white knight uses the 10 o'clock facing")
	_check(is_equal_approx(pieces.get_node("Black_Knight_b8").rotation.y, -deg_to_rad(60.0)),
		"black knight mirrors the 10 o'clock facing")
	var key_light := game.get_node("World/KeyLight") as DirectionalLight3D
	_check(is_equal_approx(key_light.rotation_degrees.x, -90.0),
		"game key light is directly above the board")
	_check(is_equal_approx(game._camera.target.y, -0.45),
		"game camera centers the board in the usable screen area")
	_check(game.get_node("World/OpponentFillLight") is OmniLight3D,
		"game has an opponent-side fill light")
	_check(game.get_node("World/PlayerFillLight") is OmniLight3D,
		"game has a player-side fill light")
	_check(game.get_node("World/LeftFillLight") is OmniLight3D,
		"game has a left-side fill light")
	_check(game.get_node("World/RightFillLight") is OmniLight3D,
		"game has a right-side fill light")
	var ground := game.get_node("World/Ground") as MeshInstance3D
	_check(ground != null and ground.mesh is PlaneMesh,
		"game grounds the board with a quiet surface")
	_check(key_light.light_energy >= 1.5,
		"game key light is bright enough for the dark pieces")
	_check((game.get_node("World/OpponentFillLight") as OmniLight3D).light_energy >= 0.8,
		"opponent-side fill light lifts the dark pieces")
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
	# On the board, not at (0,0). A press in the corner lands on the header and the
	# camera now refuses to drag from there, so a drag test that does not say where it
	# presses was testing the refusal rather than the rotation.
	drag_start.position = Vector2(400.0, 520.0)
	game._camera._input(drag_start)
	var drag_motion := InputEventMouseMotion.new()
	drag_motion.relative = Vector2(40.0, 0.0)
	game._camera._input(drag_motion)
	var drag_end := InputEventMouseButton.new()
	drag_end.button_index = MOUSE_BUTTON_LEFT
	drag_end.pressed = false
	game._camera._input(drag_end)
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
