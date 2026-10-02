class_name CreateGameScreen
extends GameScreen

## The waiting room: a game has been made, and the only thing left is to show someone
## the code and wait.
##
## The code is the object this screen exists for, so it is the largest thing on it and
## everything else is either above it or under it. A host reads this code aloud or sends
## it in a message, and nothing else on the screen is worth reading out.
##
## Side choice is here rather than on the landing screen because hosting is the point
## at which it becomes a real question. On the landing screen the player is choosing
## between making a game and joining one, and a colour would be a second decision
## asked before the first.
##
## Nothing connects yet, so the code is generated and shown and the room waits. The
## screen is otherwise complete: it has its states, its copy action and its way out.

signal cancel_requested
signal side_chosen(side: int)
signal opponent_found_requested

const TITLE := "CREATE GAME"
const SIDES := ["White", "Black", "Random"]

## Which side the host wants. Matches the VS screen's values so the two are the same
## decision asked in the same way.
var side: int = BoardState.DARK

var code_label: Label = null
var status_label: Label = null
var side_group: VBoxContainer = null
var copy_button: Button = null
var cancel_button: Button = null
var _code := ""


## Two acts, one at a time.
##
## Choosing a side and being handed a code are sequential, not simultaneous: the
## document's own flow is CREATE GAME, choose side, game created, show code. Showing
## both meant a player had to hold a colour choice in their head while looking at a code
## they could not use yet, and it made the screen 596 px tall, which is 92% of the
## screen. The first act is brief and ends; the second is the reason the screen exists.
##
## Only one of the two is ever on the screen, so whichever it is gets the whole of it.
func _build_content() -> void:
	_side_act()


## The first act: choose a side, then move on. Deliberately short, because the player
## has come here to make a game, not to configure one.
func _side_act() -> void:
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
	side_group = add_options("PLAY AS", SIDES)
	var note := add_notice("The other player takes the other side.")
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_gap(14.0)
	var cont := add_action("CONTINUE", 220.0, 52.0, 20, "Continue")
	cont.pressed.connect(func() -> void: _code_act())
	for i in options_of(side_group).get_child_count():
		var button := options_of(side_group).get_child(i) as Button
		button.pressed.connect(_on_option_pressed.bind(i))
	mark_option(options_of(side_group), SIDES.find(
		MatchConfig.label_for(MatchConfig.SIDES, side)))


## The second act: the code, and waiting. Everything on this screen is either the code
## or context for it.
func _code_act() -> void:
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
	add_title(TITLE, 40)
	add_gap(4.0)

	var caption := Label.new()
	caption.name = "CodeCaption"
	caption.text = "YOUR GAME CODE"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.custom_minimum_size = Vector2(0.0, 20.0)
	caption.add_theme_font_size_override("font_size", ScreenStyle.CAPTION_SIZE)
	caption.add_theme_color_override("font_color", ScreenStyle.CAPTION)
	column.add_child(caption)

	code_label = Label.new()
	code_label.name = "Code"
	code_label.text = _code
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# As wide as the code and no wider. At the content width it claimed 760 px for
	# seven characters, which made the code look like a heading rather than a thing to
	# read out.
	code_label.custom_minimum_size = Vector2(300.0, 74.0)
	code_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	code_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	code_label.add_theme_font_size_override("font_size", 46)
	code_label.add_theme_color_override("font_color", ScreenStyle.TITLE)
	code_label.add_theme_color_override("font_outline_color", ScreenStyle.OUTLINE)
	code_label.add_theme_constant_override("outline_size", ScreenStyle.OUTLINE_SIZE)
	column.add_child(code_label)

	# Close under the code, because the two are one thing: this is what you read out
	# and this is what you do about it.
	add_gap(2.0)
	copy_button = add_action("COPY CODE", 190.0, 46.0, 17, "CopyCode")
	copy_button.pressed.connect(_on_copy)
	add_gap(10.0)

	status_label = add_notice("Waiting for opponent...")
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cancel_button = _quiet_cancel()
	add_divider()
	column.add_child(cancel_button)
	cancel_button.pressed.connect(_on_cancel)


## Cancel is the way out, so it does not get the language of the thing you came for.
## A player who is looking for COPY CODE should not have a second outlined button
## below it offering the same kind of tap.
func _quiet_cancel() -> Button:
	var button := Button.new()
	button.name = "Cancel"
	button.text = "Cancel"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(190.0, 40.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", ScreenStyle.MUTED)
	button.add_theme_color_override("font_hover_color", ScreenStyle.TEXT)
	var flat := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", flat)
	button.add_theme_stylebox_override("hover", ScreenStyle.faint_box())
	button.add_theme_stylebox_override("pressed", flat)
	button.add_theme_stylebox_override("focus", flat)
	return button


func _show_defaults() -> void:
	_code = GameCode.generate()


## The code, for a test or a host that needs it before the room exists.
func game_code() -> String:
	return _code


## Records the side and shows it. The joiner gets the other one, so the pair always
## adds up to a game.
func choose_side(value: int) -> void:
	side = value
	mark_option(options_of(side_group), SIDES.find(
		MatchConfig.label_for(MatchConfig.SIDES, value)))
	side_chosen.emit(value)


## Choosing an option. The side is recorded as it is chosen rather than on Continue,
## so the button and the choice cannot drift apart.
func _on_option_pressed(index: int) -> void:
	var values := [BoardState.LIGHT, BoardState.DARK,
		MatchConfig.Difficulty.RANDOM_SIDE]
	if index >= 0 and index < values.size():
		choose_side(values[index])


## Puts the code on the clipboard, because a host on a phone is sending this in a
## message and retyping it is the whole job.
func _on_copy() -> void:
	DisplayServer.clipboard_set(_code)
	copy_button.text = "COPIED"
	status_label.text = "Waiting for opponent..."
	get_tree().create_timer(1.6).timeout.connect(_restore_copy)


func _restore_copy() -> void:
	if is_instance_valid(copy_button):
		copy_button.text = "COPY CODE"


func _on_cancel() -> void:
	cancel_requested.emit()
	get_tree().change_scene_to_file("res://p2p_lobby.tscn")