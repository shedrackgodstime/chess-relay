@tool
class_name PieceView
extends MeshInstance3D

## A single procedurally generated chess piece.
##
## Exposes the piece's identity as exported properties so pieces can be
## configured in the inspector and duplicated freely. The mesh is generated on
## change rather than stored in the scene, so changing a property re-lathes the
## piece immediately in the editor viewport.
##
## side is an index into PieceProfiles' palette: 0 is the light set, 1 the dark.

@export_enum("Light", "Dark") var side: int = 0:
	set(value):
		side = clampi(value, 0, 1)
		rebuild()

@export var piece_type: PieceProfiles.Type = PieceProfiles.Type.PAWN:
	set(value):
		piece_type = value
		rebuild()

## Knight heads are modelled facing +X. Rotating them to face the opposing
## side is what makes a full set read correctly, so this is exposed rather than
## hard-coded.
@export var face_opponent: bool = false:
	set(value):
		face_opponent = value
		rotation.y = PI if value else 0.0


func _ready() -> void:
	rebuild()


## Regenerates the piece geometry for the current type and side.
func rebuild() -> void:
	mesh = PieceMesh.build(piece_type, side)
	rotation.y = PI if face_opponent else 0.0
