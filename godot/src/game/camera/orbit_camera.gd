class_name GameOrbitCamera
extends Camera3D

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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging_mouse = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_distance(distance / wheel_zoom_step)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_distance(distance * wheel_zoom_step)
	elif event is InputEventMouseMotion and _dragging_mouse:
		# Two fingers down means the gesture is a pinch and belongs to the touch
		# tracker, not to the emulated mouse.
		if _touches.size() < 2:
			orbit_by(-event.relative.x * rotate_degrees_per_pixel,
				-event.relative.y * rotate_degrees_per_pixel)
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touches[touch.index] = touch.position
		else:
			_touches.erase(touch.index)
			if _touches.is_empty():
				_dragging_mouse = false
				remove_meta(&"_pinch_previous")
	elif event is InputEventScreenDrag:
		_screen_drag(event as InputEventScreenDrag)
	elif event is InputEventMagnifyGesture:
		set_distance(distance / (event as InputEventMagnifyGesture).factor)


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
