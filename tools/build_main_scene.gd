extends SceneTree

## Generates res://main.tscn: the prototype scene with the board, a full
## starting set of pieces, lighting and a camera.
##
## The scene is generated rather than hand-authored because placing 32 pieces
## and wiring up transforms by hand is tedious and error-prone. Once generated
## it is an ordinary scene: open it in the editor and rearrange anything freely.
##
##     godot-headless --headless --script res://tools/build_main_scene.gd

const OUTPUT := "res://main.tscn"

## Back-rank order lives on BoardState so the visual layout and the logical
## layout share one definition of the starting position.

const LIGHT := PieceMesh.LIGHT_SIDE
const DARK := PieceMesh.DARK_SIDE


func _init() -> void:
	var root := Node3D.new()
	root.name = "Main"
	root.set_script(load("res://main.gd"))

	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)

	world.add_child(_board())
	world.add_child(_highlight())
	world.add_child(_last_move_from())
	world.add_child(_last_move_to())
	world.add_child(_check_highlight())
	world.add_child(_pieces())
	world.add_child(_table())
	world.add_child(_tray("TrayLight", LIGHT))
	world.add_child(_tray("TrayDark", DARK))
	world.add_child(_room())
	world.add_child(_key_light())
	world.add_child(_fill_light())
	world.add_child(_environment())
	world.add_child(_camera())
	root.add_child(_hud_layer())

	# Children must be owned by the root for PackedScene.pack to store them.
	_own(root, root)

	# The @tool setters on BoardView and PieceView rebuild geometry as soon as
	# properties are assigned, which would embed every generated mesh in the
	# scene file. Clearing them keeps the .tscn small and reviewable; the
	# editor and the game both regenerate the meshes when the scene loads.
	_clear_generated_meshes(root)

	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		printerr("pack failed: %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(packed, OUTPUT)
	if err != OK:
		printerr("save failed: %d" % err)
		quit(1)
		return

	print("Wrote %s" % OUTPUT)
	quit(0)


func _board() -> MeshInstance3D:
	var board := MeshInstance3D.new()
	board.name = "Board"
	board.set_script(load("res://board/board_view.gd"))
	return board


func _highlight() -> MeshInstance3D:
	var highlight := MeshInstance3D.new()
	highlight.name = "Highlight"
	highlight.set_script(load("res://board/square_highlight.gd"))
	return highlight


## The red frame for a king in check: the same marker the selection uses, in a
## different colour. Not a separate design, so the player has one shape to
## recognise and reads the colour for urgency.
func _check_highlight() -> MeshInstance3D:
	var highlight := MeshInstance3D.new()
	highlight.name = "CheckHighlight"
	highlight.set_script(load("res://board/square_highlight.gd"))
	highlight.set("colour", SquareHighlight.RED)
	return highlight


## The two faint frames marking where the last move came from and went to.
##
## Two instances of the one marker rather than a bespoke two-square mesh, so
## every highlight on the board is the same component in a different colour:
## gold for the selection, blue and green for the last move's two ends, red for a
## king in check. One shape to recognise.
func _last_move_from() -> MeshInstance3D:
	return _highlight_named("LastMoveFrom", SquareHighlight.LAST_MOVE_FROM)


func _last_move_to() -> MeshInstance3D:
	return _highlight_named("LastMoveTo", SquareHighlight.LAST_MOVE_TO)


func _highlight_named(node_name: String, tint: Color) -> MeshInstance3D:
	var highlight := MeshInstance3D.new()
	highlight.name = node_name
	highlight.set_script(load("res://board/square_highlight.gd"))
	highlight.set("colour", tint)
	return highlight


func _pieces() -> Node3D:
	var holder := Node3D.new()
	holder.name = "Pieces"

	# White occupies rank 0 (negative Z) and moves towards positive Z.
	holder.add_child(_back_rank(0, LIGHT, "White", false))
	holder.add_child(_pawns(1, LIGHT, "White"))
	holder.add_child(_back_rank(BoardMesh.SQUARES - 1, DARK, "Black", true))
	holder.add_child(_pawns(BoardMesh.SQUARES - 2, DARK, "Black"))
	return holder


func _back_rank(rank: int, side: int, label: String, face_opponent: bool) -> Node3D:
	var group := Node3D.new()
	group.name = "%sBackRank" % label
	for file in BoardMesh.SQUARES:
		group.add_child(_piece(BoardState.BACK_RANK[file], side, label, file, rank, face_opponent))
	return group


func _pawns(rank: int, side: int, label: String) -> Node3D:
	var group := Node3D.new()
	group.name = "%sPawns" % label
	for file in BoardMesh.SQUARES:
		group.add_child(_piece(PieceProfiles.Type.PAWN, side, label, file, rank, false))
	return group


func _piece(
	type: int, side: int, label: String, file: int, rank: int, face_opponent: bool
) -> Node3D:
	var piece := MeshInstance3D.new()
	var colour := "White" if side == LIGHT else "Black"
	# Named for the square it stands on, using algebraic notation. Plain indices
	# like "WhiteBishop2" read as duplicates in the scene dock when a set has
	# two bishops, which is exactly the confusion this avoids.
	piece.name = "%s%s%s" % [colour, PieceProfiles.type_name(type), square_name(file, rank)]
	piece.set_script(load("res://pieces/piece_view.gd"))
	piece.set("side", side)
	piece.set("piece_type", type)
	piece.set("face_opponent", face_opponent)
	piece.position = BoardMesh.square_position(file, rank)
	return piece


## Algebraic square name, e.g. square_name(2, 0) == "C1".
## rank is the board's 0-based index from white's side, so it maps to 1..8.
func square_name(file: int, rank: int) -> String:
	var file_letter := char("A".unicode_at(0) + file)
	return "%s%d" % [file_letter, rank + 1]


## The HUD lives on its own CanvasLayer so its layout is resolution
## independent, which matters on a cross-platform build.
func _hud_layer() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	layer.add_child(_hud())
	return layer


func _hud() -> Control:
	var hud := Control.new()
	hud.name = "Hud"
	hud.set_script(load("res://ui/hud.gd"))
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE

	hud.add_child(_turn_label())
	hud.add_child(_control_column())
	hud.add_child(_voice_row())
	hud.add_child(_menu_button())
	hud.add_child(_game_over_label())
	hud.add_child(_promotion_picker())
	return hud


func _turn_label() -> Label:
	var label := Label.new()
	label.name = "TurnLabel"
	label.unique_name_in_owner = true
	label.text = "White to move    ·    0 moves"
	# Anchored top-centre: the board owns the middle of the screen.
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.position = Vector2(-160.0, 12.0)
	label.size = Vector2(320.0, 40.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.82))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03))
	label.add_theme_constant_override("outline_size", 6)
	return label


## Icon-only buttons, stacked against the right edge and centred vertically.
## Order is deliberate: the two rotate buttons sit together as a pair, then
## flip, then reset, so the thumb rests in one place for the common actions.
func _control_column() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = "ControlColumn"
	column.unique_name_in_owner = true
	column.add_theme_constant_override("separation", 14)
	column.alignment = BoxContainer.ALIGNMENT_CENTER

	for spec in [
		["RotateLeftButton", Icons.rotate_left()],
		["RotateRightButton", Icons.rotate_right()],
		["FlipButton", Icons.flip()],
		["ResetButton", Icons.reset()],
	]:
		column.add_child(_icon_button(String(spec[0]), spec[1]))

	column.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	column.position = Vector2(-84.0, -150.0)
	column.size = Vector2(72.0, 300.0)
	return column


## The menu button sits in the top-right corner, away from the view controls
## so it never gets hit by accident mid-game.
## The end-of-game banner. Above the board, below the promotion overlay, and
## hidden until there is something to say.
func _game_over_label() -> Label:
	var label := Label.new()
	label.name = "GameOverLabel"
	label.unique_name_in_owner = true
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.position = Vector2(-190.0, 168.0)
	label.size = Vector2(380.0, 56.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.visible = false
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.72))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03))
	label.add_theme_constant_override("outline_size", 8)
	return label


## The promote-what-to overlay. Added last so it paints over everything, and
## starts hidden because it is only shown while a promotion is pending.
func _promotion_picker() -> Control:
	var picker := Control.new()
	picker.name = "PromotionPicker"
	picker.unique_name_in_owner = true
	picker.set_script(load("res://ui/promotion_picker.gd"))
	return picker


func _menu_button() -> Button:
	var button := _icon_button("MenuButton", Icons.menu())
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.position = Vector2(-Hud.MENU_INSET, 16.0)
	button.size = Hud.TOUCH_SIZE
	return button


## Voice chat, between the move count in the middle and the menu at the far
## right. Deliberately bare: no panel, so it reads as a status affordance
## rather than a control competing with the view buttons.
##
## Grouped so the whole cluster can be hidden when there is no opponent; the
## menu keeps its own slot rather than shifting when voice disappears.
func _voice_row() -> Control:
	var row := Control.new()
	row.name = "VoiceRow"
	row.unique_name_in_owner = true
	# Measured from the menu rather than from the screen, because the two are
	# one corner cluster and must keep their spacing at any width.
	#
	# The menu centre is MENU_INSET back from the right edge, less half a touch
	# target; the mic centre is a further VOICE_GAP to the left of that.
	var menu_centre := Hud.MENU_INSET - Hud.TOUCH_SIZE.x * 0.5
	var mic_centre := menu_centre + Hud.VOICE_GAP
	row.anchor_left = 1.0
	row.anchor_right = 1.0
	row.anchor_top = 0.0
	row.anchor_bottom = 0.0
	row.offset_left = -mic_centre - Hud.TOUCH_SIZE.x * 0.5
	row.offset_right = -mic_centre + Hud.TOUCH_SIZE.x * 0.5
	row.offset_top = 16.0
	row.offset_bottom = 16.0 + Hud.TOUCH_SIZE.y
	row.visible = true

	var ring := Panel.new()
	ring.name = "MicRing"
	ring.unique_name_in_owner = true
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.visible = false
	ring.add_theme_stylebox_override("panel", _ring_box())
	row.add_child(ring)

	var button := _bare_icon_button("MicButton", Icons.mic_off())
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_child(button)

	var dot := Panel.new()
	dot.name = "RemoteDot"
	dot.unique_name_in_owner = true
	dot.position = Vector2(Hud.TOUCH_SIZE.x - 14.0, Hud.TOUCH_SIZE.y - 14.0)
	dot.size = Vector2(11.0, 11.0)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.visible = false
	dot.add_theme_stylebox_override("panel", _dot_box())
	row.add_child(dot)

	return row


## One capture tray, anchored to a bottom corner.
##
## The two trays sit at opposite bottom corners so they cannot crowd each other
## once both sides have taken pieces, and neither collides with the control
## column, which owns the middle of the right edge. A flow container rather
## than a row so sixteen pieces wrap instead of running off a narrow screen.
## A hairline outline that appears only while the mic is live. Carries the same
## information as the glyph so the state survives a hard-to-read icon.
func _ring_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.border_color = Color(1.0, 0.88, 0.62, 0.62)
	box.set_border_width_all(2)
	box.set_corner_radius_all(Hud.TOUCH_SIZE.x / 2.0)
	return box


## Activity light for the opponent transmitting. Placed at the far corner from
## the mic glyph so it cannot be read as your own state.
func _dot_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.55, 0.92, 0.62, 0.92)
	box.set_corner_radius_all(6)
	box.set_border_width_all(1)
	box.border_color = Color(0.1, 0.14, 0.1, 0.85)
	return box


## An icon button with no panel behind it.
func _bare_icon_button(node_name: String, icon: Texture2D) -> Button:
	var button := Button.new()
	button.name = node_name
	button.unique_name_in_owner = true
	button.icon = null
	button.custom_minimum_size = Hud.TOUCH_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "voice"
	button.flat = true
	button.add_child(_glyph(icon))
	return button


func _icon_button(node_name: String, icon: Texture2D) -> Button:
	var button := Button.new()
	button.name = node_name
	button.unique_name_in_owner = true
	button.icon = null
	button.custom_minimum_size = Hud.TOUCH_SIZE
	button.add_child(_glyph(icon))
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = node_name.trim_suffix("Button").to_lower()
	button.add_theme_stylebox_override("normal", _button_box())
	button.add_theme_stylebox_override("hover", _button_box(Color(0.16, 0.13, 0.11)))
	button.add_theme_stylebox_override("pressed", _button_box(Color(0.26, 0.20, 0.15)))
	return button


## The glyph itself, in a rect inset from the button on all four sides and
## scaled to fit without distorting. KEEP_ASPECT_CENTERED guarantees the
## artwork is optically centred whatever size the texture imported at, which
## is the whole point: the Android and desktop imports can differ in size and
## the button must not care.
func _glyph(icon: Texture2D) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = "Glyph"
	rect.texture = icon
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The rect fills the button apart from a fixed inset, so the glyph is
	# centred in the button rather than wherever the icon layout puts it.
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.offset_left = Hud.ICON_INSET
	rect.offset_top = Hud.ICON_INSET
	rect.offset_right = -Hud.ICON_INSET
	rect.offset_bottom = -Hud.ICON_INSET
	return rect


## Rounded dark panel behind each icon, so the controls read as a deliberate
## set sitting on the table rather than as default buttons.
func _button_box(fill := Color(0.09, 0.08, 0.07, 0.72)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(14)
	box.border_color = Color(0.45, 0.34, 0.24, 0.55)
	box.set_border_width_all(1)
	return box


## The round table the board rests on. Round because the camera orbits: a
## wall or a corner would break as soon as the player spun past it.
func _table() -> MeshInstance3D:
	var table := MeshInstance3D.new()
	table.name = "Table"
	table.set_script(load("res://surroundings/table_view.gd"))
	return table


## A capture tray lying on the table, one each side of the board.
##
## The trays hold pieces by the colour that was taken, so the tray on a given
## side always shows the opponent's pieces. They are keyed to a board side
## rather than to the camera, so orbiting the board never swaps them.
func _tray(node_name: String, capturer: int) -> Node3D:
	var tray := Node3D.new()
	tray.name = node_name
	tray.set_script(load("res://surroundings/tray_view.gd"))
	tray.set("capturer", capturer)
	# Clear of the board frame, level with the table surface, long axis across
	# the board's depth so both trays flank it symmetrically.
	var side := -1.0 if capturer == LIGHT else 1.0
	tray.position = Vector3(side * TrayMesh.TRAY_X, TableMesh.TOP_Y, 0.0)
	if capturer == DARK:
		# Mirrored so the row of wells faces the board from both sides.
		tray.scale = Vector3(-1.0, 1.0, 1.0)
	return tray


## The round room enclosing the table.
func _room() -> Node3D:
	var room := Node3D.new()
	room.name = "Room"
	room.set_script(load("res://surroundings/room_view.gd"))
	return room


func _key_light() -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = "KeyLight"
	light.light_energy = 1.25
	light.light_color = Color(1.0, 0.965, 0.910)
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 40.0
	light.transform = Transform3D(Basis(), Vector3.ZERO).looking_at(
		Vector3(-0.55, -1.0, -0.35), Vector3.UP
	)
	return light


func _fill_light() -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = "FillLight"
	light.light_energy = 0.35
	light.light_color = Color(0.760, 0.830, 1.0)
	light.shadow_enabled = false
	light.transform = Transform3D(Basis(), Vector3.ZERO).looking_at(
		Vector3(0.65, -0.55, 0.55), Vector3.UP
	)
	return light


func _environment() -> WorldEnvironment:
	var node := WorldEnvironment.new()
	node.name = "Environment"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY

	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.180, 0.290, 0.470)
	sky_material.sky_horizon_color = Color(0.640, 0.700, 0.760)
	sky_material.ground_bottom_color = Color(0.090, 0.100, 0.115)
	sky_material.ground_horizon_color = Color(0.480, 0.520, 0.560)
	env.sky = Sky.new()
	env.sky.sky_material = sky_material

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	node.environment = env
	return node


func _camera() -> Camera3D:
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.set_script(load("res://camera/orbit_camera.gd"))
	camera.fov = 45.0
	camera.current = true
	# Default orbit matches Main's framing exports; Main reframes on ready.
	camera.set("target", Vector3.ZERO)
	camera.set("yaw_degrees", 0.0)
	camera.set("pitch_degrees", 34.0)
	camera.set("distance", 11.7)
	return camera


## Marks the whole subtree as owned by root so it is written into the scene.
func _own(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_own(child, root)


## Drops generated meshes so they are not serialised into the scene file. The
## ground plane keeps its mesh, since PlaneMesh is a plain built-in resource.
func _clear_generated_meshes(node: Node) -> void:
	if node is MeshInstance3D and node.name != "Ground":
		node.mesh = null
	for child in node.get_children():
		_clear_generated_meshes(child)
