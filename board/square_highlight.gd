@tool
class_name SquareHighlight
extends MeshInstance3D

## Flat emissive frame marking the selected square.
##
## A frame rather than a filled quad, so the square's wood grain stays visible
## underneath. Emissive so it reads identically under any light. Generated in
## _ready like every other procedural mesh here, which keeps it out of the
## .tscn; Main moves and toggles it.

const OUTER := 0.94
const BAR := 0.11
const HEIGHT := 0.014
const LIFT := 0.008


func _ready() -> void:
	mesh = build_mesh()
	visible = false


## Builds the frame mesh. Static so tests can inspect it without a node.
static func build_mesh() -> ArrayMesh:
	var half := OUTER * 0.5
	var builder := MeshBuilder.new()
	for xform in [
		Transform3D(Basis(), Vector3(0.0, 0.0, -half + BAR * 0.5)),
		Transform3D(Basis(), Vector3(0.0, 0.0, half - BAR * 0.5)),
		Transform3D(Basis(), Vector3(-half + BAR * 0.5, 0.0, 0.0)),
		Transform3D(Basis(), Vector3(half - BAR * 0.5, 0.0, 0.0)),
	]:
		var horizontal := absf(xform.origin.z) > 0.0
		var size := Vector3(OUTER, HEIGHT, BAR) if horizontal else Vector3(BAR, HEIGHT, OUTER)
		builder.add_part(Primitives.box(size), null, xform)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.85, 0.25)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.80, 0.20)
	material.emission_energy_multiplier = 1.6
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return builder.build_merged(material)


## Moves the frame onto a square and shows it.
func show_at(file: int, rank: int) -> void:
	position = BoardMesh.square_position(file, rank) + Vector3(0.0, LIFT, 0.0)
	visible = true


func hide_marker() -> void:
	visible = false
