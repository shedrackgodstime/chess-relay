class_name Icons
extends RefCounted

## Control icons.
##
## The shipped glyphs are Lucide SVGs in ui/icons, recoloured to the game's
## cream-gold and authored at 64 px so they stay crisp when a button expands
## them. Lucide is the reference; see https://lucide.dev.
##
## Each has a procedural fallback drawn from an arc, a triangle and a disc.
## The fallback exists because SVG import needs the editor's asset pipeline,
## which is unavailable in the headless environment the tests run in, so a
## missing import would otherwise leave the HUD with no icons at all and fail
## the layout tests for no real reason. On a machine that can import, the SVG
## always wins.

const CANVAS := 128
## Warm cream-gold, matching the selection highlight.
const COLOUR := Color(1.0, 0.88, 0.62)

static var _cache := {}


static func rotate_left() -> Texture2D:
	return _icon("rotate_left", _fallback_rotate_left)


static func rotate_right() -> Texture2D:
	return _icon("rotate_right", _fallback_rotate_right)


## Two arrows pointing opposite ways: the universal "swap sides" glyph.
static func flip() -> Texture2D:
	return _icon("flip", _fallback_flip)


static func reset() -> Texture2D:
	return _icon("reset", _fallback_reset)


static func menu() -> Texture2D:
	return _icon("menu", _fallback_menu)


## Reserved for the settings screen in the menu.
static func settings() -> Texture2D:
	return _icon("settings", _fallback_menu)


## Voice chat. The muted glyph is a separate icon rather than a tint, because
## "you are not speaking" needs to be unmistakable at a glance mid-game.
static func mic() -> Texture2D:
	return _icon("mic", _fallback_mic)


static func mic_off() -> Texture2D:
	return _icon("mic_off", _fallback_mic)


## Asking for voice, distinct from having it. Broadcasting rather than merely
## muted, so it must not be confusable with the off state.
static func mic_signal() -> Texture2D:
	return _icon("mic_signal", _fallback_mic_signal)


static func clear_cache() -> void:
	_cache.clear()


## Prefers the imported SVG, falling back to a drawn glyph when it is absent.
## Signal bars for the connection indicator, in the colour asked for.
##
## Not built through _icon, because that bakes the cream-gold in and this is the
## one glyph whose colour is the message. Nor is it cached on the count alone: two
## states of the same shape in different colours must stay distinct textures, so the
## cache key carries both.
##
## Ascending bars rather than the wifi arcs. This is a direct peer-to-peer link,
## not a network being associated with, and nested arcs say router. Bars also
## survive being drawn small, where arcs stop being countable.
##
## How many bars the meter has, and so how tall the unlit frame is.
const SIGNAL_BARS := 4

## The unlit frame. White at low opacity rather than a state colour, so it reads as
## capacity and can never be mistaken for a level.
## 0.22 was drawn, and drawn correctly, and read as nothing on a real screen: the
## bars were too faint to see and only the baseline dot registered, which looks
## exactly like a broken control. Drawn is not visible. At this size on a dark room
## the frame needs to be near half opacity to read as a meter, and the strokes need
## to be wide enough to survive being scaled down.
const SIGNAL_GHOST := Color(1.0, 1.0, 1.0, 0.42)

## The live bars. Opaque, so the two are separable by brightness alone, which is what
## lets the test tell capacity from level without reading hues.
const NETWORK_LIT_ALPHA := 1.0

static func signal_bars(count: int, colour: Color) -> Texture2D:
	var key := "signal_%d_%s" % [count, colour.to_html(false)]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Lucide's geometry in its own 24-unit space, scaled up: baseline at y=20, and the
	# four bars topping out at 16, 12, 8 and 4.
	var scale := CANVAS / 24.0
	var baseline := 20.0 * scale
	# Thicker than Lucide's 2, deliberately. Faithful at 64 px, this is drawn at 36,
	# where a 2-unit stroke lands on about two pixels and stops reading as a bar.
	var width := 2.6 * scale
	# The baseline dot belongs to the frame, not to any state.
	stroke_disc_tinted(img, Vector2(2.0 * scale, baseline), 3.0, SIGNAL_GHOST)
	# The whole frame first, faintly, then the live bars on top of it. The frame is
	# the reason this reads at all: a bare dot says nothing about what the control is
	# or what it could show, and an idle state with nothing drawn is
	# indistinguishable from a broken one. With it, idle says "a meter, at nothing".
	for i in maxi(SIGNAL_BARS, 0):
		stroke_bar_v(img, (7.0 + 5.0 * i) * scale,
			(20.0 - 4.0 - 4.0 * i) * scale, baseline, width, SIGNAL_GHOST)
	for i in clampi(count, 0, SIGNAL_BARS):
		stroke_bar_v(img, (7.0 + 5.0 * i) * scale,
			(20.0 - 4.0 - 4.0 * i) * scale, baseline, width, colour)
	var texture := ImageTexture.create_from_image(img)
	_cache[key] = texture
	return texture


## A vertical stroke, which is the only primitive Lucide's bars need and which
## nothing else in this file draws. Plain and squared-off rather than rounded: at
## the size this is actually seen, rounding is two pixels of guessing that cannot be
## checked here.
static func stroke_bar_v(
	img: Image, x: float, top: float, bottom: float, width: float, colour: Color
) -> void:
	var half := width * 0.5
	# The colour is used as given, alpha included. Forcing the alpha to opaque here is
	# what made the signal meter's unlit frame indistinguishable from its live bars:
	# the frame drew fully solid, so every state painted the same four bars and only
	# the hue differed.
	for y in range(int(top), int(bottom) + 1):
		for px in range(int(x - half), int(x + half) + 1):
			if px < 0 or px >= CANVAS or y < 0 or y >= CANVAS:
				continue
			img.set_pixel(px, y, colour)


static func _icon(name: String, fallback: Callable) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var texture: Texture2D = null
	var path := "res://ui/icons/%s.svg" % name
	if ResourceLoader.exists(path):
		var loaded := ResourceLoader.load(path)
		if loaded is Texture2D:
			texture = loaded
	if texture == null:
		texture = ImageTexture.create_from_image(fallback.call())
	_cache[name] = texture
	return texture


## Fallback glyphs, used only when the SVG has not been imported.


static func _fallback_rotate_right() -> Image:
	return _circular_arrow()


static func _fallback_rotate_left() -> Image:
	return _mirror_x(_circular_arrow())


## Circular arrow, clockwise. The left-facing one is this mirrored, which
## guarantees the pair is exactly symmetric instead of nearly so.
static func _circular_arrow() -> Image:
	var img := blank_canvas()
	var centre := Vector2(CANVAS * 0.5, CANVAS * 0.5)
	var radius := CANVAS * 0.30
	var width := CANVAS * 0.068
	# Most of a ring, leaving a gap where the arrow sits. Angles run clockwise
	# on screen because +Y points down.
	var start := -50.0
	var end := 240.0
	stroke_arc(img, centre, radius, width, start, end, 1.0)
	var end_angle := deg_to_rad(end)
	var tip := centre + Vector2(cos(end_angle), sin(end_angle)) * radius
	# Tangent in the direction of travel at the arc's end.
	var tangent := Vector2(-sin(end_angle), cos(end_angle))
	_arrow_head(img, tip, tangent, CANVAS * 0.15, width * 0.95)
	return img


static func _fallback_flip() -> Image:
	return _swap_arrows()


## Two arrows pointing opposite ways: the universal "swap sides" glyph.
static func _swap_arrows() -> Image:
	var img := blank_canvas()
	var half := CANVAS * 0.30
	var width := CANVAS * 0.070
	var head := CANVAS * 0.13
	var top := CANVAS * 0.35
	var bottom := CANVAS * 0.65
	# Upper arrow points right, lower points left.
	stroke_bar(img, Vector2(-half, top), Vector2(half - head * 0.7, top), width)
	_arrow_head(img, Vector2(half - head * 0.7, top), Vector2.RIGHT, head, width * 1.15)
	stroke_bar(img, Vector2(half, bottom), Vector2(-half + head * 0.7, bottom), width)
	_arrow_head(img, Vector2(-half + head * 0.7, bottom), Vector2.LEFT, head, width * 1.15)
	return img


static func _fallback_reset() -> Image:
	return _crosshair()


## A crosshair: recentre the view.
static func _crosshair() -> Image:
	var img := blank_canvas()
	var centre := Vector2(CANVAS * 0.5, CANVAS * 0.5)
	stroke_arc(img, centre, CANVAS * 0.20, CANVAS * 0.055, 0.0, 360.0, 1.0)
	stroke_disc(img, centre, CANVAS * 0.05)
	for i in 4:
		var direction := Vector2.RIGHT.rotated(deg_to_rad(90.0 * i))
		stroke_bar(img, centre + direction * CANVAS * 0.28, centre + direction * CANVAS * 0.40, CANVAS * 0.05)
	return img


static func _fallback_menu() -> Image:
	return _three_dots()


## Capsule plus stand: close enough to a microphone that the button is never
## ambiguous before the real icon has been imported.
static func _fallback_mic_signal() -> Image:
	var img := _fallback_mic()
	# Two radiating arcs either side, signalling a request going out.
	var y := CANVAS * 0.40
	stroke_arc(img, Vector2(CANVAS * 0.24, y), CANVAS * 0.22, CANVAS * 0.05, 250.0, 290.0, 1.0)
	stroke_arc(img, Vector2(CANVAS * 0.76, y), CANVAS * 0.22, CANVAS * 0.05, 250.0, 290.0, -1.0)
	return img


static func _fallback_mic() -> Image:
	var img := blank_canvas()
	var width := CANVAS * 0.17
	# Capsule: a bar with a disc capping each end, so no polygon fill needed.
	stroke_bar(img, Vector2(CANVAS * 0.5, CANVAS * 0.20), Vector2(CANVAS * 0.5, CANVAS * 0.48), width)
	stroke_disc(img, Vector2(CANVAS * 0.5, CANVAS * 0.20), width * 0.5)
	stroke_disc(img, Vector2(CANVAS * 0.5, CANVAS * 0.48), width * 0.5)
	# Cradle, stem and base.
	stroke_arc(img, Vector2(CANVAS * 0.5, CANVAS * 0.42), CANVAS * 0.21, CANVAS * 0.05, 0.0, 180.0, 1.0)
	stroke_bar(img, Vector2(CANVAS * 0.5, CANVAS * 0.63), Vector2(CANVAS * 0.5, CANVAS * 0.80), CANVAS * 0.05)
	stroke_bar(img, Vector2(CANVAS * 0.37, CANVAS * 0.83), Vector2(CANVAS * 0.63, CANVAS * 0.83), CANVAS * 0.05)
	return img


static func _three_dots() -> Image:
	var img := blank_canvas()
	for i in 3:
		stroke_disc(img, Vector2(CANVAS * 0.5, CANVAS * (0.30 + 0.20 * i)), CANVAS * 0.075)
	return img


## A triangle pointing along direction, with its base on the given point.
static func _arrow_head(img: Image, base: Vector2, direction: Vector2, length: float, half_width: float) -> void:
	var forward := direction.normalized()
	var side := forward.rotated(PI * 0.5)
	_triangle(
		img,
		base + forward * length,
		base + side * half_width,
		base - side * half_width
	)


## Flips an image left to right.
static func _mirror_x(image: Image) -> Image:
	var size := image.get_size()
	var out := Image.create(int(size.x), int(size.y), false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for y in int(size.y):
		for x in int(size.x):
			out.set_pixel(int(size.x) - 1 - x, y, image.get_pixel(x, y))
	return out


# --- raster primitives -------------------------------------------------------

## Shared drawing primitives. Public because the captured-tray glyphs fall back
## to the same rasteriser rather than keeping a second copy of it.
static func blank_canvas() -> Image:
	var img := Image.create(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


static func _plot(img: Image, x: int, y: int) -> void:
	if x >= 0 and x < CANVAS and y >= 0 and y < CANVAS:
		img.set_pixel(x, y, COLOUR)


static func stroke_arc(
	img: Image, centre: Vector2, radius: float, width: float,
	start_deg: float, end_deg: float, direction: float
) -> void:
	var inner := radius - width * 0.5
	var outer := radius + width * 0.5
	for y in CANVAS:
		for x in CANVAS:
			var offset := Vector2(x + 0.5, y + 0.5) - centre
			var distance := offset.length()
			if distance < inner or distance > outer:
				continue
			var angle := rad_to_deg(atan2(offset.y, offset.x))
			if not _angle_in_sweep(angle, start_deg, end_deg, direction):
				continue
			_plot(img, x, y)


## Sweep test that honours the direction of travel, so an arc can wrap past
## 360 degrees the short way instead of drawing almost nothing.
static func _angle_in_sweep(angle: float, start: float, end: float, direction: float) -> bool:
	var a := fposmod(angle, 360.0)
	var s := fposmod(start, 360.0)
	var e := fposmod(end, 360.0)
	# A full turn: the naive test below would reduce this to a single angle.
	if is_equal_approx(s, e):
		return true
	if direction >= 0.0:
		return (a >= s and a <= e) if s <= e else (a >= s or a <= e)
	return (a <= s and a >= e) if s >= e else (a <= s or a >= e)


static func _triangle(img: Image, a: Vector2, b: Vector2, c: Vector2) -> void:
	var min_x := maxi(0, int(floor(minf(a.x, minf(b.x, c.x)))))
	var max_x := mini(CANVAS - 1, int(ceil(maxf(a.x, maxf(b.x, c.x)))))
	var min_y := maxi(0, int(floor(minf(a.y, minf(b.y, c.y)))))
	var max_y := mini(CANVAS - 1, int(ceil(maxf(a.y, maxf(b.y, c.y)))))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if _inside_triangle(Vector2(x + 0.5, y + 0.5), a, b, c):
				_plot(img, x, y)


## A straight stroke: one quad as two triangles, plus a round-ish cap.
## A stroke of constant width between two points, with rounded caps.
static func stroke_bar(img: Image, from: Vector2, to: Vector2, width: float) -> void:
	var axis := to - from
	# Offsets must be perpendicular to the line, not always vertical: a fixed
	# vertical offset makes the two triangles collapse to zero area on a
	# vertical bar, so the stroke silently vanishes.
	if axis.length_squared() < 0.0001:
		stroke_disc(img, from, width * 0.5)
		return
	var normal := axis.orthogonal().normalized() * (width * 0.5)
	_triangle(img, from + normal, to + normal, from - normal)
	_triangle(img, to + normal, to - normal, from - normal)
	# Both ends, so bars meeting at an angle join without a notch.
	stroke_disc(img, from, width * 0.5)
	stroke_disc(img, to, width * 0.5)


static func _inside_triangle(point: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := _sign(point, a, b)
	var d2 := _sign(point, b, c)
	var d3 := _sign(point, c, a)
	var has_negative := d1 < 0.0 or d2 < 0.0 or d3 < 0.0
	var has_positive := d1 > 0.0 or d2 > 0.0 or d3 > 0.0
	return not (has_negative and has_positive)


static func _sign(p1: Vector2, p2: Vector2, p3: Vector2) -> float:
	return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)


## A disc in a given colour, for the signal meter's baseline dot, which belongs to
## the unlit frame rather than to any state.
static func stroke_disc_tinted(
	img: Image, centre: Vector2, radius: float, colour: Color
) -> void:
	for y in CANVAS:
		for x in CANVAS:
			if Vector2(x + 0.5, y + 0.5).distance_squared_to(centre) <= radius * radius:
				if x >= 0 and x < CANVAS and y >= 0 and y < CANVAS:
					img.set_pixel(x, y, colour)


static func stroke_disc(img: Image, centre: Vector2, radius: float) -> void:
	for y in CANVAS:
		for x in CANVAS:
			if Vector2(x + 0.5, y + 0.5).distance_squared_to(centre) <= radius * radius:
				_plot(img, x, y)


static func _min_of(points: PackedVector2Array, want_y: bool) -> float:
	var best := INF
	for p in points:
		best = minf(best, p.y if want_y else p.x)
	return best


static func _max_of(points: PackedVector2Array, want_y: bool) -> float:
	var best := -INF
	for p in points:
		best = maxf(best, p.y if want_y else p.x)
	return best