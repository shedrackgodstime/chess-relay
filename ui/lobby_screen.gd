## Game setup, playing a computer. Being built one piece at a time.
##
## For now the screen is only the frame: the photograph, the wash, and the empty box the
## words will go in. Everything that was on it is gone, including the way out, because
## this screen is being rebuilt from scratch and a half-built screen with a working Back
## button is a screen that looks finished and is not.
class_name LobbyScreen
extends GameScreen


## Set before the frame is built, which is the only moment it is read.
func _init() -> void:
	offers_way_back = false


## Nothing here yet, on purpose.
func _build_content() -> void:
	pass
