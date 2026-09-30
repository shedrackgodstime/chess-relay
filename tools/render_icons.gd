extends SceneTree

## Draws every control icon inside a simulated button, at the real button
## size and inset, so centring and padding can be judged by eye.
##
##     godot-headless --headless --script res://tools/render_icons.gd

const CELL := 96
const PAD := 12
## Must match Hud.TOUCH_SIZE / Hud.ICON_INSET so this mirrors the real thing.
const BUTTON := Vector2i(64, 64)
const INSET := 12
const PANEL := Color(0.09, 0.08, 0.07, 1.0)
const EDGE := Color(0.45, 0.34, 0.24, 1.0)
const BACKGROUND := Color(0.105, 0.115, 0.135, 1.0)


func _init() -> void:
	Quality.set_preset(Quality.Preset.MEDIUM)
	Icons.clear_cache()
	var icons := [
		["rotate_left", Icons.rotate_left()],
		["rotate_right", Icons.rotate_right()],
		["flip", Icons.flip()],
		["reset", Icons.reset()],
		["menu", Icons.menu()],
		["settings", Icons.settings()],
	]

	var sheet := Image.create(CELL * icons.size() + PAD * 2, CELL + PAD * 2, false, Image.FORMAT_RGB8)
	sheet.fill(BACKGROUND)

	for i in icons.size():
		var entry: Array = icons[i]
		var name := String(entry[0])
		var texture: Texture2D = entry[1]
		var origin := Vector2i(PAD + i * CELL, PAD)
		_panel(sheet, origin)
		var glyph := _centred(texture, BUTTON, INSET)
		_composite(sheet, glyph, origin + Vector2i(BUTTON) / 2 - glyph.get_size() / 2)

		# Measure where the ink actually landed, rather than trusting it.
		var centre := _ink_centre(sheet, origin)
		var target := Vector2(BUTTON) * 0.5
		var drift := centre - target if centre != Vector2(-1, -1) else Vector2(-1, -1)
		print("%-13s size=%dx%d  ink centre offset=(%+.1f, %+.1f) from button centre" % [
			name, texture.get_width(), texture.get_height(), drift.x, drift.y
		])

	var path := ProjectSettings.globalize_path("user://icons_preview.png")
	sheet.save_png(path)
	print("Wrote ", path)
	quit(0)


## Scales a texture into a box the way STRETCH_KEEP_ASPECT_CENTERED does.
func _centred(texture: Texture2D, box: Vector2i, inset: float) -> Image:
	var inner := int(box.x - inset * 2.0)
	var source := texture.get_image()
	if source == null:
		return Image.create(inner, inner, false, Image.FORMAT_RGBA8)
	var scale := minf(float(inner) / source.get_width(), float(inner) / source.get_height())
	var size := Vector2i(maxi(1, int(round(source.get_width() * scale))), maxi(1, int(round(source.get_height() * scale))))
	var out := source.duplicate() as Image
	out.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	return out


## Rounded rectangle, matching the StyleBoxFlat the scene uses: 14 px corners
## with a 1 px border. A signed distance test keeps the border even around
## the corners, which a bounding-box test does not.
func _panel(sheet: Image, origin: Vector2i) -> void:
	var radius := 14.0
	var half := Vector2(BUTTON) * 0.5
	for y in BUTTON.y:
		for x in BUTTON.x:
			var at := origin + Vector2i(x, y)
			var point := Vector2(x + 0.5, y + 0.5)
			var q := (point - half).abs() - (half - Vector2(radius, radius))
			var outside := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() \
				+ minf(maxf(q.x, q.y), 0.0) - radius
			if outside > 0.5:
				continue
			sheet.set_pixel(at.x, at.y, EDGE if outside > -1.0 else PANEL)


func _composite(sheet: Image, image: Image, at: Vector2i) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.01:
				continue
			var target := Vector2i(at.x + x, at.y + y)
			if target.x < 0 or target.y < 0 or target.x >= sheet.get_width() or target.y >= sheet.get_height():
				continue
			sheet.set_pixel(target.x, target.y, sheet.get_pixel(target.x, target.y).lerp(
				Color(pixel.r, pixel.g, pixel.b), pixel.a))


## Average position of non-background pixels inside a button, so centring is
## measured instead of assumed.
func _ink_centre(sheet: Image, origin: Vector2i) -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	for y in BUTTON.y:
		for x in BUTTON.x:
			var at := origin + Vector2i(x, y)
			var pixel := sheet.get_pixel(at.x, at.y)
			# The glyph is cream; the panel and border are not.
			if pixel.r > 0.55 and pixel.g > 0.45 and pixel.b < 0.75:
				total += Vector2(x, y)
				count += 1
	if count == 0:
		return Vector2(-1, -1)
	return total / float(count)
