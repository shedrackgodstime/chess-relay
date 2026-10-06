class_name GameOrbitCamera
extends Camera3D

## Orbit camera: drag to rotate, wheel or pinch to zoom.
##
## Input is read in `_input` rather than `_unhandled_input`, and that is not a
## style choice. `_unhandled_input` only runs for events the GUI let through, so
## it sits behind every Control on screen: the game screen's root is a full-rect
## Control, and a Control that stops input ends the event before the camera ever
## sees it. That is why the board could not be dragged round while the buttons that
## call `orbit_by` directly worked fine. `_input` runs first and cannot be blocked
## by the GUI, which removes that whole class of problem.
##
## The cost of reading first is that the camera also sees drags that began on a
## button, so a drag is only started when the press did not land on something that
## handles input. See _dragged_by_gui.

@export var target := Vector3.ZERO
@export var yaw_degrees := 0.0
@export var pitch_degrees := 45.0
@export var distance := 15.27
@export var min_distance := 9.0
@export var max_distance := 22.0
@export var min_pitch_degrees := 24.0
@export var max_pitch_degrees := 72.0
@export var rotate_degrees_per_pixel := 0.45
@export var wheel_zoom_step := 1.12

var _dragging_mouse := false

## Fingers currently down, by index.
##
## Tracked because Godot also delivers touch as emulated mouse events. Without
## knowing how many fingers are down, a two-finger pinch arrives as two streams of
## emulated mouse motion and the board spins while the player is trying to zoom.
var _touches := {}


func _ready() -> void:
	_apply()


func reset_view(new_yaw := 0.0, new_pitch := 45.0) -> void:
	yaw_degrees = new_yaw
	pitch_degrees = new_pitch
	_apply()


func set_distance(new_distance: float) -> void:
	distance = clampf(new_distance, min_distance, max_distance)
	_apply()


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


## Reads every kind of pointer input from one place, on purpose: mouse, wheel,
## single-finger drag, two-finger pinch.
##
## Nothing here calls `set_input_as_handled`. Events this camera is not interested
## in have to keep travelling, or the buttons underneath stop working.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventScreenTouch:
		_screen_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_screen_drag(event as InputEventScreenDrag)
	elif event is InputEventMagnifyGesture:
		set_distance(distance / (event as InputEventMagnifyGesture).factor)


func _mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Only a drag that started on empty space rotates the board. Reading input
			# before the GUI means this camera also sees presses meant for a button.
			_dragging_mouse = not _dragged_by_gui(event.position)
		else:
			_dragging_mouse = false
	elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		set_distance(distance / wheel_zoom_step)
	elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		set_distance(distance * wheel_zoom_step)


func _mouse_motion(event: InputEventMouseMotion) -> void:
	# Two fingers down means the gesture is a pinch and belongs to the touch
	# tracker, not to the emulated mouse.
	if not _dragging_mouse or _touches.size() >= 2:
		return
	orbit_by(-event.relative.x * rotate_degrees_per_pixel,
		-event.relative.y * rotate_degrees_per_pixel)


## Whether a press at this point landed on something that handles input.
##
## Walked rather than asked of the viewport, because `gui_get_hovered_control`
## reflects the GUI's own picking and this runs before the GUI has seen the event.
## The deepest match wins, so a button inside a panel beats the panel.
func _dragged_by_gui(position: Vector2) -> bool:
	var blocker: Control = null
	for node in _input_handling_controls(get_viewport()):
		var control := node as Control
		if control.get_global_rect().has_point(position):
			blocker = control
	# No blocker at all is a free drag.
	return blocker != null


func _input_handling_controls(from: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in from.get_children():
		if child is Control:
			var control := child as Control
			# Only controls that actually take input count, and only ones that are
			# really on screen: a hidden panel still has a rect.
			if control.mouse_filter == Control.MOUSE_FILTER_STOP \
					and control.is_visible_in_tree():
				found.append(control)
		found.append_array(_input_handling_controls(child))
	return found


func _screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
	else:
		_touches.erase(event.index)
		if _touches.is_empty():
			_dragging_mouse = false
			remove_meta(&"_pinch_previous")


## One finger tracks its position but does not rotate, because the emulated mouse
## motion already does that and doing it twice doubles the speed. Two fingers pinch.
func _screen_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	_touches[event.index] = event.position
	if _touches.size() == 2:
		_pinch()


func _pinch() -> void:
	var points := _touches.values()
	var current: float = (points[0] as Vector2).distance_to(points[1] as Vector2)
	if current <= 0.0:
		return
	if not has_meta(&"_pinch_previous"):
		set_meta(&"_pinch_previous", current)
		return
	var previous := float(get_meta(&"_pinch_previous"))
	if previous > 0.0:
		set_distance(distance * previous / current)
	set_meta(&"_pinch_previous", current)