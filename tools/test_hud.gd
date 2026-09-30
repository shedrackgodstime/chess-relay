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

	_asset_checks()
	_layout_checks(main, hud)
	_menu_check(main, hud)
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


func _layout_checks(main: Main, hud: Hud) -> void:
	print("HUD layout")
	_check("turn label exists", hud.turn_label != null, "")
	var view_buttons := [hud.rotate_left_button, hud.rotate_right_button,
		hud.flip_button, hud.reset_button]
	_check("four view buttons plus a menu button exist",
		all_buttons_present(view_buttons) and hud.menu_button != null, "")
	var touch := 0
	for button in view_buttons:
		if button.custom_minimum_size.x >= 48.0 and button.custom_minimum_size.y >= 44.0:
			touch += 1
	_check("buttons meet phone touch size", touch == 4, "ok=%d/4" % touch)

	# Icon-only: no text, but a tooltip, and a real glyph on the button.
	var labelled := 0
	var with_icon := 0
	for button: Button in view_buttons + [hud.menu_button]:
		if button.text == "" and button.tooltip_text != "":
			labelled += 1
		var glyph := button.get_node_or_null("Glyph") as TextureRect
		if glyph != null and glyph.texture != null:
			with_icon += 1
	_check("all buttons are icon-only with tooltips", labelled == 5,
		"ok=%d/5" % labelled)
	_check("all buttons carry a generated icon", with_icon == 5, "ok=%d/5" % with_icon)

	# Vertical column, right-aligned, in a deliberate order.
	var column := hud.control_column
	_check("controls live in one vertical column", column is VBoxContainer, "")
	_check("column holds the four view buttons", column.get_child_count() == 4,
		"children=%d" % column.get_child_count())
	_check("column order is rotate pair, flip, reset",
		column.get_child(0).name == "RotateLeftButton"
			and column.get_child(1).name == "RotateRightButton"
			and column.get_child(2).name == "FlipButton"
			and column.get_child(3).name == "ResetButton",
		str(_child_names(column)))
	# Anchors, not absolute pixels: the layout must hold at any resolution,
	# which is the point of anchoring in the first place.
	_centering_checks(view_buttons)
	_mic_checks(main, hud)

	_check("column is anchored to the right edge", column.anchor_left >= 0.9,
		"anchor_left=%.2f" % column.anchor_left)
	_check("column is vertically centred",
		absf(column.anchor_top - 0.5) < 0.01 and absf(column.anchor_bottom - 0.5) < 0.01,
		"top=%.2f bottom=%.2f" % [column.anchor_top, column.anchor_bottom])


## Centring must not depend on Button's own icon layout. expand_icon sizes
## the icon from the button rect and clamps afterwards, so the draw offset can
## be derived from the pre-clamp size and land off-centre. The glyph instead
## lives in an inset rect, which is centred by construction.
func _centering_checks(buttons: Array) -> void:
	print("Icon centring")
	var checked := 0
	for button in buttons:
		if button == null:
			continue
		var glyph := button.get_node_or_null("Glyph") as TextureRect
		if glyph == null:
			continue
		checked += 1
		# Symmetric insets on every side, so the glyph sits dead centre.
		var symmetric: bool = is_equal_approx(glyph.offset_left, -glyph.offset_right) \
			and is_equal_approx(glyph.offset_top, -glyph.offset_bottom)
		# A real inset, so the glyph does not touch the panel edge.
		var padded: bool = glyph.offset_left > 0.0 and glyph.offset_top > 0.0
		# Aspect preserved and centred whatever size the texture imported at.
		var centred: bool = glyph.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# The button must not also be doing its own icon layout.
		var button_has_icon: Texture2D = button.icon
		var not_on_button: bool = button_has_icon == null and not button.expand_icon
		# Clicks must reach the button through the glyph.
		var clickable: bool = glyph.mouse_filter == Control.MOUSE_FILTER_IGNORE
		if symmetric and padded and centred and not_on_button and clickable:
			continue
		_check("%s glyph centred" % button.name, false,
			"symmetric=%s padded=%s centred=%s offButton=%s clickable=%s" % [
				symmetric, padded, centred, not_on_button, clickable
			])
	if checked == 4:
		_check("all four view glyphs are centred and padded", true,
			"inset=%.0f" % Hud.ICON_INSET)
	_check("all four view buttons use the inset glyph",
		checked == 4, "found=%d" % checked)


## The mic control sits between the move count and the menu, with no panel,
## and swaps its glyph rather than tinting so muted cannot look like styling.
func _mic_checks(main: Main, hud: Hud) -> void:
	print("Mic control")
	_check("mic button exists", hud.mic_button != null, "")
	_check("mic sits left of the menu",
		hud.mic_button.position.x < hud.menu_button.position.x,
		"mic=%.0f menu=%.0f" % [hud.mic_button.position.x, hud.menu_button.position.x])
	_check("mic is in the top band", hud.mic_button.position.y < 100.0,
		"y=%.0f" % hud.mic_button.position.y)
	_check("mic has no panel behind it", hud.mic_button.flat, "")

	var glyph := hud.mic_button.get_node_or_null("Glyph") as TextureRect
	_check("mic carries a glyph", glyph != null and glyph.texture != null, "")
	# The scene stores the generated texture, so the button starts with a
	# deserialised copy rather than the instance Icons caches in this process.
	# Identity is therefore only meaningful after a toggle.
	var muted_texture: Texture2D = glyph.texture

	var fired: Array[bool] = []
	hud.mic_toggled.connect(func(on: bool) -> void: fired.append(on))
	hud.mic_button.emit_signal("pressed")
	_check("mic toggles on and announces it",
		fired.size() == 1 and fired[0] and hud.mic_enabled, "fired=%d" % fired.size())
	_check("live and muted use different glyphs", glyph.texture != muted_texture, "")
	hud.mic_button.emit_signal("pressed")
	_check("mic toggles back off", not hud.mic_enabled and fired.size() == 2, "")
	_check("muted glyph is restored", glyph.texture == Icons.mic_off(), "")


## The menu button exists and announces itself; its screen is Phase 4.
func _menu_check(main: Main, hud: Hud) -> void:
	print("Menu button")
	var fired := [false]
	hud.menu_requested.connect(func() -> void: fired[0] = true)
	hud.menu_button.emit_signal("pressed")
	_check("menu button emits its intent", fired[0], "")
	_check("menu button is separate from the view column",
		hud.menu_button.get_parent() != hud.control_column, "")
	_check("menu button is anchored top-right",
		hud.menu_button.anchor_left >= 0.9 and hud.menu_button.anchor_top <= 0.1,
		"left=%.2f top=%.2f" % [hud.menu_button.anchor_left, hud.menu_button.anchor_top])


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


## The shipped glyphs are SVGs. They cannot be imported in this environment,
## so this checks the source instead: present, non-empty, and carrying the
## viewBox and raster size the importer needs.
func _asset_checks() -> void:
	print("Icon assets")
	for name in ["rotate_left", "rotate_right", "flip", "reset", "menu", "settings", "mic", "mic_off"]:
		var path := "res://ui/icons/%s.svg" % name
		var exists := FileAccess.file_exists(path)
		_check("svg present: %s" % name, exists, path)
		if not exists:
			continue
		var text := FileAccess.get_file_as_string(path)
		_check("svg is sized for crisp expansion: %s" % name,
			text.contains('width="64"') and text.contains('height="64"')
				and text.contains('viewBox="0 0 24 24"'), "")
		_check("svg is recoloured to the palette: %s" % name,
			text.contains("#ffe19e") and not text.contains("currentColor"), "")
		_check("svg has geometry: %s" % name,
			text.contains("<path") or text.contains("<circle"), "")

	# Every icon resolves to a real texture here, via SVG or the drawn fallback.
	var resolved: Array[Texture2D] = [
		Icons.rotate_left(), Icons.rotate_right(), Icons.flip(), Icons.reset(),
		Icons.menu(), Icons.settings(), Icons.mic(), Icons.mic_off(),
	]
	var names := ["rotate_left", "rotate_right", "flip", "reset", "menu", "settings", "mic", "mic_off"]
	for i in resolved.size():
		_check("icon resolves: %s" % names[i], resolved[i] != null, "")


func _child_names(node: Node) -> Array:
	var names: Array = []
	for child in node.get_children():
		names.append(child.name)
	return names


func all_buttons_present(buttons: Array) -> bool:
	for button in buttons:
		if button == null:
			return false
	return true


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		print("  ok   %s  %s" % [label, detail])
	else:
		_failures += 1
		printerr("  FAIL %s  %s" % [label, detail])