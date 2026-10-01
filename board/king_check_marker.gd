@tool
class_name KingCheckMarker
extends Node3D

## Marks the square of a king that is in check.
##
## Deliberately the opposite treatment to the last-move marker. That one is
## reference and stays faint; this one is a warning and has to be impossible to
## miss, because "my king is attacked" changes what every legal move means and
## the player may not have registered that it happened.
##
## Two parts so the shape reads at a glance from the game's camera pitch: a
## wash over the square, and a brighter border around it. The border is what
## makes it legible when a piece is standing on the square, since the wash alone
## is behind the piece.
##
## Pulses slowly. Static red would sit there and be filtered out within a few
## turns; a slow breath keeps pulling the eye back without becoming a distraction
## the way a fast blink would.

const SIZE := 0.98
const HEIGHT := 0.009
const BORDER := 0.085

const FILL_COLOR := Color(0.94, 0.20, 0.14)
const BORDER_COLOR := Color(1.0, 0.44, 0.20)

## Seconds for one full pulse, in and back out.
const PULSE_SECONDS := 1.20

## How low the pulse goes, as a fraction of full strength.
const PULSE_FLOOR := 0.55

var _fill: MeshInstance3D
var _border: MeshInstance3D
var _phase := 0.0
var _active := false


func _ready() -> void:
	if _fill == null:
		_build()
	set_process(false)


func _build() -> void:
	_fill = _add_quad(SIZE, FILL_COLOR, "Fill")
	_border = _add_quad(SIZE, BORDER_COLOR, "Border")
	# A ring, not a square: the middle is transparent so the king stays visible.
	_border.mesh = _ring_mesh(SIZE, BORDER)
	hide_marker()


func _add_quad(size: float, colour: Color, part_name: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = part_name
	node.mesh = _square_mesh(size)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Above the squares but behind the pieces standing on them.
	material.no_depth_test = true
	material.render_priority = 2
	node.material_override = material
	add_child(node)
	return node


## Marks the given square, or clears the marker for a negative one.
func show_at(file: int, rank: int) -> void:
	if _fill == null:
		_build()
	visible = true
	position = BoardMesh.square_position(file, rank)
	_phase = 0.0
	_active = true
	set_process(true)
	_apply()


func hide_marker() -> void:
	_active = false
	set_process(false)
	visible = false


func is_marked() -> bool:
	return _active


## The square the marker is on, or (-1, -1).
func marked_square() -> Vector2i:
	if not _active:
		return Vector2i(-1, -1)
	var file := int(round(position.x + (BoardMesh.SQUARES - 1) * 0.5))
	var rank := int(round(position.z + (BoardMesh.SQUARES - 1) * 0.5))
	return Vector2i(file, rank)


func _process(delta: float) -> void:
	if not _active:
		return
	_phase = fmod(_phase + delta / PULSE_SECONDS, 1.0)
	_apply()


func _apply() -> void:
	# A sine rather than a triangle so the easing is smooth at both ends, which is
	# where a pulse stops reading as a flash.
	var wave := 0.5 - 0.5 * cos(_phase * TAU)
	var strength := lerpf(PULSE_FLOOR, 1.0, wave)
	_fill.material_override.albedo_color = Color(
		FILL_COLOR.r, FILL_COLOR.g, FILL_COLOR.b, FILL_COLOR.a * strength)
	_border.material_override.albedo_color = Color(
		BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, BORDER_COLOR.a * strength)


func _square_mesh(size: float) -> ArrayMesh:
	var half := BoardMesh.SQUARE_SIZE * size * 0.5
	return _to_mesh(_quad_data(-half, half, -half, half))


## Four thin quads forming the border, leaving the middle open.
func _ring_mesh(size: float, thickness: float) -> ArrayMesh:
	var outer := BoardMesh.SQUARE_SIZE * size * 0.5
	var inner := outer - BoardMesh.SQUARE_SIZE * thickness
	# One builder for all four, so the border is a single surface.
	var builder := MeshBuilder.new()
	builder.add_part(_quad_data(-outer, outer, -outer, -inner))
	builder.add_part(_quad_data(-outer, outer, inner, outer))
	builder.add_part(_quad_data(-outer, -inner, -outer, outer))
	builder.add_part(_quad_data(inner, outer, -outer, outer))
	return builder.build()


## Geometry as data, so the ring can merge four of these into one surface.
func _quad_data(x0: float, x1: float, z0: float, z1: float) -> MeshData:
	var data := MeshData.new()
	var corners := [
		Vector3(x0, HEIGHT, z0),
		Vector3(x1, HEIGHT, z0),
		Vector3(x1, HEIGHT, z1),
		Vector3(x0, HEIGHT, z1),
	]
	for corner: Vector3 in corners:
		data.vertices.append(corner)
		data.normals.append(Vector3.UP)
		data.uvs.append(Vector2(0.0, 0.0))
	data.indices.append_array([0, 2, 1, 0, 3, 2])
	return data


## Wraps geometry data into a single-surface mesh.
static func _to_mesh(data: MeshData) -> ArrayMesh:
	var builder := MeshBuilder.new()
	builder.add_part(data)
	return builder.build()