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

## What the screen is doing. Not three screens: typing, waiting and failing are
## steps through one act, and a player who mistypes a code should be able to get back
## to the field without navigating away from it and losing what they typed.
enum State { TYPING, CONNECTING, FAILED }

var code_label: Label = null
var status_label: Label = null
var state: State = State.TYPING

## Set while a complaint is on screen, so the quiet line and the complaint are not
## two labels fighting over the same space.
var _notice_hidden := true
var join_button: Button = null
var retry_button: Button = null
var retry_caption: Label = null
var cancel_button: Button = null


## The field is 240 px and the error line needs somewhere to wrap, so the composition
## is wider than either.
func content_width() -> float:
	return 460.0


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
	# Handed to the shared frame, which watches the keyboard on its behalf.
	field = self.field
	# Handed to the shared frame, which is what watches the keyboard on its behalf.
	field = self.field
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

	retry_caption = Label.new()
	retry_caption.name = "RetryCaption"
	retry_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	retry_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	retry_caption.visible = false
	retry_caption.add_theme_font_size_override("font_size", 22)
	retry_caption.add_theme_color_override("font_color", ScreenStyle.TEXT)
	retry_caption.add_theme_color_override("font_outline_color", ScreenStyle.OUTLINE)
	retry_caption.add_theme_constant_override("outline_size", ScreenStyle.OUTLINE_SIZE)
	column.add_child(retry_caption)

	status_label = add_notice("")
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.visible = false

	add_gap(8.0)
	join_button = add_action("JOIN", 200.0, 52.0, 20, "Join")
	join_button.pressed.connect(_on_join)
	retry_button = add_action("RETRY", 200.0, 52.0, 20, "Retry")
	retry_button.pressed.connect(_on_retry)
	retry_button.visible = false
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
	if status_label != null and state == State.TYPING:
		status_label.visible = not _notice_hidden


## The code was accepted, which is the end of this screen's job.
##
## Two calls rather than one, so a real transport has somewhere to hook onto and this
## screen never has to know what a transport is. Both routes to the table go through
## here, so connection has one exit rather than one per screen that ends in it.
func connected() -> void:
	get_tree().change_scene_to_file("res://terms.tscn")


## The code did not work. Kept separate from show_failed so the transport reads as a
## pair of outcomes rather than as a screen telling itself it failed.
func not_connected() -> void:
	show_failed()


## What the field is replaced with once there is nothing to type.
func _show_outcome() -> void:
	show_connecting(typed_code())


## The code is being tried. Not a screen of its own: the title and the code stay
## where they were and only the things a player could press change, because the
## thing being waited for is the same thing they were just looking at.
func show_connecting(code: String) -> void:
	state = State.CONNECTING
	_notice_hidden = false
	field.visible = false
	join_button.visible = false
	status_label.visible = true
	status_label.text = "Connecting..."
	_notice("Connecting to %s" % GameCode.readable_of(code))


## The code did not work, said in words a player can act on.
##
## Not a reason code and not an error dump: a player who mistyped cannot do anything
## with either, and the one thing they can do is check the code and try again. A
## well-formed code that nobody is hosting reads the same as one mistyped, because
## from here they are the same problem.
func show_failed() -> void:
	state = State.FAILED
	_notice_hidden = false
	field.visible = false
	join_button.visible = false
	retry_button.visible = true
	status_label.visible = true
	status_label.text = "Check the game code and try again."
	_notice("Couldn't connect.")


## Back to the field, with what was typed still in it, so retrying is one tap rather
## than retyping a code somebody sent over a message.
func retry() -> void:
	_show_typing()


## Says what is happening, above the field when there is one.
func _notice(text: String) -> void:
	if retry_caption != null:
		retry_caption.visible = text != ""
		retry_caption.text = text


## Retrying puts the player back at the field with the code they typed still in it,
## so trying again is one tap rather than retyping something a person sent them.
func _on_retry() -> void:
	retry()


func _on_join() -> void:
	join_requested.emit(typed_code())
	show_connecting(typed_code())


## The screen as a player finds it: a field and something to do with it.
##
## Every path back into typing goes through here, so there is one place that knows
## what the screen looks like when nothing has gone wrong.
func _show_typing() -> void:
	state = State.TYPING
	_notice_hidden = true
	field.visible = true
	join_button.visible = true
	retry_button.visible = false
	retry_caption.visible = false
	if status_label != null:
		status_label.visible = false
		status_label.text = ""
	_update_join()


func _on_cancel() -> void:
	cancel_requested.emit()
	get_tree().change_scene_to_file("res://p2p_lobby.tscn")