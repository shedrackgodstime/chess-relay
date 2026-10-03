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
var copy_button: Button = null
var cancel_button: Button = null
var _code := ""


## One screen, and the order of it is the whole point.
##
## Creating a game means one thing: give someone something to join with. That is the
## code, and it is at the top because it is what the player came for and it is what
## they have to pass on.
##
## This screen has exactly one job, which is to get a person into the room behind a
## code. It used to also ask what colour they wanted. That was a separate first act with a
## CONTINUE in front of the code, which meant the screen asked a secondary question
## before it would answer the primary one, and the player had to press a button to
## reach the thing they came for. Both players choose their own side and neither is
## told what the other picked, so this is a preference rather than a decision, and a
## preference belongs below the thing that matters rather than in front of it.

## Wide enough for a title and a row of options, rather than the 300 px the code
## happened to need.
func content_width() -> float:
	return 460.0


func _build_content() -> void:
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

	add_gap(8.0)
	status_label = add_notice("Waiting for opponent...")
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	## Play As is not here. Choosing a colour before there is anybody to play it
	## against is answering a question that has not been asked, and it made the one
	## screen with a job to do look like a form. It belongs on the table, where both
	## players are in the room and it is a choice between two people rather than a
	## setting for one.
	cancel_button = _quiet_cancel()
	add_gap(2.0)
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


## The code is made here, after the label that shows it exists, so the screen is never
## built showing nothing and then filled in behind the player's back.
func _show_defaults() -> void:
	if _code == "":
		_code = GameCode.generate()
	if code_label != null:
		code_label.text = _code


## The code, for a test or a host that needs it before the room exists.
func game_code() -> String:
	return _code


## The joiner gets the other colour, so the pair always adds up to a game. Which
## colour is whose is not decided here either.
func choose_side(value: int) -> void:
	side = value
	side_chosen.emit(value)



## Choosing an option, recorded as it is chosen rather than on a later button, so a
## button and the value it stands for cannot drift apart.
## so the button and the choice cannot drift apart.
## Somebody arrived. The document would go straight to the board from here rather
## than asking, which is right for chess: a confirmation step before a game that is
## both players already in is only something to get wrong.
##
## The copy button goes away because the code has stopped being the thing to do.
## Somebody arrived, which is the end of this screen's job. It goes to the table,
## which is where what they play for gets agreed; a waiting room that ended in a game
## would skip past the only screen where the two players find out they agree.
func opponent_connected() -> void:
	waited = true
	status_label.text = "Opponent connected."
	copy_button.visible = false
	get_tree().change_scene_to_file("res://terms.tscn")


## Whoever left, so the host is back to handing a code to someone.
func opponent_left() -> void:
	waited = false
	status_label.text = "Waiting for opponent..."
	copy_button.visible = true


## Joins a table that is already set up, which is the other end of the same connection
## the create screen makes. Shared so both routes land in one place rather than each
## spelling out its own.
func enter_table() -> void:
	get_tree().change_scene_to_file("res://terms.tscn")


## Whether someone is already in the room.
var waited := false


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