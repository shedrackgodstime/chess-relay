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
const AI_SIDE := BoardState.DARK
const AI_DELAY_SECONDS := 0.8
@export var ai_opponent := true

var _ai_thinking := false

## A tap is a press and release with barely any movement, so it never fights
## the orbit drags: anything that travels further is a camera gesture.
const TAP_MAX_DISTANCE := 12.0
const TAP_MAX_SECONDS := 0.6
## How far a picking ray reaches before giving up, in world units. The board
## is 8.76 across, so this comfortably covers it from any allowed zoom.
const PICK_RAY_LENGTH := 40.0

var _press_position := Vector2.ZERO
var _press_time := 0.0
var _press_active := false
var _press_moved := false

## Camera placement as multiples of the board's half-extent, so the default
## view survives a change to BoardMesh's dimensions.
@export_range(0.5, 4.0) var framing_height := 1.50:
	set(value):
		framing_height = value
		frame_board()

@export_range(0.5, 4.0) var framing_distance := 2.20:
	set(value):
		framing_distance = value
		frame_board()


func _ready() -> void:
	frame_board()
	game.reset()
	game.moved.connect(_on_game_moved)
	_collect_pieces()
	_connect_hud()
	hud.bind()
	hud.set_turn(game.state.side_to_move, game.history.size())


## The HUD emits intents; this is the only place that decides what they mean.
## Keeping the routing here means the camera and the game never learn that a
## button exists.
func _connect_hud() -> void:
	hud.rotate_requested.connect(_on_rotate_requested)
	hud.reset_view_requested.connect(frame_board)
	hud.flip_requested.connect(_on_flip_requested)


func _on_rotate_requested(direction: int) -> void:
	camera.orbit_by(direction * HUD_ROTATE_STEP, 0.0)


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
func frame_board() -> void:
	if camera == null:
		return
	camera.reset_view(Vector3.ZERO, 0.0, _framing_pitch(), _framing_distance())


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
		if pieces.has(square):
			selected = square
			highlight.show_at(square.x, square.y)
		return
	if square == selected:
		_deselect()
		return
	if game.apply_move(ChessMove.new(selected, square)):
		_deselect()
		_maybe_ai_move()


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
	piece.glide_to(
		BoardMesh.square_position(move.to_square.x, move.to_square.y),
		piece.piece_type == PieceProfiles.Type.KNIGHT
	)


## Hands the move to the AI when it is its turn. One thinker at a time; the
## delay is presentation pacing, not game logic.
func _maybe_ai_move() -> void:
	if not ai_opponent or _ai_thinking:
		return
	if game.state.side_to_move != AI_SIDE:
		return
	_ai_thinking = true
	await get_tree().create_timer(AI_DELAY_SECONDS).timeout
	_ai_thinking = false
	if game.state.side_to_move != AI_SIDE:
		return
	var move := AiPlayer.choose_move(game, AI_SIDE)
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
