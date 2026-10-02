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


## The picture, or nothing if it has not been imported. A missing background is not
## worth a crash and is not worth a fallback that pretends to be the art.
static func background_texture() -> Texture2D:
	if not ResourceLoader.exists(BACKGROUND):
		return null
	return load(BACKGROUND) as Texture2D