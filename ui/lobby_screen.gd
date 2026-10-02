class_name LobbyScreen
extends Control

## Where a match is set up. Reached from the home screen, and the first thing that
## knows a game is a computer game rather than another player.
##
## It asks three things and hands them over: how hard, which side, and go. Nothing
## else, because a lobby that also tries to be a settings screen, a room browser and a
## chat window is four screens wearing one name.
##
## The two choices are rows of buttons rather than dropdowns. Every option is visible
## at once, so the panel is read rather than opened, and there is no state where a
## player has expanded something to find out what it currently says.
##
## Difficulty is present and not yet acted on. It is honest about that in the row
## itself rather than pretending, which is the same rule the home screen follows for
## P2P and Settings.

## Emitted with the side the player will play, since Random is resolved before the
## board exists rather than by the board noticing later.
signal start_requested(side: int)
signal back_requested

const TITLE := "VS COMPUTER"
## The wide action, half the band's height so PLAY reads as the thing to press.
## Narrow, because a lobby that fills a landscape screen asks the eye to travel for
## three small decisions. One column, centred, read downwards.
const COLUMN_WIDTH := 300.0

## The wide action, narrower than the screen and right-aligned within the column so
## the reading runs down the options and then across to the one thing to do.
const ACTION_WIDTH := 180.0


var column: VBoxContainer = null
var title_label: Label = null
## Built in build() rather than found with %: the nodes do not exist until this screen
## builds itself, and a lookup for a node that is not there yet would silently leave
## the whole thing unconnected.
var difficulty_group: VBoxContainer = null
var side_group: VBoxContainer = null
var start_button: Button = null
var back_button: Button = null


func _ready() -> void:
	build()
	start_button.pressed.connect(func() -> void: start_requested.emit())
	back_button.pressed.connect(func() -> void: back_requested.emit())
	# Default selections, shown rather than assumed. A row with nothing chosen looks
	# broken, and a player who has not chosen should still be able to press Start.
	_choose_difficulty(MatchConfig.difficulty)
	_choose_side(MatchConfig.side)


func build() -> void:
	# The shared dark, centred. No picture: the artwork belongs to the front door, and
	# putting it behind every screen would make them all look like the same screen.
	var backdrop := ColorRect.new()
	backdrop.name = "LobbyBackdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = ScreenStyle.SHADE
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	# One column down the screen. The two questions stack, each with its own options
	# beside them, and PLAY sits below them: something to decide, the ways to decide
	# it, then go. Read downwards rather than across, which is how a form is read on a
	# screen held sideways.
	column = VBoxContainer.new()
	column.name = "LobbyColumn"
	column.unique_name_in_owner = true
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 16)
	centre.add_child(column)

	title_label = Label.new()
	title_label.name = "LobbyTitle"
	title_label.unique_name_in_owner = true
	title_label.text = TITLE
	title_label.custom_minimum_size = Vector2(0.0, 48.0)
	ScreenStyle.title_style(title_label, 32)
	column.add_child(title_label)
	column.add_child(_divider("TitleDivider"))

	# Difficulty, with radio marks in the labels. The marks are text rather than a
	# second widget, so the chosen option says so in the same breath as its name
	# instead of a player having to compare three lit boxes and work out which.
	difficulty_group = _row("LobbyDifficulty", "DIFFICULTY", column)
	for pair in MatchConfig.DIFFICULTIES:
		var name: String = str(pair[0])
		var button := _choice(_row_node(difficulty_group), "Diff%s" % name, name)
		var value: int = int(pair[1])
		button.pressed.connect(func() -> void: choose_difficulty(value))

	# Play as, with the chosen one filled in rather than circled: these are not a
	# scale, so a ring would imply one.
	side_group = _row("LobbySide", "PLAY AS", column)
	for pair in MatchConfig.SIDES:
		var name: String = str(pair[0])
		var button := _choice(_row_node(side_group), "Side%s" % name, name)
		var value: int = int(pair[1])
		button.pressed.connect(func() -> void: choose_side(value))

	# A rule above the action, so PLAY is not just the next thing down from the last
	# option. Configuration and action are different kinds of thing and the gap says
	# so; without it the last option and the button read as one list.
	column.add_child(_divider("LobbyDivider"))

	start_button = _wide("LobbyStart", "PLAY")
	start_button.custom_minimum_size = Vector2(ACTION_WIDTH, 58.0)
	ScreenStyle.button_styles(start_button, 24)
	start_button.add_theme_stylebox_override("normal", ScreenStyle.button_box(
		ScreenStyle.PANEL_PRESSED))
	# Right-aligned within the column rather than centred: the eye finishes the list
	# and then moves across to the one thing to do, instead of dropping down onto it.
	start_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	column.add_child(start_button)

	# Back is not added to the column at all. It is about leaving this screen rather
	# than about this game, so it belongs to the screen and not to the form; sitting in
	# the column it read as one more choice, and every player who wanted out had to
	# find it first.
	_back_button()


## A caption with its options stacked under it, added to the column as a single unit
## so a caption cannot end up beside the wrong set of buttons.
func _row(node_name: String, label_text: String, into: Control) -> VBoxContainer:
	# Caption, then the options stacked one per line. Stacked rather than in a row
	# across the screen because this is a phone held sideways and a full-width target
	# per option is a thumb tap rather than a small label to aim at; three options
	# across on a narrow screen are three small targets side by side.
	var group := VBoxContainer.new()
	group.name = node_name
	group.unique_name_in_owner = true
	group.add_theme_constant_override("separation", 6)
	into.add_child(group)

	var caption := Label.new()
	caption.name = "%sLabel" % node_name
	caption.text = label_text
	caption.custom_minimum_size = Vector2(0.0, 24.0)
	caption.add_theme_font_size_override("font_size", 15)
	caption.add_theme_color_override("font_color", ScreenStyle.CAPTION)
	group.add_child(caption)

	var options := VBoxContainer.new()
	options.name = "%sRow" % node_name
	options.add_theme_constant_override("separation", 4)
	group.add_child(options)
	return group


## The node that holds a group's buttons. The build path needs the container to add
## to; everything else wants the buttons themselves.
func _row_node(group: VBoxContainer) -> VBoxContainer:
	if group == null:
		return null
	return group.get_node_or_null("%sRow" % group.name) as VBoxContainer


## The buttons inside a labelled group, as opposed to the caption above them.
##
## Returned as an array rather than as the row itself. Iterating a live node means
## every caller holds a reference into the tree, and a caller that outlives a
## queue_free then walks freed children and fails on the next step of the loop rather
## than on the line that caused it. An array of the buttons is what every caller
## actually wanted.
func _options(group: VBoxContainer) -> Array:
	if group == null:
		return []
	var row := group.get_node_or_null("%sRow" % group.name) as VBoxContainer
	return [] if row == null else row.get_children()


## Pinned to the top left of the screen, out of the way of the column.
##
## Anchored rather than laid out, because it is the same place on every screen size
## and a player who backs out of one game expects to find it in the same corner next
## time. Muted, because a screen with no way out is a trap but this is still not the
## thing anyone came here to do.
func _back_button() -> void:
	back_button = Button.new()
	back_button.name = "LobbyBack"
	back_button.text = "Back"
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.add_theme_font_size_override("font_size", 17)
	back_button.add_theme_color_override("font_color", ScreenStyle.MUTED)
	back_button.add_theme_color_override("font_hover_color", ScreenStyle.TEXT)
	back_button.add_theme_stylebox_override("normal", ScreenStyle.button_box(
		ScreenStyle.PANEL))
	back_button.add_theme_stylebox_override("hover", ScreenStyle.button_box(
		ScreenStyle.PANEL_HOVER))
	back_button.add_theme_stylebox_override("pressed", ScreenStyle.button_box(
		ScreenStyle.PANEL_PRESSED))
	# A wide target in the corner rather than a word: it is the way out and it should
	# be reachable without aiming.
	back_button.custom_minimum_size = Vector2(104.0, 48.0)
	back_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	back_button.position = Vector2(ScreenStyle.EDGE, ScreenStyle.EDGE)
	add_child(back_button)


## A thin rule between one part of the column and the next. A line rather than a gap
## because a gap alone has to be guessed at, and this screen has three parts that are
## genuinely different from each other.
func _divider(node_name: String) -> ColorRect:
	var rule := ColorRect.new()
	rule.name = node_name
	rule.color = Color(ScreenStyle.BORDER, 0.7)
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


func _wide(node_name: String, text: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.unique_name_in_owner = true
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(ACTION_WIDTH, 56.0)
	ScreenStyle.button_styles(button)
	return button


## One option in a row. A toggle rather than a plain button so the chosen one shows
## as chosen: with three options and no selection the row reads as undecided, and a
## player cannot tell what START will use.
func _choice(parent: Control, node_name: String, text: String) -> Button:
	var button := _wide(node_name, text)
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(COLUMN_WIDTH, 46.0)
	ScreenStyle.choice_styles(button)
	parent.add_child(button)
	return button


## Records the difficulty and shows which one is chosen.
func choose_difficulty(value: int) -> void:
	MatchConfig.difficulty = value
	_choose_difficulty(value)


## Records the side. Random is a real choice, not a placeholder for undecided, so it
## is stored as itself and resolved later.
func choose_side(value: int) -> void:
	MatchConfig.side = value
	_choose_side(value)


## Shows a difficulty as chosen without recording it, so the screen can display a
## stored decision without quietly rewriting the store on the way past.
func _choose_difficulty(value: int) -> void:
	_mark(difficulty_group, MatchConfig.DIFFICULTIES,
		MatchConfig.label_for(MatchConfig.DIFFICULTIES, value), true)


func _choose_side(value: int) -> void:
	_mark(side_group, MatchConfig.SIDES,
		MatchConfig.label_for(MatchConfig.SIDES, value), false)


## Marks whichever option is chosen, and rewrites the difficulty labels to carry
## their radio circles.
##
## One pass, from the chosen value, rather than setting the pressed state and then
## decorating the labels: two passes meant the decoration could be applied to the
## previous selection, and the split had already produced a row that said one thing
## and showed another. Marking by position rather than by text, because the labels are
## rewritten and stop identifying their own options.
func _mark(group: VBoxContainer, labels: Array, wanted: String, circled: bool) -> void:
	if group == null:
		return
	var buttons := _options(group)
	for i in mini(buttons.size(), labels.size()):
		var child: Node = buttons[i]
		if not child is Button:
			continue
		var label: String = str((labels[i] as Array)[0])
		var chosen: bool = label == wanted
		(child as Button).button_pressed = chosen
		if circled:
			(child as Button).text = "%s %s" % ["●" if chosen else "○", label]


## The difficulty label that is currently marked, circles included. Read rather than
## reconstructed, so a test can see what a player sees.
func marked_difficulty() -> String:
	for child in _options(difficulty_group):
		if child is Button and (child as Button).button_pressed:
			return (child as Button).text
	return ""


## Walks back home, forgetting what was chosen, so a later game does not inherit it.
func go_back() -> void:
	back_requested.emit()


## Starts the game, handing over what was chosen. Random is resolved here so the board
## is built for the side it will actually be played from and is never seen turning
## around after it appears.
func start() -> void:
	var chosen := MatchConfig.resolve_side()
	start_requested.emit(chosen)