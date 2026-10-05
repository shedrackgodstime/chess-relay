extends Control

enum State { IDLE, CONNECTING, DEGRADED, GOOD, LOST }

const BAR_COLOR_IDLE := Color(0.62, 0.60, 0.58, 1.0)
const BAR_COLOR_CONNECTING := Color(1.0, 0.85, 0.25, 1.0)
const BAR_COLOR_GOOD := Color(0.42, 0.92, 0.52, 1.0)
const BAR_COLOR_LOST := Color(1.0, 0.27, 0.20, 1.0)
const BAR_GHOST := Color(1.0, 1.0, 1.0, 0.26)
const BAR_TOPS := [24.0, 18.0, 12.0, 6.0]
const BAR_CENTERS := [10.5, 18.0, 25.5, 33.0]
const BAR_BASELINE := 30.0
const BAR_WIDTH := 3.9

var _active_bars := 0
var _active_color := BAR_COLOR_IDLE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_state(State.IDLE)


func set_state(state: int) -> void:
	match state:
		State.CONNECTING:
			_set_visual_state(1, BAR_COLOR_CONNECTING, "Connection: connecting")
		State.DEGRADED:
			_set_visual_state(2, BAR_COLOR_CONNECTING, "Connection: degraded")
		State.GOOD:
			_set_visual_state(3, BAR_COLOR_GOOD, "Connection: good")
		State.LOST:
			_set_visual_state(1, BAR_COLOR_LOST, "Connection: lost")
		_:
			_set_visual_state(0, BAR_COLOR_IDLE, "Connection: idle")


func _set_visual_state(count: int, color: Color, description: String) -> void:
	_active_bars = count
	_active_color = color
	tooltip_text = description
	queue_redraw()


func _draw() -> void:
	var scale_factor := minf(size.x, size.y) / 36.0
	var origin := Vector2((size.x - 36.0 * scale_factor) * 0.5,
		(size.y - 36.0 * scale_factor) * 0.5)
	draw_circle(origin + Vector2(3.0, BAR_BASELINE) * scale_factor,
		1.5 * scale_factor, BAR_GHOST)
	for index in range(BAR_TOPS.size()):
		var top: float = BAR_TOPS[index] * scale_factor
		var rect := Rect2(
			origin + Vector2(BAR_CENTERS[index] - BAR_WIDTH * 0.5, top),
			Vector2(BAR_WIDTH * scale_factor,
				(BAR_BASELINE - BAR_TOPS[index]) * scale_factor)
		)
		draw_rect(rect, BAR_GHOST)
		if index < _active_bars:
			draw_rect(rect, _active_color)
