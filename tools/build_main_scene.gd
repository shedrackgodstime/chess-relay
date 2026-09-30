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
	world.add_child(_pieces())
	world.add_child(_table())
	world.add_child(_floor())
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
	hud.add_child(_menu_button())
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


## The menu button sits alone in the top-right corner, away from the view
## controls so it never gets hit by accident mid-game.
func _menu_button() -> Button:
	var button := _icon_button("MenuButton", Icons.menu())
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.position = Vector2(-84.0, 16.0)
	button.size = Hud.TOUCH_SIZE
	return button


func _icon_button(node_name: String, icon: Texture2D) -> Button:
	var button := Button.new()
	button.name = node_name
	button.unique_name_in_owner = true
	button.icon = icon
	button.custom_minimum_size = Hud.TOUCH_SIZE
	button.expand_icon = true
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = node_name.trim_suffix("Button").to_lower()
	button.add_theme_stylebox_override("normal", _button_box())
	button.add_theme_stylebox_override("hover", _button_box(Color(0.16, 0.13, 0.11)))
	button.add_theme_stylebox_override("pressed", _button_box(Color(0.26, 0.20, 0.15)))
	return button


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


## Distant floor, visible only as the horizon behind the table.
func _floor() -> MeshInstance3D:
	var floor_node := MeshInstance3D.new()
	floor_node.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(TableMesh.FLOOR_SIZE, TableMesh.FLOOR_SIZE)
	floor_node.mesh = plane
	floor_node.material_override = TableMesh.floor_material()
	floor_node.position = Vector3(0.0, TableMesh.FLOOR_Y, 0.0)
	return floor_node


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
