class_name GameScreen
extends Control

signal leave_requested

const PIECE_SCENE: PackedScene = preload("res://src/game/pieces/piece_view.tscn")

@onready var _board: ChessBoardView = %Board
@onready var _pieces: Node3D = %Pieces
@onready var _header: GameHeader = %GameHeader


func _ready() -> void:
	_header.menu_requested.connect(_open_game_menu)
	_board.square_pressed.connect(_on_square_pressed)
	_build_demo_position()


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
