class_name Indicators
extends RefCounted

## Whether the board marks where a selected piece may legally go.
##
## The shipping default is OFF, chosen deliberately, and this file currently says
## otherwise on purpose. Both uses of the hint pull against each other: marking
## the destinations is a real training aid, since it shows where a piece can and
## cannot go and is how a beginner stops hunting blindly for a knight, but in a
## game against someone it is noise, and worse than noise, because every marked
## square announces your intent a beat before you commit to it. Neither default
## suits both players, so this is a lobby setting and not a rule.
##
## TEMPORARY: the default is ON so that every feature can be seen working while
## the game is being built. It is flipped for review, not chosen. Before this
## ships, put it back to false and delete this paragraph. Until then every feature
## being visible is worth more than the intent it gives away, because nothing else
## can be judged until it has been watched at all.
##
## Like the quality tier this lives in ProjectSettings and is read lazily, so a
## lobby can change it before the board is built and a test can pin it, with no
## initialisation order to get wrong and nothing to thread through a constructor.

const SETTING := "chess_relay/show_legal_moves"


## ON while the game is being built, so the hints can be seen working. See the
## note above: this is not the shipping default and has to go back to false.
const DEV_DEFAULT := true


static func show_legal_moves() -> bool:
	return bool(ProjectSettings.get_setting(SETTING, DEV_DEFAULT))


static func set_show_legal_moves(enabled: bool) -> void:
	ProjectSettings.set_setting(SETTING, enabled)