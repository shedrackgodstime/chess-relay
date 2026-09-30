class_name TextureKit
extends RefCounted

## CPU-generated textures for the procedural materials.
##
## Everything visual in this project is generated, including the surface detail:
## wood grain for the board and a subtle hand-finished mottling for the pieces.
## That keeps the zero-asset rule intact — there are still no image files, no
## import step, and every pixel is reproducible from its seed.
##
## The default 256 px with mipmaps is plenty for phone-sized 3D and keeps
## generation time under a frame budget. Callers pass Quality.texture_size()
## and cache the resulting materials rather than regenerating per rebuild.

## Wood grain: concentric growth rings distorted by low-frequency noise, plus a
## fine speckle. base is the dominant tone, vein is the darker ring colour,
## strength caps how dark the veins get (0..1).
static func wood(base: Color, vein: Color, strength: float, seed_value: int, size: int = 256) -> ImageTexture:
	var warp := FastNoiseLite.new()
	warp.seed = seed_value
	warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	warp.frequency = 0.035

	var fine := FastNoiseLite.new()
	fine.seed = seed_value * 7 + 3
	fine.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fine.frequency = 0.35

	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var nx := float(x) / float(size)
			# Rings run across X, warped so they wander like real grain.
			var rings := sin(
				(nx * 9.0 + warp.get_noise_2d(float(x), float(y)) * 1.6) * TAU
			) * 0.5 + 0.5
			var vein_amount := pow(rings, 2.2) * strength
			var speckle := fine.get_noise_2d(float(x), float(y)) * 0.06
			var t := clampf(vein_amount + speckle, 0.0, 1.0)
			image.set_pixel(x, y, base.lerp(vein, t))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## A quiet finish for turned pieces: large soft mottling plus a whisper of
## grain, so highlights roll off like polished wood or bone instead of flat
## plastic. Variation caps the effect strength (0..1); 0.08 reads as handmade.
static func finish(base: Color, variation: float, seed_value: int, size: int = 256) -> ImageTexture:
	var blotch := FastNoiseLite.new()
	blotch.seed = seed_value
	blotch.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	blotch.frequency = 0.02

	var grain := FastNoiseLite.new()
	grain.seed = seed_value * 13 + 5
	grain.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	grain.frequency = 0.25

	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	var dark := base.darkened(0.35)
	var light := base.lightened(0.12)
	for y in size:
		for x in size:
			var large := blotch.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var small := grain.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var colour := base.lerp(dark, large * variation)
			colour = colour.lerp(light, small * variation * 0.5)
			image.set_pixel(x, y, colour)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
