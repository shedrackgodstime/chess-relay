class_name LobbyScreen
extends Control

## Where a computer game is set up. One step in from the home screen, and built to
## look like the same application rather than a different interface.
##
## The composition is the document's: two option groups side by side, each stacked
## vertically, balanced about the centre axis, with the action below a rule. Vertically
## stacked choices inside each group, horizontally arranged groups. That is the whole
## idea: the screen is landscape, so it should use its width without becoming a form.
##
## The groups sit on the photograph, not in a card. A panel large enough to hold both
## would hide the picture, and the picture is the reason the screen looks like Chess
## Relay and not like a settings dialog.
##
## Every mark here is drawn or typed from a character the font actually has. The font
## is Open Sans SemiBold, which has no white king, no black king and no filled circle;
## all three were tried and all three render as missing glyphs. Side choice is a disc,
## hollow for White and filled for Black, which is the convention anyway, and the
## selection mark is a bullet.

signal start_requested(side: int)
signal back_requested

const TITLE := "VS COMPUTER"
const ACTION := "PLAY"


var column: VBoxContainer = null
var title_label: Label = null
var difficulty_group: VBoxContainer = null
var side_group: VBoxContainer = null
var start_button: Button = null
var back_button: Button = null


func _ready() -> void:
	build()
	start_button.pressed.connect(_on_play)
	back_button.pressed.connect(_on_back)
	# Whatever was chosen last, shown rather than assumed. A screen with nothing
	# chosen looks broken, and a player who has not chosen should still be able to play.
	_show_difficulty(MatchConfig.difficulty)
	_show_side(MatchConfig.side)


func build() -> void:
	# The home screen's background treatment exactly: the same photograph, covered
	# rather than fitted, under the same wash. Reusing it is what makes this read as
	# the next screen of the same game.
	var background := TextureRect.new()
	background.name = "LobbyBackground"
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.texture = ScreenStyle.background_texture()
	add_child(background)

	var shade := ColorRect.new()
	shade.name = "LobbyShade"
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = ScreenStyle.background_shade(ScreenStyle.SHADE,
		ScreenStyle.BACKGROUND_SHADE)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	column = VBoxContainer.new()
	column.name = "LobbyColumn"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	# Tight, with the room below the title coming from a spacer rather than from the
	# column as a whole. Spacing every part this far apart made the lobby taller than
	# the home screen, and the document asks for the opposite.
	column.add_theme_constant_override("separation", 10)
	centre.add_child(column)

	# Less vertical space than the home screen. This is one step in a flow, not the
	# cover, and it should not demand as much of the screen as the cover does.
	title_label = Label.new()
	title_label.name = "LobbyTitle"
	title_label.text = TITLE
	title_label.custom_minimum_size = Vector2(0.0, 44.0)
	ScreenStyle.title_style(title_label, 40)
	column.add_child(title_label)
	var under_title := Control.new()
	under_title.name = "UnderTitle"
	under_title.custom_minimum_size = Vector2(0.0, 8.0)
	under_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(under_title)

	_groups()

	var rule := _divider()
	# Centred inside its own slot rather than given a full row: at one pixel it was
	# already the thinnest thing on the screen and the gap above and below it was doing
	# the spacing, so the two gaps around it are what the space is actually made of.
	column.add_child(rule)

	start_button = Button.new()
	start_button.name = "LobbyStart"
	start_button.text = ACTION
	start_button.focus_mode = Control.FOCUS_NONE
	# Outlined like the home buttons, but narrower: this is one action on a screen with
	# two decisions, and it should not outweigh them.
	start_button.custom_minimum_size = Vector2(220.0, 52.0)
	# Shrink, not fill. A Button in a VBox fills the column by default, so PLAY came
	# out as wide as the whole composition, which is the same width as the title above
	# it and made the two read as a pair rather than a title and an action.
	start_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ScreenStyle.button_styles(start_button, 22)
	column.add_child(start_button)

	# About leaving the screen, not about this game, so it is anchored to a corner
	# rather than laid out in the column where it would read as a third choice.
	back_button = Button.new()
	back_button.name = "LobbyBack"
	back_button.text = "Back"
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.add_theme_font_size_override("font_size", 17)
	back_button.add_theme_color_override("font_color", ScreenStyle.MUTED)
	back_button.add_theme_color_override("font_hover_color", ScreenStyle.TEXT)
	back_button.add_theme_stylebox_override("normal",
		ScreenStyle.button_box(ScreenStyle.PANEL))
	back_button.add_theme_stylebox_override("hover",
		ScreenStyle.button_box(ScreenStyle.PANEL_HOVER))
	back_button.add_theme_stylebox_override("pressed",
		ScreenStyle.button_box(ScreenStyle.PANEL_PRESSED))
	back_button.custom_minimum_size = Vector2(104.0, 48.0)
	back_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	back_button.position = Vector2(ScreenStyle.EDGE, ScreenStyle.EDGE)
	add_child(back_button)


## The two questions, side by side.
##
## One row holding both groups rather than two rows, because the point of the
## composition is that they are alternatives asked at the same time. The row is as wide
## as both groups and their gap put together and no wider, which is what keeps the pair
## balanced about the centre instead of drifting apart on a wide screen.
func _groups() -> void:
	var row := HBoxContainer.new()
	row.name = "LobbyGroups"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(ScreenStyle.GROUP_GAP))
	row.custom_minimum_size = Vector2(
		ScreenStyle.GROUP_WIDTH * 2.0 + ScreenStyle.GROUP_GAP, 0.0)
	column.add_child(row)

	difficulty_group = _group("LobbyDifficulty", "DIFFICULTY", row)
	for pair in MatchConfig.DIFFICULTIES:
		_option(difficulty_group, str(pair[0]))
	_fit_options(difficulty_group)

	side_group = _group("LobbySide", "PLAY AS", row)
	for pair in MatchConfig.SIDES:
		_option(side_group, str(pair[0]))
	_fit_options(side_group)


## A caption with its options stacked under it.
##
## Equal width whatever the caption says, so the two groups line up without either of
## them being measured against the other.
func _group(node_name: String, caption_text: String, into: Control) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.name = node_name
	group.add_theme_constant_override("separation", 8)
	group.custom_minimum_size = Vector2(ScreenStyle.GROUP_WIDTH, 0.0)
	into.add_child(group)

	var caption := Label.new()
	caption.name = "%sCaption" % node_name
	caption.text = caption_text
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.custom_minimum_size = Vector2(0.0, 20.0)
	caption.add_theme_font_size_override("font_size", ScreenStyle.CAPTION_SIZE)
	caption.add_theme_color_override("font_color", ScreenStyle.CAPTION)
	group.add_child(caption)

	var options := VBoxContainer.new()
	options.name = "%sOptions" % node_name
	options.add_theme_constant_override("separation", 2)
	# The block is centred inside the group and is only as wide as its widest option,
	# so its rows all start in the same place and the block as a whole sits on the
	# centre axis.
	options.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	group.add_child(options)
	return group


## One selectable option: a mark, maybe a disc, and the label.
##
## No face and no border. These are a list, not a row of buttons, and a filled
## rectangle on every line makes the chosen one look like the only thing there is to
## do. The row keeps a full thumb's height anyway, because the space is what makes it
## easy to hit, not the drawing.
func _option(group: VBoxContainer, label: String) -> Button:
	var options := _options_node(group)
	if options == null:
		return null
	var button := Button.new()
	button.name = "%s%s" % [group.name, label]
	button.focus_mode = Control.FOCUS_NONE
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(0.0, 42.0)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT

	# The label and the disc are laid out by a row inside the button, not by putting
	# the disc in as a child and hoping. A child of a Button sits at the button's own
	# origin, which is exactly where the text is drawn, so the disc landed on top of
	# the word: both were measured at x=636 before this was a row.
	var row := HBoxContainer.new()
	row.name = "Row"
	# Left-aligned, deliberately. Centring each row on its own put every word at a
	# different x, because the pair is centred and "White" is wider than "Black": the
	# three labels of a group stepped in and out instead of hanging on one edge.
	# Alignment comes from centring the block they all sit in, not from each row.
	row.add_theme_constant_override("separation", 10)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)

	# All three side options carry a mark, Random included. It had a spacer there and
	# was the one option that did not look like the others, which read as though it
	# were not a real choice.
	var mark: TextureRect = null
	if group == side_group:
		mark = TextureRect.new()
		mark.name = "Mark"
		mark.texture = _side_icon(label)
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark.custom_minimum_size = Vector2(ScreenStyle.MARK_SIZE,
			ScreenStyle.MARK_SIZE)
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(mark)
	row.add_child(_option_label(label, ScreenStyle.MARK_OFF))

	button.add_theme_font_size_override("font_size", ScreenStyle.OPTION_SIZE)
	button.add_theme_color_override("font_color", ScreenStyle.CAPTION)
	button.add_theme_color_override("font_hover_color", ScreenStyle.TEXT)
	# A hover that is only slightly lighter, since the choice is already carried by the
	# bullet and the text and a heavy face would fight both.
	button.add_theme_stylebox_override("hover", ScreenStyle.faint_box())
	var empty := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", empty)
	button.add_theme_stylebox_override("pressed", empty)
	button.add_theme_stylebox_override("focus", empty)
	button.add_theme_stylebox_override("hover_pressed", empty)
	button.pressed.connect(_on_option_pressed.bind(group, button))
	options.add_child(button)
	return button


## Gives every row in a group the width of the widest one.
##
## The width has to be stated rather than left to be measured out, because a Button's
## own minimum comes from its text and these have none now: the word is a Label inside
## it. Left to itself the block measured zero wide, and every row was only as wide as
## its own word, so "White" and "Black" started in different places.
##
## All rows are then the same width, which is what makes the labels line up, and the
## block is centred as one thing rather than each row centring itself.
func _fit_options(group: VBoxContainer) -> void:
	var options := _options_node(group)
	if options == null:
		return
	var widest := 0.0
	for child in options.get_children():
		var row := child.get_node_or_null("Row") as Control
		if row == null:
			continue
		var needed: float = row.get_combined_minimum_size().x
		if needed > 0.0:
			widest = maxf(widest, needed)
	if widest <= 0.0:
		return
	for child in options.get_children():
		# On the button, not the row. A Button's minimum width comes from its own text
		# and icon and does not include the Controls inside it, so sizing the row left
		# the button at nothing and the whole block measured zero wide.
		(child as Control).custom_minimum_size = Vector2(widest, 42.0)


## The mark for a side: a piece for White and Black, a diamond for Random.
##
## One glyph in two colours, and the border is drawn around both of them rather than
## asked for in the file. See Icons.outlined for why.
static func _side_icon(label: String) -> Texture2D:
	if label == "Random":
		return Icons.side_diamond()
	return Icons.side_piece(label == "Black")


## Every option in a group, in the order they were added.
func _options_node(group: VBoxContainer) -> VBoxContainer:
	if group == null:
		return null
	return group.get_node_or_null("%sOptions" % group.name) as VBoxContainer


func _options(group: VBoxContainer) -> Array:
	var options := _options_node(group)
	return [] if options == null else options.get_children()


## The word on an option, as its own node inside the button.
##
## A Label rather than the button's own text, because the button also carries a disc
## and a mark and text is drawn across all of it. Keeping the word separate is what lets
## the disc and the word sit side by side instead of on top of each other.
func _option_label(text: String, mark: String) -> Label:
	var label := Label.new()
	label.name = "Word"
	label.text = mark + text
	# Set here as well as on the button: the word is a Label inside it, and a Label
	# reads the theme's own size, not the override on the Button it sits in. Measured
	# at 16 px with an 18 px override in place, which is the theme default winning.
	label.add_theme_font_size_override("font_size", ScreenStyle.OPTION_SIZE)
	label.add_theme_color_override("font_color", ScreenStyle.CAPTION)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Shrink to the text rather than filling the row: a label that expands takes all the
	# spare width, which puts its text back at the left edge and quietly undoes the
	# centring of the row around it.
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return label


## Reads the option off its own label, so the two never disagree about which is which.
##
## By position within its own group, since the label carries the mark and the disc and
## so is no longer a stable identifier: it changes when the choice does.
func _on_option_pressed(group: VBoxContainer, button: Button) -> void:
	var options := _options(group)
	var index := options.find(button)
	if index < 0:
		return
	if group == difficulty_group:
		choose_difficulty(int(MatchConfig.DIFFICULTIES[index][1]))
	else:
		choose_side(int(MatchConfig.SIDES[index][1]))


## Records the difficulty and shows it.
func choose_difficulty(value: int) -> void:
	MatchConfig.difficulty = value
	_show_difficulty(value)


## Records the side. Random is a real choice rather than a stand-in for undecided.
func choose_side(value: int) -> void:
	MatchConfig.side = value
	_show_side(value)


## Shows a difficulty without recording it, so a screen can display a stored decision
## without quietly rewriting the store on the way past.
func _show_difficulty(value: int) -> void:
	_mark(difficulty_group, MatchConfig.DIFFICULTIES,
		MatchConfig.label_for(MatchConfig.DIFFICULTIES, value))


func _show_side(value: int) -> void:
	_mark(side_group, MatchConfig.SIDES,
		MatchConfig.label_for(MatchConfig.SIDES, value))


## Marks one option and unmarks the rest, in a single pass from the chosen label.
##
## Two passes over a row, one to press and another to decorate, is how a row ends up
## saying one thing and showing another; this writes both from the same decision.
func _mark(group: VBoxContainer, pairs: Array, wanted: String) -> void:
	var options := _options(group)
	for index in mini(options.size(), pairs.size()):
		var button := options[index] as Button
		if button == null:
			continue
		var label := str(pairs[index][0])
		var chosen := label == wanted
		button.button_pressed = chosen
		var mark := ScreenStyle.MARK_ON if chosen else ScreenStyle.MARK_OFF
		var word := button.get_node_or_null("Row/Word") as Label
		if word != null:
			# The bullet goes in front of the word so the chosen line starts a little
			# further in, and every line is padded to the same width so the labels
			# below the caption stay aligned whether chosen or not.
			word.text = mark + label
			word.add_theme_color_override("font_color",
				ScreenStyle.TITLE if chosen else ScreenStyle.CAPTION)
		else:
			button.text = mark + label
		# The mark is not swapped on selection: it says which side the option is, and
		# the bullet already says whether it is chosen. One mark per option, doing one
		# job.


## The label of whichever option is marked, bullet and all. Read rather than
## reconstructed, so a test sees what a player sees.
func marked_difficulty() -> String:
	return _marked(difficulty_group)


func _marked(group: VBoxContainer) -> String:
	for child in _options(group):
		if not child is Button or not (child as Button).button_pressed:
			continue
		var word := (child as Button).get_node_or_null("Row/Word") as Label
		return word.text if word != null else (child as Button).text
	return ""


## A thin rule between configuration and action.
func _divider() -> ColorRect:
	var rule := ColorRect.new()
	rule.name = "LobbyDivider"
	rule.color = Color(ScreenStyle.BORDER, 0.75)
	# Shorter than the content, so it marks a change of kind rather than spanning the
	# composition like a border around it.
	rule.custom_minimum_size = Vector2(ScreenStyle.DIVIDER_WIDTH, 1.0)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


## Starts the game, handing over the side already resolved, so the board is built for
## whoever is playing and is never seen turning around after it appears.
func start() -> void:
	start_requested.emit(MatchConfig.resolve_side())


func _on_play() -> void:
	start()


## Back to the home screen, which is where the lobby was reached from.
##
## It used to emit a signal that nothing listened to, so the button was decoration: a
## way out that did not get you out is worse than no button, because it says there is a
## way out.
func _on_back() -> void:
	back_requested.emit()
	get_tree().change_scene_to_file("res://home.tscn")