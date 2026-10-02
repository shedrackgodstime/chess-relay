class_name ScreenStyle
extends RefCounted

## The one place the game's screens are described, so they cannot drift apart.
##
## The lobby was built once without this and rendered flush to the corner of a blank
## screen, one tap after a centred menu over artwork. Both screens were individually
## defensible and together they were inconsistent, which is the failure mode this file
## exists to remove: styling that is written per screen is styling that is written
## slightly differently per screen.
##
## So a colour or a corner radius appears here once and every screen reads it. If
## something genuinely needs to differ between two screens, that is the signal to
## change it here and look at both, rather than to open a third copy.

## Warm cream-gold, used by the title on every screen and by the selection highlight
## on the board. One hue across the game, so the words and the pieces belong together.
const TITLE := Color(1.0, 0.88, 0.62)
const TEXT := Color(1.0, 0.90, 0.72)
const TEXT_HOVER := Color(1.0, 1.0, 1.0)
const CAPTION := Color(0.92, 0.86, 0.74)
const MUTED := Color(0.72, 0.66, 0.58)
const SHADE := Color(0.05, 0.04, 0.03)

## Outline on text, because text sits over artwork and a bare word on a picture is
## unreadable in half the frame.
const OUTLINE := Color(0.05, 0.04, 0.03)
const OUTLINE_SIZE := 8
const OUTLINE_SIZE_SMALL := 6

## How much the home picture is held back so the words read first.
##
## Judged by eye on a real screen four times: 0.55 and 0.72 were too light, 0.86 a
## touch too dark, and this is the settled value. The glow behind the king survives a
## light wash almost intact because it is a large luminance contrast rather than a
## bright area, and dimming a contrast is not the same as dimming a highlight.
const BACKGROUND_SHADE := 0.90

## The dark an in-app screen sits on, where there is no picture behind it. Darker than
## a plain black so the buttons read as raised rather than as holes.
const PANEL := Color(0.11, 0.09, 0.08)
const PANEL_HOVER := Color(0.16, 0.13, 0.11)
const PANEL_PRESSED := Color(0.26, 0.20, 0.15)

## The chosen option, deliberately amber rather than another cream: it has to read as
## selected rather than as lit, and it is the same warm accent the board uses to mean
## something is live.
const CHOSEN := Color(0.42, 0.32, 0.12)

const BORDER := Color(0.30, 0.24, 0.18)
const BORDER_WIDTH := 2
const CORNER := 12

## Width of the content on a configuration screen: two option groups with a gap
## between them, which needs room to sit either side of the centre axis without
## sprawling. Chosen so the composition stays in the middle third of a landscape
## screen rather than reaching towards the edges.
const CONTENT_WIDTH := 760.0

## One option group. Wide enough for the longest label and its selection mark without
## the text looking loose in the space.
const GROUP_WIDTH := 232.0

## The gap between the two groups. Close enough that they read as one pair of
## questions and not as two screens; wide enough that a word in one cannot be mistaken
## for a word in the other.
const GROUP_GAP := 72.0

## The rule between configuration and action. Shorter than the content, so it marks a
## change of kind rather than spanning the whole composition like a border.
const DIVIDER_WIDTH := 220.0

## One option's text. Well under the title, which is the point: they were the same
## size once and the title stopped reading as a title.
const OPTION_SIZE := 18

## A group's caption above its options.
const CAPTION_SIZE := 13

## The mark that says an option is chosen. A bullet rather than a filled circle:
## Open Sans has no U+25CF and it would render as a missing glyph, and a bullet is a
## dot at the size this is drawn anyway. Kept in one place so every list in the game
## marks its choice the same way.
const MARK_ON := "\u2022 "
const MARK_OFF := "\u00a0\u00a0"

## Side indicators, drawn rather than typed. The font has no white or black king, so
## the marks are discs: hollow for White, filled for Black, which is the convention
## everyone already reads, and Random is a question mark the font does have.
const MARK_SIZE := 17.0

const DISC_SIZE := 13.0
const DISC_HOLLOW := Color(0.92, 0.86, 0.74, 0.85)
const DISC_FILLED := Color(0.30, 0.26, 0.22, 0.95)

## How far in from the screen edge a screen-level control sits, such as the lobby's
## Back. One value so it does not creep towards the edge on whichever screen was
## adjusted last.
const EDGE := 20.0

## The picture used on the front door. Static so every screen that shows one reads the
## same file rather than loading its own idea of it.
const BACKGROUND := "res://home_bg.jpg"


## A button face. One function so hover, pressed and chosen are all the same shape.
static func button_box(tint: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = tint
	box.border_color = BORDER
	box.set_border_width_all(BORDER_WIDTH)
	box.set_corner_radius_all(CORNER)
	return box


## The three states a plain button is drawn in.
static func button_styles(button: Button, font_size: int = 22) -> void:
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", TEXT_HOVER)
	button.add_theme_stylebox_override("normal", button_box(PANEL))
	button.add_theme_stylebox_override("hover", button_box(PANEL_HOVER))
	button.add_theme_stylebox_override("pressed", button_box(PANEL_PRESSED))


## An option that can be chosen, which is pressed-looking when it is. Applied after
## button_styles so the chosen face wins over the normal one.
static func choice_styles(button: Button, font_size: int = 20) -> void:
	button_styles(button, font_size)
	button.add_theme_stylebox_override("pressed", button_box(CHOSEN))


## A title, sized for a screen rather than for a panel.
static func title_style(label: Label, font_size: int = 40) -> void:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TITLE)
	label.add_theme_color_override("font_outline_color", OUTLINE)
	label.add_theme_constant_override("outline_size", OUTLINE_SIZE)


## A line that says something without asking for anything.
static func quiet_style(label: Label, font_size: int = 15) -> void:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", MUTED)
	label.add_theme_color_override("font_outline_color", OUTLINE)
	label.add_theme_constant_override("outline_size", OUTLINE_SIZE_SMALL)


## The wash that holds the front-door picture back. See BACKGROUND_SHADE.
static func background_shade(colour: Color, alpha: float) -> Color:
	return Color(colour.r, colour.g, colour.b, alpha)


## Almost nothing, for a row that shows its own state in its text.
##
## Separate from an empty box on purpose: this is the one state where a hover is worth
## having at all, because there is no face to notice otherwise, and it has to stay
## faint or it competes with the bullet that says which option is chosen.
static func faint_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(TITLE, 0.06)
	box.set_corner_radius_all(CORNER)
	return box


## A small disc, hollow or filled, as a texture.
##
## Drawn here rather than typed because the font has no king glyph for either side.
## An Image is used directly rather than an ImageTexture so the caller gets something
## it can draw with whatever it likes, and the disc is anti-aliased by hand since a
## hard-edged 13 px dot is the one place the lobby looks cheap.
static func disc_texture(filled: bool, radius: int = 8) -> ImageTexture:
	var size := radius * 2 + 3
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var centre := Vector2(radius + 1.0, radius + 1.0)
	var tint := DISC_FILLED if filled else DISC_HOLLOW
	for y in size:
		for x in size:
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(centre)
			var coverage := 0.0
			if filled:
				coverage = clampf(radius + 0.5 - distance, 0.0, 1.0)
			else:
				# A ring is the band between the inner and outer radius, so coverage is
				# the *smaller* of how far inside the outer edge and how far past the
				# inner one. Subtracting them instead filled the middle in, which made
				# the hollow disc identical to the filled one and both sides of the
				# choice look the same.
				var outer := clampf(radius + 0.5 - distance, 0.0, 1.0)
				var past_inner := clampf(distance - (radius - 3.0), 0.0, 1.0)
				coverage = minf(outer, past_inner)
			if coverage > 0.0:
				image.set_pixel(x, y, Color(tint.r, tint.g, tint.b, tint.a * coverage))
	return ImageTexture.create_from_image(image)


## The picture, or nothing if it has not been imported. A missing background is not
## worth a crash and is not worth a fallback that pretends to be the art.
static func background_texture() -> Texture2D:
	if not ResourceLoader.exists(BACKGROUND):
		return null
	return load(BACKGROUND) as Texture2D