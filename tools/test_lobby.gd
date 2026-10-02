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
	MatchConfig.clear()

	_check("it says what kind of game this is",
		(lobby.title_label as Label).text == "VS COMPUTER",
		"title=%s" % (lobby.title_label as Label).text)

	# Both questions must be asked, with every option visible at once. A dropdown hides
	# what is currently chosen behind a tap, which is the thing a player most needs.
	var difficulty: Array = []
	for child in lobby.difficulty_group.get_children():
		if child is Button:
			difficulty.append((child as Button).text)
	_check("difficulty offers Easy, Medium and Hard",
		difficulty == ["Easy", "Medium", "Hard"], "%s" % str(difficulty))
	var sides: Array = []
	for child in lobby.side_group.get_children():
		if child is Button:
			sides.append((child as Button).text)
	_check("your colour offers Random, White and Black",
		sides == ["Random", "White", "Black"], "%s" % str(sides))

	# Each row is labelled, so the buttons are not just three unlabelled boxes.
	var captions: Array = []
	for row in [lobby.difficulty_group, lobby.side_group]:
		var caption := (row as HBoxContainer).get_node_or_null("%sLabel" % row.name) as Label
		captions.append(caption.text if caption != null else "<none>")
	_check("and both rows say what they are asking",
		captions == ["Difficulty", "Your color"], "%s" % str(captions))

	# The chosen option must be visible, or START uses something the player cannot see.
	_check("something is chosen before anything is pressed",
		_pressed_count(lobby.difficulty_group) == 1
			and _pressed_count(lobby.side_group) == 1,
		"difficulty=%d side=%d" % [_pressed_count(lobby.difficulty_group),
			_pressed_count(lobby.side_group)])

	# Choosing records it and moves the mark.
	lobby.choose_difficulty(MatchConfig.Difficulty.HARD)
	_check("difficulty is recorded", MatchConfig.difficulty == MatchConfig.Difficulty.HARD,
		"difficulty=%d" % MatchConfig.difficulty)
	_check("and the new one is the marked one",
		_marked(lobby.difficulty_group) == "Hard",
		"marked=%s" % _marked(lobby.difficulty_group))
	lobby.choose_side(BoardState.DARK)
	_check("side is recorded", MatchConfig.side == BoardState.DARK,
		"side=%d" % MatchConfig.side)
	_check("and shown", _marked(lobby.side_group) == "Black",
		"marked=%s" % _marked(lobby.side_group))

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

	# Both scenes must exist, or the flow is a dead end.
	_check("the lobby is reachable as a scene", ResourceLoader.exists("res://lobby.tscn"),
		"")
	_check("and the game is a scene of its own", ResourceLoader.exists("res://main.tscn"),
		"")

	MatchConfig.clear()
	if _failures == 0:
		print("lobby: all checks passed")
	else:
		printerr("lobby: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


## How many options in a row are currently marked.
func _pressed_count(row: HBoxContainer) -> int:
	var count := 0
	for child in row.get_children():
		if child is Button and (child as Button).button_pressed:
			count += 1
	return count


## The label of whichever option is marked.
func _marked(row: HBoxContainer) -> String:
	for child in row.get_children():
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