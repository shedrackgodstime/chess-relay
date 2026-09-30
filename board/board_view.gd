@tool
class_name BoardView
extends MeshInstance3D

## Draws the procedurally generated board.
##
## Being a tool script means the geometry is rebuilt in the editor, so the
## board is visible while working on the scene instead of only at runtime.
## The mesh is generated rather than authored, so it is not saved into the
## .tscn; rebuild() is the only way to refresh it after changing the
## constants in BoardMesh.

func _ready() -> void:
	rebuild()


## Regenerates the board geometry. Cheap enough to call freely.
func rebuild() -> void:
	mesh = BoardMesh.build()
