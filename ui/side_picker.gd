@tool
class_name SidePicker
extends Control

## Chooses which side the player takes, before anything has moved.
##
## Not decoration. Almost everything downstream depends on the answer: which
## pieces may be picked up, which side the AI plays, and which way the camera
## faces, since a Black player otherwise opens the game looking at the back of
## White's pieces.
##
## Shown at start and dismissed on choosing. Once a move has been played it stays
## gone, because changing sides mid-game would mean handing the player a position
## that is not theirs.

## Emitted with the chosen side, BoardState.LIGHT or DARK.
signal side_chosen(side: int)

const CARD_SIZE := Vector2(132.0, 150.0)
const PREVIEW_SIZE := Vector2(96.0, 104.0)


func _ready() -> void:
	if get_child_count() == 0:
		_build()
	visible = false


## Whether it still makes sense to ask. False once the game is under way.
func should_offer(game: ChessGame) -> bool:
	return game == null or game.history.is_empty()


func open(current: int) -> void:
	if get_node_or_null("Panel") != null:
		_select(current)
	visible = true


## How many sides are on offer.
func card_count() -> int:
	var cards := get_node_or_null("Centre/Panel/Column/Cards")
	return cards.get_child_count() if cards != null else 0


func close() -> void:
	visible = false


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.018, 0.016, 0.80)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var centre := CenterContainer.new()
	# Named because the cards are reached by path, and an auto-generated name
	# would not survive being looked up by anything.
	centre.name = "Centre"
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel", _panel_box())
	centre.add_child(panel)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	var title := Label.new()
	title.name = "Title"
	title.text = "Play as"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.94, 0.82))
	column.add_child(title)

	var row := HBoxContainer.new()
	row.name = "Cards"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	column.add_child(row)

	row.add_child(_make_card(BoardState.LIGHT, "White"))
	row.add_child(_make_card(BoardState.DARK, "Black"))

	var note := Label.new()
	note.name = "Note"
	note.text = "You move the side you pick. The board faces you."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color(0.86, 0.80, 0.70))
	column.add_child(note)


## One side to choose, previewed with that side's own pieces.
func _make_card(side: int, caption: String) -> Button:
	var button := Button.new()
	button.name = "Card%s" % caption
	button.custom_minimum_size = CARD_SIZE
	button.tooltip_text = "Play as %s" % caption.to_lower()
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void:
		_select(side)
		side_chosen.emit(side)
	)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	button.add_child(column)

	# A rook and a pawn in this side's colours: enough to read the difference at
	# a glance, which two flat squares would not be.
	for type in [PieceProfiles.Type.ROOK, PieceProfiles.Type.PAWN]:
		var preview := SubViewportContainer.new()
		preview.custom_minimum_size = Vector2(PREVIEW_SIZE.x, PREVIEW_SIZE.y * 0.5)
		preview.stretch = true
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(preview)
		var viewport := SubViewport.new()
		viewport.transparent_bg = true
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.msaa_3d = Viewport.MSAA_4X
		preview.add_child(viewport)
		var mesh := MeshInstance3D.new()
		mesh.mesh = PieceMesh.build(type, side)
		viewport.add_child(mesh)
		var aabb: AABB = mesh.mesh.get_aabb()
		var height: float = maxf(aabb.size.y, 0.2)
		var camera := Camera3D.new()
		camera.position = Vector3(0.0, aabb.get_center().y + height * 0.1, height * 1.3)
		_aim_at(camera, Vector3(0.0, aabb.get_center().y, 0.0))
		viewport.add_child(camera)
		camera.current = true
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-34.0, 28.0, 0.0)
		light.light_energy = 1.7
		light.light_color = Color(1.0, 0.955, 0.885)
		viewport.add_child(light)

	var label := Label.new()
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.82))
	column.add_child(label)
	return button


## Marks which card is currently chosen, so opening the picker shows the side
## already in effect rather than appearing undecided.
func _select(side: int) -> void:
	# Reached by path rather than by walking children, because the cards sit
	# inside the panel's column.
	var cards := get_node_or_null("Centre/Panel/Column/Cards")
	if cards == null:
		return
	for child in cards.get_children():
		var button := child as Button
		if button == null:
			continue
		var chosen: bool = (button.name == "CardWhite") == (side == BoardState.LIGHT)
		button.modulate = Color(1.0, 1.0, 1.0) if chosen else Color(0.62, 0.62, 0.62)


## Rotates a camera to look at a point without needing a tree.
static func _aim_at(camera: Camera3D, target: Vector3) -> void:
	var forward := (target - camera.position).normalized()
	var z := -forward
	var up := Vector3.UP
	if absf(z.dot(up)) > 0.999:
		up = Vector3.FORWARD
	var x := up.cross(z).normalized()
	camera.basis = Basis(x, z.cross(x), z)


func _panel_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.075, 0.068, 0.062, 0.97)
	box.set_corner_radius_all(14)
	box.set_border_width_all(1)
	box.border_color = Color(1.0, 0.88, 0.62, 0.30)
	box.content_margin_left = 18.0
	box.content_margin_right = 18.0
	box.content_margin_top = 14.0
	box.content_margin_bottom = 14.0
	return box