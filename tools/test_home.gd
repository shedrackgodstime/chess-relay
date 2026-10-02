extends SceneTree

## The home screen: the first thing the game shows, in its own scene.
##
## Worth its own suite because it is the project's entry point. A parse error here is
## a game that opens on a blank window, and nothing in the in-game tests would notice.

var _failures := 0


func _init() -> void:
	var scene := (load("res://home.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	_check("the scene boots", scene is HomeScreen, "")
	if not scene is HomeScreen:
		quit(1)
		return
	var home := scene as HomeScreen

	_check("it has a title", home.title_label != null
		and home.title_label.text == "CHESS RELAY",
		"title=%s" % (home.title_label.text if home.title_label != null else "<none>"))

	var labels: Array = []
	for row in home.column.get_children():
		if row is Button:
			labels.append((row as Button).text)
	_check("with exactly the entries agreed",
		labels == ["Vs computer", "P2P game", "Settings"], "%s" % str(labels))

	_check("the picture covers the screen rather than being letterboxed",
		home.background.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED,
		"mode=%d" % home.background.stretch_mode)
	_check("and takes no taps, so it cannot eat a press meant for a button",
		home.background.mouse_filter == Control.MOUSE_FILTER_IGNORE, "")
	_check("nothing is focusable, so a stray key cannot start a game",
		(home.computer_button as Button).focus_mode == Control.FOCUS_NONE, "")
	var shade := home.get_node_or_null("HomeShade") as ColorRect
	_check("and the words have darkness of their own behind them", shade != null, "")
	if shade != null:
		# The picture must actually be held back, not just covered by a node that
		# happens to exist. Asserting the node's presence is how 0.55 passed review
		# while the image still shouted over the title.
		_check("and it really dims the picture", shade.color.a >= 0.88,
			"alpha=%.2f" % shade.color.a)
		_check("over the whole screen", shade.size.x >= home.size.x * 0.9
			and shade.size.y >= home.size.y * 0.9,
			"shade=%.0fx%.0f home=%.0fx%.0f" % [shade.size.x, shade.size.y,
				home.size.x, home.size.y])

	# P2P leads to a screen of its own now, rather than dead-ending here.
	_check("the multiplayer entry exists", home.p2p_button != null, "")
	_check("and it leads to the multiplayer screen",
		ResourceLoader.exists("res://p2p_lobby.tscn"), "")

	# Settings is still nothing behind it, and must say so where it is pressed.
	home.settings_button.pressed.emit()
	await process_frame
	var notice := home.column.get_node_or_null("HomeNotice") as Label
	_check("an entry with nothing behind it explains itself",
		notice != null and notice.text.find("Settings") >= 0,
		"notice=%s" % (notice.text if notice != null else "<none>"))

	# The entry point is this scene. Getting that wrong is a game that boots into the
	# board with no way to start a match, so it is asserted rather than assumed.
	var configured := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	_check("and it is the project's main scene", configured == "res://home.tscn",
		"configured=%s" % configured)
	_check("the board is a separate scene, not this one",
		ResourceLoader.exists("res://main.tscn")
			and str(ResourceLoader.get_resource_uid("res://main.tscn"))
				!= str(ResourceLoader.get_resource_uid("res://home.tscn")), "")

	if _failures == 0:
		print("home: all checks passed")
	else:
		printerr("home: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok   %s" % label)
		return
	_failures += 1
	printerr("  FAIL %s  %s" % [label, detail])