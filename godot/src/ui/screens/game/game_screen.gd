class_name GameScreen
extends Control

signal leave_requested


@onready var _board: ChessBoardView = %Board
@onready var _header: GameHeader = %GameHeader
@onready var _camera: Camera3D = %Camera
@onready var _board_view_button: Button = %BoardViewButton

const CAMERA_TARGET := Vector3(0.0, -0.45, 0.0)
const PIECE_VIEW_SCENE := preload("res://src/game/pieces/piece_view.tscn")
var _camera_scale := 1.0


func _ready() -> void:
	_header.menu_requested.connect(_open_game_menu)
	_board_view_button.pressed.connect(_toggle_board_view_menu)
	_board.square_pressed.connect(_on_square_pressed)
	_camera.target = CAMERA_TARGET
	_update_camera_framing()
	_build_demo_position()


func _build_demo_position() -> void:
	var pieces_root := Node3D.new()
	pieces_root.name = "Pieces"
	_board.add_child(pieces_root)
	var back_rank := ["rook", "knight", "bishop", "queen", "king", "bishop", "knight", "rook"]
	for file in range(8):
		_add_piece(pieces_root, back_rank[file], "white", "%s1" % char("a".unicode_at(0) + file))
		_add_piece(pieces_root, "pawn", "white", "%s2" % char("a".unicode_at(0) + file))
		_add_piece(pieces_root, "pawn", "black", "%s7" % char("a".unicode_at(0) + file))
		_add_piece(pieces_root, back_rank[file], "black", "%s8" % char("a".unicode_at(0) + file))


func _add_piece(parent: Node3D, piece_type: String, side: String, square: String) -> void:
	var piece = PIECE_VIEW_SCENE.instantiate()
	piece.name = "%s_%s_%s" % [side.capitalize(), piece_type.capitalize(), square]
	piece.configure(piece_type, side)
	piece.position = _board.square_to_world(square, 0.02)
	parent.add_child(piece)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_update_camera_framing()


func _toggle_board_view_menu() -> void:
	var existing := get_node_or_null("HUD/BoardViewOverlay")
	if existing != null:
		existing.queue_free()
		return
	var overlay := Control.new()
	overlay.name = "BoardViewOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_board_view_overlay_input.bind(overlay))
	$HUD.add_child(overlay)
	var menu := PanelContainer.new()
	menu.name = "BoardViewMenu"
	menu.theme_type_variation = &"Card"
	menu.custom_minimum_size = Vector2(190.0, 0.0)
	menu.position = Vector2(maxf(size.x - 214.0, 16.0), size.y - 270.0)
	overlay.add_child(menu)
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	menu.add_child(actions)
	actions.add_child(_board_view_action("Rotate left", -22.5, menu))
	actions.add_child(_board_view_action("Rotate right", 22.5, menu))
	actions.add_child(_board_view_action("Flip board", 180.0, menu))
	var reset := Button.new()
	reset.text = "Reset view"
	reset.custom_minimum_size.y = 42.0
	reset.theme_type_variation = &"QuietButton"
	reset.pressed.connect(func():
		_camera.reset_view()
	)
	actions.add_child(reset)


func _board_view_action(label: String, degrees: float, menu: Control) -> Button:
	var action := Button.new()
	action.text = label
	action.custom_minimum_size.y = 42.0
	action.theme_type_variation = &"QuietButton"
	action.pressed.connect(func():
		_camera.orbit_by(degrees)
	)
	return action


func _on_board_view_overlay_input(event: InputEvent, overlay: Control) -> void:
	if event is InputEventMouseButton and event.pressed:
		overlay.queue_free()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and event.pressed:
		overlay.queue_free()
		get_viewport().set_input_as_handled()


func _update_camera_framing(width: float = -1.0, height: float = -1.0) -> void:
	var viewport_size := get_viewport_rect().size
	var viewport_width := viewport_size.x if width < 0.0 else width
	var viewport_height := viewport_size.y if height < 0.0 else height
	if viewport_height <= 0.0:
		return
	var aspect := viewport_width / viewport_height
	_camera_scale = clampf(1.5 / maxf(aspect, 0.65), 1.0, 1.45)
	_camera.set_distance(15.27 * _camera_scale)


func _on_square_pressed(square: String) -> void:
	_header.set_center_text("Selected %s" % square.to_upper())


func _open_game_menu() -> void:
	var confirmation := ConfirmationDialog.new()
	confirmation.theme_type_variation = &"ModalDialog"
	confirmation.title = "Leave game?"
	confirmation.dialog_text = "Leave this game and return to the home screen?"
	confirmation.dialog_autowrap = true
	confirmation.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirmation.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirmation.ok_button_text = "Leave game"
	confirmation.cancel_button_text = "Stay"
	confirmation.get_ok_button().theme_type_variation = &"ModalDangerButton"
	confirmation.get_cancel_button().theme_type_variation = &"ModalSecondaryButton"
	confirmation.confirmed.connect(func():
		leave_requested.emit()
		confirmation.queue_free()
	)
	confirmation.canceled.connect(confirmation.queue_free)
	add_child(confirmation)
	confirmation.popup_centered(Vector2i(460, 220))
