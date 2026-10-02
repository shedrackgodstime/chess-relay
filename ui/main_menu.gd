class_name MainMenu
extends CanvasLayer

## The screen the game opens on, and the only place a game is started.
##
## Everything else happens on the board, so this stays deliberately small: two ways
## to play and a way into settings. It is a menu of choices, not a lobby, and it
## grows no more rows than it has real answers to give.
##
## The board stays loaded and visible behind this, dimmed. That is a deliberate cost
## of having one scene rather than two: starting a game is instant because nothing is
## built at that moment, and a player waiting to be matched or to choose a side is
## looking at an empty room instead of a still chessboard, which is the game's own
## subject rather than a placeholder. The menu is a layer over the board, never a
## replacement for it.
##
## Only the buttons exist here. Settings has no screen yet, so it says so rather than
## opening nothing, and P2P has no transport, so it says that too. An entry point that
## is not wired yet is honest as long as it is clearly not wired, and a button that
## silently does nothing is worse than one that explains itself.

signal play_computer_requested
signal p2p_requested
signal settings_requested

const TITLE := "CHESS RELAY"
const INSET := Hud.MENU_INSET


@onready var dim: ColorRect = %MenuDim
@onready var title_label: Label = %MenuTitle
@onready var column: VBoxContainer = %MenuColumn
@onready var computer_button: Button = %MenuComputer
@onready var p2p_button: Button = %MenuP2P
@onready var settings_button: Button = %MenuSettings


func _ready() -> void:
	build()
	computer_button.pressed.connect(func() -> void: play_computer_requested.emit())
	p2p_button.pressed.connect(func() -> void: p2p_requested.emit())
	settings_button.pressed.connect(func() -> void: settings_requested.emit())


## Builds the menu in code rather than in the scene.
##
## The project's rule, already used by the board highlights: anything generated lives
## in _ready and stays out of the .tscn, so the scene file holds structure rather than
## a copy of it that has to be regenerated to change a label. Two screens would
## otherwise mean two generated scene files drifting apart.
func build() -> void:
	dim = ColorRect.new()
	dim.name = "MenuDim"
	dim.unique_name_in_owner = true
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.04, 0.03, 0.82)
	# Stops, so a tap that misses cannot fall through to the board underneath and move
	# a piece before the game has even started.
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	column = VBoxContainer.new()
	column.name = "MenuColumn"
	column.unique_name_in_owner = true
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 12)
	centre.add_child(column)

	title_label = Label.new()
	title_label.name = "MenuTitle"
	title_label.unique_name_in_owner = true
	title_label.text = TITLE
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.custom_minimum_size = Vector2(420.0, 64.0)
	title_label.add_theme_font_size_override("font_size", 44)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.62))
	title_label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03))
	title_label.add_theme_constant_override("outline_size", 8)
	column.add_child(title_label)

	computer_button = _row("MenuComputer", "Vs computer")
	p2p_button = _row("MenuP2P", "P2P game")
	settings_button = _row("MenuSettings", "Settings")
	column.add_child(computer_button)
	column.add_child(p2p_button)
	column.add_child(settings_button)

	_notice("No transport yet: P2P and Settings are on their way.")


## Says so, in the same place, when something is asked for that cannot be done yet.
## An entry point that is not wired is honest while it is clearly not wired.
func show_notice(text: String) -> void:
	var label := get_node_or_null("Centre/MenuColumn/MenuNotice") as Label
	if label == null:
		_notice(text)
		return
	label.text = text


## A quiet line under the buttons, so the entries that do nothing yet say so.
func _notice(text: String) -> void:
	var label := Label.new()
	label.name = "MenuNotice"
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(420.0, 40.0)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.72, 0.66, 0.58))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03))
	label.add_theme_constant_override("outline_size", 6)
	column.add_child(label)


## One entry. Wide enough to be read at arm's length in landscape, which is a thumb
## tap rather than a glance.
func _row(node_name: String, text: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.unique_name_in_owner = true
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(420.0, 56.0)
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


## Shows the board: the menu is a layer over it, never a replacement.
func dismiss() -> void:
	visible = false


## Brings it back, which is what quitting to the menu will need.
func present() -> void:
	visible = true