class_name RoomMesh
extends RefCounted

## The room the table stands in: a round shell with a floor, a skirting and a
## ceiling.
##
## Round on purpose. The camera orbits the board and pitches from 12 to 85
## degrees, and a square or rectangular room eventually shows a corner, then
## the seams where its walls meet. A cylinder has no corners to catch, and it
## matches the round table, so the geometry and the camera agree about where
## they are.
##
## Every part is lathed from a profile ordered so its normals face inward. That
## means the inside of the room is the shaded side, with no culling tricks and
## no risk of the walls rendering inside-out from one orbit angle.

## Far enough out that the wall is never between the camera and the table.
const RADIUS := 16.0

## Above the camera at its highest pitch, so a steep look-down never pokes
## through the ceiling.
const CEILING_Y := 13.0

const SKIRTING_HEIGHT := 0.55
const SKIRTING_PROUD := 0.10
const RAIL_HEIGHT := 6.4
const RAIL_PROUD := 0.06

## Warm plaster, light enough to read as a lit wall rather than a void. The
## room is scenery: it must not compete with the board for brightness.
const WALL_COLOR := Color(0.420, 0.360, 0.305)
const RAIL_COLOR := Color(0.330, 0.270, 0.225)
const CEILING_COLOR := Color(0.290, 0.262, 0.240)

static var _cache := {}


static func build_floor() -> ArrayMesh:
	if _cache.has("floor"):
		return _cache["floor"]
	# Traversed inwards, so the normal ends up pointing up.
	var builder := MeshBuilder.new()
	builder.add_part(Lathe.build(PackedVector2Array([
		Vector2(RADIUS, TableMesh.FLOOR_Y),
		Vector2(0.0, TableMesh.FLOOR_Y),
	]), Quality.mesh_segments(), false, false), TableMesh.floor_material())
	var mesh := builder.build()
	_cache["floor"] = mesh
	return mesh


static func build_wall() -> ArrayMesh:
	if _cache.has("wall"):
		return _cache["wall"]
	var builder := MeshBuilder.new()
	# Top to bottom, so the normal faces the room rather than the sky.
	var profile := PackedVector2Array([
		Vector2(RADIUS, CEILING_Y),
		Vector2(RADIUS, TableMesh.FLOOR_Y + SKIRTING_PROUD),
	])
	builder.add_part(Lathe.build(profile, Quality.mesh_segments(), false, false),
		wall_material())
	var mesh := builder.build()
	_cache["wall"] = mesh
	return mesh


## The baseboard. Purely a detail, but it gives the wall a floor line to sit
## against, without which the room reads as an untextured tube.
static func build_skirting() -> ArrayMesh:
	if _cache.has("skirting"):
		return _cache["skirting"]
	var builder := MeshBuilder.new()
	var inner := RADIUS - SKIRTING_PROUD
	var profile := PackedVector2Array([
		Vector2(RADIUS, TableMesh.FLOOR_Y + SKIRTING_HEIGHT),
		Vector2(inner, TableMesh.FLOOR_Y + SKIRTING_HEIGHT),
		Vector2(inner, TableMesh.FLOOR_Y),
	])
	# Reverse order to keep the visible faces pointing inwards.
	var flipped := PackedVector2Array([
		profile[2], profile[1], profile[0],
	])
	builder.add_part(Lathe.build(flipped, Quality.mesh_segments(), false, false),
		rail_material())
	var mesh := builder.build()
	_cache["skirting"] = mesh
	return mesh


static func build_rail() -> ArrayMesh:
	if _cache.has("rail"):
		return _cache["rail"]
	var builder := MeshBuilder.new()
	var profile := PackedVector2Array([
		Vector2(RADIUS - RAIL_PROUD, RAIL_HEIGHT + 0.14),
		Vector2(RADIUS - RAIL_PROUD, RAIL_HEIGHT - 0.14),
		Vector2(RADIUS, RAIL_HEIGHT - 0.14),
		Vector2(RADIUS, RAIL_HEIGHT + 0.14),
	])
	builder.add_part(Lathe.build(profile, Quality.mesh_segments(), false, false),
		rail_material())
	var mesh := builder.build()
	_cache["rail"] = mesh
	return mesh


static func build_ceiling() -> ArrayMesh:
	if _cache.has("ceiling"):
		return _cache["ceiling"]
	var builder := MeshBuilder.new()
	# Outwards from the centre, which turns the normal downwards into the room.
	builder.add_part(Lathe.build(PackedVector2Array([
		Vector2(0.0, CEILING_Y),
		Vector2(RADIUS, CEILING_Y),
	]), Quality.mesh_segments(), false, false), ceiling_material())
	var mesh := builder.build()
	_cache["ceiling"] = mesh
	return mesh


static func wall_material() -> StandardMaterial3D:
	if _cache.has("wall_mat"):
		return _cache["wall_mat"]
	var material := StandardMaterial3D.new()
	material.albedo_color = WALL_COLOR
	# Faint mottling so a large flat wall is not a dead colour field.
	material.albedo_texture = TextureKit.wood(WALL_COLOR, RAIL_COLOR, 0.5, 17,
		Quality.texture_size())
	material.uv1_scale = Vector3(6.0, 2.0, 1.0)
	material.roughness = 0.92
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	_cache["wall_mat"] = material
	return material


static func rail_material() -> StandardMaterial3D:
	if _cache.has("rail_mat"):
		return _cache["rail_mat"]
	var material := StandardMaterial3D.new()
	material.albedo_color = RAIL_COLOR
	material.roughness = 0.7
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	_cache["rail_mat"] = material
	return material


static func ceiling_material() -> StandardMaterial3D:
	if _cache.has("ceiling_mat"):
		return _cache["ceiling_mat"]
	var material := StandardMaterial3D.new()
	material.albedo_color = CEILING_COLOR
	material.roughness = 0.95
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	_cache["ceiling_mat"] = material
	return material


static func clear_cache() -> void:
	_cache.clear()
