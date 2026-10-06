class_name GameScreen
extends Control

signal leave_requested


@onready var _board: ChessBoardView = %Board
@onready var _header: GameHeader = %GameHeader
@onready var _camera: Camera3D = %Camera
@onready var _board_view_button: Button = %BoardViewButton
@onready var _opponent_clock: Label = $HUD/HUDRoot/ClockStrip/Content/OpponentClock
@onready var _player_clock: Label = $HUD/HUDRoot/ClockStrip/Content/PlayerClock
@onready var _move_number_label: Label = $HUD/HUDRoot/ClockStrip/Content/MoveNumber
@onready var _clock_timer: Timer = $ClockTimer

const CAMERA_TARGET := Vector3(0.0, -0.45, 0.0)
const PIECE_VIEW_SCENE := preload("res://src/game/pieces/piece_view.tscn")
const FEN_PIECE_TYPES := {"p": "pawn", "n": "knight", "b": "bishop", "r": "rook", "q": "queen", "k": "king"}
var _camera_scale := 1.0
var _is_multiplayer := false
var _active_clock_side := "white"
var _white_seconds := 600
var _black_seconds := 598
var _selected_piece_square := ""
var _selected_piece_type := ""
var _legal_targets: Array[String] = []
var _move_number := 1
var _bridge: Node = null


func configure_peer() -> void:
	_is_multiplayer = true
	if is_node_ready():
		_update_header_visibility()


func _ready() -> void:
	_header.menu_requested.connect(_open_game_menu)
	_board_view_button.pressed.connect(_toggle_board_view_menu)
	_board.square_pressed.connect(_on_square_pressed)
	_clock_timer.timeout.connect(_on_clock_tick)
	_update_header_visibility()
	_update_clock_strip()
	_camera.target = CAMERA_TARGET
	_update_camera_framing()
	_start_bridge()
	_rebuild_position()


func _update_header_visibility() -> void:
	_header.set_visibility(_is_multiplayer, _is_multiplayer, true, true)


func _on_clock_tick() -> void:
	if _active_clock_side == "white":
		_white_seconds = maxi(0, _white_seconds - 1)
		if _white_seconds == 0:
			_clock_timer.stop()
	else:
		_black_seconds = maxi(0, _black_seconds - 1)
		if _black_seconds == 0:
			_clock_timer.stop()
	_update_clock_strip()


func _update_clock_strip() -> void:
	_opponent_clock.text = "MORGAN  %s" % _format_clock(_black_seconds)
	_player_clock.text = "%s  YOU" % _format_clock(_white_seconds)
	var active_color := Color(1.0, 0.94, 0.82, 1.0)
	var idle_color := Color(0.72, 0.66, 0.58, 1.0)
	var warning_color := Color(1.0, 0.45, 0.28, 1.0)
	var opponent_color := warning_color if _black_seconds <= 60 \
		else active_color if _active_clock_side == "black" else idle_color
	var player_color := warning_color if _white_seconds <= 60 \
		else active_color if _active_clock_side == "white" else idle_color
	_opponent_clock.add_theme_color_override(
		"font_color", opponent_color)
	_player_clock.add_theme_color_override(
		"font_color", player_color)


func _format_clock(seconds: int) -> String:
	return "%02d:%02d" % [seconds / 60, seconds % 60]


func _start_bridge() -> void:
	if not ClassDB.class_exists("ChessRelayBridge"):
		_header.set_center_text("Chess engine unavailable")
		return
	_bridge = ClassDB.instantiate("ChessRelayBridge")
	add_child(_bridge)
	_bridge.move_applied.connect(_on_core_move_applied)
	_bridge.bridge_error.connect(_on_bridge_error)
	_bridge.start()


## Position rendering: the board observes the core, never the reverse.
## Every applied move rebuilds the piece set from the authoritative FEN,
## so captures, promotions and castling need no special cases here.

func _rebuild_position() -> void:
	var pieces_root := _board.get_node_or_null("Pieces")
	if pieces_root == null:
		pieces_root = Node3D.new()
		pieces_root.name = "Pieces"
		_board.add_child(pieces_root)
	for child in pieces_root.get_children():
		pieces_root.remove_child(child)
		child.queue_free()
	if _bridge == null:
		return
	_build_position_from_fen(pieces_root, _bridge.fen())


func _build_position_from_fen(pieces_root: Node3D, fen: String) -> void:
	var placement := fen.split(" ")[0]
	var rank := 8
	var file := 0
	for index in range(placement.length()):
		var token := placement.substr(index, 1)
		if token == "/":
			rank -= 1
			file = 0
		elif token.is_valid_int():
			file += token.to_int()
		elif FEN_PIECE_TYPES.has(token.to_lower()):
			var square := "%s%d" % [char("a".unicode_at(0) + file), rank]
			var side := "white" if token == token.to_upper() else "black"
			_add_piece(pieces_root, FEN_PIECE_TYPES[token.to_lower()], side, square)
			file += 1


func _add_piece(parent: Node3D, piece_type: String, side: String, square: String) -> void:
	var piece = PIECE_VIEW_SCENE.instantiate()
	piece.name = "%s_%s_%s" % [side.capitalize(), piece_type.capitalize(), square]
	piece.piece_pressed.connect(_on_piece_pressed)
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
	if _bridge == null:
		return
	if not _selected_piece_square.is_empty() and square in _legal_targets:
		var uci := _selected_piece_square + square
		if _selected_piece_type == "pawn" and (square.right(1) == "8" or square.right(1) == "1"):
			uci += "q"
		if _bridge.submit_move(uci):
			return
		_header.set_center_text("Illegal move")
		return
	_select_square(square, "", "")


func _on_piece_pressed(piece: Node) -> void:
	var square: String = piece.name.right(2).to_lower()
	_select_square(square, str(piece.get("side")), str(piece.get("piece_type")))


func _select_square(square: String, side: String, piece_type: String) -> void:
	_selected_piece_square = square
	_selected_piece_type = piece_type
	_legal_targets.clear()
	if _bridge != null:
		for target in _bridge.legal_moves_from(square):
			_legal_targets.append(target)
	_board.set_highlight(square)
	_board.set_legal_moves(_legal_targets)
	if _legal_targets.is_empty():
		if side.is_empty():
			_header.set_center_text("Selected %s" % square.to_upper())
		else:
			_header.set_center_text("Selected %s" % piece_type.capitalize())
	else:
		_header.set_center_text("Choose a move")


func _on_core_move_applied(seq: int, uci: String, by: String, agreed: bool) -> void:
	var from_square := uci.left(2)
	var to_square := uci.substr(2, 2)
	_rebuild_position()
	_board.set_last_move(from_square, to_square)
	_board.set_highlight("")
	_board.set_legal_moves([])
	_selected_piece_square = ""
	_selected_piece_type = ""
	_legal_targets.clear()
	_move_number += 1
	_move_number_label.text = "M%d" % _move_number
	if _bridge != null:
		_active_clock_side = _bridge.turn()
	_update_clock_strip()
	_header.set_center_text("Move %d · %s to move" % [_move_number, _active_clock_side.capitalize()])


func _on_bridge_error(message: String) -> void:
	_header.set_center_text(message)


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
