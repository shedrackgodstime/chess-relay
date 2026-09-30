@tool
class_name OrbitCamera
extends Camera3D

## Orbit camera: drag to rotate, wheel or pinch to zoom.
##
## Spherical state (yaw, pitch, distance) around a target point. Pitch and
## distance are clamped so the camera can neither dive under the board nor
## leave it. The maths is tree-independent (Transform3D.looking_at, never
## Node3D.look_at), so the orbit can be unit-tested headlessly.
##
## Input covers both desktop and phone in one place: mouse drag and wheel,
## plus single-finger drag and two-finger pinch. Single-finger drags also
## arrive as emulated mouse events, so the touch tracker suppresses mouse
## rotation while two fingers are down — otherwise pinching would also spin
## the view. Handled in _unhandled_input so future UI gets first refusal.

@export var target := Vector3.ZERO

@export_range(0.0, 360.0) var yaw_degrees := 0.0:
	set(value):
		yaw_degrees = value
		_apply()

@export_range(5.0, 88.0) var pitch_degrees := 34.0:
	set(value):
		pitch_degrees = clampf(value, min_pitch_degrees, max_pitch_degrees)
		_apply()

@export var distance := 11.7:
	set(value):
		distance = clampf(value, min_distance, max_distance)
		_apply()

@export var min_distance := 5.5
@export var max_distance := 20.0
@export var min_pitch_degrees := 12.0
@export var max_pitch_degrees := 85.0

## Degrees of orbit per pixel of drag. The sign yaws the scene the way map
## apps do; flip it if it ever feels backwards on device.
@export var rotate_degrees_per_pixel := 0.45
## Multiplicative zoom per wheel tick.
@export var wheel_zoom_step := 1.12

var _dragging_mouse := false
var _touches := {}


func _ready() -> void:
	_apply()


## Points the camera at the current state. Public so Main can reframe after
## changing the target or the framing exports.
func reset_view(new_target: Vector3, new_yaw: float, new_pitch: float, new_distance: float) -> void:
	target = new_target
	yaw_degrees = new_yaw
	pitch_degrees = new_pitch
	distance = new_distance
	_apply()


func zoom_by(factor: float) -> void:
	distance = clampf(distance * factor, min_distance, max_distance)
	_apply()


func orbit_by(yaw_delta: float, pitch_delta: float) -> void:
	yaw_degrees = fmod(yaw_degrees + yaw_delta, 360.0)
	pitch_degrees = clampf(pitch_degrees + pitch_delta, min_pitch_degrees, max_pitch_degrees)
	_apply()


func _apply() -> void:
	var yaw := deg_to_rad(yaw_degrees)
	var pitch := deg_to_rad(pitch_degrees)
	var offset := Vector3(
		cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)
	) * distance
	transform = Transform3D(Basis(), target + offset).looking_at(target, Vector3.UP)


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


func _mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			_dragging_mouse = event.pressed
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				zoom_by(1.0 / wheel_zoom_step)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				zoom_by(wheel_zoom_step)


func _mouse_motion(event: InputEventMouseMotion) -> void:
	# While pinching, the first finger also arrives as emulated mouse motion;
	# the touch tracker owns the gesture then, so the mouse stays out of it.
	if not _dragging_mouse or _touches.size() >= 2:
		return
	orbit_by(-event.relative.x * rotate_degrees_per_pixel,
		-event.relative.y * rotate_degrees_per_pixel)


func _screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
	else:
		_touches.erase(event.index)
		if _touches.size() < 2 and has_meta("_pinch_previous"):
			remove_meta("_pinch_previous")
		if _touches.is_empty():
			_dragging_mouse = false


func _screen_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	_touches[event.index] = event.position
	if _touches.size() == 1:
		# Single finger: the emulated mouse motion already rotates, so doing
		# it here too would double the speed. Touch only tracks position.
		pass
	elif _touches.size() == 2:
		_pinch_zoom()


func _pinch_zoom() -> void:
	var points := _touches.values()
	var current := (points[0] as Vector2).distance_to(points[1] as Vector2)
	if current <= 0.0:
		return
	if not has_meta("_pinch_previous"):
		set_meta("_pinch_previous", current)
		return
	var previous := float(get_meta("_pinch_previous"))
	if previous > 0.0:
		zoom_by(previous / current)
	set_meta("_pinch_previous", current)
