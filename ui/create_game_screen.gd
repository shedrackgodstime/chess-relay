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


func _build_content() -> void:
	add_title(TITLE, 40)
	add_gap(6.0)

	side_group = add_options("PLAY AS", SIDES)

	add_gap(6.0)
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
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_label.custom_minimum_size = Vector2(ScreenStyle.CONTENT_WIDTH, 68.0)
	code_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	code_label.add_theme_font_size_override("font_size", 44)
	code_label.add_theme_color_override("font_color", ScreenStyle.TITLE)
	code_label.add_theme_color_override("font_outline_color", ScreenStyle.OUTLINE)
	code_label.add_theme_constant_override("outline_size", ScreenStyle.OUTLINE_SIZE)
	column.add_child(code_label)

	status_label = add_notice("Waiting for opponent...")
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	add_gap(6.0)
	copy_button = add_action("COPY CODE", 200.0, 48.0, 18, "CopyCode")
	copy_button.pressed.connect(_on_copy)
	add_divider()
	cancel_button = add_action("Cancel", 200.0, 46.0, 18, "Cancel")
	cancel_button.pressed.connect(_on_cancel)


func _show_defaults() -> void:
	_code = GameCode.generate()
	code_label.text = _code
	mark_option(options_of(side_group), SIDES.find(MatchConfig.label_for(
		MatchConfig.SIDES, side)))


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