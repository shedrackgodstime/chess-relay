class_name BoardMesh
extends RefCounted

## Procedural chessboard: 64 squares, a raised frame and a plinth.
##
## The board is centred on the origin and its playing surface sits at y = 0, so
## a piece authored with its base at y = 0 rests on the squares with no offset.
## Files run along X and ranks along Z, with rank 0 at negative Z.
##
## Squares are emitted as two merged groups rather than 64 nodes, so the whole
## board is one MeshInstance3D with three surfaces: light squares, dark squares
## and frame. That keeps the draw-call count and the node count low.

const SQUARES := 8
const SQUARE_SIZE := 1.0
## Gap between squares, in world units, so each square reads as its own tile.
const SQUARE_GAP := 0.035
## Chamfer on the top edge of each tile, so squares catch a highlight.
const SQUARE_BEVEL := 0.018
const SQUARE_THICKNESS := 0.07
const FRAME_MARGIN := 0.38
const FRAME_LIP := 0.025
const FRAME_DEPTH := 0.16
const PLINTH_DEPTH := 0.26
const PLINTH_INSET := 0.12




## World position of the centre of a square, on the playing surface.
## file is 0..7 along X, rank is 0..7 along Z with rank 0 at negative Z.
static func square_position(file: int, rank: int) -> Vector3:
	var half := (SQUARES - 1) * 0.5
	return Vector3((file - half) * SQUARE_SIZE, 0.0, (rank - half) * SQUARE_SIZE)


## Half-extent of the playing area, i.e. the distance from the centre to the
## outer edge of the outermost squares.
static func playing_half_extent() -> float:
	return SQUARES * SQUARE_SIZE * 0.5


static func build() -> ArrayMesh:
	var light := MeshData.new()
	var dark := MeshData.new()
	var frame := MeshData.new()

	var tile := SQUARE_SIZE - SQUARE_GAP
	for file in SQUARES:
		for rank in SQUARES:
			var centre := square_position(file, rank)
			var box := Primitives.beveled_box(
				Vector3(tile, SQUARE_THICKNESS, tile), SQUARE_BEVEL)
			# Squares hang below y = 0 so the surface is flush with the pieces.
			var target := light if (file + rank) % 2 == 0 else dark
			target.append(box, Transform3D(Basis(), centre + Vector3(0.0, -SQUARE_THICKNESS * 0.5, 0.0)))

	_build_frame(frame)
	_build_plinth(frame)

	var builder := MeshBuilder.new()
	builder.add_part(light, BoardMaterials.light_square())
	builder.add_part(dark, BoardMaterials.dark_square())
	builder.add_part(frame, BoardMaterials.frame())
	return builder.build()


## Four rails around the playing area, plus a plinth beneath them.
static func _build_frame(frame: MeshData) -> void:
	var inner := playing_half_extent()
	var outer := inner + FRAME_MARGIN
	var centre_offset := (outer + inner) * 0.5
	var mid_y := FRAME_LIP - FRAME_DEPTH * 0.5

	# Rails running along X cover the full outer width; rails along Z span the
	# gap between them so the corners do not overlap.
	for side in [-1.0, 1.0]:
		var along_x := Primitives.box(Vector3(outer * 2.0, FRAME_DEPTH, FRAME_MARGIN))
		frame.append(
			along_x,
			Transform3D(Basis(), Vector3(0.0, mid_y, side * centre_offset))
		)
		var along_z := Primitives.box(Vector3(FRAME_MARGIN, FRAME_DEPTH, inner * 2.0))
		frame.append(
			along_z,
			Transform3D(Basis(), Vector3(side * centre_offset, mid_y, 0.0))
		)


## A base slab tucked under the tiles and rails, so the board reads as a solid
## object rather than a floating plane. Its top meets the underside of the
## squares to avoid coincident faces.
static func _build_plinth(frame: MeshData) -> void:
	var half := playing_half_extent() + FRAME_MARGIN - PLINTH_INSET
	var plinth := Primitives.box(Vector3(half * 2.0, PLINTH_DEPTH, half * 2.0))
	var top := -SQUARE_THICKNESS
	frame.append(
		plinth,
		Transform3D(Basis(), Vector3(0.0, top - PLINTH_DEPTH * 0.5, 0.0))
	)


