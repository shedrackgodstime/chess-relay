class_name TrayMesh
extends RefCounted

## Geometry for a capture tray: a shallow moulded slab with a lip and a marked
## well at every slot.
##
## Modelled in local space with the tray centred on the origin and its long axis
## along Z, standing on y = 0, so TrayView can place it on the table with a
## single position.
##
## The wells are inlays rather than cut-outs. Sinking a disc into a solid slab
## needs either CSG or a modelled channel across the whole face, and an inlay
## sitting a hair proud of the surface reads as a slot at this scale for a
## fraction of the geometry. The lift is deliberate: flush would z-fight.

## Maximum pieces one side can lose, and therefore the slot count.
const SLOTS := 16

## Distance between slot centres.
const SLOT_SPACING := 0.5

const WIDTH := 1.08
const HEIGHT := 0.085
const LIP_HEIGHT := 0.055
const LIP_WIDTH := 0.085
const WELL_RADIUS := 0.185
const INLAY_LIFT := 0.003
const BEVEL := 0.012

## Board-like dark composite for the body, and a darker one for the wells so
## each slot reads even before a piece is standing in it.
const BODY_COLOR := Color(0.128, 0.118, 0.112)
const WELL_COLOR := Color(0.062, 0.056, 0.052)
const EDGE_COLOR := Color(0.30, 0.27, 0.24)

const LENGTH := SLOT_SPACING * float(SLOTS - 1) + 1.05

## Distance from the board centre to a tray's centre line. The board's playing
## half-extent is 4.0 and its frame adds 0.38, so this leaves a clear gap
## between frame and tray while staying inside the table's 7.6 radius.
const TRAY_X := 5.45

static var _cache := {}


## World-space offset of a slot within the tray, for slot 0 through SLOTS-1.
## Slot 0 sits at the -Z end, which is where the first captured piece goes.
static func slot_position(index: int) -> Vector3:
	var centre := float(SLOTS - 1) * 0.5
	return Vector3(0.0, HEIGHT + INLAY_LIFT, (float(index) - centre) * SLOT_SPACING)


static func build() -> ArrayMesh:
	if _cache.has("body"):
		return _cache["body"]
	var builder := MeshBuilder.new()
	builder.add_part(Primitives.beveled_box(Vector3(WIDTH, HEIGHT, LENGTH), BEVEL),
		body_material())
	# Raised rails down both long edges, so the tray has a rim to read against
	# rather than looking like a tile.
	for side in [-1.0, 1.0]:
		var rail := Primitives.beveled_box(
			Vector3(LIP_WIDTH, LIP_HEIGHT, LENGTH), BEVEL * 0.8
		)
		builder.add_part(rail, body_material(), Transform3D(
			Basis.IDENTITY,
			Vector3(side * (WIDTH * 0.5 - LIP_WIDTH * 0.5), HEIGHT * 0.5 + LIP_HEIGHT * 0.5, 0.0)
		))
	var mesh := builder.build()
	_cache["body"] = mesh
	return mesh


## The slot wells, in a second surface so they can be a darker material.
static func build_wells() -> ArrayMesh:
	if _cache.has("wells"):
		return _cache["wells"]
	var disc := Lathe.build(PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(WELL_RADIUS, 0.0),
		Vector2(WELL_RADIUS, 0.004),
		Vector2(0.0, 0.004),
	]), Quality.mesh_segments(), false, false)
	var builder := MeshBuilder.new()
	for i in SLOTS:
		builder.add_part(disc, well_material(),
			Transform3D(Basis.IDENTITY, slot_position(i)))
	var mesh := builder.build()
	_cache["wells"] = mesh
	return mesh


static func body_material() -> StandardMaterial3D:
	if _cache.has("body_mat"):
		return _cache["body_mat"]
	var material := StandardMaterial3D.new()
	material.albedo_color = BODY_COLOR
	material.albedo_texture = TextureKit.wood(
		BODY_COLOR, EDGE_COLOR, 0.42, 53, Quality.texture_size()
	)
	material.uv1_scale = Vector3(1.4, 3.2, 1.0)
	material.roughness = 0.46
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	_cache["body_mat"] = material
	return material


static func well_material() -> StandardMaterial3D:
	if _cache.has("well_mat"):
		return _cache["well_mat"]
	var material := StandardMaterial3D.new()
	material.albedo_color = WELL_COLOR
	material.roughness = 0.62
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	_cache["well_mat"] = material
	return material


static func clear_cache() -> void:
	_cache.clear()
