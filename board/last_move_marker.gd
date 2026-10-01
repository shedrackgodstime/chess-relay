@tool
class_name LastMoveMarker
extends MeshInstance3D

## Marks the squares of the move just played: where it came from and where it
## went.
##
## Separate from the selection highlight rather than a second colour on it,
## because the two answer different questions. Selection says "this is the piece
## you are holding"; this says "this is what just happened", and it has to stay
## visible when nothing is selected at all, which is most of the time.
##
## Deliberately faint. It is reference, not emphasis: the board is the thing
## being looked at, and a strong marker on the last move competes with the
## pieces for attention every single turn.

const SIZE := 0.86
const HEIGHT := 0.006

## Warm amber, well below the selection highlight's brightness.
const TINT := Color(1.0, 0.76, 0.36, 0.30)

var _from_square := Vector2i(-1, -1)
var _to_square := Vector2i(-1, -1)
var _material: StandardMaterial3D


func _ready() -> void:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.albedo_color = TINT
		# Draw order matters: the pieces sit above y = 0 and this is a hair off
		# the squares, so it has to win against the board without poking through
		# anything.
		_material.no_depth_test = true
		_material.render_priority = 1
		material_override = _material
	_rebuild()


## Marks a move, or clears the marker when given nothing.
func show_move(from: Vector2i, to: Vector2i) -> void:
	_from_square = from
	_to_square = to
	_rebuild()


func hide_marker() -> void:
	_from_square = Vector2i(-1, -1)
	_to_square = Vector2i(-1, -1)
	_rebuild()


func marked_from() -> Vector2i:
	return _from_square


func marked_to() -> Vector2i:
	return _to_square


func is_marked() -> bool:
	return _from_square.x >= 0 and _to_square.x >= 0


## A flat quad sitting just above the playing surface.
func _rebuild() -> void:
	var data := MeshData.new()
	var half := BoardMesh.SQUARE_SIZE * SIZE * 0.5
	var y := BoardMesh.SQUARE_THICKNESS * 0.5 + 0.004
	for square in [_from_square, _to_square]:
		if square.x < 0:
			continue
		var centre := BoardMesh.square_position(square.x, square.y)
		var corners := [
			Vector3(centre.x - half, y, centre.z - half),
			Vector3(centre.x + half, y, centre.z - half),
			Vector3(centre.x + half, y, centre.z + half),
			Vector3(centre.x - half, y, centre.z + half),
		]
		var base := data.vertices.size()
		for corner: Vector3 in corners:
			data.vertices.append(corner)
			data.normals.append(Vector3.UP)
			data.uvs.append(Vector2(0.0, 0.0))
		data.indices.append_array([
			base, base + 2, base + 1,
			base, base + 3, base + 2,
		])
	if data.is_empty():
		mesh = null
		return
	var builder := MeshBuilder.new()
	builder.add_part(data)
	mesh = builder.build()