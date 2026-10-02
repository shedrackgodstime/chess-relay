class_name HomeScreen
extends Control

## The first scene in the game: a title and two ways in, over a still of a king.
##
## A separate scene from the game, deliberately. The board is a whole 3D world, and it
## does not belong alive behind a menu: it costs memory and startup on a phone, and it
## invites the player to drag a camera and pick up pieces before choosing to play.
## Layering the menu over the loaded board was tried and is wrong on both counts.
##
## It builds itself in _ready rather than living in home.tscn, which is the same rule
## the board highlights follow: generated things stay out of the scene file, so the
## scene holds structure and a change of wording is a change of code.
##
## Nothing here decides anything. The buttons emit and this screen is dismissed by
## whoever opened it, so the lobby that hangs off these entries will not have to know
## how the home screen is built, and the home screen will not have to know what a lobby
## is.

signal play_computer_requested
signal p2p_requested
signal settings_requested

const TITLE := "CHESS RELAY"
const BACKGROUND := "res://home_bg.jpg"

## Long enough for a title and three entries to read as one column, and short enough
## to sit clear of the middle of the picture: the king is the subject and the words
## must not land on his face.
const COLUMN_WIDTH := 460.0


@onready var background: TextureRect = %HomeBackground
@onready var column: VBoxContainer = %HomeColumn
@onready var title_label: Label = %HomeTitle
@onready var computer_button: Button = %HomeComputer
@onready var p2p_button: Button = %HomeP2P
@onready var settings_button: Button = %HomeSettings


func _ready() -> void:
	build()
	computer_button.pressed.connect(func() -> void: open_game())
	p2p_button.pressed.connect(func() -> void: show_notice(
		"P2P needs a transport, which is not built yet."))
	settings_button.pressed.connect(func() -> void: show_notice(
		"Settings has no screen yet."))


## Loads the game. A separate scene rather than a layer over this one, so nothing of
## the board exists until a game is actually asked for.
func open_game() -> void:
	get_tree().change_scene_to_file("res://main.tscn")


func build() -> void:
	background = TextureRect.new()
	background.name = "HomeBackground"
	background.unique_name_in_owner = true
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Cover, not fit: the picture is cropped rather than letterboxed, so no edges show
	# on any aspect ratio. Fit would frame the whole image and leave black bars on a
	# phone, which reads as a mistake rather than as a choice.
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.texture = _background()
	add_child(background)

	# The picture is dark at the edges and very bright behind the king, so the words
	# need their own darkness to sit on rather than relying on the art being calm
	# where the text happens to land.
	var shade := ColorRect.new()
	shade.name = "HomeShade"
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.05, 0.04, 0.03, 0.55)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	column = VBoxContainer.new()
	column.name = "HomeColumn"
	column.unique_name_in_owner = true
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 12)
	centre.add_child(column)

	title_label = Label.new()
	title_label.name = "HomeTitle"
	title_label.unique_name_in_owner = true
	title_label.text = TITLE
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.custom_minimum_size = Vector2(COLUMN_WIDTH, 64.0)
	title_label.add_theme_font_size_override("font_size", 44)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.62))
	title_label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03))
	title_label.add_theme_constant_override("outline_size", 8)
	column.add_child(title_label)

	computer_button = _row("HomeComputer", "Vs computer")
	p2p_button = _row("HomeP2P", "P2P game")
	settings_button = _row("HomeSettings", "Settings")
	column.add_child(computer_button)
	column.add_child(p2p_button)
	column.add_child(settings_button)
	_notice("P2P and Settings are not ready yet.")


## The picture, or nothing if it has not been imported.
##
## A missing background is not worth a crash and is not worth a fallback that pretends
## to be the art. The shade behind the words is enough to read them either way, so an
## absent texture leaves a plain dark screen rather than an error.
func _background() -> Texture2D:
	if not ResourceLoader.exists(BACKGROUND):
		return null
	return load(BACKGROUND) as Texture2D


## Says so, in the same place, when something is asked for that cannot be done yet. An
## entry that is not wired is honest while it is clearly not wired.
func show_notice(text: String) -> void:
	var label := column.get_node_or_null("HomeNotice") as Label
	if label == null:
		_notice(text)
		return
	label.text = text


func _notice(text: String) -> void:
	var label := Label.new()
	label.name = "HomeNotice"
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(COLUMN_WIDTH, 40.0)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.72, 0.66, 0.58))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03))
	label.add_theme_constant_override("outline_size", 6)
	column.add_child(label)


## One entry. Wide enough to read at arm's length in landscape, which is a thumb tap
## rather than a glance.
func _row(node_name: String, text: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.unique_name_in_owner = true
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(COLUMN_WIDTH, 56.0)
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color(1.0, 0.90, 0.72))
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	button.add_theme_stylebox_override("normal", _button_box())
	button.add_theme_stylebox_override("hover", _button_box(Color(0.16, 0.13, 0.11)))
	button.add_theme_stylebox_override("pressed", _button_box(Color(0.26, 0.20, 0.15)))
	return button


static func _button_box(tint: Color = Color(0.11, 0.09, 0.08)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = tint
	box.border_color = Color(0.30, 0.24, 0.18)
	box.set_border_width_all(2)
	box.set_corner_radius_all(12)
	return box