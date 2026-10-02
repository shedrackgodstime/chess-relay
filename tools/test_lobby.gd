extends SceneTree

## The lobby: where a match is set up.
##
## Separate from the home screen's tests because it is a different question. Home asks
## what kind of game; the lobby asks how this one goes. A parse error here is a game
## that cannot be started at all.

var _failures := 0


func _init() -> void:
	var scene := (load("res://lobby.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	_check("the scene boots", scene is LobbyScreen, "")
	if not scene is LobbyScreen:
		quit(1)
		return
	var lobby := scene as LobbyScreen
	# Cleared before the scene is built, not after: the screen reads its defaults
	# while it builds, so clearing it afterwards changed the store without changing
	# what was on screen, and the two disagreed.
	MatchConfig.clear()
	var scene2 := (load("res://lobby.tscn") as PackedScene).instantiate()
	root.add_child(scene2)
	await process_frame
	await process_frame
	scene.queue_free()
	await process_frame
	scene = scene2
	lobby = scene2 as LobbyScreen

	_check("it says what kind of game this is",
		(lobby.title_label as Label).text == "VS COMPUTER",
		"title=%s" % (lobby.title_label as Label).text)

	# Both questions must be asked, with every option visible at once. A dropdown hides
	# what is currently chosen behind a tap, which is the thing a player most needs.
	var difficulty: Array = []
	for child in _options(lobby.difficulty_group):
		if child is Button:
			difficulty.append((child as Button).text)
	# Difficulty carries its choice in the label, as a radio mark.
	_check("difficulty offers Easy, Medium and Hard, with Medium circled",
		difficulty == ["○ Easy", "● Medium", "○ Hard"], "%s" % str(difficulty))
	var sides: Array = []
	for child in _options(lobby.side_group):
		if child is Button:
			sides.append((child as Button).text)
	_check("play as offers White, Black and Random",
		sides == MatchConfig.labels_of(MatchConfig.SIDES)
			and sides == ["White", "Black", "Random"], "%s" % str(sides))
	# The labels and the values they stand for are one list, so reordering one cannot
	# leave the other behind. Choosing Black used to mark Random.
	_check("and every label means the value beside it",
		MatchConfig.value_for(MatchConfig.SIDES, "Black") == BoardState.DARK
			and MatchConfig.value_for(MatchConfig.SIDES, "Random")
				== MatchConfig.Difficulty.RANDOM_SIDE, "")

	# Each row is labelled, so the buttons are not just three unlabelled boxes.
	var captions: Array = []
	for group in [lobby.difficulty_group, lobby.side_group]:
		var caption := group.get_node_or_null("%sLabel" % group.name) as Label
		captions.append(caption.text if caption != null else "<none>")
	_check("and both groups say what they are asking",
		captions == ["DIFFICULTY", "PLAY AS"], "%s" % str(captions))

	# The chosen option must be visible, or START uses something the player cannot see.
	_check("something is chosen before anything is pressed",
		_pressed_count(lobby.difficulty_group) == 1
			and _pressed_count(lobby.side_group) == 1,
		"difficulty=%d side=%d" % [_pressed_count(lobby.difficulty_group),
			_pressed_count(lobby.side_group)])
	# Down the screen, not across it: title, then the two questions, then PLAY. Read
	# the way a form is read.
	# Title, rule, difficulty, play as, rule, PLAY. Checked by name rather than by
	# index, since a divider between two parts is exactly the sort of thing an index
	# assertion breaks on the next time someone adds one.
	var order: Array = []
	for child in lobby.column.get_children():
		order.append(child.name)
	_check("the column reads title, questions, then action",
		order[0] == "LobbyTitle" and order[2] == "LobbyDifficulty"
			and order[3] == "LobbySide" and order[5] == "LobbyStart",
		"%s" % str(order))
	# Stacked, not in a row across: a full-width target per option is a thumb tap on a
	# phone held sideways, where three options side by side are three small targets.
	_check("each question stacks its options under its caption",
		(lobby.difficulty_group as VBoxContainer).get_node_or_null("LobbyDifficultyRow")
			is VBoxContainer
			and (lobby.difficulty_group.get_child(0) as Label).text == "DIFFICULTY", "")
	_check("and the options are full width rather than small side by side",
		(_options(lobby.difficulty_group)[0] as Button).custom_minimum_size.x >= 280.0,
		"width=%.0f" % (_options(lobby.difficulty_group)[0] as Button)
			.custom_minimum_size.x)
	_check("with a rule between the parts",
		lobby.column.has_node("TitleDivider") and lobby.column.has_node("LobbyDivider"),
		"")
	_check("and the action right-aligned, so the eye crosses to it after the list",
		(lobby.start_button as Button).size_flags_horizontal
			== Control.SIZE_SHRINK_END, "")
	_check("with nothing in the column after it but the action itself",
		lobby.column.get_child(lobby.column.get_child_count() - 1) == lobby.start_button,
		"last=%s" % lobby.column.get_child(
			lobby.column.get_child_count() - 1).name)

	# Choosing records it and moves the mark.
	lobby.choose_difficulty(MatchConfig.Difficulty.HARD)
	_check("difficulty is recorded", MatchConfig.difficulty == MatchConfig.Difficulty.HARD,
		"difficulty=%d" % MatchConfig.difficulty)
	_check("and the new one is the marked one",
		lobby.marked_difficulty() == "● Hard",
		"marked=%s" % lobby.marked_difficulty())
	# The radio mark is in the label, so the chosen option says so in the same breath
	# as its name and the three options keep the same size either way.
	var labels: Array = []
	for child in _options(lobby.difficulty_group):
		labels.append((child as Button).text)
	_check("the chosen difficulty is circled in its own label",
		labels.count("● Hard") == 1 and labels.count("○ Easy") == 1
			and labels.count("○ Medium") == 1, "%s" % str(labels))
	lobby.choose_side(BoardState.DARK)
	_check("side is recorded", MatchConfig.side == BoardState.DARK,
		"side=%d" % MatchConfig.side)
	_check("and shown", _marked(lobby.side_group) == "Black",
		"marked=%s" % _marked(lobby.side_group))
	lobby.choose_difficulty(MatchConfig.Difficulty.EASY)
	_check("moving the mark leaves exactly one filled",
		lobby.marked_difficulty() == "● Easy",
		"marked=%s" % lobby.marked_difficulty())

	# Random is a real choice, not a stand-in for undecided.
	lobby.choose_side(MatchConfig.Difficulty.RANDOM_SIDE)
	_check("random is stored as itself",
		MatchConfig.side == MatchConfig.Difficulty.RANDOM_SIDE, "")
	_check("and resolves to a real side", MatchConfig.resolve_side(
			_seeded(0)) in [BoardState.LIGHT, BoardState.DARK], "")

	# Starting hands over the side, already resolved.
	lobby.choose_side(BoardState.DARK)
	var started := {"count": 0, "side": -1}
	lobby.start_requested.connect(func(side: int) -> void:
		started["count"] += 1
		started["side"] = side)
	lobby.start()
	_check("start asks for a game exactly once", int(started["count"]) == 1,
		"count=%d" % int(started["count"]))
	_check("and says which side the player has", int(started["side"]) == BoardState.DARK,
		"side=%d" % int(started["side"]))

	# The lobby must be built like every other screen: centred, on something, with the
	# shared styling. This is here because the first version wrapped nothing at all and
	# hung a column off the root, so it rendered flush to the corner of a blank screen
	# one tap after a centred menu. Two screens a player moves between in a single tap
	# must not be visibly built by different people.
	var backdrop := lobby.get_node_or_null("LobbyBackdrop") as ColorRect
	var centre := lobby.get_node_or_null("Centre") as CenterContainer
	_check("the lobby sits on something rather than on nothing", backdrop != null, "")
	_check("and that something takes no taps meant for a button",
		backdrop != null and backdrop.mouse_filter == Control.MOUSE_FILTER_STOP, "")
	_check("the column is centred rather than hung off the corner",
		centre != null and lobby.column.get_parent() == centre, "")
	if backdrop != null:
		# Dark, but not the picture: the artwork belongs to the front door, and
		# putting it behind every screen would make them all look like the same screen.
		_check("and is the shared dark rather than the home artwork",
			is_equal_approx(backdrop.color.a, 1.0), "alpha=%.2f" % backdrop.color.a)
	if centre != null and centre.size.x > 0:
		var content := centre.get_combined_minimum_size().x
		_check("which means the words sit in the middle of the screen",
			absf(centre.get_child(0).position.x - (centre.size.x - content) * 0.5) < 2.0,
			"column_x=%.1f expected=%.1f centre=%.1f" % [centre.get_child(0).position.x,
				(centre.size.x - content) * 0.5, centre.size.x])

	# Both scenes must exist, or the flow is a dead end.
	_check("the lobby is reachable as a scene", ResourceLoader.exists("res://lobby.tscn"),
		"")
	_check("and its action is called PLAY", (lobby.start_button as Button).text == "PLAY",
		"play=%s" % (lobby.start_button as Button).text)
	# Back is about leaving the screen, not about this game, so it is anchored to the
	# top-left corner and is not part of the column. In the column it read as one more
	# choice and had to be found before anyone could use it.
	var back := lobby.back_button as Button
	_check("there is a way back, because a screen with no way out is a trap",
		back != null and back.text == "Back", "")
	_check("and it is not part of the form", back.get_parent() == lobby
			and not lobby.column.has_node("LobbyBack"), "")
	_check("it is in the top left corner", back.position.x <= ScreenStyle.EDGE + 1.0
			and back.position.y <= ScreenStyle.EDGE + 1.0,
		"pos=%s" % str(back.position))
	_check("with somewhere to put a thumb on it",
		back.custom_minimum_size.x >= 90.0 and back.custom_minimum_size.y >= 44.0,
		"size=%s" % str(back.custom_minimum_size))
	_check("and it stays in the corner at any width",
		back.anchor_left == 0.0 and back.anchor_top == 0.0, "")
	# MEDIUM is the value behind the dot, not its position in the list. The earlier
	# version compared to MatchConfig.Difficulty.MEDIUM after the suite had already
	# chosen something else, so it could never pass.
	var medium: int = MatchConfig.value_for(MatchConfig.DIFFICULTIES, "Medium")
	# Cleared first, since the checks above changed it. Otherwise the fresh lobby
	# inherits the last choice and the default is never really observed.
	MatchConfig.clear()
	var lobby_defaults := (load("res://lobby.tscn") as PackedScene).instantiate()
	root.add_child(lobby_defaults)
	await process_frame
	await process_frame
	_check("and a fresh lobby opens on Medium",
		(lobby_defaults as LobbyScreen).marked_difficulty() == "● Medium"
			and MatchConfig.difficulty == medium,
		"marked=%s" % (lobby_defaults as LobbyScreen).marked_difficulty())
	lobby_defaults.queue_free()
	await process_frame
	# And the two screens must read as one game, which is what the shared style file is
	# for. Checked rather than assumed: styling written per screen drifts per screen.
	var lobby_title := (lobby.title_label as Label).get_theme_color("font_color")
	var option := _options(lobby.difficulty_group)[1] as Button
	_check("and it reads its colours from the shared palette, not its own",
		lobby_title == ScreenStyle.TITLE
			and option.get_theme_stylebox("normal").bg_color == ScreenStyle.PANEL,
		"title=%s panel=%s" % [str(lobby_title),
			str(option.get_theme_stylebox("normal").bg_color)])
	_check("and the game is a scene of its own", ResourceLoader.exists("res://main.tscn"),
		"")

	MatchConfig.clear()
	if _failures == 0:
		print("lobby: all checks passed")
	else:
		printerr("lobby: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


## How many options in a row are currently marked.
## The option buttons inside a labelled group, ignoring the caption above them.
## Matches what LobbyScreen._options looks for, so the test and the screen cannot
## disagree about which node holds the options.
func _options(group: VBoxContainer) -> Array:
	if group == null:
		return []
	var row := group.get_node_or_null("%sRow" % group.name) as VBoxContainer
	return row.get_children() if row != null else []


func _pressed_count(group: VBoxContainer) -> int:
	var count := 0
	for child in _options(group):
		if child is Button and (child as Button).button_pressed:
			count += 1
	return count


## The label of whichever option is marked.
func _marked(group: VBoxContainer) -> String:
	for child in _options(group):
		if child is Button and (child as Button).button_pressed:
			return (child as Button).text
	return ""


func _seeded(value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = value
	return rng


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok   %s" % label)
		return
	_failures += 1
	printerr("  FAIL %s  %s" % [label, detail])