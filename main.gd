@tool
class_name Main
extends Node3D

## Entry point for the prototype.
##
## Following the recommended scene layout, Main owns the World and is the only
## place that knows about both the board and the pieces. Gameplay will grow
## here; for now the one piece of logic worth having is camera framing, so the
## camera stays correct if the board size ever changes.

@onready var world: Node3D = $World
@onready var camera: OrbitCamera = $World/Camera

## Camera placement as multiples of the board's half-extent, so the default
## view survives a change to BoardMesh's dimensions.
@export_range(0.5, 4.0) var framing_height := 1.50:
	set(value):
		framing_height = value
		frame_board()

@export_range(0.5, 4.0) var framing_distance := 2.20:
	set(value):
		framing_distance = value
		frame_board()


func _ready() -> void:
	frame_board()


## Places the camera back and above the board, looking at its centre.
## The height/distance ratios convert to an orbit pitch and distance, so the
## default view survives a change to BoardMesh's dimensions. Changing either
## export resets a user-moved camera back to this framing.
func frame_board() -> void:
	if camera == null:
		return
	var extent: float = BoardMesh.playing_half_extent() + BoardMesh.FRAME_MARGIN
	var pitch := rad_to_deg(atan2(framing_height, framing_distance))
	var orbit_distance := extent * Vector2(framing_distance, framing_height).length()
	camera.reset_view(Vector3.ZERO, 0.0, pitch, orbit_distance)
