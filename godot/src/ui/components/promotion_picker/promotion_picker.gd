class_name PromotionPicker
extends Control
## Asks which piece a pawn becomes, showing the real pieces.
##
## Shown instead of applying the move: a promotion cannot be tapped as two
## squares, and applying first would animate the wrong piece. Cancelling is
## not a dead end: it falls back to a queen, so the player can always
## finish the move.
##
## The previews are snapshots of the actual catalog meshes, rendered once per
## side into plain textures and shown in TextureRects. No live viewports, no
## per-frame 3D cost: after the one-time capture the picker is pure 2D.
## Presentation only: nothing here decides legality; the screen opens it
## solely for legal targets.
##
## Built in code: no subscene instances, no overrides, nothing for export
## conversion to drop.
##
## Emitted with "queen", "rook", "bishop" or "knight".

signal chosen(piece: String)

const PIECES: Array[String] = ["Queen", "Rook", "Bishop", "Knight"]
const SUFFIXES := {"queen": "q", "rook": "r", "bishop": "b", "knight": "n"}
const CATALOG := preload("res://src/game/pieces/piece_catalog.gd")
const WHITE_MATERIAL := preload("res://src/game/pieces/piece_white_material.tres")
const BLACK_MATERIAL := preload("res://src/game/pieces/piece_black_material.tres")
const PIECE_SCALE := 16.0
const KNIGHT_FACING := deg_to_rad(60.0)
const OPTION_SIZE := Vector2(96.0, 112.0)
const PREVIEW_SIZE := Vector2(80.0, 84.0)

## Side to rendered preview textures, filled once in the background.
var _textures: Array[Texture2D] = []
var _textured_side := ""


static func suffix_for(piece: String) -> String:
	return SUFFIXES.get(piece, "q")


var _options: HBoxContainer
var _title: Label
var _side := "white"


func _ready() -> void:
	_build()
	visible = false


## Shows the picker for a pawn of the given side ("white"/"black").
## Previews fill in when their one-time capture finishes.
func open(side: String) -> void:
	_side = side
	_rebuild_options()
	_title.text = "%s pawn promotes to" % side.capitalize()
	visible = true
	_fill_previews()


func close() -> void:
	visible = false


## How many choices are on offer, so tests assert population, not visibility.
func option_count() -> int:
	return _options.get_child_count() if _options != null else 0


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.018, 0.016, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.theme_type_variation = &"Card"
	centre.add_child(panel)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	_title = Label.new()
	_title.theme_type_variation = &"SetupSectionTitle"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.text = "Promote to"
	column.add_child(_title)

	_options = HBoxContainer.new()
	_options.name = "Options"
	_options.add_theme_constant_override("separation", 6)
	_options.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_options)

	var queen := Button.new()
	queen.name = "Cancel"
	queen.text = "Queen"
	queen.custom_minimum_size = Vector2(0, 42)
	queen.theme_type_variation = &"QuietButton"
	queen.focus_mode = Control.FOCUS_NONE
	queen.pressed.connect(_on_cancel_pressed)
	column.add_child(queen)


func _rebuild_options() -> void:
	if _options == null:
		return
	for child in _options.get_children():
		_options.remove_child(child)
		child.queue_free()
	for piece in PIECES:
		_options.add_child(_make_option(piece))


## A tappable button holding a 2D snapshot of the real piece.
func _make_option(piece: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = OPTION_SIZE
	button.tooltip_text = piece
	button.focus_mode = Control.FOCUS_NONE
	button.flat = true
	button.pressed.connect(_on_choice.bind(piece.to_lower()))
	var preview := TextureRect.new()
	preview.name = "Preview"
	preview.custom_minimum_size = PREVIEW_SIZE
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(preview)
	return button


## Renders each catalog mesh once per side, then frees the 3D machinery.
func _fill_previews() -> void:
	if _textured_side == _side and _textures.size() == PIECES.size():
		_apply_previews()
		return
	await _capture_side(_side)
	_apply_previews()


func _apply_previews() -> void:
	if _options == null or _textures.size() != PIECES.size():
		return
	var buttons := _options.get_children()
	for index in range(mini(buttons.size(), PIECES.size())):
		var preview := (buttons[index] as Button).get_node_or_null("Preview") as TextureRect
		if preview != null:
			preview.texture = _textures[index]


func _capture_side(side: String) -> void:
	_textures.clear()
	_textured_side = ""
	var viewport := SubViewport.new()
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# No MSAA: on tile-based mobile GPUs the multisampled resolve is what
	# comes back black on readback. Snapshots are scaled down 2x anyway.
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.size = Vector2i(160, 168)
	add_child(viewport)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-34.0, 28.0, 0.0)
	light.light_energy = 1.7
	light.light_color = Color(1.0, 0.955, 0.885)
	viewport.add_child(light)
	for piece in PIECES:
		_textures.append(await _snapshot_piece(viewport, piece.to_lower(), side))
	viewport.queue_free()
	_textured_side = side


func _snapshot_piece(viewport: SubViewport, piece: String, side: String) -> Texture2D:
	var source := CATALOG.scene_for(piece).instantiate()
	var mesh := _find_mesh(source)
	if mesh == null:
		push_error("Promotion preview has no mesh: %s" % piece)
		source.free()
		return null
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
	_aim_at(camera, Vector3(0.0, centre_y, 0.0))
	viewport.add_child(camera)
	camera.current = true
	# First render can lag frames behind on mobile (shader warmup), so wait
	# for drawn pixels rather than a fixed frame count. A blank viewport
	# reads back transparent everywhere; anything alpha means a piece.
	var image: Image = null
	for _attempt in range(60):
		await get_tree().process_frame
		await get_tree().process_frame
		image = viewport.get_texture().get_image()
		if _has_content(image):
			break
	viewport.remove_child(mesh)
	viewport.remove_child(camera)
	mesh.queue_free()
	camera.queue_free()
	if not _has_content(image):
		push_warning("Promotion preview captured blank: %s %s" % [side, piece])
		return null
	return ImageTexture.create_from_image(image)


## Whether the capture holds drawn pixels (color content anywhere).
##
## Checks color channels, not alpha: a failed mobile readback can come
## back opaque black, which alpha alone would misread as content.
static func _has_content(image: Image) -> bool:
	if image == null or image.is_empty():
		return false
	for y in range(0, image.get_height(), 7):
		for x in range(0, image.get_width(), 7):
			var pixel := image.get_pixel(x, y)
			if maxf(pixel.r, maxf(pixel.g, pixel.b)) > 0.03:
				return true
	return false


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null


## Rotates a camera to look at a point without needing a tree.
func _aim_at(camera: Camera3D, target: Vector3) -> void:
	var forward := (target - camera.position).normalized()
	var axis_z := -forward
	var up := Vector3.UP
	if absf(axis_z.dot(up)) > 0.999:
		up = Vector3.FORWARD
	var axis_x := up.cross(axis_z).normalized()
	camera.basis = Basis(axis_x, axis_z.cross(axis_x), axis_z)


func _on_choice(piece: String) -> void:
	close()
	chosen.emit(piece)


func _on_cancel_pressed() -> void:
	close()
	chosen.emit("queen")
