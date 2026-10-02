class_name JoinGameScreen
extends GameScreen

## Join a game somebody has made.
##
## The player has a code and needs a way to type it. So this screen is a field, a
## button, and whatever went wrong if it did not work. It is deliberately the smallest
## of the multiplayer screens, because it has the least to decide.
##
## Nothing here says connection, peer or handshake. It says the code was wrong, because
## that is the one thing the player can do about it, and a player told a game code was
## invalid when they mistyped it has no idea what to try next. Anything else the screen
## can report is a sentence a person can act on.
##
## The states are on the same screen rather than across several: type it, it is being
## tried, it worked or it did not. Those are steps through one act, and a player who
## mistypes a code should be able to see the field again without navigating back to it.

signal join_requested(code: String)
signal cancel_requested

const TITLE := "JOIN GAME"

var field: LineEdit = null
var code_label: Label = null
var status_label: Label = null
## Set while a complaint is on screen, so the quiet line and the complaint are not
## two labels fighting over the same space.
var _notice_hidden := true
var join_button: Button = null
var cancel_button: Button = null


func _build_content() -> void:
	add_title(TITLE, 40)
	add_gap(14.0)

	var caption := Label.new()
	caption.name = "CodeCaption"
	caption.text = "ENTER GAME CODE"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.custom_minimum_size = Vector2(0.0, 20.0)
	caption.add_theme_font_size_override("font_size", ScreenStyle.CAPTION_SIZE)
	caption.add_theme_color_override("font_color", ScreenStyle.CAPTION)
	column.add_child(caption)

	field = LineEdit.new()
	field.name = "CodeField"
	field.placeholder_text = "ABC-123"
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.max_length = 7
	# Focusable, which every other control here is not. A field that cannot be focused
	# cannot raise the keyboard on a phone, so the player cannot type into it at all
	# and the screen is unusable rather than merely awkward.
	field.focus_mode = Control.FOCUS_ALL
	field.custom_minimum_size = Vector2(240.0, 58.0)
	field.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	field.add_theme_font_size_override("font_size", 28)
	field.add_theme_color_override("font_color", ScreenStyle.TITLE)
	field.add_theme_color_override("font_placeholder_color", ScreenStyle.MUTED)
	field.add_theme_color_override("caret_color", ScreenStyle.TITLE)
	field.text_changed.connect(_on_typed)
	# Also on focus lost, since a player can paste into a field without the signal
	# arriving, and the join button has to agree with what is in the box.
	field.focus_exited.connect(_on_typed)
	column.add_child(field)

	# The code is shown back as it is typed, normalised, so a player can see the field
	# is right rather than find out by being refused.
	code_label = Label.new()
	code_label.name = "Echo"
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_label.custom_minimum_size = Vector2(0.0, 24.0)
	code_label.add_theme_font_size_override("font_size", 18)
	code_label.add_theme_color_override("font_color", ScreenStyle.MUTED)
	column.add_child(code_label)

	status_label = add_notice("")
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.visible = false

	add_gap(8.0)
	join_button = add_action("JOIN", 200.0, 52.0, 20, "Join")
	join_button.pressed.connect(_on_join)
	add_divider()
	cancel_button = add_action("Cancel", 200.0, 46.0, 18, "Cancel")
	cancel_button.pressed.connect(_on_cancel)


func _show_defaults() -> void:
	_update_echo()
	_update_join()


## What the field holds once spaces and dashes are taken out and it is upper-cased, so
## a pasted message and a typed code are the same thing.
func typed_code() -> String:
	if field == null:
		return ""
	return GameCode.normalise(field.text)


## The field with the code put back in its readable shape, for the echo.
static func readable(code: String) -> String:
	var clean := GameCode.normalise(code)
	if clean.length() <= GameCode.LENGTH:
		return clean
	return "%s-%s" % [clean.substr(0, GameCode.LENGTH),
		clean.substr(GameCode.LENGTH, GameCode.LENGTH)]


func _on_typed(_text: String) -> void:
	# Wrong shape while it is still being typed would scold a player who has not
	# finished, so only the join button changes and the complaint waits for it.
	_update_echo()
	_update_join()


## Both of these are hidden while they have nothing to say.
##
## They were 48 px of empty rows in the middle of the screen before the first
## keystroke, which is most of what made this screen feel padded: the space was there
## before the content, rather than appearing with it.
func _update_echo() -> void:
	if code_label == null:
		return
	var text := readable(field.text if field != null else "")
	code_label.text = text
	code_label.visible = text != ""


func _update_join() -> void:
	if join_button != null:
		join_button.disabled = typed_code().length() < GameCode.GROUPS * GameCode.LENGTH
	if status_label != null:
		status_label.visible = not _notice_hidden


func _on_join() -> void:
	join_requested.emit(typed_code())
	get_tree().change_scene_to_file("res://home.tscn")


func _on_cancel() -> void:
	cancel_requested.emit()
	get_tree().change_scene_to_file("res://p2p_lobby.tscn")