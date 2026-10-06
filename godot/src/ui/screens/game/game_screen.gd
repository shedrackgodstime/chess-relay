class_name GameScreen
extends Control

signal leave_requested

const PIECE_SCENE: PackedScene = preload("res://src/game/pieces/piece_view.tscn")

@onready var _board: ChessBoardView = %Board
@onready var _pieces: Node3D = %Pieces
@onready var _header: GameHeader = %GameHeader
@onready var _camera: Camera3D = %Camera
@onready var _board_view_button: Button = %BoardViewButton

const CAMERA_DISTANCE := 15.27
const CAMERA_MIN_PITCH := 24.0
const CAMERA_MAX_PITCH := 72.0
const CAMERA_DRAG_SENSITIVITY := 0.35

var _camera_yaw := 0.0
var _camera_pitch := 45.0
var _camera_scale := 1.0
var _orbit_dragging := false


func _ready() -> void:
	_header.menu_requested.connect(_open_game_menu)
	_board_view_button.pressed.connect(_toggle_board_view_menu)
	_board.square_pressed.connect(_on_square_pressed)
	_update_camera_framing()
	_build_demo_position()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_update_camera_framing()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.position.y > 80.0 \
			and not _board_view_button.get_global_rect().has_point(event.position):
			_orbit_dragging = true
			get_viewport().set_input_as_handled()
		elif not event.pressed:
			_orbit_dragging = false
	elif event is InputEventMouseMotion and _orbit_dragging:
		_camera_yaw -= event.relative.x * CAMERA_DRAG_SENSITIVITY
		_camera_pitch = clampf(
			_camera_pitch + event.relative.y * CAMERA_DRAG_SENSITIVITY,
			CAMERA_MIN_PITCH,
			CAMERA_MAX_PITCH
		)
		_apply_camera_orbit()
		get_viewport().set_input_as_handled()


func _toggle_board_view_menu() -> void:
	var existing := get_node_or_null("HUD/BoardViewMenu")
	if existing != null:
		existing.queue_free()
		return
	var menu := PanelContainer.new()
	menu.name = "BoardViewMenu"
	menu.theme_type_variation = &"Card"
	menu.custom_minimum_size = Vector2(190.0, 0.0)
	menu.position = Vector2(maxf(size.x - 214.0, 16.0), size.y - 270.0)
	$HUD.add_child(menu)
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	menu.add_child(actions)
	actions.add_child(_board_view_action("Rotate left", -90.0, menu))
	actions.add_child(_board_view_action("Rotate right", 90.0, menu))
	actions.add_child(_board_view_action("Flip board", 180.0, menu))
	var reset := Button.new()
	reset.text = "Reset view"
	reset.custom_minimum_size.y = 42.0
	reset.theme_type_variation = &"QuietButton"
	reset.pressed.connect(func():
		_camera_yaw = 0.0
		_camera_pitch = 45.0
		_apply_camera_orbit()
		menu.queue_free()
	)
	actions.add_child(reset)


func _board_view_action(label: String, degrees: float, menu: Control) -> Button:
	var action := Button.new()
	action.text = label
	action.custom_minimum_size.y = 42.0
	action.theme_type_variation = &"QuietButton"
	action.pressed.connect(func():
		_camera_yaw += degrees
		_apply_camera_orbit()
		menu.queue_free()
	)
	return action


func _update_camera_framing(width: float = -1.0, height: float = -1.0) -> void:
	var viewport_size := get_viewport_rect().size
	var viewport_width := viewport_size.x if width < 0.0 else width
	var viewport_height := viewport_size.y if height < 0.0 else height
	if viewport_height <= 0.0:
		return
	var aspect := viewport_width / viewport_height
	_camera_scale = clampf(1.5 / maxf(aspect, 0.65), 1.0, 1.45)
	_apply_camera_orbit()


func _apply_camera_orbit() -> void:
	var yaw := deg_to_rad(_camera_yaw)
	var pitch := deg_to_rad(_camera_pitch)
	var distance := CAMERA_DISTANCE * _camera_scale
	_camera.position = Vector3(
		sin(yaw) * cos(pitch) * distance,
		sin(pitch) * distance,
		cos(yaw) * cos(pitch) * distance
	)
	_camera.look_at(Vector3.ZERO, Vector3.UP)


func _on_square_pressed(square: String) -> void:
	_header.set_center_text("Selected %s" % square.to_upper())


func _build_demo_position() -> void:
	var back_rank := ["rook", "knight", "bishop", "queen", "king", "bishop", "knight", "rook"]
	for file in 8:
		_add_piece(back_rank[file], "white", "%s1" % char("a".unicode_at(0) + file))
		_add_piece("pawn", "white", "%s2" % char("a".unicode_at(0) + file))
		_add_piece("pawn", "black", "%s7" % char("a".unicode_at(0) + file))
		_add_piece(back_rank[file], "black", "%s8" % char("a".unicode_at(0) + file))


func _add_piece(type: String, piece_side: String, square: String) -> void:
	var piece := PIECE_SCENE.instantiate() as ChessPieceView
	piece.configure(type, piece_side)
	piece.position = _board.square_to_world(square, 0.0)
	_pieces.add_child(piece)


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
