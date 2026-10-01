@tool
class_name Main
extends Node3D

## Entry point for the prototype.
##
## Following the recommended scene layout, Main owns the World and is the only
## place that knows about both the board and the pieces. Gameplay will grow
## here; for now the one piece of logic worth having is camera framing, so the
## camera stays correct if the board size ever changes.

@onready var world: Node3D = $World
@onready var camera: OrbitCamera = $World/Camera
@onready var highlight: SquareHighlight = $World/Highlight
@onready var hud: Hud = $UILayer/Hud
@onready var tray_light: TrayView = $World/TrayLight
@onready var tray_dark: TrayView = $World/TrayDark

## Degrees of orbit per press of a rotate button.
const HUD_ROTATE_STEP := 22.5

## Selected square as (file, rank), or (-1, -1) for nothing selected.
var selected := Vector2i(-1, -1)

## Piece node on each occupied square. Presentation only: the authoritative
## position of every piece lives in `game`. Main is the only owner of this
## mapping; pieces animate themselves, but only Main decides where they stand.
var pieces := {}

## The authoritative game. Taps, the AI and later network peers all submit
## moves here; this node only reacts to its `moved` signal.
var game := ChessGame.new()

## The AI plays Dark a short beat after every move that leaves it to move.
## Off in tests, on for the demo; the funnel does not care who submits.

const AI_DELAY_SECONDS := 0.8
@export var ai_opponent := true

## The side the human plays. The opponent is always the other one, so flipping
## the board is purely cosmetic and can never hand the player the other side's
## pieces.
@export_enum("Light", "Dark") var player_side: int = BoardState.LIGHT:
	set(value):
		player_side = clampi(value, 0, 1)
		_deselect()

## Dev only. The voice controls stay up in every mode so the affordance can be
## exercised without a second device on the network. Flip this to false once the
## transport exists and the button can gate on a connected opponent for real.
const DEV_SHOW_VOICE := true

var _ai_thinking := false

## A tap is a press and release with barely any movement, so it never fights
## the orbit drags: anything that travels further is a camera gesture.
const TAP_MAX_DISTANCE := 12.0
const TAP_MAX_SECONDS := 0.6
## How far a picking ray reaches before giving up, in world units. The board
## is 8.76 across, so this comfortably covers it from any allowed zoom.
const PICK_RAY_LENGTH := 40.0

## Yaw the reset view sits at: looking in from the player's own side, so their
## pieces are at the bottom of the screen and the opponent's at the top.
const DEFAULT_YAW := 180.0

var _press_position := Vector2.ZERO
var _press_time := 0.0
var _press_active := false
var _press_moved := false

## Camera placement as multiples of the board's half-extent, so the default view
## survives a change to BoardMesh's dimensions.
##
## The current pair was set from an on-screen readout: yaw 0.2, pitch 41.9,
## distance 10.81. These two encode that angle and reach rather than being them,
## so to go back to a raw pitch and distance, take the ratio length as
## distance / (half-extent + frame margin) and split it by the pitch angle.
@export_range(0.5, 4.0) var framing_height := 1.648235:
	set(value):
		framing_height = value
		frame_board()

@export_range(0.5, 4.0) var framing_distance := 1.836988:
	set(value):
		framing_distance = value
		frame_board()


func _ready() -> void:
	frame_board()
	game.reset()
	game.moved.connect(_on_game_moved)
	_collect_pieces()
	_connect_hud()
	if hud.promotion_picker != null:
		hud.promotion_picker.chosen.connect(_on_promotion_chosen)
	hud.bind()
	hud.set_turn(game.state.side_to_move, game.history.size())
	# Voice is a property of the mode, so it is decided once here rather than
	# on every move. DEV_SHOW_VOICE keeps it up without a second device.
	hud.set_voice_visible(DEV_SHOW_VOICE or not ai_opponent)
	_refresh_trays()


## The HUD emits intents; this is the only place that decides what they mean.
## Keeping the routing here means the camera and the game never learn that a
## button exists.
func _connect_hud() -> void:
	hud.rotate_requested.connect(_on_rotate_requested)
	hud.reset_view_requested.connect(frame_board)
	hud.flip_requested.connect(_on_flip_requested)
	# The menu has no screen behind it yet; Phase 4 builds the settings
	# shell that listens for this.
	hud.menu_requested.connect(_on_menu_requested)


func _on_rotate_requested(direction: int) -> void:
	camera.orbit_by(direction * HUD_ROTATE_STEP, 0.0)


func _on_menu_requested() -> void:
	pass


## Flipping the board is a half turn; pressing it again returns to the
## original side, which is what players expect from a flip control. It reuses
## the same framing as reset rather than calling frame_board, which would
## zero the yaw again and undo the flip.
func _on_flip_requested() -> void:
	if camera == null:
		return
	var target := 180.0 if fmod(camera.yaw_degrees, 360.0) < 90.0 else 0.0
	camera.reset_view(Vector3.ZERO, target, _framing_pitch(), _framing_distance())


## Registers every piece by the square it stands on. Positions come from the
## scene layout, so the generator stays the single source of placement.
func _collect_pieces() -> void:
	pieces.clear()
	_register_subtree(world)


func _register_subtree(node: Node) -> void:
	for child in node.get_children():
		if child is PieceView:
			var square := world_to_square((child as Node3D).position)
			if square.x >= 0:
				(child as PieceView).home_square = square
				pieces[square] = child
		_register_subtree(child)


## Places the camera back and above the board, looking at its centre.
## The height/distance ratios convert to an orbit pitch and distance, so the
## default view survives a change to BoardMesh's dimensions. Changing either
## export resets a user-moved camera back to this framing.
## Default view: the player's own pieces at the bottom of the screen, the
## opponent's at the top.
##
## Yaw 180 puts the camera on the -Z side, which is where rank 1 is, so White's
## back rank sits nearest the viewer. Yaw 0 looked from +Z instead, which put
## rank 8 at the bottom: the player's pieces were at the top and, because squares
## are named A1 to H8 with White on ranks 1 and 2, the labels were upside down
## relative to what was on screen.
func frame_board() -> void:
	if camera == null:
		return
	camera.reset_view(Vector3.ZERO, DEFAULT_YAW, _framing_pitch(), _framing_distance())


## Pitch and distance that frame the board, derived from the exported ratios
## so the default view survives a change to BoardMesh's dimensions. Shared by
## reset and flip, which differ only in yaw.
func _framing_pitch() -> float:
	return rad_to_deg(atan2(framing_height, framing_distance))


func _framing_distance() -> float:
	var extent: float = BoardMesh.playing_half_extent() + BoardMesh.FRAME_MARGIN
	return extent * Vector2(framing_distance, framing_height).length()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_tap_button((event as InputEventMouseButton).pressed,
			(event as InputEventMouseButton).position,
			(event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT)
	elif event is InputEventMouseMotion:
		_tap_move((event as InputEventMouseMotion).position)
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.index == 0:
			_tap_button(touch.pressed, touch.position, true)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == 0:
			_tap_move(drag.position)


func _tap_button(pressed: bool, position: Vector2, is_primary: bool) -> void:
	if not is_primary:
		_press_active = false
		return
	if pressed:
		_press_active = true
		_press_moved = false
		_press_position = position
		_press_time = Time.get_ticks_msec() / 1000.0
	elif _press_active:
		_press_active = false
		var held := Time.get_ticks_msec() / 1000.0 - _press_time
		if not _press_moved and held <= TAP_MAX_SECONDS:
			_tap(position)


func _tap_move(position: Vector2) -> void:
	if _press_active and _press_position.distance_to(position) > TAP_MAX_DISTANCE:
		_press_moved = true


## Handles a tap: selection is local intent, but every move goes through the
## game funnel, exactly like an AI or network move will. No legality yet, by
## design: tapping a piece selects it, tapping anywhere else submits the move,
## and landing on an enemy piece captures it.
func _tap(screen_position: Vector2) -> void:
	var square := _pick_square(screen_position)
	if square.x < 0:
		_deselect()
		return
	if selected.x < 0:
		if _may_take(square):
			selected = square
			highlight.show_at(square.x, square.y)
		return
	if square == selected:
		_deselect()
		return
	# A piece already in hand can only be released on a legal turn. Without
	# this the player could move their own pieces while it was the opponent's
	# move, which puts two sides in the same game.
	if not _may_move_now():
		_deselect()
		return
	var move := ChessMove.new(selected, square)
	# A promotion is the one move two taps cannot fully describe. Hold it until
	# the player has said which piece, rather than applying a queen and changing
	# it afterwards: the glide would animate the wrong piece, and the opponent's
	# copy would have to be told about it after the fact.
	if Rules.is_promotion(game.state, move) and move.promotion < 0 \
			and _may_ask_for_promotion():
		_pending_promotion = move
		hud.ask_promotion(player_side)
		_deselect()
		return
	if game.apply_move(move):
		_deselect()
		_maybe_ai_move()


## The promotion waiting on the player's answer, if any.
var _pending_promotion: ChessMove = null


## Whether a promotion should be put to the player. Only for the side they
## play: the AI chooses for itself, and a move arriving over the wire has
## already been decided by whoever sent it.
func _may_ask_for_promotion() -> bool:
	return _pending_promotion == null


## Finishes the held promotion with the player's choice. The move was never
## applied, so there is nothing to roll back.
func _on_promotion_chosen(type: int) -> void:
	hud.close_promotion()
	var move := _pending_promotion
	_pending_promotion = null
	if move == null:
		return
	move.promotion = type
	# The view is updated before the move is applied, so the piece that glides
	# across the board is already the one that was chosen rather than a pawn
	# wearing a new mesh on arrival.
	if pieces.has(move.from_square):
		(pieces[move.from_square] as PieceView).piece_type = type
	if game.apply_move(move):
		_maybe_ai_move()


## The side the opponent plays: always the one the player is not.
func opponent_side() -> int:
	return 1 - player_side


## Whether this square may be picked up right now.
##
## With an AI opponent the player only ever touches their own side, and only on
## their own turn. Without one, both sides are playable so the rules engine can
## be driven from a single device.
func _may_take(square: Vector2i) -> bool:
	if not pieces.has(square):
		return false
	if not ai_opponent:
		return true
	var piece: PieceView = pieces[square]
	return piece.side == player_side and game.state.side_to_move == player_side


func _may_move_now() -> bool:
	if not ai_opponent:
		return true
	return game.state.side_to_move == player_side


## Which board square a screen point refers to, preferring an actual piece
## over the board beneath it.
##
## The picking ray is tested against each piece's collider first, because a
## ray aimed at the y = 0 plane alone passes straight over anything tall: a
## tap on a king's head used to miss entirely. Only if no piece is hit does
## the ray fall through to the board, so empty squares still work.
func _pick_square(screen_position: Vector2) -> Vector2i:
	if camera == null:
		return Vector2i(-1, -1)
	var world := get_viewport().get_camera_3d()
	if world == null:
		return Vector2i(-1, -1)

	var origin := world.project_ray_origin(screen_position)
	var direction := world.project_ray_normal(screen_position)

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * PICK_RAY_LENGTH)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		var node := hit.get("collider") as Node
		var owner_piece := _piece_owning(node)
		if owner_piece != null and owner_piece.home_square.x >= 0:
			return owner_piece.home_square

	return screen_to_square(screen_position)


## Walks up from a hit node to the PieceView that owns it, so the collider can
## be any descendant of the piece.
func _piece_owning(node: Node) -> PieceView:
	var current := node
	while current != null:
		if current is PieceView:
			return current as PieceView
		current = current.get_parent()
	return null


func _deselect() -> void:
	selected = Vector2i(-1, -1)
	highlight.hide_marker()


## Presents a committed move: updates the node registry, captures victims,
## glides the mover. The registry updates immediately; animation only moves
## pixels, so presentation never depends on a tween finishing.
func _on_game_moved(move: ChessMove, _captured: int) -> void:
	if not pieces.has(move.from_square):
		return
	var piece: PieceView = pieces[move.from_square]
	pieces.erase(move.from_square)
	if pieces.has(move.to_square):
		var victim: PieceView = pieces[move.to_square]
		pieces.erase(move.to_square)
		victim.capture()
	pieces[move.to_square] = piece
	piece.home_square = move.to_square
	hud.set_turn(game.state.side_to_move, game.history.size())
	_refresh_trays()
	piece.glide_to(
		BoardMesh.square_position(move.to_square.x, move.to_square.y),
		piece.piece_type == PieceProfiles.Type.KNIGHT
	)


## Repaints both capture trays from the game's capture lists.
##
## Read from the game rather than pushed to the trays as moves happen, so a tray
## can never show pieces the board state no longer has.
func _refresh_trays() -> void:
	if tray_light != null:
		tray_light.refresh_from(game)
	if tray_dark != null:
		tray_dark.refresh_from(game)


## Hands the move to the AI when it is its turn. One thinker at a time; the
## delay is presentation pacing, not game logic.
func _maybe_ai_move() -> void:
	if not ai_opponent or _ai_thinking:
		return
	if game.state.side_to_move != opponent_side():
		return
	_ai_thinking = true
	await get_tree().create_timer(AI_DELAY_SECONDS).timeout
	_ai_thinking = false
	if game.state.side_to_move != opponent_side():
		return
	var move := AiPlayer.choose_move(game, opponent_side())
	if move != null:
		game.apply_move(move)


## Maps a world position onto a board square. Used to register pieces from
## the scene layout; input uses screen_to_square instead.
static func world_to_square(world_position: Vector3) -> Vector2i:
	var file := int(round(world_position.x + 3.5))
	var rank := int(round(world_position.z + 3.5))
	if file < 0 or file >= BoardMesh.SQUARES or rank < 0 or rank >= BoardMesh.SQUARES:
		return Vector2i(-1, -1)
	return Vector2i(file, rank)


## Maps a screen point onto a board square via the playing plane (y = 0).
## Returns (-1, -1) when the ray misses the board entirely.
func screen_to_square(screen_position: Vector2) -> Vector2i:
	if camera == null:
		return Vector2i(-1, -1)
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.00001:
		return Vector2i(-1, -1)
	var distance := -origin.y / direction.y
	if distance < 0.0:
		return Vector2i(-1, -1)
	var hit := origin + direction * distance
	return world_to_square(hit)
