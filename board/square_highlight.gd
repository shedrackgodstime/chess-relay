@tool
class_name SquareHighlight
extends MeshInstance3D

## Flat emissive frame marking a square.
##
## A frame rather than a filled quad, so the square's wood grain stays visible
## underneath. Emissive so it reads identically under any light. Generated in
## _ready like every other procedural mesh here, which keeps it out of the
## .tscn; Main moves and toggles it.
##
## Four colours on one marker, and that is as many as this board should carry:
## from, to, selection, check. What keeps it readable is not the hue but the
## brightness. The selection frame is the brightest thing on the board, the
## check frame is strong, the arrival is middling and the departure is faint. Hue
## only adds to that, so a player who cannot separate two colours still reads the
## right thing from how loud each one is.

const OUTER := 0.94

## Thickness of each side of the frame, as a fraction of the square. Thinner than
## it was: at 0.11 the frame read as a box drawn around the square rather than a
## highlight laid over it.
const BAR := 0.07
const HEIGHT := 0.014
const LIFT := 0.008

## The last move, in two hues so the direction reads at a glance without
## inferring which square the piece came from.
##
## Blue for where it left, green for where it arrived. Both deliberately far
## from the gold of the selection frame, so holding a piece never looks like
## the same thing as the move that just happened.
const LAST_MOVE_FROM := Color(0.42, 0.58, 1.0, 0.40)
const LAST_MOVE_TO := Color(0.38, 0.94, 0.54, 0.58)

## Selection: the warm gold used throughout the HUD.
const GOLD := Color(1.0, 0.85, 0.25)

## Legal destinations, in two brightnesses of one hue rather than two shapes.
##
## The board already commits to one frame that the player learns once, so a dot
## for an ordinary move and a ring for a capture would spend that. What
## distinguishes a capture is urgency, and urgency has already been given to
## brightness throughout: a square you can take is louder than a square you can
## only step to. Deliberately cool and far from the gold of the selection, so a
## marked destination never looks like something selected.
const LEGAL := Color(0.52, 0.70, 0.96, 0.26)
const LEGAL_CAPTURE := Color(0.66, 0.88, 1.0, 0.78)

## Check: same frame, red. Bright enough to read against the warm wood, which a
## duller red would not be.
const RED := Color(1.0, 0.27, 0.20)

## The colour this frame is drawn in. Assigning rebuilds, since the colour is
## baked into the merged surface.
@export var colour: Color = GOLD:
	set(value):
		if is_equal_approx(value.r, colour.r) and is_equal_approx(value.g, colour.g) \
				and is_equal_approx(value.b, colour.b):
			return
		colour = value
		if is_inside_tree():
			mesh = build_mesh(colour)


func _ready() -> void:
	mesh = build_mesh(colour)
	visible = false


## Builds the frame mesh. Static so tests can inspect it without a node.
static func build_mesh(tint: Color = GOLD) -> ArrayMesh:
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
	material.albedo_color = tint
	material.emission_enabled = true
	# The emission follows the albedo, so a red frame glows red rather than
	# glowing the same gold the selection does.
	material.emission = Color(tint.r * 0.8, tint.g * 0.8, tint.b * 0.8)
	material.emission_energy_multiplier = 1.6
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return builder.build_merged(material)


## The square this frame is on, or (-1, -1) when it is not showing.
func marked_square() -> Vector2i:
	if not visible:
		return Vector2i(-1, -1)
	var half := (BoardMesh.SQUARES - 1) * 0.5
	return Vector2i(
		int(round(position.x + half)),
		int(round(position.z + half))
	)


## Moves the frame onto a square and shows it.
func show_at(file: int, rank: int) -> void:
	position = BoardMesh.square_position(file, rank) + Vector3(0.0, LIFT, 0.0)
	visible = true


func hide_marker() -> void:
	visible = false
