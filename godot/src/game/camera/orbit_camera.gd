class_name GameOrbitCamera
extends Camera3D

## Orbit camera: drag to rotate, wheel or pinch to zoom.
##
## This is the reference prototype's camera, brought over rather than rewritten.
## The behaviour is its behaviour: the same spherical state, the same clamps, the
## same touch tracking, and the same suppression of emulated mouse motion while two
## fingers are down so that pinching zooms instead of spinning the board.
##
## It is brought over because this version, written from scratch in this project,
## would rotate with the on-screen buttons and would not rotate when dragged, on a
## device where the original does both. That is not an argument about style. The
## original works and this one did not, so the original is the one to use.
##
## Two things stay different, because this project's screen needs them and the
## prototype's does not:
##
## - Input is read in `_unhandled_input`, matching the prototype and Godot's
##   gameplay-input guidance. The game screen and HUD roots explicitly use
##   `MOUSE_FILTER_IGNORE`, while interactive controls keep the default STOP filter,
##   so buttons receive first refusal and board drags reach the camera.
## - The distance and pitch limits are this project's, since they are sized against
##   this board and this viewport rather than the prototype's room.

@export var target := Vector3.ZERO

@export_range(0.0, 360.0) var yaw_degrees := 0.0:
	set(value):
		yaw_degrees = value
		_apply()

@export_range(5.0, 90.0) var pitch_degrees := 45.0:
	set(value):
		pitch_degrees = clampf(value, min_pitch_degrees, max_pitch_degrees)
		_apply()

@export var distance := 15.27:
	set(value):
		distance = clampf(value, min_distance, max_distance)
		_apply()

@export var min_distance := 9.0
@export var max_distance := 22.0
@export var min_pitch_degrees := 24.0
@export var max_pitch_degrees := 72.0

## Degrees of orbit per pixel of drag.
@export var rotate_degrees_per_pixel := 0.45
## Multiplicative zoom per wheel tick.
@export var wheel_zoom_step := 1.12

var _dragging_mouse := false
var _touches := {}
var _last_mouse_position := Vector2.ZERO
var _polling_mouse_drag := false


func _ready() -> void:
	_apply()


func _process(_delta: float) -> void:
	if not _touches.is_empty():
		return
	_update_mouse_drag(get_viewport().get_mouse_position(),
		Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))


## Points the camera at the current state.
func reset_view(new_yaw := 0.0, new_pitch := 45.0) -> void:
	yaw_degrees = new_yaw
	pitch_degrees = new_pitch
	_apply()


func set_distance(new_distance: float) -> void:
	distance = clampf(new_distance, min_distance, max_distance)
	_apply()


func zoom_by(factor: float) -> void:
	set_distance(distance * factor)


func orbit_by(yaw_delta: float, pitch_delta := 0.0) -> void:
	yaw_degrees = fmod(yaw_degrees + yaw_delta, 360.0)
	pitch_degrees = clampf(pitch_degrees + pitch_delta, min_pitch_degrees, max_pitch_degrees)
	_apply()


func _apply() -> void:
	var yaw := deg_to_rad(yaw_degrees)
	var pitch := deg_to_rad(pitch_degrees)
	var offset := Vector3(
		cos(pitch) * sin(yaw),
		sin(pitch),
		cos(pitch) * cos(yaw)
	) * distance
	transform = Transform3D(Basis(), target + offset).looking_at(target, Vector3.UP)


## Every kind of pointer input, in one place: mouse drag and wheel, single-finger
## drag and two-finger pinch.
##
## Nothing here calls `set_input_as_handled`. Events the camera is not interested in
## have to keep travelling, or the buttons underneath stop working.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventScreenTouch:
		_screen_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_screen_drag(event as InputEventScreenDrag)
	elif event is InputEventMagnifyGesture:
		zoom_by(1.0 / (event as InputEventMagnifyGesture).factor)
	elif event is InputEventPanGesture:
		var pan := event as InputEventPanGesture
		if absf(pan.delta.y) > 0.0:
			zoom_by(1.0 + pan.delta.y * 0.02)


func _mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_last_mouse_position = event.position
			_dragging_mouse = true
			_polling_mouse_drag = false
		else:
			_dragging_mouse = false
			_polling_mouse_drag = false
	elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		zoom_by(1.0 / wheel_zoom_step)
	elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		zoom_by(wheel_zoom_step)


func _mouse_motion(event: InputEventMouseMotion) -> void:
	# Any finger down means the touch tracker owns the gesture, so the mouse stays out
	# of it entirely.
	#
	# The prototype only stood aside for two fingers, because with one finger the
	# emulated mouse motion did the rotating. On the device this was built on, that
	# emulated motion does not arrive: pinch zoom works, which proves the touch events
	# themselves are delivered, and dragging does nothing, which proves the mouse ones
	# are not. So the touch tracker rotates on its own and the mouse stands aside
	# whenever a finger is down rather than only when two are.
	if not _dragging_mouse or _polling_mouse_drag:
		return
	orbit_by(-event.relative.x * rotate_degrees_per_pixel,
		-event.relative.y * rotate_degrees_per_pixel)


func _update_mouse_drag(position: Vector2, held: bool) -> void:
	if not held:
		_dragging_mouse = false
		_polling_mouse_drag = false
		_last_mouse_position = position
		return
	if not _dragging_mouse:
		if _dragged_by_gui(position):
			_last_mouse_position = position
			return
		_dragging_mouse = true
		_polling_mouse_drag = true
		_last_mouse_position = position
		return
	if not _polling_mouse_drag:
		return
	var relative := position - _last_mouse_position
	_last_mouse_position = position
	if relative.length_squared() > 0.0:
		orbit_by(-relative.x * rotate_degrees_per_pixel,
			-relative.y * rotate_degrees_per_pixel)


## A finger drags the board. Two fingers pinch it.
##
## The rotation is done here rather than left to emulated mouse motion because that
## cannot be relied on: see _mouse_motion. _mouse_motion stands aside while any finger
## is down, so the two cannot both rotate and the board does not spin at twice speed.
func _screen_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	_touches[event.index] = event.position
	if _touches.size() == 1:
		orbit_by(-event.relative.x * rotate_degrees_per_pixel,
			-event.relative.y * rotate_degrees_per_pixel)
	else:
		_pinch_zoom()


func _screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
	else:
		_touches.erase(event.index)
		if _touches.size() < 2 and has_meta(&"_pinch_previous"):
			remove_meta(&"_pinch_previous")
		if _touches.is_empty():
			_dragging_mouse = false
			_polling_mouse_drag = false


func _pinch_zoom() -> void:
	var points := _touches.values()
	var current: float = (points[0] as Vector2).distance_to(points[1] as Vector2)
	if current <= 0.0:
		return
	if not has_meta(&"_pinch_previous"):
		set_meta(&"_pinch_previous", current)
		return
	var previous := float(get_meta(&"_pinch_previous"))
	if previous > 0.0:
		zoom_by(previous / current)
	set_meta(&"_pinch_previous", current)


## Whether a press at this point landed on something that handles input.
##
## Walked rather than asked of the viewport, because `gui_get_hovered_control`
## reflects the GUI's own picking and this runs before the GUI has seen the event.
func _dragged_by_gui(position: Vector2) -> bool:
	for node in _input_handling_controls(get_viewport()):
		var control := node as Control
		if control.get_global_rect().has_point(position):
			return true
	return false


func _input_handling_controls(from: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in from.get_children():
		if child is Control:
			var control := child as Control
			# Only controls that take input, and only ones really on screen: a hidden
			# panel still has a rect.
			if control.mouse_filter == Control.MOUSE_FILTER_STOP \
					and control.is_visible_in_tree():
				found.append(control)
		found.append_array(_input_handling_controls(child))
	return found
