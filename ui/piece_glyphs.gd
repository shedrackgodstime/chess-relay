class_name PieceGlyphs
extends RefCounted

## Flat piece silhouettes for the captured trays.
##
## The trays cannot reuse the board's 3D meshes: a tray row needs to read as a
## count at a glance, and sixteen small lit meshes would be both slow and
## illegible. These are 2D outlines instead.
##
## Every SVG is authored with a white stroke and no fill so a single asset
## serves both sides. Godot's modulate multiplies, so a white glyph tinted
## white stays white and the same glyph tinted near-black goes dark. Authoring
## the stroke dark instead would have made black pieces unrepresentable, since
## multiply can only ever darken.
##
## Loading an SVG here gives one asset per piece rather than two; the caller
## picks the colour.

static var _cache := {}

const NAMES := {
	PieceProfiles.Type.PAWN: "pawn",
	PieceProfiles.Type.KNIGHT: "knight",
	PieceProfiles.Type.BISHOP: "bishop",
	PieceProfiles.Type.ROOK: "rook",
	PieceProfiles.Type.QUEEN: "queen",
	PieceProfiles.Type.KING: "king",
}


static func glyph(kind: int) -> Texture2D:
	if _cache.has(kind):
		return _cache[kind]
	var name: String = NAMES.get(kind, "")
	var texture: Texture2D = null
	if name != "" and ResourceLoader.exists("res://ui/pieces/%s.svg" % name):
		texture = load("res://ui/pieces/%s.svg" % name) as Texture2D
	if texture == null:
		texture = ImageTexture.create_from_image(_fallback(kind))
	_cache[kind] = texture
	return texture


static func clear_cache() -> void:
	_cache.clear()


## The tint for a side's pieces in the trays. Light pieces take the warm cream
## used elsewhere in the HUD; dark pieces are near-black rather than pure, so
## they stay readable against the dark board instead of vanishing into it.
static func tint_for(side: int) -> Color:
	if side == BoardState.LIGHT:
		return Color(0.98, 0.94, 0.86)
	return Color(0.16, 0.14, 0.13)


## Rough stand-ins, only reached when the SVGs have not been imported. Enough to
## tell the six apart in a count; the real artwork is what ships.
static func _fallback(kind: int) -> Image:
	var img := Icons.blank_canvas()
	var c := Icons.CANVAS
	var w := c * 0.055
	match kind:
		PieceProfiles.Type.PAWN:
			Icons.stroke_disc(img, Vector2(c * 0.5, c * 0.28), c * 0.12)
			Icons.stroke_bar(img, Vector2(c * 0.5, c * 0.42), Vector2(c * 0.5, c * 0.70), w)
			Icons.stroke_bar(img, Vector2(c * 0.36, c * 0.56), Vector2(c * 0.64, c * 0.56), w)
			Icons.stroke_bar(img, Vector2(c * 0.32, c * 0.76), Vector2(c * 0.68, c * 0.76), w)
		PieceProfiles.Type.KNIGHT:
			Icons.stroke_disc(img, Vector2(c * 0.46, c * 0.30), c * 0.11)
			# Muzzle jutting left, then the neck falling to the base.
			Icons.stroke_bar(img, Vector2(c * 0.30, c * 0.32), Vector2(c * 0.38, c * 0.38), w)
			Icons.stroke_bar(img, Vector2(c * 0.50, c * 0.42), Vector2(c * 0.58, c * 0.72), w)
			Icons.stroke_bar(img, Vector2(c * 0.32, c * 0.76), Vector2(c * 0.66, c * 0.76), w)
		PieceProfiles.Type.BISHOP:
			Icons.stroke_disc(img, Vector2(c * 0.5, c * 0.18), c * 0.07)
			Icons.stroke_arc(img, Vector2(c * 0.5, c * 0.56), c * 0.15, w, 0.0, 180.0, 1.0)
			Icons.stroke_bar(img, Vector2(c * 0.35, c * 0.50), Vector2(c * 0.35, c * 0.62), w)
			Icons.stroke_bar(img, Vector2(c * 0.65, c * 0.50), Vector2(c * 0.65, c * 0.62), w)
			Icons.stroke_bar(img, Vector2(c * 0.34, c * 0.74), Vector2(c * 0.66, c * 0.74), w)
		PieceProfiles.Type.ROOK:
			Icons.stroke_bar(img, Vector2(c * 0.26, c * 0.22), Vector2(c * 0.74, c * 0.22), w)
			Icons.stroke_bar(img, Vector2(c * 0.32, c * 0.22), Vector2(c * 0.32, c * 0.40), w)
			Icons.stroke_bar(img, Vector2(c * 0.68, c * 0.22), Vector2(c * 0.68, c * 0.40), w)
			Icons.stroke_bar(img, Vector2(c * 0.50, c * 0.22), Vector2(c * 0.50, c * 0.40), w)
			Icons.stroke_bar(img, Vector2(c * 0.32, c * 0.22), Vector2(c * 0.32, c * 0.72), w)
			Icons.stroke_bar(img, Vector2(c * 0.68, c * 0.22), Vector2(c * 0.68, c * 0.72), w)
			Icons.stroke_bar(img, Vector2(c * 0.26, c * 0.76), Vector2(c * 0.74, c * 0.76), w)
		PieceProfiles.Type.QUEEN:
			for i in 3:
				var x := c * (0.28 + 0.22 * i)
				Icons.stroke_disc(img, Vector2(x, c * 0.22), c * 0.065)
				Icons.stroke_bar(img, Vector2(x, c * 0.28), Vector2(c * 0.5, c * 0.58), w)
			Icons.stroke_bar(img, Vector2(c * 0.26, c * 0.62), Vector2(c * 0.74, c * 0.62), w)
			Icons.stroke_bar(img, Vector2(c * 0.24, c * 0.78), Vector2(c * 0.76, c * 0.78), w)
		PieceProfiles.Type.KING:
			Icons.stroke_bar(img, Vector2(c * 0.5, c * 0.12), Vector2(c * 0.5, c * 0.34), w)
			Icons.stroke_bar(img, Vector2(c * 0.40, c * 0.20), Vector2(c * 0.60, c * 0.20), w)
			for i in 3:
				var x := c * (0.28 + 0.22 * i)
				Icons.stroke_bar(img, Vector2(x, c * 0.46), Vector2(c * 0.5, c * 0.66), w)
			Icons.stroke_bar(img, Vector2(c * 0.26, c * 0.70), Vector2(c * 0.74, c * 0.70), w)
			Icons.stroke_bar(img, Vector2(c * 0.24, c * 0.84), Vector2(c * 0.76, c * 0.84), w)
	return img