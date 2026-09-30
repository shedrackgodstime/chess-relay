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

## Selected square as (file, rank), or (-1, -1) for nothing selected.
var selected := Vector2i(-1, -1)

## Piece on each occupied square. Main is the only owner of this mapping:
## pieces animate themselves, but only Main decides where they stand.
var pieces := {}

## A tap is a press and release with barely any movement, so it never fights
## the orbit drags: anything that travels further is a camera gesture.
const TAP_MAX_DISTANCE := 12.0
const TAP_MAX_SECONDS := 0.6

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
	_collect_pieces()


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
	var extent: float = BoardMesh.playing_half_extent() + BoardMesh.FRAME_MARGIN
	var pitch := rad_to_deg(atan2(framing_height, framing_distance))
	var orbit_distance := extent * Vector2(framing_distance, framing_height).length()
	camera.reset_view(Vector3.ZERO, 0.0, pitch, orbit_distance)


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


## Handles a tap. No legality yet, by design: tapping a piece selects it,
## tapping anywhere else moves the selection there, and landing on an enemy
## piece captures it. Same square or empty space deselects.
func _tap(screen_position: Vector2) -> void:
	var square := screen_to_square(screen_position)
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
	_move_selected_to(square)
	_deselect()


func _deselect() -> void:
	selected = Vector2i(-1, -1)
	highlight.hide_marker()


## Moves the selected piece, capturing whatever stands on the destination.
## The registry updates immediately; the animation only moves pixels, so game
## state never depends on a tween finishing.
func _move_selected_to(square: Vector2i) -> void:
	if not pieces.has(selected):
		return
	var piece: PieceView = pieces[selected]
	pieces.erase(selected)
	if pieces.has(square):
		var victim: PieceView = pieces[square]
		pieces.erase(square)
		victim.capture()
	pieces[square] = piece
	piece.home_square = square
	piece.glide_to(
		BoardMesh.square_position(square.x, square.y),
		piece.piece_type == PieceProfiles.Type.KNIGHT
	)


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
