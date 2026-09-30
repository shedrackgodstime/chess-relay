@tool
class_name TableView
extends MeshInstance3D

## Draws the round table. Same pattern as BoardView: generated in _ready rather
## than stored in the scene, so the .tscn stays small and the mesh follows the
## quality tier.

func _ready() -> void:
	rebuild()


func rebuild() -> void:
	mesh = TableMesh.build()
