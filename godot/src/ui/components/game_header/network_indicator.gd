extends Control

enum State { IDLE, CONNECTING, DEGRADED, GOOD, LOST }

## The meter's colours live in the theme under the NetworkBars type, and are read
## here rather than held as constants. The control draws its own bars, so it cannot
## take them from a built-in type the way a themed Label would.
const BARS := &"NetworkBars"
const BAR_COUNT := 4
## Array constants are typed explicitly. A plain `[24.0, ...]` is an untyped
## Array, so every read is a Variant, and the arithmetic below then needs a cast
## that the escalating warning gate correctly refuses.
const BAR_TOPS: Array[float] = [24.0, 18.0, 12.0, 6.0]
const BAR_CENTERS: Array[float] = [10.5, 18.0, 25.5, 33.0]
const BAR_BASELINE := 30.0
const BAR_WIDTH := 3.9
## Ban overlay shares the meter's 36-unit space and stroke weight, so LOST reads
## as the same faint ghost signal with a prohibition mark on top rather than a
## second visual language. Direction matches the Lucide ban diagonal (NW-SE).
const BAN_CENTER := Vector2(18.0, 18.0)
const BAN_RADIUS := 13.5
const BAN_POINTS := 48
const BAN_DIAGONAL := 0.7071

var _active_bars := 0
var _active_color := Color.WHITE
var _ghost_color := Color.WHITE
var _show_ban := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ghost_color = _color("bar_ghost")
	set_state(State.IDLE)


## One of this control's own theme colours. A custom theme type has to be read from a
## script; nothing applies it automatically.
func _color(item: String) -> Color:
	return get_theme_color(item, BARS)


func set_state(state: int) -> void:
	match state:
		State.CONNECTING:
			_set_visual_state(1, _color("bar_connecting"), "Connection: connecting", false)
		State.DEGRADED:
			_set_visual_state(2, _color("bar_connecting"), "Connection: degraded", false)
		State.GOOD:
			_set_visual_state(3, _color("bar_good"), "Connection: good", false)
		State.LOST:
			_set_visual_state(0, _color("bar_lost"), "Connection: lost", true)
		_:
			_set_visual_state(0, _color("bar_idle"), "Connection: idle", false)


## Applies measured peer-path quality. Lifecycle state remains separate: this
## method is never used to infer connected/disconnected.
func set_quality(level: int, rtt_ms: int, loss_percent: int, direct: bool) -> void:
	var bounded_level := clampi(level, 1, 4)
	var color := _color("bar_good") if bounded_level >= 3 else _color("bar_connecting")
	if bounded_level == 1:
		color = _color("bar_lost")
	var path_name := "direct" if direct else "relay"
	_set_visual_state(
		bounded_level,
		color,
		"Connection quality: %d/4 · %d ms · %d%% loss · %s" % [
			bounded_level, rtt_ms, loss_percent, path_name],
		false)


func _set_visual_state(count: int, color: Color, description: String, show_ban: bool) -> void:
	_active_bars = count
	_active_color = color
	_show_ban = show_ban
	tooltip_text = description
	queue_redraw()


func _draw() -> void:
	var scale_factor := minf(size.x, size.y) / 36.0
	var origin := Vector2((size.x - 36.0 * scale_factor) * 0.5,
		(size.y - 36.0 * scale_factor) * 0.5)
	draw_circle(origin + Vector2(3.0, BAR_BASELINE) * scale_factor,
		1.5 * scale_factor, _ghost_color)
	for index in range(BAR_COUNT):
		var top: float = BAR_TOPS[index] * scale_factor
		var centre_x: float = BAR_CENTERS[index]
		var rect := Rect2(
			origin + Vector2(centre_x - BAR_WIDTH * 0.5, top),
			Vector2(BAR_WIDTH * scale_factor,
				(BAR_BASELINE - BAR_TOPS[index]) * scale_factor)
		)
		draw_rect(rect, _ghost_color)
		if index < _active_bars:
			draw_rect(rect, _active_color)
	if _show_ban:
		var center := origin + BAN_CENTER * scale_factor
		var radius := BAN_RADIUS * scale_factor
		var width := BAR_WIDTH * scale_factor
		draw_arc(center, radius, 0.0, TAU, BAN_POINTS, _active_color, width, true)
		var diag := Vector2(radius * BAN_DIAGONAL, radius * BAN_DIAGONAL)
		draw_line(center - diag, center + diag, _active_color, width, true)
