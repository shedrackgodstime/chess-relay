extends SceneTree

## Lays every generated icon out at its display size on a background matching
## the game, so the glyphs can be judged by eye.
##
##     godot-headless --headless --script res://tools/render_icons.gd

const CELL := 72
const PAD := 16


func _init() -> void:
	Quality.set_preset(Quality.Preset.MEDIUM)
	var icons := [
		["rotate_left", Icons.rotate_left()],
		["rotate_right", Icons.rotate_right()],
		["flip", Icons.flip()],
		["reset", Icons.reset()],
		["menu", Icons.menu()],
	]

	var sheet := Image.create(CELL * icons.size() + PAD * 2, CELL + PAD * 2, false, Image.FORMAT_RGB8)
	# Same dark ground the scene uses behind the HUD.
	sheet.fill(Color(0.105, 0.115, 0.135))

	for i in icons.size():
		var entry: Array = icons[i]
		var name := String(entry[0])
		var texture: ImageTexture = entry[1]
		var image := texture.get_image()
		image.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
		# Composite over the background, since the icons are transparent.
		for y in CELL:
			for x in CELL:
				var pixel := image.get_pixel(x, y)
				var base := sheet.get_pixel(PAD + i * CELL + x, PAD + y)
				sheet.set_pixel(PAD + i * CELL + x, PAD + y, base.lerp(Color(pixel.r, pixel.g, pixel.b), pixel.a))
		var painted := 0
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).a > 0.35:
					painted += 1
		print("%-13s painted=%d px (%.1f%% of cell)" % [
			name, painted, 100.0 * float(painted) / float(CELL * CELL)
		])

	var path := ProjectSettings.globalize_path("user://icons_preview.png")
	image_save(sheet, path)
	print("Wrote ", path)
	quit(0)


func image_save(image: Image, path: String) -> void:
	image.save_png(path)