class_name GameScreen
extends Control

signal leave_requested


@onready var _board: ChessBoardView = %Board
@onready var _header: GameHeader = %GameHeader
@onready var _camera: GameOrbitCamera = %Camera
@onready var _board_view_button: Button = %BoardViewButton
@onready var _opponent_clock: Label = $HUD/HUDRoot/ClockStrip/Content/OpponentClock
@onready var _player_clock: Label = $HUD/HUDRoot/ClockStrip/Content/PlayerClock
@onready var _move_number_label: Label = $HUD/HUDRoot/ClockStrip/Content/MoveNumber
@onready var _clock_timer: Timer = $ClockTimer
@onready var _picker: PromotionPicker = %PromotionPicker

const CAMERA_TARGET := Vector3(0.0, -0.45, 0.0)
const PIECE_VIEW_SCENE := preload("res://src/game/pieces/piece_view.tscn")
const IDENTITY_FILE := "user://chess_relay_identity.key"
const SAVE_FILE := "user://chess_relay_save.bin"
const AI_SAVE_FILE := "user://chess_relay_ai_save.bin"
const FEN_PIECE_TYPES := {"p": "pawn", "n": "knight", "b": "bishop", "r": "rook", "q": "queen", "k": "king"}
var _camera_scale := 1.0
var _is_multiplayer := false
var _is_ai := false
var _ai_side := "White"
var _ai_difficulty := "Medium"
var _fresh_start := false
var _opponent_name := "Opponent"
var _active_clock_side := "white"
# Out-of-scope furniture, not timekeeping: application_core.md puts the
# clock out of v1 (the host would be timekeeper). This strip only shows
# whose turn the core reports. Delete or replace when the clock lands.
var _white_seconds := 600
var _black_seconds := 598
var _selected_piece_square := ""
var _selected_piece_type := ""
var _selected_piece_side := ""
var _legal_targets: Array[String] = []
var _capture_targets: Array[String] = []
var _castle_targets: Array[String] = []
var _pending_promotion := ""
var _finished := false
var _network_local_loaded := false
var _bridge: ChessCoreBridge
## When false the bridge belongs to the app root (networked game) and
## this screen only borrows it: no resume, no save, no resign-on-leave
## beyond its own side.
var _owns_bridge := true


## Marks a networked game. With a bridge the screen borrows the live
## session; without one it behaves as before (tests, previews).
func configure_peer(bridge: ChessCoreBridge = null, opponent_name: String = "Opponent") -> void:
	_is_multiplayer = true
	# Hide before the node enters the tree. GameStarted can be emitted by the
	# borrowed bridge during the same transition that creates this screen.
	var board := get_node_or_null("%Board") as ChessBoardView
	if board != null:
		board.visible = false
	_opponent_name = opponent_name if not opponent_name.is_empty() else "Opponent"
	if bridge != null:
		_bridge = bridge
		_owns_bridge = false
	if is_node_ready():
		_header.set_peer_context(_is_multiplayer)


func configure_ai(side: String, difficulty: String) -> void:
	_is_ai = true
	_ai_side = side
	_ai_difficulty = difficulty
	_fresh_start = true


func _ready() -> void:
	_header.menu_requested.connect(_open_game_menu)
	_board_view_button.pressed.connect(_toggle_board_view_menu)
	_board.square_pressed.connect(_on_square_pressed)
	_clock_timer.timeout.connect(_on_clock_tick)
	_header.set_peer_context(_is_multiplayer)
	_update_clock_strip()
	_camera.target = CAMERA_TARGET
	_update_camera_framing()
	_start_bridge()
	_sync_bridge_snapshot()
	if _is_multiplayer and _bridge.fen().is_empty():
		_header.set_center_text("Waiting for opponent...")
	if _is_multiplayer:
		_board.visible = false
		_header.set_center_text("Waiting for opponent to load...")
		_network_local_loaded = _bridge.mark_network_loaded()
		if _bridge.network_peer_loaded():
			_reveal_network_board()


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
	var local_side := _bridge.my_side() if _bridge != null else _ai_side.to_lower()
	var local_is_black := local_side == "black"
	var player_seconds := _black_seconds if local_is_black else _white_seconds
	var opponent_seconds := _white_seconds if local_is_black else _black_seconds
	var local_active := "black" if local_is_black else "white"
	_opponent_clock.text = "%s  %s" % [_opponent_name.to_upper(), _format_clock(opponent_seconds)]
	_player_clock.text = "%s  YOU" % _format_clock(player_seconds)
	var active_color := Color(1.0, 0.94, 0.82, 1.0)
	var idle_color := Color(0.72, 0.66, 0.58, 1.0)
	var warning_color := Color(1.0, 0.45, 0.28, 1.0)
	var opponent_color := warning_color if opponent_seconds <= 60 \
		else active_color if _active_clock_side != local_active else idle_color
	var player_color := warning_color if player_seconds <= 60 \
		else active_color if _active_clock_side == local_active else idle_color
	_opponent_clock.add_theme_color_override(
		"font_color", opponent_color)
	_player_clock.add_theme_color_override(
		"font_color", player_color)


## Whole minutes and seconds.
##
## `floori` rather than `/`: integer division silently truncates, which is right
## for a clock by accident and wrong the moment the value is negative or
## fractional. See `game_screen.gd` integer division in the quality gates doc.
func _format_clock(seconds: int) -> String:
	return "%02d:%02d" % [floori(seconds / 60.0), seconds % 60]


## SPIKE-ONLY: the core behind this bridge plays both sides from committed
## spike keys (see rust/src/bridge.rs). Every local game is a forged
## opponent until the transport path replaces it in Phase 7. Do not build
## networked features on local play.
func _start_bridge() -> void:
	if _bridge == null:
		_bridge = ChessCoreBridge.new()
		add_child(_bridge)
	_picker.chosen.connect(_on_promotion_chosen)
	_connect_bridge_signals()
	if _owns_bridge:
		var restored := false
		if _is_ai:
			restored = _bridge.start_ai(
				_abs(IDENTITY_FILE), _abs(AI_SAVE_FILE), _ai_side, _ai_difficulty, _fresh_start)
		else:
			restored = _bridge.start_resumable(
				_abs(IDENTITY_FILE), _abs(SAVE_FILE), _fresh_start)
		if restored:
			_header.set_center_text("Game restored")


## Reconstructs presentation from the current core snapshot after wiring.
## This covers borrowed bridges whose startup events happened before this
## screen existed, as well as restored owned sessions.
func _sync_bridge_snapshot() -> void:
	if not _bridge.is_available() or _bridge.fen().is_empty():
		return
	_sync_board_perspective()
	_rebuild_position()
	_active_clock_side = _bridge.turn()
	_move_number_label.text = "M%d" % _bridge.move_number()
	_update_clock_strip()
	if _bridge.session_finished():
		_finished = true
		_header.set_center_text("Game over")


## One wiring for owned and borrowed bridges alike. A borrowed bridge
## may still be handshaking, so the first game start rebuilds too.
func _connect_bridge_signals() -> void:
	_bridge.move_applied.connect(_on_core_move_applied)
	_bridge.game_started.connect(_on_core_game_started)
	_bridge.game_ended.connect(_on_core_game_ended)
	_bridge.draw_offered.connect(_on_core_draw_offered)
	_bridge.draw_answered.connect(_on_core_draw_answered)
	_bridge.bridge_error.connect(_on_bridge_error)
	_bridge.network_error.connect(_on_net_error)
	_bridge.network_reconnecting.connect(_on_net_reconnecting)
	_bridge.peer_disconnected.connect(_on_peer_disconnected)
	_bridge.peer_loaded.connect(_on_peer_loaded)
	_header.bind_net_bridge(_bridge)


func _on_core_game_started() -> void:
	_sync_board_perspective()
	_rebuild_position()
	_header.set_center_text("Game started · %s to move" % _bridge.turn().capitalize())


func _on_peer_loaded() -> void:
	if _is_multiplayer and _network_local_loaded:
		_reveal_network_board()


func _reveal_network_board() -> void:
	if not _network_local_loaded or not _bridge.network_peer_loaded():
		return
	_board.visible = true
	_header.set_center_text("Game started · %s to move" % _bridge.turn().capitalize())


func _sync_board_perspective() -> void:
	var side := _bridge.my_side()
	if side.is_empty():
		side = _ai_side.to_lower()
	_board.set_player_side(side)


func _on_peer_disconnected() -> void:
	_header.set_center_text("Opponent disconnected")


func _on_net_reconnecting() -> void:
	_header.set_center_text("Reconnecting…")


func _on_net_error(message: String) -> void:
	_header.set_center_text(message)


## Platform paths stay platform business: Godot resolves `user://` per
## OS (desktop profile, app-private storage on Android) and Rust only
## ever sees absolute paths it reads and writes blindly.
func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path)


## Position rendering: the board observes the core, never the reverse.
## Every applied move rebuilds the piece set from the authoritative FEN,
## so captures, promotions and castling need no special cases here.

func _rebuild_position() -> void:
	var pieces_root: Node3D
	var existing := _board.get_node_or_null("Pieces")
	if existing == null:
		pieces_root = Node3D.new()
		pieces_root.name = "Pieces"
		_board.add_child(pieces_root)
	else:
		pieces_root = existing as Node3D
	# Removed synchronously, freed deferred: the rebuild runs inside the
	# tapped surface's own signal emission, and freeing an object while it
	# is emitting is illegal ("Object is locked"). queue_free() runs at
	# idle, outside any emission. The immediate remove is what keeps stale
	# names out of lookups, not the free.
	for child in pieces_root.get_children():
		pieces_root.remove_child(child)
		child.queue_free()
	if not _bridge.is_available():
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
			_add_piece(pieces_root, str(FEN_PIECE_TYPES[token.to_lower()]), side, square)
			file += 1


func _add_piece(parent: Node3D, piece_type: String, side: String, square: String) -> void:
	var piece := PIECE_VIEW_SCENE.instantiate() as ChessPieceView
	# The name carries the square, which is also how a press reads it back in
	# `_on_piece_pressed`. See that function for why that is fragile.
	piece.name = "%s_%s_%s" % [side.capitalize(), piece_type.capitalize(), square]
	piece.piece_pressed.connect(_on_piece_pressed)
	piece.configure(piece_type, side, square)
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
	reset.pressed.connect(func() -> void:
		_camera.reset_view()
	)
	actions.add_child(reset)


func _board_view_action(label: String, degrees: float, menu: Control) -> Button:
	var action := Button.new()
	action.text = label
	action.custom_minimum_size.y = 42.0
	action.theme_type_variation = &"QuietButton"
	action.pressed.connect(func() -> void:
		_camera.orbit_by(degrees)
	)
	return action


func _on_board_view_overlay_input(event: InputEvent, overlay: Control) -> void:
	if not ChessBoardView.is_selecting_press(event):
		return
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
	if not _bridge.is_available():
		return
	if (_is_multiplayer or _is_ai) and _bridge.turn() != _bridge.my_side():
		_header.set_center_text("Waiting for opponent")
		return
	if not _selected_piece_square.is_empty() and square in _legal_targets:
		# A pawn reaching the last rank cannot move as two squares: the
		# promotion piece is the player's call, so ask instead of assuming.
		if _selected_piece_type == "pawn" and (square.right(1) == "8" or square.right(1) == "1"):
			_pending_promotion = _selected_piece_square + square
			_picker.open(_selected_piece_side)
			return
		if _bridge.submit_move(_selected_piece_square + square):
			return
		_header.set_center_text("Illegal move")
		return
	var occupied_side := str(_position_sides(_bridge.fen().split(" ")[0]).get(square, ""))
	var local_side := _bridge.my_side().to_lower()
	if (_is_multiplayer or _is_ai) and not occupied_side.is_empty() and occupied_side != local_side:
		_header.set_center_text("Waiting for opponent")
		return
	_select_square(square, "", "")


func _on_piece_pressed(piece: ChessPieceView) -> void:
	if _finished:
		return
	# Live taps fire both the piece and the board surface for one tap. The
	# first handler can rebuild the position, freeing this node before the
	# second handler runs; calling into a freed node aborts the handler.
	if not is_instance_valid(piece):
		return
	var square: String = piece.square
	# A tap on an occupied target square is a capture, not a new selection:
	# the piece surface sits above the board surface and fires first.
	if not _selected_piece_square.is_empty() and square in _legal_targets:
		_on_square_pressed(square)
		return
	# Ownership applies when selecting a source piece. It must not block an
	# opponent piece that is the destination of an already-selected capture.
	var local_side := _bridge.my_side().to_lower()
	if (_is_multiplayer or _is_ai) and (
		piece.side.to_lower() != local_side or _bridge.turn() != local_side
	):
		_header.set_center_text("Waiting for opponent")
		return
	_select_square(square, piece.side, piece.piece_type)


func _select_square(square: String, side: String, piece_type: String) -> void:
	_selected_piece_square = square
	_selected_piece_type = piece_type
	_selected_piece_side = side
	_legal_targets.clear()
	_capture_targets.clear()
	_castle_targets.clear()
	for target: String in _bridge.legal_moves_from(square):
		if not target in _legal_targets:
			_legal_targets.append(target)
	_capture_targets = _capture_squares(square, _legal_targets)
	_castle_targets = _castle_squares(square, piece_type, _legal_targets)
	var quiet: Array[String] = []
	for target: String in _legal_targets:
		if not target in _capture_targets and not target in _castle_targets:
			quiet.append(target)
	_board.set_highlight(square)
	_board.set_legal_moves(quiet)
	_board.set_capture_moves(_capture_targets)
	_board.set_castle_moves(_castle_targets)
	if _legal_targets.is_empty():
		if side.is_empty():
			_header.set_center_text("Selected %s" % square.to_upper())
		else:
			_header.set_center_text("Selected %s" % piece_type.capitalize())
	else:
		_header.set_center_text("Choose a move")


## Targets holding an enemy piece (or the en-passant square) read as
## captures. Presentation only: the core already decided legality, this
## only chooses the marker from the observed position.
func _capture_squares(from_square: String, targets: Array[String]) -> Array[String]:
	var captures: Array[String] = []
	if _bridge == null:
		return captures
	var fen := _bridge.fen()
	var fields := fen.split(" ")
	if fields.size() < 4:
		return captures
	var occupants := _position_sides(fields[0])
	var mover_side := str(occupants.get(from_square, ""))
	for target in targets:
		if target == fields[3] or str(occupants.get(target, "")) != "" and str(occupants.get(target, "")) != mover_side:
			if not target in captures:
				captures.append(target)
	return captures


## Castling destinations: the king sidestepping two files. Read off the
## visible geometry of the move, like captures; legality stays in the core.
func _castle_squares(from_square: String, piece_type: String, targets: Array[String]) -> Array[String]:
	var castles: Array[String] = []
	if piece_type != "king" or from_square.length() != 2:
		return castles
	for target in targets:
		if target.length() == 2 and abs(target.unicode_at(0) - from_square.unicode_at(0)) == 2:
			castles.append(target)
	return castles


## Maps board squares to "white"/"black" from a FEN placement field.
func _position_sides(placement: String) -> Dictionary:
	var occupants := {}
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
			occupants[square] = "white" if token == token.to_upper() else "black"
			file += 1
	return occupants


func _on_core_move_applied(seq: int, uci: String, by: String, agreed: bool) -> void:
	var from_square := uci.left(2)
	var to_square := uci.substr(2, 2)
	_rebuild_position()
	_board.set_last_move(from_square, to_square)
	_board.set_check_square(_bridge.check_square())
	_board.set_highlight("")
	_board.set_legal_moves([])
	_board.set_capture_moves([])
	_board.set_castle_moves([])
	_selected_piece_square = ""
	_selected_piece_type = ""
	_selected_piece_side = ""
	_pending_promotion = ""
	_legal_targets.clear()
	_capture_targets.clear()
	_castle_targets.clear()
	var move_number := _bridge.move_number()
	_move_number_label.text = "M%d" % move_number
	_active_clock_side = _bridge.turn()
	_update_clock_strip()
	_header.set_center_text("Move %d · %s to move" % [move_number, _active_clock_side.capitalize()])
	_save_if_local()


## Persists the log for owned (local) sessions only. A borrowed
## networked session must never touch the local save: its peers are
## not the resume path's spike pair.
func _save_if_local() -> void:
	if _owns_bridge:
		_bridge.save_game()


func _on_core_game_ended(reason: String) -> void:
	_finished = true
	_pending_promotion = ""
	_picker.close()
	_save_if_local()
	_board.set_highlight("")
	_board.set_legal_moves([])
	_board.set_capture_moves([])
	_board.set_castle_moves([])
	_selected_piece_square = ""
	_legal_targets.clear()
	_capture_targets.clear()
	_castle_targets.clear()
	_header.set_center_text(_end_text(reason))


## Presentation wording for a finished session; the fact itself is Rust's.
func _end_text(reason: String) -> String:
	if "Checkmate" in reason:
		if "White" in reason:
			return "Checkmate · White wins"
		return "Checkmate · Black wins"
	if "Stalemate" in reason:
		return "Draw · stalemate"
	if "FiftyMove" in reason:
		return "Draw · fifty moves"
	if "Threefold" in reason:
		return "Draw · threefold repetition"
	if "InsufficientMaterial" in reason:
		return "Draw · insufficient material"
	if "AgreedDraw" in reason:
		return "Draw agreed"
	if "Resignation" in reason:
		return "Resignation · game over"
	if "Abort" in reason:
		return "Game aborted"
	return "Game over"


func _on_core_draw_offered(by: String, _seq: int) -> void:
	var offering_side := _bridge.side_of_peer(by)
	var is_mine := (_is_multiplayer or _is_ai) and (by == _bridge.my_peer() or offering_side == _bridge.my_side())
	if is_mine:
		_header.set_center_text("Draw offer sent · waiting for opponent")
		return

	var text := "Opponent offers a draw. Accept?"
	if not _is_multiplayer and not _is_ai and not offering_side.is_empty():
		text = "%s offers a draw. Accept?" % offering_side.capitalize()

	var answer := ConfirmationDialog.new()
	answer.theme_type_variation = &"ModalDialog"
	answer.title = "Draw offered"
	answer.dialog_text = text
	answer.dialog_autowrap = true
	answer.ok_button_text = "Accept"
	answer.cancel_button_text = "Decline"
	answer.confirmed.connect(func() -> void:
		_bridge.answer_draw(true)
		answer.queue_free()
	)
	answer.canceled.connect(func() -> void:
		_bridge.answer_draw(false)
		answer.queue_free()
	)
	add_child(answer)
	answer.popup_centered(Vector2i(460, 220))


func _on_core_draw_answered(by: String, accept: bool) -> void:
	if not accept:
		_header.set_center_text("Draw declined")


func _on_promotion_chosen(piece: String) -> void:
	if _pending_promotion.is_empty():
		return
	var uci := _pending_promotion + PromotionPicker.suffix_for(piece)
	_pending_promotion = ""
	if _bridge.submit_move(uci):
		return
	_header.set_center_text("Illegal move")


func _on_bridge_error(message: String) -> void:
	_header.set_center_text(message)


func _open_game_menu() -> void:
	HeaderMenu.toggle_in(
		self,
		["Offer draw", "Leave game"],
		[_offer_draw, _confirm_leave]
	)


func _offer_draw() -> void:
	if not _bridge.offer_draw():
		return
	if _is_multiplayer or _is_ai:
		_header.set_center_text("Draw offer sent · waiting for opponent")


func _confirm_leave() -> void:
	HeaderMenu.confirm_in(
		self,
		"Leave game?",
		"Leave this game and return to the home screen?",
		"Leave game",
		"Stay",
		func() -> void:
			if _is_ai:
				_bridge.stop_ai()
			# Leaving mid-game resigns the side; the result is logged
			# like any other session action.
			_bridge.resign()
			leave_requested.emit()
	)
