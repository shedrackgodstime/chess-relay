extends SceneTree

## Headless checks for the HUD controls and their routing.
##
##     godot-headless --headless --script res://tools/test_hud.gd

var _failures := 0


func _init() -> void:
	Quality.set_preset(Quality.Preset.MEDIUM)
	var scene := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var main: Main = scene
	main.ai_opponent = false
	var hud: Hud = main.hud

	_layout_checks(hud)
	_rotate_checks(main, hud)
	_flip_checks(main)
	_reset_checks(main)
	_turn_checks(main, hud)

	scene.queue_free()
	if _failures == 0:
		print("hud: all checks passed")
	else:
		printerr("hud: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _layout_checks(hud: Hud) -> void:
	print("HUD layout")
	_check("turn label exists", hud.turn_label != null, "")
	_check("four control buttons exist",
		hud.rotate_left_button != null and hud.rotate_right_button != null
			and hud.flip_button != null and hud.reset_button != null, "")
	var touch := 0
	for button in [hud.rotate_left_button, hud.rotate_right_button,
			hud.flip_button, hud.reset_button]:
		if button.custom_minimum_size.x >= 48.0 and button.custom_minimum_size.y >= 44.0:
			touch += 1
	_check("buttons meet phone touch size", touch == 4, "ok=%d/4" % touch)
	_check("buttons are labelled",
		hud.rotate_left_button.text != "" and hud.reset_button.text != "", "")


func _rotate_checks(main: Main, hud: Hud) -> void:
	print("Rotate controls")
	var camera: OrbitCamera = main.camera
	camera.reset_view(Vector3.ZERO, 0.0, 34.0, 11.0)
	var start := camera.yaw_degrees

	hud.rotate_right_button.emit_signal("pressed")
	_check("right button yaws clockwise", camera.yaw_degrees > start,
		"yaw %.1f -> %.1f" % [start, camera.yaw_degrees])
	var after_right := camera.yaw_degrees

	hud.rotate_left_button.emit_signal("pressed")
	hud.rotate_left_button.emit_signal("pressed")
	_check("left button yaws back past the start",
		camera.yaw_degrees < after_right, "yaw %.1f" % camera.yaw_degrees)

	# The camera must keep its pitch and distance while yawing.
	_check("rotating does not change pitch or zoom",
		is_equal_approx(camera.pitch_degrees, 34.0) and is_equal_approx(camera.distance, 11.0),
		"pitch=%.1f dist=%.1f" % [camera.pitch_degrees, camera.distance])

	# Still looks at the board after a spin.
	var forward := -camera.transform.basis.z.normalized()
	var want := (Vector3.ZERO - camera.transform.origin).normalized()
	_check("still framed on the board after rotating",
		forward.distance_squared_to(want) < 1e-6, "")


func _flip_checks(main: Main) -> void:
	print("Board flip")
	var camera: OrbitCamera = main.camera
	camera.reset_view(Vector3.ZERO, 0.0, 34.0, 11.0)

	main._on_flip_requested()
	_check("flip turns the board around", is_equal_approx(camera.yaw_degrees, 180.0),
		"yaw=%.1f" % camera.yaw_degrees)
	main._on_flip_requested()
	_check("flip again returns to the original side",
		is_equal_approx(camera.yaw_degrees, 0.0), "yaw=%.1f" % camera.yaw_degrees)


func _reset_checks(main: Main) -> void:
	print("Reset view")
	var camera: OrbitCamera = main.camera
	camera.yaw_degrees = 123.0
	camera.distance = 19.0
	camera.pitch_degrees = 70.0

	main.frame_board()
	_check("reset restores yaw", is_zero_approx(camera.yaw_degrees),
		"yaw=%.1f" % camera.yaw_degrees)
	_check("reset restores a usable distance", camera.distance < 15.0,
		"dist=%.1f" % camera.distance)
	_check("reset restores a sensible pitch",
		camera.pitch_degrees > 10.0 and camera.pitch_degrees < 60.0,
		"pitch=%.1f" % camera.pitch_degrees)


func _turn_checks(main: Main, hud: Hud) -> void:
	print("Turn display")
	_check("label names the side to move",
		hud.turn_label.text.begins_with("White"), "text=%s" % hud.turn_label.text)
	_check("label starts with zero moves",
		hud.turn_label.text.contains("0 moves"), "text=%s" % hud.turn_label.text)

	hud.set_turn(BoardState.DARK, 1)
	_check("singular move is not pluralised",
		hud.turn_label.text.begins_with("Black")
			and hud.turn_label.text.contains("1 move")
			and not hud.turn_label.text.contains("1 moves"),
		"text=%s" % hud.turn_label.text)
	hud.set_turn(BoardState.LIGHT, 12)
	_check("plural handling for many moves",
		hud.turn_label.text.contains("12 moves"), "text=%s" % hud.turn_label.text)

	# A real move must update it through the normal funnel.
	hud.set_turn(BoardState.LIGHT, 0)
	main.game.apply_move(ChessMove.new(Vector2i(4, 1), Vector2i(4, 3)))
	_check("a move advances the counter", hud.turn_label.text.contains("1 move"),
		"text=%s" % hud.turn_label.text)
	_check("a move passes the turn", hud.turn_label.text.begins_with("Black"),
		"text=%s" % hud.turn_label.text)


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		print("  ok   %s  %s" % [label, detail])
	else:
		_failures += 1
		printerr("  FAIL %s  %s" % [label, detail])