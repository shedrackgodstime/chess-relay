@tool
class_name StudioView
extends Node3D

## The room the table sits in: a backdrop dome and the lamp above it.
##
## The scene used to be an open blue sky over a flat grey plane, which lit
## everything evenly from every direction. The board was as bright as the floor
## and the whole thing read as unfinished. This inverts it: one warm lamp over
## the table, and everything past the table edge falling away into darkness.
##
## The dome exists because the camera can pitch down to 12 degrees, nearly
## level with the table. Without something enclosing the scene, that shows the
## floor's own edge as a hard line against the sky. A dome plus fog means the
## floor fades into the backdrop instead of stopping.
##
## A lit room with walls would be the other option and was rejected: the camera
## orbits, so any enclosing geometry eventually shows its corners and the seams
## between them. Darkness has no corners.

## Well beyond the camera's furthest reach (20 units) and the floor's own
## extent, so nothing can ever see past it.
const DOME_RADIUS := 60.0

## Height of the lamp above the table surface.
const LAMP_HEIGHT := 5.6

## Slightly behind the board centre, so pieces get a rim rather than light
## straight down the top of their heads.
const LAMP_OFFSET := Vector3(-1.1, 0.0, -0.8)

const LAMP_ANGLE_DEGREES := 58.0
const LAMP_RANGE := 18.0

## Warm, matching the amber the HUD already uses.
const LAMP_COLOR := Color(1.0, 0.905, 0.775)

## Spot energy runs on a different scale to a directional light, and there is
## no headless way to check how bright this actually looks. Kept as named
## constants rather than buried so it is one edit to tune on a device.
const LAMP_ENERGY := 26.0

## Cool fill so the shaded sides of pieces are not solid black. Deliberately
## dim: it separates silhouettes, it does not light the room.
const FILL_ENERGY := 0.55
const FILL_COLOR := Color(0.700, 0.790, 1.0)

## Dark enough that the floor never competes with the board, warm enough not to
## read as pure black on cheap phone panels.
## A dark room floor, but still a warm brown. Near-black was tried and reads as
## a hole rather than a floor, and takes the wood's palette with it.
const FLOOR_COLOR := Color(0.090, 0.064, 0.050)

## The dome is unlit on purpose. A shaded sphere would pick up the lamp and
## glow, which is the opposite of receding.
const DOME_COLOR := Color(0.105, 0.092, 0.088)
const FOG_COLOR := Color(0.105, 0.092, 0.088)
const FOG_DENSITY := 0.018

## Warm and bright enough that materials keep their own colour. Ambient is what
## a surface facing away from the lamp sees, and starving it is what turned the
## wood and the board's two square tones into flat grey.
const AMBIENT_COLOR := Color(0.300, 0.255, 0.225)
const AMBIENT_ENERGY := 1.05

## Filmic tonemap crushes saturation in the shadows, which is most of this
## scene, so exposure is pulled up to put the colour back.
const EXPOSURE := 1.30


func _ready() -> void:
	if get_node_or_null("Dome") == null:
		_build()


func _build() -> void:
	var dome := MeshInstance3D.new()
	dome.name = "Dome"
	dome.mesh = _dome_mesh()
	dome.material_override = dome_material()
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dome)

	var lamp := SpotLight3D.new()
	lamp.name = "Lamp"
	lamp.position = LAMP_OFFSET + Vector3.UP * LAMP_HEIGHT
	# The basis is built by hand rather than with look_at: look_at depends on the
	# node already being in the tree with a final global transform, which is not
	# guaranteed while a scene is still being constructed. A spot emits along
	# its local -Z, so that axis is aimed at the table centre directly.
	_aim_at_origin(lamp)
	lamp.light_color = LAMP_COLOR
	lamp.light_energy = LAMP_ENERGY
	lamp.spot_range = LAMP_RANGE
	lamp.spot_angle = deg_to_rad(LAMP_ANGLE_DEGREES)
	lamp.spot_angle_attenuation = 0.7
	lamp.shadow_enabled = true
	lamp.shadow_bias = 0.04
	lamp.shadow_normal_bias = 1.6
	add_child(lamp)

	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = FILL_COLOR
	fill.light_energy = FILL_ENERGY
	fill.shadow_enabled = false
	add_child(fill)


## Rotates a node so its local -Z points at the origin.
static func _aim_at_origin(node: Node3D) -> void:
	var forward := (-node.position).normalized()
	# The basis Z axis is the reverse of the emission direction, because a spot
	# lights along local -Z. Putting forward in Z instead aims it backwards.
	var z := -forward
	var up := Vector3.UP
	if absf(z.dot(up)) > 0.999:
		up = Vector3.FORWARD
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	node.basis = Basis(x, y, z)


func _dome_mesh() -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = DOME_RADIUS
	mesh.height = DOME_RADIUS * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	mesh.is_hemisphere = false
	# Inside faces: the camera is always within the dome.
	mesh.flip_faces = true
	return mesh


func dome_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = DOME_COLOR
	# The constant is 0 in this engine's enum, so reading shading_mode back as
	# 0 does mean unshaded. Verified rather than assumed, after mistaking the
	# value for the opposite once.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	return material


## Applied to the shared WorldEnvironment. Kept here rather than in the scene
## builder because these values only make sense together with the lamp.
static func apply_to(env: Environment) -> void:
	env.background_mode = Environment.BG_COLOR
	env.background_color = DOME_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT_COLOR
	env.ambient_light_energy = AMBIENT_ENERGY
	# Irrelevant with a colour source, but left at 1.0 it looks like the sky is
	# still driving the light when reading the environment back.
	env.ambient_light_sky_contribution = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = EXPOSURE
	# Fog is what actually sells the falloff: without it the floor ends in a
	# visible edge, and with it the floor simply gets further away.
	env.fog_enabled = true
	env.fog_light_color = FOG_COLOR
	env.fog_density = FOG_DENSITY
	env.fog_sky_affect = 0.0
