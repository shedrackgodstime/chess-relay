class_name PieceMesh
extends RefCounted

## Turns a piece type and side into a single ArrayMesh.
##
## The lathed body carries most of the silhouette, but three pieces need extra
## geometry that a solid of revolution cannot express: the rook's merlons, the
## queen's crown points, and the king's cross. The knight instead replaces its
## top with an extruded head. Every part is merged into one surface so a piece
## stays a single MeshInstance3D with a single material.

const LIGHT_SIDE := 0
const DARK_SIDE := 1


## Builds the mesh for one piece. Returns an empty mesh for an unknown type.
static func build(type: int, side: int, segments: int = -1) -> ArrayMesh:
	var profile := PieceProfiles.profile(type)
	if profile.is_empty():
		return ArrayMesh.new()
	if segments < 0:
		segments = Quality.mesh_segments()

	var material := PieceMaterials.for_side(side)
	var builder := MeshBuilder.new()
	builder.add_part(Lathe.build(profile, segments), material)

	match type:
		PieceProfiles.Type.ROOK:
			_rook_details(builder, material)
		PieceProfiles.Type.QUEEN:
			_queen_details(builder, material)
		PieceProfiles.Type.KING:
			_king_details(builder, material)
		PieceProfiles.Type.KNIGHT:
			_knight_head(builder, material)

	return builder.build_merged(material)


## A ring of merlons around the rook's rim, which is what makes it read as a
## rook rather than a barrel. Sized and placed off the piece's own radius.
static func _rook_details(builder: MeshBuilder, material: Material) -> void:
	var radius := PieceProfiles.radius_for(PieceProfiles.Type.ROOK)
	var merlon := Primitives.box(Vector3(radius * 0.194, radius * 0.406, radius * 0.275))
	# The rim tops out at 0.676; the merlons sit on it.
	var placed := Primitives.ring(merlon, 6, radius * 0.766, 0.676 + radius * 0.203)
	builder.add_part(placed, material)


## Crown points around the queen's band. These, more than the profile, are what
## separate a queen from a king at a glance.
static func _queen_details(builder: MeshBuilder, material: Material) -> void:
	var radius := PieceProfiles.radius_for(PieceProfiles.Type.QUEEN)
	var point := Primitives.spike(radius * 0.079, radius * 0.258, 4)
	builder.add_part(Primitives.ring(point, 8, radius * 0.339, 0.782), material)


## The cross on top, built from two boxes.
static func _king_details(builder: MeshBuilder, material: Material) -> void:
	var radius := PieceProfiles.radius_for(PieceProfiles.Type.KING)
	var profile_top := 1.030
	var upright := Primitives.box(Vector3(radius * 0.171, radius * 0.765, radius * 0.171))
	builder.add_part(upright, material, Transform3D(Basis(), Vector3(0.0, profile_top + 0.130, 0.0)))
	var arm := Primitives.box(Vector3(radius * 0.441, radius * 0.162, radius * 0.171))
	builder.add_part(arm, material, Transform3D(Basis(), Vector3(0.0, profile_top + 0.170, 0.0)))


## The horse head, extruded and tipped forward a little so it reads as a
## knight from the usual three-quarter view.
static func _knight_head(builder: MeshBuilder, material: Material) -> void:
	var head := Extrude.build(
		PieceProfiles.KNIGHT_HEAD,
		PieceProfiles.KNIGHT_HEAD_HALF_DEPTH,
		PieceProfiles.KNIGHT_HEAD_TAPER,
		7,
		PieceProfiles.KNIGHT_HEAD_PIVOT
	)
	if head.is_empty():
		push_error("Knight head extrusion produced no geometry")
		return
	var tilt := Transform3D(
		Basis(Vector3.FORWARD, deg_to_rad(PieceProfiles.KNIGHT_HEAD_TILT_DEGREES))
	)
	tilt.origin = Vector3(0.0, PieceProfiles.KNIGHT_HEAD_HEIGHT, 0.0)
	builder.add_part(head, material, tilt)
