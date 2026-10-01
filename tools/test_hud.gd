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
	# Dev only: the cluster is up in every mode so it can be exercised alone.
	# Guard the flag, so flipping it back cannot silently hide the control.
	_check("dev flag keeps voice up", Main.DEV_SHOW_VOICE, "")
	# Assert both modes rather than whichever one the test happens to start in.
	for with_ai: bool in [true, false]:
		main.ai_opponent = with_ai
		hud.set_voice_visible(Main.DEV_SHOW_VOICE or not with_ai)
		_check("voice visible with ai_opponent=%s" % with_ai, hud.voice_row.visible, "")
	# Not "left of the menu" but exactly between the two references, measured
	# rather than assumed so a resize cannot quietly undo it.
	var label := hud.get_node("TurnLabel") as Label
	var label_mid := label.global_position.x + label.size.x * 0.5
	var menu_mid := hud.menu_button.global_position.x + hud.menu_button.size.x * 0.5
	var mic_mid := hud.mic_button.global_position.x + hud.mic_button.size.x * 0.5
	# The gap is the contract: a fixed distance from the menu, measured, so it
	# cannot silently drift. The old 'leans right' assertion is gone because
	# at a fixed gap that only holds above a certain width, and would have
	# failed on a narrow screen for a placement that is actually correct.
	_check("mic holds its gap from the menu",
		absf(menu_mid - mic_mid - Hud.VOICE_GAP) <= 1.0,
		"gap=%.1f wanted=%.1f" % [menu_mid - mic_mid, Hud.VOICE_GAP])
	_check("mic sits between the move count and the menu",
		mic_mid > label_mid and mic_mid < menu_mid,
		"mic=%.0f label=%.0f menu=%.0f" % [mic_mid, label_mid, menu_mid])
	_check("mic is in the top band", hud.mic_button.global_position.y < 100.0,
		"y=%.0f" % hud.mic_button.global_position.y)
	_check("mic has no panel behind it", hud.mic_button.flat, "")

	# The ring and the dot are separate channels, so neither may be the only
	# way to read the state. The ring means live only: a request must never be
	# mistakable for an open mic, or the opponent talks over someone asking.
	hud.set_voice_visible(true)
	var ring := hud.mic_ring
	var dot := hud.remote_dot
	_check("nothing shows at rest", not ring.visible and not dot.visible, "")

	var states: Array[int] = []
	hud.voice_state_changed.connect(func(st: Hud.VoiceState) -> void: states.append(st))

	# One tap from rest must ask, not transmit.
	hud.mic_button.emit_signal("pressed")
	_check("first tap requests voice",
		hud.voice_state == Hud.VoiceState.REQUESTING and states == [Hud.VoiceState.REQUESTING],
		"state=%d" % hud.voice_state)
	_check("a request shows no ring", not ring.visible, "")
	_check("a request is not live", not hud.is_voice_live(), "")
	var requesting_texture: Texture2D = (hud.mic_button.get_node("Glyph") as TextureRect).texture

	hud.mic_button.emit_signal("pressed")
	_check("second tap goes live", hud.is_voice_live(), "")
	_check("live shows the ring", ring.visible, "")
	var live_texture: Texture2D = (hud.mic_button.get_node("Glyph") as TextureRect).texture
	_check("live uses a different glyph from requesting", live_texture != requesting_texture, "")

	hud.mic_button.emit_signal("pressed")
	_check("third tap returns to off",
		hud.voice_state == Hud.VoiceState.OFF and states.size() == 3, "n=%d" % states.size())
	_check("off clears the ring", not ring.visible, "")
	var off_texture: Texture2D = (hud.mic_button.get_node("Glyph") as TextureRect).texture
	_check("all three states use distinct glyphs",
		off_texture != requesting_texture and requesting_texture != live_texture
			and off_texture != live_texture, "")

	hud.set_remote_speaking(true)
	_check("dot shows the opponent transmitting", dot.visible, "")
	hud.set_remote_speaking(false)
	_check("dot clears when they stop", not dot.visible, "")

	# Hidden voice must not leave a live mic behind it.
	hud.set_voice_state(Hud.VoiceState.LIVE)
	hud.set_voice_visible(false)
	_check("hiding voice hides the row", not hud.voice_row.visible, "")
	_check("hiding voice forces muted", hud.voice_state == Hud.VoiceState.OFF, "")
	hud.set_remote_speaking(true)
	_check("hiding voice clears the opponent dot", not dot.visible, "")
	hud.set_voice_visible(true)
	_check("showing voice reveals the row", hud.voice_row.visible, "")
	hud.set_remote_speaking(false)
	hud.set_voice_state(Hud.VoiceState.OFF)

	_check("mic carries a glyph",
		hud.mic_button.get_node_or_null("Glyph") is TextureRect, "")


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
	# The default view looks in from the player's own side, so their pieces are
	# at the bottom of the screen and the opponent's at the top.
	_check("reset looks in from the player's side",
		is_equal_approx(camera.yaw_degrees, Main.yaw_for_side(main.player_side)),
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
	for name in ["rotate_left", "rotate_right", "flip", "reset", "menu", "settings",
		"mic", "mic_off", "mic_signal"]:
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
		Icons.menu(), Icons.settings(), Icons.mic(), Icons.mic_off(), Icons.mic_signal(),
	]
	var names := ["rotate_left", "rotate_right", "flip", "reset", "menu", "settings",
		"mic", "mic_off", "mic_signal"]
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