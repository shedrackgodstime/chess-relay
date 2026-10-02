extends SceneTree

## Prints what the lobby actually laid out, so it can be looked at rather than guessed
## at. The headless renderer draws nothing, so this is the substitute for seeing it:
## real rectangles, real computed font sizes, real colours, in the order they stack.
##
## Every design argument this session has had was made from an assumption about what a
## screen would look like, and several were wrong. Numbers do not do that.

func _init() -> void:
	# The headless root window is 64x64 whatever is asked for, so the screen size comes
	# from the project settings and the numbers below are measured against what the
	# game will actually be shown at.
	var screen := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1536)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 864)))
	root.size = Vector2i(int(screen.x), int(screen.y))
	var scene := (load("res://lobby.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	await process_frame

	print("screen %d x %d (root is %d x %d headless)" % [int(screen.x),
		int(screen.y), root.size.x, root.size.y])

	var lobby := scene as LobbyScreen
	_dump(lobby.column, 0)
	_dump(lobby.back_button, 0)

	# What the eye actually lands on first, by size: the biggest text on the screen is
	# what reads as the title, and if an option matches it then neither reads as a
	# title.
	print("\n-- text by size --")
	var sizes: Array = []
	_collect_text(lobby, sizes)
	sizes.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	for entry in sizes:
		print("  %3d px  %s" % [int(entry[1]), str(entry[0])])

	print("\n-- how much of the screen is used --")
	var content := lobby.column as Control
	print("  content %.0f x %.0f at x=%.0f y=%.0f"
		% [content.size.x, content.size.y, content.global_position.x,
			content.global_position.y])
	print("  column is %.0f%% of the screen width"
		% (content.size.x / screen.x * 100.0))
	print("  content is %.0f%% of the screen height"
		% (content.size.y / screen.y * 100.0))
	var left := lobby.difficulty_group as Control
	var right := lobby.side_group as Control
	var screen_mid := screen.x * 0.5
	print("  left group mid %.1f, right group mid %.1f, screen mid %.1f"
		% [left.global_position.x + left.size.x * 0.5,
			right.global_position.x + right.size.x * 0.5, screen_mid])
	print("  groups off centre by %.1f px"
		% absf((left.global_position.x + left.size.x * 0.5
			+ right.global_position.x + right.size.x * 0.5) * 0.5 - screen_mid))
	print("  gap between groups %.0f"
		% (right.global_position.x - (left.global_position.x + left.size.x)))

	# Where the ink actually is, not where the boxes are. Two equal boxes can still be
	# badly balanced if their contents sit at opposite ends of them, which is exactly
	# what a left-aligned caption and left-aligned words inside a wide group do.
	var left_ink := _ink_left(lobby.difficulty_group)
	var right_ink := _ink_right(lobby.side_group)
	print("  left group ink %.0f .. %.0f" % [left_ink.x, left_ink.y])
	print("  right group ink %.0f .. %.0f" % [right_ink.x, right_ink.y])
	print("  distance from screen centre: left %.0f, right %.0f"
		% [screen_mid - left_ink.y, right_ink.x - screen_mid])
	print("  ink off balance by %.0f px"
		% absf((screen_mid - left_ink.y) - (right_ink.x - screen_mid)))
	# The multiplayer screen too, since it is the other one built on the shared frame.
	var p2p := (load("res://p2p_lobby.tscn") as PackedScene).instantiate()
	root.add_child(p2p)
	await process_frame
	await process_frame
	var p2p_column := p2p.find_child("Column", true, false) as Control
	print("\n-- P2P screen --")
	if p2p_column != null:
		print("  content %.0f x %.0f  (%.0f%% of screen height)"
			% [p2p_column.size.x, p2p_column.size.y,
				p2p_column.size.y / screen.y * 100.0])
		for child in p2p_column.get_children():
			print("    %s %.0fx%.0f" % [child.name, child.size.x, child.size.y])

	# The home screen for comparison. The design document asks for the lobby to occupy
	# LESS vertical space than the home screen, which has to be measured rather than
	# assumed. It was assumed the other way until now.
	var home := (load("res://home.tscn") as PackedScene).instantiate()
	root.add_child(home)
	await process_frame
	await process_frame
	# Found by name rather than by path: the home screen builds itself, so its
	# tree shape is its own business and a path here would be a second thing to keep
	# in step.
	var home_column := home.find_child("HomeColumn", true, false) as Control
	var lobby_height := content.size.y
	var home_height := home_column.size.y if home_column != null else 0.0
	print("\n-- vertical space, against the home screen --")
	print("  lobby %.0f px (%.0f%%), home %.0f px (%.0f%%)"
		% [lobby_height, lobby_height / screen.y * 100.0,
			home_height, home_height / screen.y * 100.0])
	print("  %s" % ("the lobby is smaller, as the document asks"
		if lobby_height <= home_height
		else "THE LOBBY IS TALLER THAN HOME, which the document rules out"))
	quit(0)


## The span the words actually occupy inside a group, from the first word's left to
## the widest word's right.
func _ink_left(group: VBoxContainer) -> Vector2:
	var words := _words(group)
	var left := INF
	var right := -INF
	for w in words:
		left = minf(left, w.global_position.x)
		right = maxf(right, w.global_position.x + w.size.x)
	return Vector2(left, right)


func _ink_right(group: VBoxContainer) -> Vector2:
	var words := _words(group)
	var left := INF
	var right := -INF
	for w in words:
		left = minf(left, w.global_position.x)
		right = maxf(right, w.global_position.x + w.size.x)
	return Vector2(left, right)


func _words(group: VBoxContainer) -> Array:
	var out: Array = []
	var options := group.get_node_or_null("%sOptions" % group.name)
	if options == null:
		return out
	for option in options.get_children():
		var word := option.get_node_or_null("Row/Word")
		if word != null:
			out.append(word)
	return out


func _dump(node: Node, depth: int) -> void:
	if node == null:
		return
	var pad := "  ".repeat(depth)
	if node is Control:
		var c := node as Control
		var extra := ""
		if c is Label:
			extra = " \"%s\"" % (c as Label).text
		elif c is Button:
			extra = " \"%s\"" % (c as Button).text
		print("%s%s %dx%d at %.0f,%.0f%s%s" % [pad, c.name, c.size.x, c.size.y,
			c.global_position.x, c.global_position.y, extra,
			"" if c.visible else "  [hidden]"])
	for child in node.get_children():
		_dump(child, depth + 1)


func _collect_text(node: Node, out: Array) -> void:
	if node is Label:
		var label := node as Label
		var size := label.get_theme_font_size("font_size")
		out.append([label.text, size])
	elif node is Button:
		var button := node as Button
		out.append([button.text, button.get_theme_font_size("font_size")])
	for child in node.get_children():
		_collect_text(child, out)