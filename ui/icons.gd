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
	var img := _blank()
	var centre := Vector2(CANVAS * 0.5, CANVAS * 0.5)
	var radius := CANVAS * 0.30
	var width := CANVAS * 0.068
	# Most of a ring, leaving a gap where the arrow sits. Angles run clockwise
	# on screen because +Y points down.
	var start := -50.0
	var end := 240.0
	_arc(img, centre, radius, width, start, end, 1.0)
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
	var img := _blank()
	var half := CANVAS * 0.30
	var width := CANVAS * 0.070
	var head := CANVAS * 0.13
	var top := CANVAS * 0.35
	var bottom := CANVAS * 0.65
	# Upper arrow points right, lower points left.
	_bar(img, Vector2(-half, top), Vector2(half - head * 0.7, top), width)
	_arrow_head(img, Vector2(half - head * 0.7, top), Vector2.RIGHT, head, width * 1.15)
	_bar(img, Vector2(half, bottom), Vector2(-half + head * 0.7, bottom), width)
	_arrow_head(img, Vector2(-half + head * 0.7, bottom), Vector2.LEFT, head, width * 1.15)
	return img


static func _fallback_reset() -> Image:
	return _crosshair()


## A crosshair: recentre the view.
static func _crosshair() -> Image:
	var img := _blank()
	var centre := Vector2(CANVAS * 0.5, CANVAS * 0.5)
	_arc(img, centre, CANVAS * 0.20, CANVAS * 0.055, 0.0, 360.0, 1.0)
	_disc(img, centre, CANVAS * 0.05)
	for i in 4:
		var direction := Vector2.RIGHT.rotated(deg_to_rad(90.0 * i))
		_bar(img, centre + direction * CANVAS * 0.28, centre + direction * CANVAS * 0.40, CANVAS * 0.05)
	return img


static func _fallback_menu() -> Image:
	return _three_dots()


## Capsule plus stand: close enough to a microphone that the button is never
## ambiguous before the real icon has been imported.
static func _fallback_mic_signal() -> Image:
	var img := _fallback_mic()
	# Two radiating arcs either side, signalling a request going out.
	var y := CANVAS * 0.40
	_arc(img, Vector2(CANVAS * 0.24, y), CANVAS * 0.22, CANVAS * 0.05, 250.0, 290.0, 1.0)
	_arc(img, Vector2(CANVAS * 0.76, y), CANVAS * 0.22, CANVAS * 0.05, 250.0, 290.0, -1.0)
	return img


static func _fallback_mic() -> Image:
	var img := _blank()
	var width := CANVAS * 0.17
	# Capsule: a bar with a disc capping each end, so no polygon fill needed.
	_bar(img, Vector2(CANVAS * 0.5, CANVAS * 0.20), Vector2(CANVAS * 0.5, CANVAS * 0.48), width)
	_disc(img, Vector2(CANVAS * 0.5, CANVAS * 0.20), width * 0.5)
	_disc(img, Vector2(CANVAS * 0.5, CANVAS * 0.48), width * 0.5)
	# Cradle, stem and base.
	_arc(img, Vector2(CANVAS * 0.5, CANVAS * 0.42), CANVAS * 0.21, CANVAS * 0.05, 0.0, 180.0, 1.0)
	_bar(img, Vector2(CANVAS * 0.5, CANVAS * 0.63), Vector2(CANVAS * 0.5, CANVAS * 0.80), CANVAS * 0.05)
	_bar(img, Vector2(CANVAS * 0.37, CANVAS * 0.83), Vector2(CANVAS * 0.63, CANVAS * 0.83), CANVAS * 0.05)
	return img


static func _three_dots() -> Image:
	var img := _blank()
	for i in 3:
		_disc(img, Vector2(CANVAS * 0.5, CANVAS * (0.30 + 0.20 * i)), CANVAS * 0.075)
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

static func _blank() -> Image:
	var img := Image.create(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


static func _plot(img: Image, x: int, y: int) -> void:
	if x >= 0 and x < CANVAS and y >= 0 and y < CANVAS:
		img.set_pixel(x, y, COLOUR)


static func _arc(
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
static func _bar(img: Image, from: Vector2, to: Vector2, width: float) -> void:
	var up := Vector2(0.0, -width * 0.5)
	var down := Vector2(0.0, width * 0.5)
	_triangle(img, from + up, to + up, from + down)
	_triangle(img, to + up, to + down, from + down)
	_disc(img, from, width * 0.5)


static func _inside_triangle(point: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := _sign(point, a, b)
	var d2 := _sign(point, b, c)
	var d3 := _sign(point, c, a)
	var has_negative := d1 < 0.0 or d2 < 0.0 or d3 < 0.0
	var has_positive := d1 > 0.0 or d2 > 0.0 or d3 > 0.0
	return not (has_negative and has_positive)


static func _sign(p1: Vector2, p2: Vector2, p3: Vector2) -> float:
	return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)


static func _disc(img: Image, centre: Vector2, radius: float) -> void:
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