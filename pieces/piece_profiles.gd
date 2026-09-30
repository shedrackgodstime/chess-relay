class_name PieceProfiles
extends RefCounted

## Profile data for the six chess pieces, plus the palette.
##
## Every piece except the knight is a solid of revolution, so it is described
## by a single Vector2(radius, height) profile running bottom to top. The
## knight needs a non-axisymmetric head, which is added separately as an
## extruded outline.
##
## Proportions: the board square is 1.0 unit, so a piece's base radius is kept
## near 0.27-0.34. Wider than that and the pieces read as discs balancing on
## the board rather than as carved chessmen. Heights run from about 0.64 for a
## pawn to 1.29 for the king including its cross.
##
## This class is data only. PieceMesh turns it into geometry.

enum Type {
	PAWN,
	KNIGHT,
	BISHOP,
	ROOK,
	QUEEN,
	KING,
}

const TYPE_NAMES := {
	Type.PAWN: "Pawn",
	Type.KNIGHT: "Knight",
	Type.BISHOP: "Bishop",
	Type.ROOK: "Rook",
	Type.QUEEN: "Queen",
	Type.KING: "King",
}

## Knight head, in its own local space: X forward, Y up from the base of the
## neck. Closed and simple, so it triangulates; Extrude handles the concavity
## around the muzzle and between the ears.
static var KNIGHT_HEAD := PackedVector2Array([
	Vector2(0.000, 0.000),
	Vector2(0.000, 0.152),
	Vector2(0.016, 0.266),
	Vector2(0.040, 0.352),
	Vector2(0.064, 0.409),
	Vector2(0.088, 0.475),
	Vector2(0.108, 0.361),
	Vector2(0.140, 0.470),
	Vector2(0.160, 0.380),
	Vector2(0.200, 0.328),
	Vector2(0.248, 0.276),
	Vector2(0.296, 0.214),
	Vector2(0.340, 0.157),
	Vector2(0.360, 0.119),
	Vector2(0.348, 0.081),
	Vector2(0.312, 0.062),
	Vector2(0.268, 0.052),
	Vector2(0.240, 0.029),
	Vector2(0.228, 0.000),
])

## Where the head sits on the knight's lathed base, and how it is posed.
const KNIGHT_HEAD_HEIGHT := 0.360
const KNIGHT_HEAD_TILT_DEGREES := -11.0
const KNIGHT_HEAD_HALF_DEPTH := 0.072
const KNIGHT_HEAD_TAPER := 0.16
const KNIGHT_HEAD_PIVOT := Vector2(0.128, 0.114)


## Shared foot. Every piece starts from the same sculpted base so the set looks
## like one family rather than six unrelated shapes. Its height scales with the
## radius, so a king's foot is proportionally deeper than a pawn's.
##
## The Y values are radius * these factors.
static func _foot(radius: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(radius * 0.840, 0.0),
		Vector2(radius * 0.960, radius * 0.045),
		Vector2(radius, radius * 0.145),
		Vector2(radius * 0.975, radius * 0.275),
		Vector2(radius * 0.875, radius * 0.385),
		Vector2(radius * 0.720, radius * 0.460),
	])


## Joins a foot to a body. The body is given as control points and sampled
## into a smooth dense profile, so each piece only describes what makes it
## different and the lathe never sees the kinks of hand-plotted points.
static func _assemble(radius: float, controls: PackedVector2Array) -> PackedVector2Array:
	var assembled := _foot(radius)
	assembled.append_array(ProfileCurve.even_spaced(ProfileCurve.sample(controls, 8), 0.030))
	return assembled


static var PAWN := _assemble(0.270, PackedVector2Array([
	Vector2(0.150, 0.170),
	Vector2(0.118, 0.245),
	Vector2(0.162, 0.295),
	Vector2(0.112, 0.332),
	Vector2(0.116, 0.375),
	Vector2(0.168, 0.455),
	Vector2(0.126, 0.540),
	Vector2(0.030, 0.612),
	Vector2(0.000, 0.640),
]))

static var ROOK := _assemble(0.320, PackedVector2Array([
	Vector2(0.190, 0.200),
	Vector2(0.172, 0.290),
	Vector2(0.175, 0.430),
	Vector2(0.205, 0.470),
	Vector2(0.260, 0.535),
	Vector2(0.262, 0.650),
	Vector2(0.262, 0.650),
	Vector2(0.248, 0.672),
	Vector2(0.150, 0.678),
	Vector2(0.000, 0.676),
]))

static var BISHOP := _assemble(0.310, PackedVector2Array([
	Vector2(0.132, 0.205),
	Vector2(0.110, 0.300),
	Vector2(0.158, 0.344),
	Vector2(0.112, 0.380),
	Vector2(0.166, 0.468),
	Vector2(0.124, 0.518),
	Vector2(0.136, 0.578),
	Vector2(0.120, 0.640),
	Vector2(0.080, 0.700),
	Vector2(0.042, 0.762),
	Vector2(0.052, 0.808),
	Vector2(0.000, 0.870),
]))

static var QUEEN := _assemble(0.330, PackedVector2Array([
	Vector2(0.140, 0.215),
	Vector2(0.118, 0.320),
	Vector2(0.192, 0.380),
	Vector2(0.122, 0.428),
	Vector2(0.146, 0.492),
	Vector2(0.184, 0.570),
	Vector2(0.168, 0.650),
	Vector2(0.124, 0.712),
	Vector2(0.140, 0.752),
	Vector2(0.110, 0.782),
	Vector2(0.066, 0.812),
	Vector2(0.070, 0.858),
	Vector2(0.038, 0.900),
	Vector2(0.000, 1.000),
]))

static var KING := _assemble(0.340, PackedVector2Array([
	Vector2(0.148, 0.225),
	Vector2(0.126, 0.340),
	Vector2(0.202, 0.400),
	Vector2(0.130, 0.452),
	Vector2(0.158, 0.520),
	Vector2(0.192, 0.600),
	Vector2(0.178, 0.680),
	Vector2(0.130, 0.742),
	Vector2(0.150, 0.782),
	Vector2(0.116, 0.812),
	Vector2(0.072, 0.845),
	Vector2(0.076, 0.892),
	Vector2(0.058, 0.962),
	Vector2(0.058, 1.030),
	Vector2(0.058, 1.030),
	Vector2(0.000, 1.030),
]))

## Two-tone palette. Index 0 is the light side, index 1 the dark side.
const PIECE_COLORS := [
	Color(0.910, 0.885, 0.830),
	Color(0.205, 0.180, 0.168),
]


## Base radius for a piece type. The detail geometry in PieceMesh scales off
## this, so changing a piece's width only needs changing it here.
static func radius_for(type: int) -> float:
	match type:
		Type.PAWN:
			return 0.270
		Type.KNIGHT:
			return 0.300
		Type.BISHOP:
			return 0.310
		Type.ROOK:
			return 0.320
		Type.QUEEN:
			return 0.330
		Type.KING:
			return 0.340
	return 0.300


static func profile(type: int) -> PackedVector2Array:
	match type:
		Type.PAWN:
			return PAWN
		Type.KNIGHT:
			return _knight_base()
		Type.BISHOP:
			return BISHOP
		Type.ROOK:
			return ROOK
		Type.QUEEN:
			return QUEEN
		Type.KING:
			return KING
	push_error("Unknown piece type: %d" % type)
	return PackedVector2Array()


## The knight's lathed part stops at the collar; the head is extruded on top.
static func _knight_base() -> PackedVector2Array:
	return _assemble(0.300, PackedVector2Array([
		Vector2(0.140, 0.200),
		Vector2(0.130, 0.255),
		Vector2(0.180, 0.292),
		Vector2(0.180, 0.322),
		Vector2(0.126, 0.348),
		Vector2(0.070, 0.372),
		Vector2(0.000, 0.380),
	]))


## Base tint for a side. PieceMaterials owns the real textured materials; this
## stays because the CPU preview renderer shades with flat tints and because
## tests use it as the readable statement of the palette.
static func color_for(side: int) -> Color:
	return PIECE_COLORS[side] if side >= 0 and side < PIECE_COLORS.size() else Color.MAGENTA


static func type_name(type: int) -> String:
	return TYPE_NAMES.get(type, "Unknown")
