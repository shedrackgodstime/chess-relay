class_name ChessPieceView
extends MeshInstance3D

## One piece standing on one square.
##
## The shape comes from `PieceMeshes` and nothing here decides what a piece looks like.
## This node is the board's business: which identity, which side, which square, and
## whether a tap landed on it.
##
## `piece_type` is a plain string rather than an export enum on purpose. An enum in this
## project would be a second list of piece types, and `application_core.md` puts that
## list in Rust's `chess_core`. A name that arrives over the boundary and is looked up
## keeps one list. The cost is no dropdown in the editor, which is the right trade: a
## dropdown would be an editor suggesting this project is the authority.

## The identity as it arrives over the boundary, and the side. Kept as they came so a
## piece moved to another square keeps exactly what it was.
@export var piece_type := "pawn"
@export_enum("white", "black") var side := "white"

## Which square this piece stands on, as board notation. Empty means not on the board.
var square := ""

## Why there is no mesh, when there is none. Set rather than left blank so a missing
## model is visible in the log rather than as a piece that simply is not there.
var missing_shape := ""


func _ready() -> void:
	_apply()


func configure(identity: String, piece_side: String) -> void:
	piece_type = identity
	side = piece_side
	if is_node_ready():
		_apply()


## Puts the piece on a square, and turns it to face the other side when it is dark.
##
## The turn is on every piece rather than only the knight because the models are not
## symmetrical front to back, and a set where only one kind of piece faces its opponent
## reads as a mistake. It is 180 degrees about Y, which is the documented orientation
## difference between the two sides.
func place_on(target_square: String, world_position: Vector3) -> void:
	square = target_square
	position = world_position
	rotation.y = PI if side == "black" else 0.0


func _apply() -> void:
	rotation.y = PI if side == "black" else 0.0
	var identity := StringName(piece_type)
	var found := PieceMeshes.mesh_for(identity)
	if found == null:
		missing_shape = piece_type
		mesh = null
		material_override = null
		push_warning("no model for piece '%s' in set '%s'"
			% [piece_type, PieceMeshes.ACTIVE_SET])
		return
	missing_shape = ""
	# The mesh is shared and carries only geometry. Colour and size are this node's:
	# they are how a piece is presented here, not something about the shape.
	mesh = found
	material_override = PieceMeshes.material_for(
		PieceMeshes.DARK if side == "black" else PieceMeshes.LIGHT)
	scale = PieceMeshes.model_scale_for(identity)
