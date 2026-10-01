class_name Indicators
extends RefCounted

## Whether the board marks where a selected piece may legally go.
##
## This is off by default and meant to be chosen in the lobby before a game
## starts, because the two uses pull against each other. Marking the destinations
## is a real training aid: it teaches where a piece can and cannot go, and it is
## how a beginner stops hunting blindly for a knight. In a game against someone
## it is noise, and worse than noise, because every marked square announces your
## intent before you have committed to it. Neither is the correct default for both
## players, so it is a setting rather than a rule.
##
## Like the quality tier this lives in ProjectSettings and is read lazily, so a
## lobby can change it before the board is built and a test can pin it, with no
## initialisation order to get wrong and nothing to thread through a constructor.

const SETTING := "chess_relay/show_legal_moves"


static func show_legal_moves() -> bool:
	return bool(ProjectSettings.get_setting(SETTING, false))


static func set_show_legal_moves(enabled: bool) -> void:
	ProjectSettings.set_setting(SETTING, enabled)