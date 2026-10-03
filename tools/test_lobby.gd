## Game setup, playing a computer.
##
## Rebuilt from nothing, so these checks are deliberately short: they say what is on the
## screen now, which is the frame and nothing else. As the screen grows, this grows with
## it. A test that kept asserting the old content would have to be deleted to let the
## work happen, and deleting it is how a screen ends up with nothing checking it.
extends SceneTree

const SCENE := "res://lobby.tscn"


## Failed checks, counted. The summary is printed from this rather than printed
## regardless, because a suite that says it passed while printing a failure is worse
## than no suite: it is believed.
var failures := 0


func _initialize() -> void:
	_frame()


func _frame() -> void:
	print("Lobby")
	var lobby := await _spawn() as LobbyScreen
	if lobby == null:
		return

	# The photograph and the wash, which are the screen.
	var background := lobby.get_node_or_null("Background") as TextureRect
	_check("it has the photograph behind it",
		background != null and background.texture != null, "")
	_check("covering the screen rather than sitting in a corner",
		background != null
			and background.anchor_right == 1.0 and background.anchor_bottom == 1.0, "")
	var shade := lobby.get_node_or_null("Shade") as ColorRect
	_check("and the wash over it, from the shared palette",
		shade != null
			and shade.color == ScreenStyle.background_shade(ScreenStyle.SHADE,
				ScreenStyle.BACKGROUND_SHADE), "")

	# Nothing else, which is the whole point of where this screen is.
	_check("and nothing on it yet",
		_content(lobby).get_child_count() == 0,
		"%d children" % _content(lobby).get_child_count())
	_check("no way out of a screen that is not built",
		lobby.find_child("Back", true, false) == null, "")
	_check("and nothing to choose",
		_buttons(lobby).is_empty(), "")

	# The empty box the words will go in, present and the right width, so the screen is
	# a frame with somewhere to put things rather than a picture with nothing on it.
	# Compared with what the frame says rather than with the palette's number: the frame
	# narrows the column on a narrow screen, and a test that wanted the palette value
	# would be wanting a width that screen does not have.
	_check("with somewhere to put them",
		lobby.column != null
			and lobby.column.custom_minimum_size.x == lobby.content_width(),
		"width=%.0f of %.0f" % [lobby.column.custom_minimum_size.x,
			lobby.content_width()])
	_check("held in the middle of the screen",
		lobby.frame_centre != null and lobby.frame_centre.size.x > 0.0, "")
	if failures > 0:
		print("lobby: %d check(s) failed" % failures)
	else:
		print("lobby: all checks passed")


func _spawn() -> Node:
	var screen := (load(SCENE) as PackedScene).instantiate()
	if screen == null:
		return null
	root.add_child(screen)
	await process_frame
	await process_frame
	return screen


## The column, which is everything a card will live in.
func _content(lobby: LobbyScreen) -> Control:
	return lobby.column as Control


func _buttons(lobby: LobbyScreen) -> Array[Node]:
	return lobby.find_children("*", "Button", true, false)


func _check(label: String, condition: bool, detail: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: %s %s" % [label, detail])
