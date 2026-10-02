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
const COLUMN_WIDTH := 460.0


@onready var column: VBoxContainer = %LobbyColumn
@onready var title_label: Label = %LobbyTitle
@onready var difficulty_group: HBoxContainer = %LobbyDifficulty
@onready var side_group: HBoxContainer = %LobbySide
@onready var start_button: Button = %LobbyStart
@onready var back_button: Button = %LobbyBack


func _ready() -> void:
	build()
	start_button.pressed.connect(func() -> void: start_requested.emit())
	back_button.pressed.connect(func() -> void: back_requested.emit())
	# Default selections, shown rather than assumed. A row with nothing chosen looks
	# broken, and a player who has not chosen should still be able to press Start.
	_choose_difficulty(MatchConfig.difficulty)
	_choose_side(MatchConfig.side)


func build() -> void:
	column = VBoxContainer.new()
	column.name = "LobbyColumn"
	column.unique_name_in_owner = true
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	add_child(column)

	title_label = Label.new()
	title_label.name = "LobbyTitle"
	title_label.unique_name_in_owner = true
	title_label.text = TITLE
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.custom_minimum_size = Vector2(COLUMN_WIDTH, 56.0)
	title_label.add_theme_font_size_override("font_size", 34)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.62))
	title_label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03))
	title_label.add_theme_constant_override("outline_size", 8)
	column.add_child(title_label)

	# Each question is a label on the left and its options on the right, so the panel
	# reads as a form: something to decide, then the ways to decide it.
	difficulty_group = _row("LobbyDifficulty", "Difficulty", column)
	for i in MatchConfig.DIFFICULTY_LABELS.size():
		var name: String = MatchConfig.DIFFICULTY_LABELS[i]
		var button := _choice(difficulty_group, "Diff%s" % name, name)
		var value: int = MatchConfig.DIFFICULTY_VALUES[i]
		button.pressed.connect(func() -> void: choose_difficulty(value))

	side_group = _row("LobbySide", "Your color", column)
	for i in MatchConfig.SIDE_LABELS.size():
		var name: String = MatchConfig.SIDE_LABELS[i]
		var button := _choice(side_group, "Side%s" % name, name)
		var value: int = MatchConfig.SIDE_VALUES[i]
		button.pressed.connect(func() -> void: choose_side(value))

	start_button = _wide("LobbyStart", "START")
	column.add_child(start_button)
	back_button = _wide("LobbyBack", "Back")
	column.add_child(back_button)


## A labelled row of choices, added to the column as one unit so the form cannot end
## up with a label beside the wrong set of buttons.
func _row(node_name: String, label_text: String, into: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = node_name
	row.unique_name_in_owner = true
	row.add_theme_constant_override("separation", 10)
	into.add_child(row)

	var caption := Label.new()
	caption.name = "%sLabel" % node_name
	caption.text = label_text
	caption.custom_minimum_size = Vector2(150.0, 48.0)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 19)
	caption.add_theme_color_override("font_color", Color(0.92, 0.86, 0.74))
	caption.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03))
	caption.add_theme_constant_override("outline_size", 6)
	row.add_child(caption)
	return row


func _wide(node_name: String, text: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.unique_name_in_owner = true
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(COLUMN_WIDTH, 56.0)
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color(1.0, 0.90, 0.72))
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	button.add_theme_stylebox_override("normal", _box(Color(0.11, 0.09, 0.08)))
	button.add_theme_stylebox_override("hover", _box(Color(0.16, 0.13, 0.11)))
	button.add_theme_stylebox_override("pressed", _box(Color(0.26, 0.20, 0.15)))
	return button


## One option in a row. A toggle rather than a plain button so the chosen one shows
## as chosen: with three options and no selection the row reads as undecided, and a
## player cannot tell what START will use.
func _choice(parent: Control, node_name: String, text: String) -> Button:
	var button := _wide(node_name, text)
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(0.0, 48.0)
	button.add_theme_stylebox_override("pressed", _box(Color(0.42, 0.32, 0.12)))
	parent.add_child(button)
	return button


static func _box(tint: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = tint
	box.border_color = Color(0.30, 0.24, 0.18)
	box.set_border_width_all(2)
	box.set_corner_radius_all(12)
	return box


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
	var index := MatchConfig.DIFFICULTY_VALUES.find(value)
	_mark(difficulty_group, MatchConfig.DIFFICULTY_LABELS[index]
		if index >= 0 else "")


func _choose_side(value: int) -> void:
	var index := MatchConfig.SIDE_VALUES.find(value)
	_mark(side_group, MatchConfig.SIDE_LABELS[index] if index >= 0 else "")


## Marks whichever option is chosen, so the state is visible in one place and there is
## no second copy of it to fall out of step.
##
## Counts only Buttons rather than indexing children: a row is a caption followed by
## its options, and walking all children would make the caption's position part of the
## answer, so adding a label to a row would silently shift every choice after it.
func _mark(group: HBoxContainer, wanted: String) -> void:
	if group == null:
		return
	for child in group.get_children():
		if child is Button:
			(child as Button).button_pressed = (child as Button).text == wanted


## Walks back home, forgetting what was chosen, so a later game does not inherit it.
func go_back() -> void:
	back_requested.emit()


## Starts the game, handing over what was chosen. Random is resolved here so the board
## is built for the side it will actually be played from and is never seen turning
## around after it appears.
func start() -> void:
	var chosen := MatchConfig.resolve_side()
	start_requested.emit(chosen)