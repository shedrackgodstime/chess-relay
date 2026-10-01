class_name TableMesh
extends RefCounted

## The round table the board sits on, and the distant floor below it.
##
## The camera orbits 360 degrees, so anything with a wall or a corner would
## break as soon as the player spins past it. A round table reads correctly
## from every yaw, which makes it the one surrounding that stays believable
## while the view rotates. It is also a solid of revolution, so it reuses
## Lathe rather than needing new geometry code.
##
## The table top is placed just under the board's plinth so the board appears
## to rest on it, and the edge is chamfered so it catches a highlight rather
## than ending in a hard rim.

const RADIUS := 7.6
## Table top surface. BoardMesh's plinth bottom sits at
## -SQUARE_THICKNESS - PLINTH_DEPTH, so this must stay below that.
const TOP_Y := -0.34
const THICKNESS := 0.30
const EDGE_CHAMFER := 0.09

## Floor well below the table, only ever seen as the horizon.
const FLOOR_Y := -3.2
const FLOOR_SIZE := 80.0

const WOOD_BASE := Color(0.310, 0.196, 0.122)
const WOOD_VEIN := Color(0.170, 0.098, 0.058)
## Dark, but a warm brown rather than near-black: the floor has to read as part
## of a room, and a black floor takes the wood's palette down with it.
const FLOOR_COLOR := Color(0.150, 0.108, 0.082)

static var _cache := {}


static func build() -> ArrayMesh:
	# Profile runs bottom-centre outwards, up the chamfered edge, then back
	# in to the top centre, so the lathe produces a closed disc. The caps are
	# already part of the profile (poles at both ends), so none are added.
	var profile := PackedVector2Array([
		Vector2(0.0, TOP_Y - THICKNESS),
		Vector2(RADIUS - EDGE_CHAMFER, TOP_Y - THICKNESS),
		Vector2(RADIUS, TOP_Y - THICKNESS + EDGE_CHAMFER),
		Vector2(RADIUS, TOP_Y - EDGE_CHAMFER),
		Vector2(RADIUS - EDGE_CHAMFER * 0.6, TOP_Y),
		Vector2(0.0, TOP_Y),
	])
	# A wide disc needs more segments than a piece to keep the rim round.
	var builder := MeshBuilder.new()
	builder.add_part(Lathe.build(profile, Quality.mesh_segments() * 2, false, false), material())
	return builder.build()


static func material() -> StandardMaterial3D:
	if _cache.has("wood"):
		return _cache["wood"]
	var material := StandardMaterial3D.new()
	material.albedo_color = WOOD_BASE
	# Grain runs along the table: the lathe's V coordinate follows arc length,
	# which on a flat top is radial, so the texture is stretched wide.
	material.albedo_texture = TextureKit.wood(
		WOOD_BASE, WOOD_VEIN, 0.5, 71, Quality.texture_size()
	)
	material.uv1_scale = Vector3(3.0, 0.35, 1.0)
	material.roughness = 0.38
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	_cache["wood"] = material
	return material


static func floor_material() -> StandardMaterial3D:
	if _cache.has("floor"):
		return _cache["floor"]
	var material := StandardMaterial3D.new()
	material.albedo_color = FLOOR_COLOR
	material.roughness = 0.9
	material.metallic = 0.0
	_cache["floor"] = material
	return material


static func clear_cache() -> void:
	_cache.clear()
