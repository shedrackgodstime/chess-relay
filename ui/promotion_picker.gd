@tool
class_name PromotionPicker
extends Control

## Asks the player which piece a pawn should become.
##
## Shown instead of applying the move, because a promotion is the one move the
## player cannot specify on their own by tapping two squares. Applying first and
## changing it afterwards would animate the wrong piece across the board and
## leave a queen sitting there for anyone watching the opponent's copy.
##
## The options are the real piece meshes rather than flat icons, rendered into a
## SubViewport each. They are generated from the same PieceMesh the board uses,
## so a promotion choice is previews of the actual pieces and not a picture of
## them, and there is no second set of artwork to keep in step.
##
## Cancelling is not a dead end: it falls back to a queen, which is also what
## ChessGame would have done on its own. The player cannot be left unable to
## finish their move.

## Emitted with the chosen piece type, or the queen if dismissed.
signal chosen(type: int)

## One preview per side, so a light player's options are not shown in dark.
@export var side: int = BoardState.LIGHT:
	set(value):
		side = clampi(value, 0, 1)
		if is_inside_tree():
			_rebuild_options()

const OPTION_SIZE := Vector2(96.0, 112.0)
const PREVIEW_SIZE := Vector2(80.0, 84.0)

var _options: HBoxContainer
var _title: Label


func _ready() -> void:
	if _options == null:
		_build()
	visible = false


func _build() -> void:
	# Anchors and offsets together: anchors alone leave the offsets at zero
	# against a parent whose size is not known yet, which leaves the overlay
	# measuring nothing and therefore invisible.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# A dimmer, so it is obvious the board is not accepting taps underneath.
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.018, 0.016, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box())
	centre.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	_title = Label.new()
	_title.text = "Promote to"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 19)
	_title.add_theme_color_override("font_color", Color(1.0, 0.94, 0.82))
	column.add_child(_title)

	_options = HBoxContainer.new()
	_options.add_theme_constant_override("separation", 6)
	_options.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_options)

	var cancel := Button.new()
	cancel.text = "Queen"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(func() -> void: chosen.emit(PieceProfiles.Type.QUEEN))
	column.add_child(cancel)

	_rebuild_options()


func _rebuild_options() -> void:
	if _options == null:
		return
	for child in _options.get_children():
		_options.remove_child(child)
		child.queue_free()
	for type in Rules.PROMOTION_CHOICES:
		_options.add_child(_make_option(type))


## A tappable preview of one piece.
func _make_option(type: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = OPTION_SIZE
	button.tooltip_text = PieceProfiles.type_name(type).to_lower()
	button.focus_mode = Control.FOCUS_NONE
	button.flat = true
	button.pressed.connect(func() -> void: chosen.emit(type))

	var preview := SubViewportContainer.new()
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.custom_minimum_size = PREVIEW_SIZE
	preview.stretch = true
	# Clicks belong to the button, not the preview sitting on top of it.
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(preview)

	var viewport := SubViewport.new()
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	preview.add_child(viewport)

	var mesh := MeshInstance3D.new()
	mesh.mesh = PieceMesh.build(type, side)
	viewport.add_child(mesh)

	# Frame each piece by its own bounds, so a pawn and a rook both fill the
	# box instead of the rook being twice the size of the pawn.
	var aabb: AABB = mesh.mesh.get_aabb()
	var height: float = maxf(aabb.size.y, 0.2)
	var centre_y: float = aabb.get_center().y
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, centre_y + height * 0.12, height * 1.35)
	# The basis is computed rather than using look_at, which needs the node to be
	# inside a tree, and these cameras are built before they are added.
	_aim_at(camera, Vector3(0.0, centre_y, 0.0))
	viewport.add_child(camera)
	camera.current = true

	# One light inside the viewport: the room's key light does not reach in here,
	# since each SubViewport has its own world.
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-34.0, 28.0, 0.0)
	light.light_energy = 1.7
	light.light_color = Color(1.0, 0.955, 0.885)
	viewport.add_child(light)

	return button


## Shows the picker for a pawn of the given side.
func open(promoting_side: int) -> void:
	side = promoting_side
	_rebuild_options()
	if _title != null:
		var who := "White" if promoting_side == BoardState.LIGHT else "Black"
		_title.text = "%s pawn promotes to" % who
	visible = true


## How many choices are on offer, so a test can assert the overlay is populated
## rather than merely visible.
func option_count() -> int:
	return _options.get_child_count() if _options != null else 0


func close() -> void:
	visible = false


## Rotates a camera so it looks at a point, without needing a tree.
static func _aim_at(camera: Camera3D, target: Vector3) -> void:
	var forward := (target - camera.position).normalized()
	# A camera looks along its local -Z, so the basis Z axis is the reverse.
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
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 12.0
	box.content_margin_bottom = 12.0
	return box