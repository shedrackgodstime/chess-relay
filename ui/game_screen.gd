class_name GameScreen
extends Control

## What every screen in the game looks like, and nothing about what any of them is
## for.
##
## The photograph, the wash over it, a centred column, and Back in the corner. Both
## the VS Computer and the P2P screens open on that, and a third will too. It was
## written twice before this file existed and the two copies already differed, which
## is what a shared frame is for.
##
## It deliberately knows nothing about the choices a screen offers. The design principle
## behind the multiplayer screens is one screen, one decision, and a base class that
## knew what the decisions were would be the first place that principle broke.

var column: VBoxContainer = null
var back_button: Button = null


## Builds the frame, then lets the screen put whatever it is about into the column.
func _ready() -> void:
	_frame()
	_build_content()
	back_button.pressed.connect(_on_back)
	_show_defaults()


## The photograph, the wash, and something to centre the words on.
func _frame() -> void:
	var background := TextureRect.new()
	background.name = "Background"
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.texture = ScreenStyle.background_texture()
	add_child(background)

	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The wash that holds the photograph back, read from the shared palette rather than
	# written here: a screen with its own value is a screen that can disagree with the
	# others about how dark the picture should be.
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
	column.name = "Column"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 16)
	centre.add_child(column)

	# About leaving the screen, not about what is on it, so it is anchored to a corner
	# and never laid out among the choices. A player who backs out of one screen finds
	# it in the same place on the next.
	back_button = Button.new()
	back_button.name = "Back"
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


## A screen's title, in the same place on every screen.
func add_title(text: String, font_size: int = 40) -> Label:
	var label := Label.new()
	label.name = "Title"
	label.text = text
	label.custom_minimum_size = Vector2(0.0, font_size + 15.0)
	ScreenStyle.title_style(label, font_size)
	column.add_child(label)
	return label


## A short gap under a title, so the title is not pressed against what follows.
func add_gap(height: float = 8.0) -> Control:
	var gap := Control.new()
	gap.name = "Gap"
	gap.custom_minimum_size = Vector2(0.0, height)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(gap)
	return gap


## An action at the bottom of the column, on the central axis and no wider than it
## needs to be. A Button in a VBoxContainer fills the column unless told otherwise,
## which would make the action as wide as the whole composition.
func add_action(text: String, width: float = 220.0, height: float = 52.0,
		font_size: int = 22) -> Button:
	var button := Button.new()
	button.name = "Action"
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(width, height)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ScreenStyle.button_styles(button, font_size)
	column.add_child(button)
	return button


## A thin rule between one part of a screen and the next.
func add_divider() -> ColorRect:
	var rule := ColorRect.new()
	rule.name = "Divider"
	rule.color = Color(ScreenStyle.BORDER, 0.75)
	# Shorter than the content, so it marks a change of kind rather than spanning the
	# composition like a border around it.
	rule.custom_minimum_size = Vector2(ScreenStyle.DIVIDER_WIDTH, 1.0)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)
	return rule


## Overridden by a screen to put its own content into the column.
func _build_content() -> void:
	pass


## Overridden by a screen to show whatever it defaults to, once its rows exist.
func _show_defaults() -> void:
	pass


## Back to the home screen, which is where every screen here is reached from.
func _on_back() -> void:
	get_tree().change_scene_to_file("res://home.tscn")