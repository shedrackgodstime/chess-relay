extends SceneTree
## One-time baker: renders catalog meshes to PNGs committed as picker art.
## Run on a real GPU (headless dummy renders blank):
##   godot --path godot --resolution 640x480 --script res://tests/bake_previews.gd
## Output: godot/assets/chess/pieces/preview_<piece>_<side>.png

const CATALOG := preload("res://src/game/pieces/piece_catalog.gd")
const WHITE_MATERIAL := preload("res://src/game/pieces/piece_white_material.tres")
const BLACK_MATERIAL := preload("res://src/game/pieces/piece_black_material.tres")
const ORDER := ["queen", "rook", "bishop", "knight"]
const SIDES := ["white", "black"]
const PIECE_SCALE := 16.0
const KNIGHT_FACING := deg_to_rad(60.0)


func _init() -> void:
	for side: String in SIDES:
		for piece: String in ORDER:
			var image := await _render_piece(piece, side)
			if image == null or image.is_empty():
				printerr("BAKE FAIL (blank): ", piece, " ", side)
				quit(1)
				return
			var path := "res://assets/chess/pieces/preview_%s_%s.png" % [piece, side]
			if image.save_png(path) != OK:
				printerr("BAKE FAIL (save): ", path)
				quit(1)
				return
			print("BAKE ok: ", path, " ", image.get_size())
	quit(0)


func _render_piece(piece: String, side: String) -> Image:
	var viewport := SubViewport.new()
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size = Vector2i(160, 168)
	root.add_child(viewport)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-34.0, 28.0, 0.0)
	light.light_energy = 1.7
	light.light_color = Color(1.0, 0.955, 0.885)
	viewport.add_child(light)
	var source: Node = CATALOG.scene_for(piece).instantiate()
	var mesh := _find_mesh(source)
	source.remove_child(mesh)
	source.free()
	mesh.scale = Vector3.ONE * PIECE_SCALE
	var bounds := mesh.get_aabb()
	mesh.position.y = -bounds.position.y * PIECE_SCALE
	mesh.material_override = WHITE_MATERIAL if side == "white" else BLACK_MATERIAL
	if piece == "knight":
		mesh.rotation.y = PI + KNIGHT_FACING if side == "white" else -KNIGHT_FACING
	viewport.add_child(mesh)
	var height: float = maxf(bounds.size.y * PIECE_SCALE, 0.2)
	var centre_y: float = (bounds.get_center().y - bounds.position.y) * PIECE_SCALE
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, centre_y + height * 0.12, height * 1.35)
	var forward := (Vector3(0.0, centre_y, 0.0) - camera.position).normalized()
	var axis_z := -forward
	var axis_x := Vector3.UP.cross(axis_z).normalized()
	camera.basis = Basis(axis_x, axis_z.cross(axis_x), axis_z)
	viewport.add_child(camera)
	camera.current = true
	await process_frame
	await process_frame
	await process_frame
	var image := viewport.get_texture().get_image()
	root.remove_child(viewport)
	viewport.queue_free()
	return image


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null
