extends SceneTree

## The VS Computer lobby: the second screen of the game, and the one that decides
## what a computer game is.
##
## Separate from the home screen's tests because it is a different question. Home asks
## what kind of game; this asks how this one goes. A parse error here is a game that
## cannot be started at all.

var _failures := 0


func _init() -> void:
	# Cleared before the screen is built, since it reads its defaults while it builds.
	MatchConfig.clear()
	var scene := (load("res://lobby.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	_check("the scene boots", scene is LobbyScreen, "")
	if not scene is LobbyScreen:
		quit(1)
		return
	var lobby := scene as LobbyScreen

	_composition(lobby)
	_option_labels(lobby)
	_selection(lobby)
	_marks_render(lobby)
	_action(lobby)

	if _failures == 0:
		print("lobby: all checks passed")
	else:
		printerr("lobby: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


## The shape of the screen: two groups side by side, each stacked, one action below a
## rule. This is the whole design and the reason the screen reads as the document's
## rather than as a settings page.
func _composition(lobby: LobbyScreen) -> void:
	print("Composition")
	_check("it says what kind of game this is",
		(lobby.title_label as Label).text == "VS COMPUTER",
		"title=%s" % (lobby.title_label as Label).text)

	# Side by side, not stacked. The screen is landscape and the two questions are
	# alternatives asked at once, which a column of six options would have turned into
	# a form.
	_check("the two questions sit side by side",
		lobby.difficulty_group.get_parent() is HBoxContainer
			and lobby.side_group.get_parent() == lobby.difficulty_group.get_parent(),
		"")
	# Each group's own options stacked, which is the other half of the same idea.
	_check("and each group's options are stacked under its caption",
		_options_node(lobby.difficulty_group) is VBoxContainer
			and _options_node(lobby.side_group) is VBoxContainer, "")
	# Equal width, or the two questions would not balance about the centre.
	_check("both groups are the same width, so they balance",
		is_equal_approx(lobby.difficulty_group.custom_minimum_size.x,
			lobby.side_group.custom_minimum_size.x)
			and lobby.difficulty_group.custom_minimum_size.x > 0.0,
		"left=%.0f right=%.0f" % [lobby.difficulty_group.custom_minimum_size.x,
			lobby.side_group.custom_minimum_size.x])
	# The gap is what holds the two questions apart, and it was wide enough to read as
	# two screens rather than one pair.
	_check("the groups are close enough to read as one pair",
		ScreenStyle.GROUP_GAP <= 96.0, "gap=%.0f" % ScreenStyle.GROUP_GAP)
	# Equal boxes are not balanced contents. Left-aligned words inside a wide box put
	# the left group's text far from the centre and the right group's nearly on top of
	# it, which measured as an inch of imbalance between two perfectly even boxes.
	# Measured on the block of options rather than on a word: the words are different
	# widths and the side ones start after a disc, so no single word sits at the centre.
	for group in [lobby.difficulty_group, lobby.side_group]:
		var block := group.get_node("%sOptions" % group.name) as Control
		var holder := group as Control
		var centre: float = holder.global_position.x + holder.size.x * 0.5
		var mid: float = block.global_position.x + block.size.x * 0.5
		_check("%s options are centred in its own box" % group.name,
			absf(mid - centre) < 4.0, "block_mid=%.1f box_mid=%.1f" % [mid, centre])
		# And every row in it starts in the same place, which is what makes the labels
		# line up. Measured, they stepped in and out by ten pixels.
		var starts: Array = []
		for word in _words(group):
			starts.append((word as Label).global_position.x)
		_check("%s rows all start together" % group.name,
			starts.size() > 1 and starts.all(
				func(x: float) -> bool: return absf(x - starts[0]) < 1.0),
			"%s" % str(starts))
	var caption_node := (lobby.difficulty_group as Control).get_node(
		"LobbyDifficultyCaption") as Label
	_check("and the caption is centred too",
		caption_node.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "")

	# The document asks for less vertical space than the home screen, so the two are
	# measured against each other rather than one being assumed.
	var home := (load("res://home.tscn") as PackedScene).instantiate()
	root.add_child(home)
	await process_frame
	await process_frame
	var home_column := home.find_child("HomeColumn", true, false) as Control
	_check("and it takes less vertical room than the home screen",
		(lobby.column as Control).size.y <= home_column.size.y,
		"lobby=%.0f home=%.0f" % [(lobby.column as Control).size.y,
			home_column.size.y])
	home.queue_free()
	await process_frame

	_check("the pair is as wide as both groups and the gap, and no wider",
		is_equal_approx((lobby.difficulty_group as Control).get_parent()
			.custom_minimum_size.x,
			ScreenStyle.GROUP_WIDTH * 2.0 + ScreenStyle.GROUP_GAP),
		"width=%.0f" % (lobby.difficulty_group as Control).get_parent()
			.custom_minimum_size.x)

	# It must look like the home screen, which means the same photograph under the same
	# wash. A screen reached in one tap that changed its background would read as a
	# different application.
	_check("the same photograph is behind it",
		(lobby.get_node_or_null("LobbyBackground") as TextureRect) != null
			and (lobby.get_node_or_null("LobbyBackground") as TextureRect).texture
				== ScreenStyle.background_texture(), "")
	var shade := lobby.get_node_or_null("LobbyShade") as ColorRect
	_check("under the same wash",
		shade != null and is_equal_approx(shade.color.a,
			ScreenStyle.BACKGROUND_SHADE),
		"alpha=%s" % (str(shade.color.a) if shade != null else "<none>"))
	# No card. A panel big enough to hold both groups would hide the picture, which is
	# the thing that makes this read as Chess Relay and not as a settings dialog.
	_check("and nothing is put in a panel over the photograph",
		lobby.column.get_parent().get_parent() == lobby
			and lobby.column.get_parent() is CenterContainer, "")


## The options each question offers.
func _option_labels(lobby: LobbyScreen) -> void:
	print("Options")
	var difficulties: Array = []
	for child in _options(lobby.difficulty_group):
		difficulties.append(_label_of(child))
	_check("difficulty offers Easy, Medium and Hard",
		difficulties == ["Easy", "Medium", "Hard"], "%s" % str(difficulties))
	var sides: Array = []
	for child in _options(lobby.side_group):
		sides.append(_label_of(child))
	_check("play as offers White, Black and Random",
		sides == ["White", "Black", "Random"], "%s" % str(sides))
	for group in [lobby.difficulty_group, lobby.side_group]:
		var caption := group.get_node_or_null("%sCaption" % group.name) as Label
		_check("a group says what it is asking",
			caption != null and caption.text.length() > 0, "")
	# Every label means the value beside it. Reordering the sides once left the values
	# behind and choosing Black marked Random; the pairs make that impossible now.
	_check("and every label means the value beside it",
		MatchConfig.value_for(MatchConfig.SIDES, "Black") == BoardState.DARK
			and MatchConfig.value_for(MatchConfig.SIDES, "Random")
				== MatchConfig.Difficulty.RANDOM_SIDE
			and MatchConfig.value_for(MatchConfig.DIFFICULTIES, "Medium")
				== MatchConfig.Difficulty.MEDIUM, "")

	# The word and the side disc must sit side by side, not on top of each other. The
	# first version added the disc as a child of the Button, which positions it at the
	# button's own origin: exactly where the text is drawn. Measuring caught it with
	# both at the same x, and nothing about the code looked wrong.
	for child in _options(lobby.side_group):
		var disc := child.get_node_or_null("Row/Mark") as TextureRect
		if disc == null:
			continue
		var word := child.get_node_or_null("Row/Word") as Label
		_check("%s has its disc beside the word, not on it" % child.name,
			word != null and disc.global_position.x
				+ disc.size.x <= word.global_position.x + 1.0,
			"disc=%.0f word=%.0f" % [disc.global_position.x,
				word.global_position.x if word != null else -1.0])
	# Random carries a spacer of the same width so all three words start together.
	var rand_option := _options(lobby.side_group)[2] as Button
	var white_option := _options(lobby.side_group)[0] as Button
	_check("random's word starts level with the others",
		is_equal_approx(
			(rand_option.get_node("Row/Word") as Label).global_position.x,
			(white_option.get_node("Row/Word") as Label).global_position.x),
		"random=%.0f white=%.0f"
			% [(rand_option.get_node("Row/Word") as Label).global_position.x,
				(white_option.get_node("Row/Word") as Label).global_position.x])

	# The title must read as a title: the document asks for a visual weight close to
	# the home screen's, and the options must be clearly smaller. They were the same
	# once, which was the first thing wrong with this screen and the easiest to miss.
	var title_size := (lobby.title_label as Label).get_theme_font_size("font_size")
	var first_button := _options(lobby.difficulty_group)[0] as Button
	var first_word := first_button.get_node("Row/Word") as Label
	var word_size: int = first_word.get_theme_font_size("font_size")
	_check("the title is well clear of the option size",
		title_size >= word_size * 2, "title=%d option=%d" % [title_size, word_size])
	# The word is a Label inside a Button, so it reads the theme's size and not the
	# override on the Button: measured at 16 px with 18 requested.
	_check("and the option word is the size asked for, not the theme's",
		word_size == ScreenStyle.OPTION_SIZE, "size=%d wanted=%d"
			% [word_size, ScreenStyle.OPTION_SIZE])
	# PLAY must be its own width and centred, not filled to the column and so the
	# same width as the title above it.
	_check("the action is its own width, not the column's",
		(lobby.start_button as Button).size.x
			< (lobby.column as Control).size.x - 1.0,
		"play=%.0f column=%.0f" % [(lobby.start_button as Button).size.x,
			(lobby.column as Control).size.x])
	_check("and centred under the title",
		absf((lobby.start_button as Control).global_position.x
			+ (lobby.start_button as Control).size.x * 0.5
			- ((lobby.title_label as Control).global_position.x
				+ (lobby.title_label as Control).size.x * 0.5)) < 1.0, "")

	# Bare: no face and no border. These are a list, not a row of buttons.
	var bare := _options(lobby.difficulty_group)[0] as Button
	_check("the options have no face and no border",
		bare.get_theme_stylebox("normal") is StyleBoxEmpty
			and bare.get_theme_stylebox("pressed") is StyleBoxEmpty,
		"normal=%s" % bare.get_theme_stylebox("normal").get_class())
	# But still a comfortable target, since the space is what makes it easy to hit.
	_check("though each is still a full thumb's height",
		bare.custom_minimum_size.y >= 40.0, "height=%.0f" % bare.custom_minimum_size.y)


## What is chosen, and that choosing works.
func _selection(lobby: LobbyScreen) -> void:
	print("Selection")
	_check("something is chosen before anything is pressed",
		_label_of_marked(lobby.difficulty_group) != ""
			and _label_of_marked(lobby.side_group) != "",
		"difficulty=%s side=%s" % [_label_of_marked(lobby.difficulty_group),
			_label_of_marked(lobby.side_group)])
	_check("and the default is Medium, not the easiest",
		_label_of_marked(lobby.difficulty_group) == "Medium",
		"marked=%s" % _label_of_marked(lobby.difficulty_group))

	lobby._on_option_pressed(lobby.difficulty_group,
		_options(lobby.difficulty_group)[2])
	_check("choosing Hard records it",
		MatchConfig.difficulty == MatchConfig.Difficulty.HARD,
		"difficulty=%d" % MatchConfig.difficulty)
	_check("and is the marked one",
		_label_of_marked(lobby.difficulty_group) == "Hard",
		"marked=%s" % _label_of_marked(lobby.difficulty_group))
	_check("leaving exactly one marked", _count_marked(lobby.difficulty_group) == 1,
		"marked=%d" % _count_marked(lobby.difficulty_group))

	lobby._on_option_pressed(lobby.side_group, _options(lobby.side_group)[1])
	_check("choosing Black records it", MatchConfig.side == BoardState.DARK,
		"side=%d" % MatchConfig.side)
	# Black was just chosen, so it is the marked one and carries the bullet.
	_check("and is shown", _label_of_marked(lobby.side_group) == "Black",
		"marked=%s" % _label_of_marked(lobby.side_group))

	lobby._on_option_pressed(lobby.side_group, _options(lobby.side_group)[2])
	_check("random is stored as itself",
		MatchConfig.side == MatchConfig.Difficulty.RANDOM_SIDE, "")
	_check("and resolves to a real side",
		MatchConfig.resolve_side(_seeded(3)) in [BoardState.LIGHT, BoardState.DARK], "")


## The marks must be things the font can actually draw.
##
## Checked by asking the font, not by trusting that the glyph exists: the font is Open
## Sans SemiBold, and it has no white king, no black king and no filled circle. All
## three render as missing glyphs, and a screen whose labels are boxes is worse than one
## with simpler labels.
func _marks_render(lobby: LobbyScreen) -> void:
	print("Marks")
	# All three side options carry a mark, Random included. It had a spacer and was the
	# one option that did not look like the others, which read as though Random were
	# not a real choice.
	var marks := 0
	for child in _options(lobby.side_group):
		if child.get_node_or_null("Row/Mark") != null:
			marks += 1
	_check("all three side options are marked alike", marks == 3, "marks=%d" % marks)
	var random_mark := _options(lobby.side_group)[2].get_node_or_null(
		"Row/Mark") as TextureRect
	_check("and Random's is a diamond, not a piece",
		random_mark != null and random_mark.texture != null
			and random_mark.texture != (_options(lobby.side_group)[0] as Button)
				.get_node("Row/Mark").texture, "")
	# White and Black are the same glyph in two values, so the pair reads as a pair.
	var white_mark := (_options(lobby.side_group)[0] as Button).get_node(
		"Row/Mark") as TextureRect
	var black_mark := (_options(lobby.side_group)[1] as Button).get_node(
		"Row/Mark") as TextureRect
	_check("and the two sides are two different glyphs",
		white_mark.texture != black_mark.texture,
		"White and Black are drawn from the same texture, so they look alike")

	# Black has to exist on a dark photograph, which means a light border around a
	# dark body. Outlined instead, it was a slightly darker patch and read as nothing.
	_check("Black is a filled dark piece, not a hollow outline",
		_dark_with_light_rim(black_mark), "")
	# The rim has to be a real ring of pixels around the body, not a colour that
	# happened to be in the file. Measured from the mask, because that is how it is
	# built now and it must keep being true if the importer changes.
	_check("and the rim is a real ring drawn around the body",
		_rim_pixels(black_mark) > 20, "rim=%.0f" % _rim_pixels(black_mark))
	_check("and White is filled light", _filled_light(white_mark), "")

	# And the mark says which side, never whether it is chosen: choosing is the
	# bullet's job. Swapping the mark on selection would make one job do two.
	var before := black_mark.texture
	lobby._on_option_pressed(lobby.side_group, _options(lobby.side_group)[0])
	_check("choosing a side swaps the bullet, not the mark",
		(black_mark.texture == before)
			and _label_of_marked(lobby.side_group) == "White",
		"marked=%s" % _label_of_marked(lobby.side_group))

	# The font has no king and no filled circle, so nothing may be drawn with them.
	var font := ThemeDB.get_default_theme().default_font
	for cp: String in ["2654", "265A", "25CF", "25CB"]:
		_check("the font has no U+%s, so nothing uses it" % cp,
			not font.has_char(cp.hex_to_int()), "")
	for label: String in ["♔", "♚", "●", "○"]:
		_check("nothing is drawn with %s" % label, not _mentions(lobby, label), "")
	_check("and the bullet it does use is available",
		font.has_char(ScreenStyle.MARK_ON.strip_edges().unicode_at(0)), "")


	print("Action")
	_check("the action is called PLAY", (lobby.start_button as Button).text == "PLAY",
		"play=%s" % (lobby.start_button as Button).text)
	# On the central axis, below a rule that marks a change of kind.
	var rule := lobby.column.get_node_or_null("LobbyDivider") as ColorRect
	_check("a rule separates the decisions from the action", rule != null, "")
	if rule != null:
		_check("shorter than the content, so it is a rule and not a border",
			rule.custom_minimum_size.x < ScreenStyle.CONTENT_WIDTH,
			"rule=%.0f" % rule.custom_minimum_size.x)
		var below := rule.get_index() < lobby.start_button.get_index()
		_check("and the action is below it", below, "")
	_check("and the action is narrower than the home buttons",
		(lobby.start_button as Button).custom_minimum_size.x < 300.0,
		"width=%.0f" % (lobby.start_button as Button).custom_minimum_size.x)

	# Starting hands over the side, already resolved.
	lobby.choose_side(BoardState.DARK)
	var started := {"count": 0, "side": -1}
	lobby.start_requested.connect(func(side: int) -> void:
		started["count"] += 1
		started["side"] = side)
	lobby.start()
	_check("play asks for a game once", int(started["count"]) == 1,
		"count=%d" % int(started["count"]))
	_check("and says which side the player has", int(started["side"]) == BoardState.DARK,
		"side=%d" % int(started["side"]))

	# Back is about leaving the screen, so it is in a corner and not in the column.
	var back := lobby.back_button as Button
	_check("there is a way back", back != null and back.text == "Back", "")
	_check("out of the form, in the top-left corner",
		back.get_parent() == lobby and not lobby.column.has_node("LobbyBack")
			and back.position.x <= ScreenStyle.EDGE + 1.0
			and back.position.y <= ScreenStyle.EDGE + 1.0,
		"pos=%s" % str(back.position))
	_check("wide enough to hit without aiming",
		back.custom_minimum_size.x >= 90.0 and back.custom_minimum_size.y >= 44.0,
		"size=%s" % str(back.custom_minimum_size))


## The option buttons inside a group.
func _options_node(group: VBoxContainer) -> VBoxContainer:
	if group == null:
		return null
	return group.get_node_or_null("%sOptions" % group.name) as VBoxContainer


func _options(group: VBoxContainer) -> Array:
	var options := _options_node(group)
	return [] if options == null else options.get_children()


## An option's word, without its mark.
##
## Read from the child Label rather than the button: the word is its own node so that
## it and the side disc can sit side by side, and reading the button's own text finds
## an empty string where the label used to be.
func _label_of(button: Button) -> String:
	var word := button.get_node_or_null("Row/Word") as Label
	var text := word.text if word != null else button.text
	if text.begins_with(ScreenStyle.MARK_ON):
		return text.substr(ScreenStyle.MARK_ON.length())
	if text.begins_with(ScreenStyle.MARK_OFF):
		return text.substr(ScreenStyle.MARK_OFF.length())
	return text


## The action, and the way out.
func _action(lobby: LobbyScreen) -> void:
	print("Action")
	_check("the action is called PLAY", (lobby.start_button as Button).text == "PLAY",
		"play=%s" % (lobby.start_button as Button).text)
	var rule := lobby.column.get_node_or_null("LobbyDivider") as ColorRect
	_check("a rule separates the decisions from the action", rule != null, "")
	if rule != null:
		_check("shorter than the content, so it is a rule and not a border",
			rule.custom_minimum_size.x < ScreenStyle.CONTENT_WIDTH,
			"rule=%.0f" % rule.custom_minimum_size.x)
		_check("and the action is below it",
			rule.get_index() < lobby.start_button.get_index(), "")
	_check("and the action is narrower than the home buttons",
		(lobby.start_button as Button).custom_minimum_size.x < 300.0,
		"width=%.0f" % (lobby.start_button as Button).custom_minimum_size.x)

	lobby.choose_side(BoardState.DARK)
	var started := {"count": 0, "side": -1}
	lobby.start_requested.connect(func(side: int) -> void:
		started["count"] += 1
		started["side"] = side)
	lobby.start()
	_check("play asks for a game once", int(started["count"]) == 1,
		"count=%d" % int(started["count"]))
	_check("and says which side the player has", int(started["side"]) == BoardState.DARK,
		"side=%d" % int(started["side"]))

	# Back is about leaving the screen, so it is in a corner and not in the column.
	var back := lobby.back_button as Button
	_check("there is a way back", back != null and back.text == "Back", "")
	_check("out of the form, in the top-left corner",
		back.get_parent() == lobby and not lobby.column.has_node("LobbyBack")
			and back.position.x <= ScreenStyle.EDGE + 1.0
			and back.position.y <= ScreenStyle.EDGE + 1.0,
		"pos=%s" % str(back.position))
	_check("wide enough to hit without aiming",
		back.custom_minimum_size.x >= 90.0 and back.custom_minimum_size.y >= 44.0,
		"size=%s" % str(back.custom_minimum_size))
	# And it is wired: it used to emit a signal nothing listened to, so the button was
	# decoration, and a way out that does not get you out is worse than no button.
	_check("and pressing it goes back to the home screen",
		back.pressed.get_connections().size() > 0,
		"connections=%d" % back.pressed.get_connections().size())
	_check("and the home screen is where it goes",
		ResourceLoader.exists("res://home.tscn"), "")


## Every word in a group, so its horizontal centre can be compared with its box's.
func _words(group: VBoxContainer) -> Array:
	var out: Array = []
	var options := _options_node(group)
	if options == null:
		return out
	for option in options.get_children():
		var word := option.get_node_or_null("Row/Word") as Label
		if word != null:
			out.append(word)
	return out


## Whether a mark is mostly dark, so it needs a light border to survive a dark
## background. Sampled from the pixels rather than trusted from the file name, since
## the whole point is what it looks like rather than what it is called.
func _dark_with_light_rim(mark: TextureRect) -> bool:
	var image := mark.texture.get_image()
	if image == null:
		return false
	var mid := Vector2i(image.get_width() / 2, image.get_height() / 2)
	var darkest := 1.0
	var lightest := 0.0
	var seen := 0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a < 0.5:
				continue
			seen += 1
			var l := (c.r + c.g + c.b) / 3.0
			darkest = minf(darkest, l)
			lightest = maxf(lightest, l)
	# A solid dark shape with a light edge: there is ink at both ends of the range.
	return seen > 0 and darkest < 0.25 and lightest > 0.7


## How many pixels are the rim: ink that sits outside the silhouette but inside the
## shape grown by a pixel or two. Zero means there is no border at all, whatever the
## file claims.
func _rim_pixels(mark: TextureRect) -> float:
	var image := mark.texture.get_image()
	if image == null:
		return 0.0
	var w := image.get_width()
	var h := image.get_height()
	var solid := PackedByteArray()
	solid.resize(w * h)
	for y in h:
		for x in w:
			solid[y * w + x] = 1 if image.get_pixel(x, y).a > 0.5 else 0
	var rim := 0
	for y in h:
		for x in w:
			if solid[y * w + x] == 1:
				continue
			var near := false
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or nx >= w or ny < 0 or ny >= h:
						continue
					if solid[ny * w + nx] == 1:
						near = true
						break
				if near:
					break
			if near:
				rim += 1
	return float(rim)


## Whether a mark is mostly light.
func _filled_light(mark: TextureRect) -> bool:
	var image := mark.texture.get_image()
	if image == null:
		return false
	var lit := 0
	var total := 0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a < 0.5:
				continue
			total += 1
			if (c.r + c.g + c.b) / 3.0 > 0.7:
				lit += 1
	return total > 0 and float(lit) / float(total) > 0.5


## The word of whichever option is marked, without its mark.
func _label_of_marked(group: VBoxContainer) -> String:
	for child in _options(group):
		if child is Button and (child as Button).button_pressed:
			return _label_of(child as Button)
	return ""


func _marked(group: VBoxContainer) -> String:
	for child in _options(group):
		if child is Button and (child as Button).button_pressed:
			return (child as Button).text
	return ""


func _count_marked(group: VBoxContainer) -> int:
	var count := 0
	for child in _options(group):
		if child is Button and (child as Button).button_pressed:
			count += 1
	return count


## Whether an option's drawn disc is the filled one.
func _is_filled(button: Button) -> bool:
	var disc := button.get_node_or_null("Row/Mark") as TextureRect
	if disc == null or disc.texture == null:
		return false
	var image := disc.texture.get_image()
	return image.get_pixel(image.get_width() / 2,
		image.get_height() / 2).a > 0.5


## Whether any text on the screen contains a character that will not render.
func _mentions(lobby: LobbyScreen, needle: String) -> bool:
	for text: String in [
		(lobby.title_label as Label).text,
		(lobby.start_button as Button).text,
		(lobby.back_button as Button).text,
	]:
		if text.find(needle) >= 0:
			return true
	for group in [lobby.difficulty_group, lobby.side_group]:
		var caption := group.get_node_or_null("%sCaption" % group.name) as Label
		if caption != null and caption.text.find(needle) >= 0:
			return true
		for child in _options(group):
			if (child as Button).text.find(needle) >= 0:
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