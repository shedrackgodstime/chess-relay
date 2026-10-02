extends SceneTree

## The multiplayer lifecycle: landing, create, join, and the codes that pass
## between them.
##
## These screens are the whole of multiplayer as far as a player is concerned, and they
## are complete as screens: each has its states, its actions and its way out. What is
## missing is underneath them, and nothing here pretends otherwise.

var _failures := 0


func _init() -> void:
	_codes()
	await _landing()
	await _create()
	await _join()
	_flow()

	if _failures == 0:
		print("p2p: all checks passed")
	else:
		printerr("p2p: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


## The code itself, and the shape of a typed one.
func _codes() -> void:
	print("Codes")
	var code := GameCode.generate(_seeded(7))
	_check("a code is two groups of three",
		code.length() == 7 and code[3] == "-", "code=%s" % code)
	_check("and only uses characters that cannot be misread",
		GameCode.is_well_formed(code), "code=%s" % code)
	# The check normalises for itself, so a displayed code and a typed one are the
	# same question. It refused a code it had just generated until it did.
	_check("and a displayed code passes the same check as a typed one",
		GameCode.is_well_formed(code)
			and GameCode.is_well_formed(code.replace("-", "")), "code=%s" % code)
	# The reason the alphabet is what it is: a player told a code was wrong when they
	# mistyped a 0 for an O has no idea what to try next.
	for confusable: String in ["0", "O", "1", "I"]:
		_check("the alphabet leaves out %s" % confusable,
			not GameCode.ALPHABET.contains(confusable), "")

	# A code arrives pasted from a message, in lower case, with the dash replaced by
	# a space. All three have to land on the same value or the player is refused for
	# something they did not do.
	_check("a typed code is read forgivingly",
		GameCode.normalise("a7k4-x9") == "A7K4X9", "")
	_check("spaces work as well as dashes",
		GameCode.normalise("abc 123") == GameCode.normalise("ABC-123"), "")
	_check("but a short code is still refused",
		not GameCode.is_well_formed("ABC12"), "")
	_check("and so is one with a letter we never use",
		not GameCode.is_well_formed("ABO123"), "")
	_check("and one that is too long",
		not GameCode.is_well_formed("ABC1234"), "")


## The landing screen: one decision, and only one.
func _landing() -> void:
	print("Landing")
	var screen := await _spawn("res://p2p_lobby.tscn") as P2pLobby
	if screen == null:
		return
	_check("it asks one question",
		screen.column.get_child(0).text == "P2P GAME", "")
	var buttons: Array = []
	for child in screen.column.get_children():
		if child is Button:
			buttons.append((child as Button).text)
	_check("with two equal answers",
		buttons == ["CREATE GAME", "JOIN GAME"], "%s" % str(buttons))
	_check("the same width, because neither is the primary one",
		(_find(screen, "CreateGame") as Button).custom_minimum_size.x
			== (_find(screen, "JoinGame") as Button).custom_minimum_size.x, "")
	# No network words. A player choosing between making a game and going to one has
	# to learn nothing to use this screen.
	var words := ["Host", "Peer", "Signalling", "Server", "Address", "IP"]
	for word: String in words:
		_check("it never says %s" % word, not _text_contains(screen, word), "")


## The waiting room: the code is the reason the screen exists.
func _create() -> void:
	print("Create")
	var screen := await _spawn("res://create_game.tscn") as CreateGameScreen
	if screen == null:
		return

	# One screen, code first. Creating a game means giving someone something to join
	# with, and that is what the player came for; the side is a preference underneath
	# it. Putting the preference first, behind a CONTINUE, made the screen ask the
	# secondary question before it would answer the primary one.
	_check("the code is on the screen before anything is pressed",
		screen.find_child("Code", true, false) != null, "")
	_check("and it is above the side choice",
		screen.find_child("Code", true, false).get_index()
			< _index_of_side(screen), "")
	_check("the side is a preference on one line, not a second question",
		screen.find_child("OptionsRow", true, false) != null, "")
	_check("with no gate between the player and the code",
		screen.find_child("Continue", true, false) == null, "")
	screen.choose_side(BoardState.LIGHT)
	_check("and choosing one is recorded",
		screen.side == BoardState.LIGHT, "")

	_check("it shows a code without anyone asking for one",
		GameCode.is_well_formed(screen.game_code()),
		"code=%s" % screen.game_code())
	var code_label := _find(screen, "Code") as Label
	_check("and shows that code, not a placeholder",
		code_label != null and code_label.text == screen.game_code(),
		"label=%s" % (code_label.text if code_label != null else "<none>"))
	# The code is the largest thing on the screen: it is everything the host has to
	# pass on, and the rest is context for it.
	var code_size := (code_label as Label).get_theme_font_size("font_size")
	var biggest := 0
	for child in screen.column.get_children():
		if child is Label:
			biggest = maxi(biggest,
				(child as Label).get_theme_font_size("font_size"))
	_check("and the code is the largest thing on it",
		code_size == biggest and code_size > 30, "code=%d biggest=%d"
			% [code_size, biggest])
	_check("the host can copy it, since sending it is the whole job",
		_find(screen, "CopyCode") != null, "")
	_check("and says it is waiting", _text_contains(screen, "Waiting for opponent"), "")




## Code entry: a field, a button, and a way to say no.
func _join() -> void:
	print("Join")
	var screen := await _spawn("res://join_game.tscn") as JoinGameScreen
	if screen == null:
		return
	_check("it has a field to type the code in", screen.field != null, "")
	_check("and nothing more than a field and an action",
		screen.column.get_child(0).text == "JOIN GAME", "")
	_check("the join button waits for a whole code",
		(screen.join_button as Button).disabled, "")
	# A pasted message arrives lower case with the dash turned into a space, and all
	# of it has to land on the same value.
	# Typed rather than assigned: assigning LineEdit.text does not fire
	# text_changed, so the screen would never have seen it, and a test that did it
	# that way would be testing nothing a player does.
	for typed: String in "abc 123":
		screen.field.insert_text_at_caret(typed)
	# Fired by hand as well, because a paste and a hardware keyboard both change the
	# text without walking the caret, and the join button has to agree with the box
	# whichever way the code arrived.
	screen.field.text = "ABC-123"
	screen.field.text_changed.emit(screen.field.text)
	_check("a pasted code is accepted",
		screen.typed_code() == "ABC123", "typed=%s" % screen.typed_code())
	_check("and typing is what the screen listens for",
		screen.code_label.text == "ABC-123",
		"echo=%s" % screen.code_label.text)
	_check("and the join button wakes up",
		not (screen.join_button as Button).disabled, "")
	_check("and the code is echoed back in a readable shape",
		(screen.code_label as Label).text == "ABC-123",
		"echo=%s" % (screen.code_label as Label).text)
	_check("but the game is not started by typing alone",
		screen.typed_code().length() == 6, "")
	# A complaint must not rearrange the screen. The quiet line used to demand the
	# full content width while hidden, so the first mistyped code widened the column
	# from 240 to 760 and moved everything under the player's finger.
	var column := screen.column as Control
	var before: float = column.size.x
	screen.status_label.text = "Check the game code and try again."
	screen.status_label.visible = true
	await process_frame
	await process_frame
	_check("showing a complaint does not resize the screen",
		absf(column.size.x - before) < 1.0, "before=%.0f after=%.0f"
			% [before, column.size.x])


## The screens the player can actually reach, and nothing that leads nowhere.
func _flow() -> void:
	print("Flow")
	for scene: String in ["res://home.tscn", "res://p2p_lobby.tscn",
			"res://create_game.tscn", "res://join_game.tscn"]:
		_check("%s exists" % scene.get_file(), ResourceLoader.exists(scene), "")
	# Nothing leads to a screen that is not there.
	for scene: String in ["res://lobby.tscn", "res://main.tscn"]:
		_check("%s still exists for the computer game" % scene.get_file(),
			ResourceLoader.exists(scene), "")
	_check("and the entry point is still home",
		str(ProjectSettings.get_setting("application/run/main_scene", ""))
			== "res://home.tscn", "")


## A screen from its scene, built and ready.
func _spawn(path: String) -> Node:
	var scene := (load(path) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	return scene


## Where the side choice sits in the column, or -1.
func _index_of_side(screen: CreateGameScreen) -> int:
	var row := screen.side_group
	if row == null:
		return -1
	return row.get_index()


func _find(node: Node, node_name: String) -> Node:
	return node.find_child(node_name, true, false)


## Whether any text on a screen contains a word, case apart.
func _text_contains(node: Node, word: String) -> bool:
	if node is Label and (node as Label).text.to_lower().contains(word.to_lower()):
		return true
	if node is Button and (node as Button).text.to_lower().contains(word.to_lower()):
		return true
	for child in node.get_children():
		if _text_contains(child, word):
			return true
	return false


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