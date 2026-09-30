extends SceneTree

## Renders the procedural board and pieces to a PNG without a GPU.
##
## There is no display or renderer available in this environment, so the
## geometry is rasterised on the CPU. That makes the visuals reviewable: run
## this, open the PNG, and judge the shapes. It is a development tool and is
## not used by the game.
##
##     godot-headless --headless --script res://tools/render_preview.gd -- board
##     godot-headless --headless --script res://tools/render_preview.gd -- pieces
##
## "board" renders res://main.tscn through its own camera. "pieces" lines the
## six piece types up side by side, which is the view to use when tuning the
## profiles in PieceProfiles.

const WIDTH := 640
const HEIGHT := 480

const OUT_DIR := "user://"

## Light direction in world space, pointing from the light towards the scene.
const LIGHT_DIR := Vector3(-0.40, -0.72, -0.57)
const AMBIENT := 0.40
const KEY := 0.85
const FILL := 0.28
const FILL_DIR := Vector3(0.65, -0.35, -0.30)
const BACKGROUND := Color(0.13, 0.15, 0.18)


var _started := false


## _init runs before the tree is ready, so the work is deferred to the first
## frame; nodes added to root() are only inside the tree by then.
func _process(_delta: float) -> bool:
	if _started:
		return true
	_started = true
	_run()
	return true


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() > 0 else "board"
	var out := args[1] if args.size() > 1 else ("preview_%s.png" % mode)

	var draws: Array = []
	var camera: Camera3D
	match mode:
		"pieces":
			camera = _lineup_camera()
			draws = _lineup_draws()
		_:
			camera = _scene_camera()
			draws = _scene_draws()

	if camera == null:
		printerr("no camera available for mode '%s'" % mode)
		quit(1)
		return

	var image := _rasterise(camera, draws)
	_verify_culling()
	var path := ProjectSettings.globalize_path(OUT_DIR + out)
	var err := image.save_png(path)
	if err != OK:
		printerr("could not write %s: %d" % [path, err])
		quit(1)
		return
	print("Wrote %s (%dx%d, %d draws)" % [path, WIDTH, HEIGHT, draws.size()])
	quit(0)


## One draw call's worth of geometry: world-space positions, normals, indices
## and colour. Indices are kept because the generators share vertices between
## adjacent triangles, so a sequential fallback would produce the wrong mesh.
class Draw:
	extends RefCounted
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var colour := Color.WHITE
	var texture: Image = null


func _collect(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		var mesh := instance.mesh
		if mesh != null:
			var xform := instance.global_transform
			var override := instance.material_override
			for surface in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				if vertices.is_empty() or indices.is_empty():
					continue
				var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				var draw := Draw.new()
				var shading := _surface_shading(mesh, surface, override)
				draw.colour = shading[0]
				draw.texture = shading[1]
				draw.indices.append_array(indices)
				for v in vertices:
					draw.positions.append(xform * v)
				for n in normals:
					draw.normals.append((xform.basis * n).normalized())
				draw.uvs.append_array(uvs)
				out.append(draw)
	for child in node.get_children():
		_collect(child, out)


## Base tint plus the albedo texture image, so the preview shows the wood
## grain and not just flat colours. Returns [colour, texture-or-null].
func _surface_shading(mesh: Mesh, surface: int, override: Material) -> Array:
	var material := override if override != null else mesh.surface_get_material(surface)
	if material is StandardMaterial3D:
		var standard := material as StandardMaterial3D
		var image: Image = null
		if standard.albedo_texture is ImageTexture:
			image = (standard.albedo_texture as ImageTexture).get_image()
		return [standard.albedo_color, image]
	return [Color(0.8, 0.8, 0.8), null]


func _scene_draws() -> Array:
	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		printerr("could not load res://main.tscn")
		return []
	var scene := packed.instantiate()
	# The view scripts build their meshes in _ready, so the node has to be in
	# a tree before the geometry can be collected.
	root.add_child(scene)
	var draws: Array = []
	_collect(scene, draws)
	return draws


func _scene_camera() -> Camera3D:
	var scene := load("res://main.tscn") as PackedScene
	if scene == null:
		return null
	var instance := scene.instantiate()
	root.add_child(instance)
	return instance.get_node_or_null("World/Camera") as Camera3D


## Lays the six pieces out in a row, all facing the camera, for silhouette
## comparison. Independent of the main scene so profiles can be judged alone.
func _lineup_draws() -> Array:
	var draws: Array = []
	var types := [
		PieceProfiles.Type.PAWN, PieceProfiles.Type.KNIGHT, PieceProfiles.Type.BISHOP,
		PieceProfiles.Type.ROOK, PieceProfiles.Type.QUEEN, PieceProfiles.Type.KING,
	]
	var spacing := 0.95
	for i in types.size():
		var type: int = types[i]
		# Only the light set here: two rows of pieces read as one plus a
		# smudge. Use the board preview to judge the two-tone read.
		for side in [PieceMesh.LIGHT_SIDE]:
			var mesh := PieceMesh.build(type, side)
			var x := (i - (types.size() - 1) * 0.5) * spacing
			var y := 0.0 if side == PieceMesh.LIGHT_SIDE else 0.0
			# The dark set stands a row behind the light one.
			var offset := Vector3(0.0, 0.0, -0.85) if side == PieceMesh.DARK_SIDE else Vector3.ZERO
			_collect_mesh(mesh, Transform3D(Basis(), Vector3(x, y, 0.0) + offset),
				PieceProfiles.color_for(side), draws)
	return draws


func _lineup_camera() -> Camera3D:
	var camera := Camera3D.new()
	camera.fov = 50.0
	camera.far = 100.0
	root.add_child(camera)
	camera.look_at_from_position(
		Vector3(0.0, 1.35, 6.2), Vector3(0.0, 0.48, -0.15), Vector3.UP
	)
	return camera


func _collect_mesh(mesh: Mesh, xform: Transform3D, tint: Color, out: Array) -> void:
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if vertices.is_empty() or indices.is_empty():
			continue
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var draw := Draw.new()
		var shading := _surface_shading(mesh, surface, null)
		draw.colour = shading[0]
		draw.texture = shading[1]
		draw.indices.append_array(indices)
		for v in vertices:
			draw.positions.append(xform * v)
		for n in normals:
			draw.normals.append((xform.basis * n).normalized())
		draw.uvs.append_array(uvs)
		out.append(draw)


## Confirms the culling convention against the engine rather than trusting
## the sign convention above.
##
## Lathe and Extrude wind their triangles the Godot way, with the
## right-hand-rule normal opposing the stored vertex normals. The winding
## conformance checks in the test suite guard that; this probe guards the
## rasteriser's own culling independently. A single camera-facing triangle
## settles it: only the correct convention keeps it.
func _verify_culling() -> void:
	var probe := Draw.new()
	# Wound so the right-hand normal points at a camera on -Z looking towards
	# +Z, which is how the preview cameras are set up.
	probe.positions = PackedVector3Array([
		Vector3(-0.5, -0.5, 0.0), Vector3(0.5, -0.5, 0.0), Vector3(0.0, 0.5, 0.0)
	])
	probe.normals = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	probe.indices = PackedInt32Array([0, 1, 2])
	probe.colour = Color.WHITE

	var camera := Camera3D.new()
	camera.fov = 60.0
	root.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 0.0, -3.0), Vector3.ZERO, Vector3.UP)
	camera.force_update_transform()

	var kept := 0
	for sign_dir in [-1.0, 1.0]:
		_RASTER_CULL_SIGN = sign_dir
		var image := _rasterise(camera, [probe])
		var lit := 0
		for y in HEIGHT:
			for x in WIDTH:
				if image.get_pixel(x, y) != BACKGROUND:
					lit += 1
		if sign_dir < 0.0:
			kept = lit
	_RASTER_CULL_SIGN = -1.0
	if kept > 0:
		print("culling: front face is clockwise on screen (as expected)")
	else:
		printerr("culling: front face is counter-clockwise; flip _RASTER_CULL_SIGN")


## Screen-space signed area is positive for one winding and negative for the
## other. Godot's documented front face is clockwise on screen, and screen Y
## grows downwards, so front faces land on a negative area.
var _RASTER_CULL_SIGN := -1.0


func _rasterise(camera: Camera3D, draws: Array) -> Image:
	var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGB8)
	image.fill(BACKGROUND)

	# 1/z buffer: larger is nearer, so a new fragment must be strictly greater.
	var depth := PackedFloat32Array()
	depth.resize(WIDTH * HEIGHT)
	depth.fill(0.0)

	camera.force_update_transform()
	var view := camera.global_transform.affine_inverse()
	var aspect := float(WIDTH) / float(HEIGHT)
	var tan_half := tan(deg_to_rad(camera.fov) * 0.5)
	var near := camera.near
	var stats := {"tris": 0, "drawn": 0, "culled": 0, "clipped": 0}

	for draw in draws:
		var positions: PackedVector3Array = draw.positions
		var normals: PackedVector3Array = draw.normals
		var uvs: PackedVector2Array = draw.uvs
		var indices: PackedInt32Array = draw.indices
		for i in range(0, indices.size(), 3):
			stats["tris"] += 1
			var ia: int = indices[i]
			var ib: int = indices[i + 1]
			var ic: int = indices[i + 2]
			var a := view * positions[ia]
			var b := view * positions[ib]
			var c := view * positions[ic]

			# Anything crossing the near plane is dropped rather than clipped;
			# the camera framing keeps that from mattering here.
			if a.z > -near or b.z > -near or c.z > -near:
				stats["clipped"] += 1
				continue

			var sa := _project(a, aspect, tan_half)
			var sb := _project(b, aspect, tan_half)
			var sc := _project(c, aspect, tan_half)

			# Signed area in screen space. Godot treats clockwise winding as the
			# front face, so a front-facing triangle has negative area here
			# because screen Y grows downwards.
			var area := (sb.x - sa.x) * (sc.y - sa.y) - (sc.x - sa.x) * (sb.y - sa.y)
			if area * _RASTER_CULL_SIGN >= 0.0:
				stats["culled"] += 1
				continue
			stats["drawn"] += 1
			var ua := _draw_uv(uvs, ia)
			var ub := _draw_uv(uvs, ib)
			var uc := _draw_uv(uvs, ic)
			_raster_triangle(image, depth, sa, sb, sc, ua, ub, uc,
				_face_normal(normals, ia, ib, ic), draw.colour, draw.texture)

	print("tris=%d drawn=%d culled=%d clipped=%d" % [
		stats["tris"], stats["drawn"], stats["culled"], stats["clipped"]
	])
	return image


## UV for one corner, defaulting to the origin when a surface carries none.
func _draw_uv(uvs: PackedVector2Array, index: int) -> Vector2:
	if uvs.size() > index:
		return uvs[index]
	return Vector2.ZERO


## Average of the three vertex normals, already in world space. Returns the
## outward-facing direction so back faces stay dark.
func _face_normal(normals: PackedVector3Array, ia: int, ib: int, ic: int) -> Vector3:
	var n := normals[ia] + normals[ib] + normals[ic]
	if n.length_squared() < 1e-12:
		return Vector3.UP
	return n.normalized()


## Projects a view-space point to screen pixels, with Y flipped because screen
## rows grow downwards. 1/z is carried for perspective-correct depth.
func _project(p: Vector3, aspect: float, tan_half: float) -> Vector3:
	var z := -p.z
	var ndc_x := (p.x / z) / (aspect * tan_half)
	var ndc_y := (p.y / z) / tan_half
	return Vector3(
		(ndc_x * 0.5 + 0.5) * WIDTH,
		(1.0 - (ndc_y * 0.5 + 0.5)) * HEIGHT,
		1.0 / z
	)


func _raster_triangle(
	image: Image,
	depth: PackedFloat32Array,
	sa: Vector3, sb: Vector3, sc: Vector3,
	ua: Vector2, ub: Vector2, uc: Vector2,
	normal: Vector3, tint: Color, texture: Image
) -> void:
	var min_x := maxi(0, int(floor(minf(sa.x, minf(sb.x, sc.x)))))
	var max_x := mini(WIDTH - 1, int(ceil(maxf(sa.x, maxf(sb.x, sc.x)))))
	var min_y := maxi(0, int(floor(minf(sa.y, minf(sb.y, sc.y)))))
	var max_y := mini(HEIGHT - 1, int(ceil(maxf(sa.y, maxf(sb.y, sc.y)))))
	if min_x > max_x or min_y > max_y:
		return

	var area := (sb.x - sa.x) * (sc.y - sa.y) - (sc.x - sa.x) * (sb.y - sa.y)
	if is_zero_approx(area):
		return
	var inv_area := 1.0 / area

	var tex_w := 0
	var tex_h := 0
	if texture != null:
		tex_w = texture.get_width()
		tex_h = texture.get_height()

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			# These edge functions give the barycentric weight of the vertex
			# OPPOSITE each edge, so w0 is c's weight, w1 is b's, and w2 is
			# a's. Pairing them with the wrong vertex inverts the depth
			# interpolation, which lets large triangles occlude what is in
			# front of them.
			var w0 := ((sb.x - sa.x) * (p.y - sa.y) - (p.x - sa.x) * (sb.y - sa.y)) * inv_area
			var w1 := ((p.x - sa.x) * (sc.y - sa.y) - (sc.x - sa.x) * (p.y - sa.y)) * inv_area
			var w2 := 1.0 - w0 - w1
			if w0 < 0.0 or w1 < 0.0 or w2 < 0.0:
				continue
			var inv_z := sa.z * w2 + sb.z * w1 + sc.z * w0
			if inv_z <= 0.0:
				continue
			var offset := y * WIDTH + x
			if inv_z <= depth[offset]:
				continue
			depth[offset] = inv_z
			# Perspective-correct UV: interpolate uv/z and renormalise by 1/z.
			var frag := _shade(normal, tint)
			if texture != null and tex_w > 0:
				var tu := (ua.x * sa.z * w2 + ub.x * sb.z * w1 + uc.x * sc.z * w0) / inv_z
				var tv := (ua.y * sa.z * w2 + ub.y * sb.z * w1 + uc.y * sc.z * w0) / inv_z
				var tx := clampi(int(tu * tex_w), 0, tex_w - 1)
				var ty := clampi(int(tv * tex_h), 0, tex_h - 1)
				var texel := texture.get_pixel(tx, ty)
				frag = Color(frag.r * texel.r, frag.g * texel.g, frag.b * texel.b)
			image.set_pixel(x, y, frag)


func _shade(normal: Vector3, tint: Color) -> Color:
	var key := maxf(0.0, normal.dot(-LIGHT_DIR.normalized())) * KEY
	var fill := maxf(0.0, normal.dot(-FILL_DIR.normalized())) * FILL
	var level := AMBIENT + key + fill
	return Color(
		minf(tint.r * level, 1.0),
		minf(tint.g * level, 1.0),
		minf(tint.b * level, 1.0)
	)
