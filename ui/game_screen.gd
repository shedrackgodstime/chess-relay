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

## The centred box the words sit in. Held onto because the keyboard moves it, and
## because moving it is the whole of the fix.
var frame_centre: CenterContainer = null

## The field on this screen, if it has one, so the keyboard has something to move for.
var field: LineEdit = null

## The last keyboard height applied, so an unchanged one is not written again.
var _keyboard_height := 0.0


## Builds the frame, then lets the screen put whatever it is about into the column.
## Whether this screen offers a way out of itself.
##
## On by default because a screen with no way back is a dead end, and because a frame
## that had to be told about it would be a frame with an opinion. A screen that is
## deliberately the whole of the flow, with nowhere else to be, turns it off.
var offers_way_back := true


func _ready() -> void:
	_frame()
	_build_content()
	if back_button != null:
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
	frame_centre = centre
	centre.name = "Centre"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	column = VBoxContainer.new()
	column.name = "Column"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 12)
	# A width of its own, rather than one decided by whichever child happens to be
	# widest. Without it a screen is as narrow as its shortest content and as wide as
	# its longest, so two screens of equal importance end up different sizes.
	column.custom_minimum_size = Vector2(content_width(), 0.0)
	centre.add_child(column)

	if not offers_way_back:
		return

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
		font_size: int = 22, node_name: String = "Action") -> Button:
	var button := Button.new()
	# Named by the caller, because a screen with two actions would otherwise have two
	# nodes called Action and nothing could tell them apart.
	button.name = node_name
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


## A quiet line that says something without asking for anything, such as why an entry
## is not ready yet.
## Not given a width of its own.
##
## It was set to the full content width, which meant a hidden complaint was still
## demanding 760 px: on the join screen the column measured 240, and the first time a
## player mistyped a code the complaint appeared and widened the whole screen to 760.
## A layout that rearranges itself when it has something to say is a layout that moves
## under the player's finger.
func add_notice(text: String) -> Label:
	var label := Label.new()
	label.name = "Notice"
	label.text = text
	label.custom_minimum_size = Vector2(0.0, 0.0)
	# Fills the column rather than shrinking to its text. Shrinking gave it a width of
	# one pixel, and a label that wraps and is one pixel wide puts every character on
	# its own line: the quiet lines grew to 547 and 606 px tall and took the screen to
	# 271%. Filling means it never asks for width of its own, so it cannot resize the
	# column either, which is what the previous fix was for.
	label.size_flags_horizontal = Control.SIZE_FILL
	ScreenStyle.quiet_style(label)
	column.add_child(label)
	return label


## A caption with its options stacked under it, the way the VS screen asks its
## questions. Shared rather than copied so a change to how an option looks reaches
## every screen that asks one.
func add_options(caption_text: String, labels: Array) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.name = "Group"
	group.add_theme_constant_override("separation", 8)
	group.custom_minimum_size = Vector2(ScreenStyle.GROUP_WIDTH, 0.0)
	column.add_child(group)

	var caption := Label.new()
	caption.name = "Caption"
	caption.text = caption_text
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.custom_minimum_size = Vector2(0.0, 20.0)
	caption.add_theme_font_size_override("font_size", ScreenStyle.CAPTION_SIZE)
	caption.add_theme_color_override("font_color", ScreenStyle.CAPTION)
	group.add_child(caption)

	var options := VBoxContainer.new()
	options.name = "Options"
	options.add_theme_constant_override("separation", 2)
	options.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	group.add_child(options)

	for i in labels.size():
		var button := Button.new()
		button.name = "Option%d" % i
		button.text = ScreenStyle.MARK_OFF + str(labels[i])
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(ScreenStyle.GROUP_WIDTH, 42.0)
		button.add_theme_font_size_override("font_size", ScreenStyle.OPTION_SIZE)
		button.add_theme_color_override("font_color", ScreenStyle.CAPTION)
		button.add_theme_color_override("font_hover_color", ScreenStyle.TEXT)
		var flat := StyleBoxEmpty.new()
		button.add_theme_stylebox_override("normal", flat)
		button.add_theme_stylebox_override("hover", ScreenStyle.faint_box())
		button.add_theme_stylebox_override("pressed", flat)
		button.add_theme_stylebox_override("focus", flat)
		options.add_child(button)

	fit_options_width(options)
	return group


## Gives every option the width of the widest one, so the labels line up and the block
## can be centred as a whole.
func fit_options_width(options: VBoxContainer) -> void:
	var widest := 0.0
	for child in options.get_children():
		widest = maxf(widest, (child as Control).get_combined_minimum_size().x)
	if widest <= 0.0:
		return
	for child in options.get_children():
		(child as Control).custom_minimum_size = Vector2(widest, 42.0)


## Marks one option and unmarks the rest, in one pass.
func mark_option(options: VBoxContainer, chosen: int) -> void:
	for i in options.get_child_count():
		var button := options.get_child(i) as Button
		if button == null:
			continue
		var label := str(button.text).trim_prefix(ScreenStyle.MARK_OFF) \
			.trim_prefix(ScreenStyle.MARK_ON)
		var marked := i == chosen
		button.button_pressed = marked
		button.text = (ScreenStyle.MARK_ON if marked else ScreenStyle.MARK_OFF) + label
		button.add_theme_color_override("font_color",
			ScreenStyle.TITLE if marked else ScreenStyle.CAPTION)


## Options on one line rather than stacked, for a choice that is not the point of the
## screen.
##
## Stacking is right for the questions a player came to answer, because it gives each
## option a full-width target. It is wrong for a preference sitting underneath the main
## content: it spent 158 px of a 648 px screen on a secondary choice and made the screen
## as tall as the whole interface, which is itself a way of saying the two are equally
## important.
func add_options_row(caption_text: String, labels: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "OptionsRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)

	var caption := Label.new()
	caption.name = "Caption"
	caption.text = caption_text
	caption.custom_minimum_size = Vector2(120.0, 42.0)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", ScreenStyle.CAPTION_SIZE)
	caption.add_theme_color_override("font_color", ScreenStyle.CAPTION)
	row.add_child(caption)

	for i in labels.size():
		var button := Button.new()
		button.name = "Option%d" % i
		button.text = ScreenStyle.MARK_OFF + str(labels[i])
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(92.0, 42.0)
		button.add_theme_font_size_override("font_size", ScreenStyle.OPTION_SIZE)
		button.add_theme_color_override("font_color", ScreenStyle.CAPTION)
		button.add_theme_color_override("font_hover_color", ScreenStyle.TEXT)
		var flat := StyleBoxEmpty.new()
		button.add_theme_stylebox_override("normal", flat)
		button.add_theme_stylebox_override("hover", ScreenStyle.faint_box())
		button.add_theme_stylebox_override("pressed", flat)
		button.add_theme_stylebox_override("focus", flat)
		row.add_child(button)
	return row


## Marks one option in a one-line group, in one pass.
func mark_option_row(row: HBoxContainer, chosen: int) -> void:
	var buttons := 0
	for child in row.get_children():
		if child is Button:
			buttons += 1
	var index := 0
	for child in row.get_children():
		if not child is Button:
			continue
		var button := child as Button
		var label := str(button.text).trim_prefix(ScreenStyle.MARK_OFF) \
			.trim_prefix(ScreenStyle.MARK_ON)
		var marked := index == chosen
		button.button_pressed = marked
		button.text = (ScreenStyle.MARK_ON if marked else ScreenStyle.MARK_OFF) + label
		button.add_theme_color_override("font_color",
			ScreenStyle.TITLE if marked else ScreenStyle.CAPTION)
		index += 1


## The options of a group added by add_options.
func options_of(group: VBoxContainer) -> VBoxContainer:
	if group == null:
		return null
	return group.get_node_or_null("Options") as VBoxContainer


## How wide the composition is. Overridden by a screen that needs a different shape;
## the default suits a column of short choices.
func content_width() -> float:
	return 460.0


## Watches the soft keyboard, which covers whatever is underneath it.
##
## A phone keyboard can take roughly half the screen, and Android leaves coping with
## it to the app rather than pushing the viewport the way iOS does. The fix is to
## shrink the centred box by however tall the keyboard is, so the column re-centres
## in whatever is left on its own.
##
## Squeezing rather than panning, and by measurement rather than by a fixed amount,
## because a keyboard can be any height and can float. Anything that shifts the
## content by a constant is wrong on somebody's phone.
##
## Polled rather than signalled, because Godot 4.7 has virtual_keyboard_get_height and
## no signal for the keyboard opening. It is polled only while a field has focus, which
## is the difference between a check while someone is typing and a check every frame for
## the life of the game.
func _process(_delta: float) -> void:
	if field == null or not is_instance_valid(field) or not field.has_focus():
		set_keyboard_height(0.0)
		return
	set_keyboard_height(_keyboard_height_in_viewport(
		DisplayServer.virtual_keyboard_get_height()))


## The keyboard's height in the units the layout is using.
##
## Android reports the keyboard in physical pixels. When the viewport is scaled those
## are not the units the layout is in, and using them directly shifts the content by
## the wrong amount by exactly the scale factor.
func _keyboard_height_in_viewport(pixels: int) -> float:
	if pixels <= 0:
		return 0.0
	var screen_scale := get_viewport().get_screen_transform().get_scale().x
	return float(pixels) / screen_scale if screen_scale > 0.0 else float(pixels)


## Shrinks the centred box by the keyboard, so the content re-centres above it.
##
## Separate from the polling and public, so a test can put a keyboard of any height on
## a screen without needing a real one.
func set_keyboard_height(height: float) -> void:
	_keyboard_height = maxf(height, 0.0)
	if frame_centre != null:
		frame_centre.offset_bottom = -_keyboard_height


## Overridden by a screen to put its own content into the column.
func _build_content() -> void:
	pass


## Overridden by a screen to show whatever it defaults to, once its rows exist.
func _show_defaults() -> void:
	pass


## Back to the home screen, which is where every screen here is reached from.
func _on_back() -> void:
	get_tree().change_scene_to_file("res://home.tscn")