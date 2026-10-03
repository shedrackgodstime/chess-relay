## The table.
##
## Everything before this was about getting two people into the same room: choosing how
## to meet, exchanging a code, checking the code was right. That is the connection, and
## it is deliberately mechanical. It decides how the two players talk and nothing about
## how they play.
##
## This is where the game gets decided. Both players arrive at the same screen, because
## the questions here are questions between two people rather than settings for one,
## and a colour picked alone in a waiting room was answering a question nobody had asked
## yet.
##
## What is here is deliberately little. The creator's choices are the ones that stand
## and the creator starts the game, which is the simplest way to make an agreement
## without a negotiation nobody has specified yet. When there is a need for both players
## to have a say, this is the screen that grows it: nothing here is written assuming the
## creator is always right.
class_name TermsScreen
extends GameScreen

const TITLE := "MATCH SETUP"

## The questions this screen asks, in the order it asks them.
##
## Grouped so a new one is a new line here rather than a new block of code, and so a
## screen that has not been designed yet is obviously a screen that has not been
## designed yet.
##
## A function rather than a constant because the option lists are values held elsewhere,
## and a constant may not be built out of those.
static func terms() -> Array:
	var times := [
		[MatchConfig.NO_CLOCK, "No clock"],
		[5, "5 min"],
		[10, "10 min"],
		[15, "15 min"],
	]
	return [
		["Play as", MatchConfig.SIDES],
		["Time control", times],
	]


## The values as agreed, kept on this screen and read when the game is started, so the
## button and the values it starts cannot drift apart.
var agreed := {
	MatchConfig.value_for(MatchConfig.SIDES, "Random"): MatchConfig.Difficulty.RANDOM_SIDE,
	0: MatchConfig.NO_CLOCK,
}

## Which end of the table this player is. Decided before this screen is built, because
## it decides whether there is a Start button at all.
var seat: int = MatchConfig.Seat.CREATOR

## Built by _finish(), and declared here because whether there is one is decided by
## which end of the table this is, not by a code path.
var start_button: Button = null
var waiting_label: Label = null

## Maps a label to its option row, so changing a value does not mean searching the
## column for it.
var rows: Dictionary = {}


## Set when the game is ready to begin.
signal start_requested()


func _build_content() -> void:
	add_title(TITLE)
	add_gap(2.0)
	_add_notice()
	add_gap(4.0)
	for group: Array in terms():
		var name := String(group[0])
		rows[name] = add_options_row(name.to_upper(), group[1])
		var index := 0
		for child in rows[name].get_children():
			if child is Button:
				(child as Button).pressed.connect(_choose.bind(name, index))
				index += 1
		_mark(name, group[1], index)
	add_gap(6.0)
	_finish()


## Says which end of the table this is, because it decides who starts and it is not
## something a player should have to work out from the absence of a button.
func _add_notice() -> void:
	var label := add_notice("You started this game." if MatchConfig.is_creator()
		else "You joined this game.")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _finish() -> void:
	## The creator starts it. A second confirmation before a game both players are
	## already in is only something to get wrong, but a start button for one of them and
	## not the other is also something to get wrong, so the joiner is told plainly that
	## they are waiting rather than shown a button that would not do anything.
	if MatchConfig.is_creator():
		start_button = add_action("START", 220.0, 52.0, 22)
		start_button.pressed.connect(_on_start)
		waiting_label = add_notice("")
		waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		waiting_label.visible = false
	else:
		waiting_label = add_notice("Waiting for the other player to start.")
		waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## Records a choice as it is made and shows it, so the lit button and the value the game
## will start with cannot drift apart.
func _choose(name: String, index: int) -> void:
	for group: Array in terms():
		if String(group[0]) == name:
			agreed[_label_to_value(group[1], index)] = group[1][index][0]
			_mark(name, group[1], index)
			return


func _mark(name: String, pairs: Array, chosen: int) -> void:
	var row: HBoxContainer = rows.get(name, null)
	if row != null:
		mark_option_row(row, chosen)


## An option's value, found by position. Options carry their value in their first cell
## throughout the project, so there is one rule rather than one per screen.
func _label_to_value(pairs: Array, index: int) -> int:
	return pairs[index][0] if index >= 0 and index < pairs.size() else pairs[0][0]


## The values as agreed, resolved. Read when the game starts.
##
## The first option of the row is the fallback, so an unchosen value can never be
## missing and the game can never start on something nobody agreed to.
func agreed_value(name: String) -> int:
	for group: Array in terms():
		if String(group[0]) != name:
			continue
		var pairs: Array = group[1]
		for pair in pairs:
			if agreed.has(pair[0]):
				return int(agreed[pair[0]])
		return int(pairs[0][0])
	return 0


## The two players agreed, so the game can begin.
##
## The agreed values are written into the shared configuration before the board is
## built, so the game cannot start with terms that differ from the ones on screen.
func start() -> void:
	MatchConfig.side = agreed_value("Play as")
	_match_colour_seat()
	start_requested.emit()


## With the creator's colour decided, the joiner takes the other one. A pair that adds
## up to a game is a fact about chess, not a preference, so it is derived rather than
## chosen.
func _match_colour_seat() -> void:
	if not MatchConfig.is_creator():
		MatchConfig.side = BoardState.DARK if MatchConfig.side == BoardState.LIGHT \
			else BoardState.LIGHT
func _on_start() -> void:
	start()
	get_tree().change_scene_to_file("res://main.tscn")


## Which colour this player is taking, resolved once for the table.
##
## Random is resolved before the board is built rather than on it, so the board is never
## seen turning around after it appears.
func resolved_side() -> int:
	return MatchConfig.side_for_seat(seat)


## For when the other player leaves before the game starts. There is nothing to go back
## to but the way in, so it goes there.
func _on_back() -> void:
	get_tree().change_scene_to_file("res://p2p_lobby.tscn")
