class_name P2pLobby
extends GameScreen

## The first multiplayer screen, and the whole of it: create a game or join one.
##
## Nothing else. No code entry, no side picker, no connection state, because each of
## those is a second decision and the rule these screens follow is one screen, one
## decision. Choosing a side belongs inside Create Game, after the player has said
## they are hosting; entering a code belongs after they have said they are joining.
##
## The VS Computer screen gets two groups side by side because it genuinely asks two
## things at once. This one is deliberately plainer than that. It is the same game, the
## same photograph and the same Back in the corner, and that is the whole of the
## resemblance, because a player who has to read two screens to start playing against a
## person is being asked to do work the design should have done.
##
## Nothing here says host, peer, signalling or server. A player is choosing whether to
## make a game or go to one, and any word here that is about the network rather than
## about the game would be a word they have to be taught before they can use the screen.
##
## Neither choice works yet, and both say so where they are pressed. A button that
## silently does nothing gets pressed twice and reported as broken, which is worse than
## a screen that admits it.

signal create_requested
signal join_requested

const TITLE := "P2P GAME"
const NOT_YET := "No transport yet: neither works yet."


func _build_content() -> void:
	add_title(TITLE, 40)
	add_gap(14.0)
	# Both the same width, so the eye does not have to work out which is the primary
	# one. They are not ranked: a player joining somebody else's game is not doing the
	# lesser thing.
	_choice("CreateGame", "CREATE GAME")
	add_gap(10.0)
	_choice("JoinGame", "JOIN GAME")
	add_divider()
	var notice := Label.new()
	notice.name = "Notice"
	notice.custom_minimum_size = Vector2(ScreenStyle.CONTENT_WIDTH, 0.0)
	ScreenStyle.quiet_style(notice)
	notice.text = NOT_YET
	column.add_child(notice)


## One of the two choices: an outlined button, the language the home screen already
## uses for its entries.
func _choice(node_name: String, text: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(260.0, 56.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ScreenStyle.button_styles(button, 22)
	button.pressed.connect(_on_choice.bind(button))
	column.add_child(button)
	return button


## The two choices lead to two screens. Each one is its own decision, which is the
## whole reason they are not on this screen.
func _on_choice(button: Button) -> void:
	if button.name == "CreateGame":
		create_requested.emit()
		get_tree().change_scene_to_file("res://create_game.tscn")
	else:
		join_requested.emit()
		get_tree().change_scene_to_file("res://join_game.tscn")