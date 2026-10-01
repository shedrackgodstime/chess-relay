@tool
class_name RoomView
extends Node3D

## The round room the table sits in.
##
## Replaces the open-sky void. Everything about the shape is driven by two
## constraints the camera imposes: it orbits, so the room must have no corners,
## and it can pitch from near-level to near-vertical, so the room must close
## over the top and stay outboard at every reach. Both are asserted in the
## tests rather than assumed, since a change to either would put the camera
## outside its own room.

static var _built := false


func _ready() -> void:
	if _built:
		return
	_built = true
	# Floor first: the old open plane extended past the wall and would have
	# poked through it.
	for part in [
		["Floor", RoomMesh.build_floor()],
		["Skirting", RoomMesh.build_skirting()],
		["Wall", RoomMesh.build_wall()],
		["Rail", RoomMesh.build_rail()],
		["Ceiling", RoomMesh.build_ceiling()],
	]:
		_add(part[0], part[1])


## Nothing in the room casts, and only the wall receives. The shell encloses
## everything the key light can reach, so casting from it would only cost
## shadow-map work for surfaces nothing can see.
func _add(part_name: String, mesh: ArrayMesh) -> void:
	var node := MeshInstance3D.new()
	node.name = part_name
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
