class_name ChessPieceCatalog
extends RefCounted

const SCENES := {
	"pawn": preload("res://assets/chess/pieces/pawn.tscn"),
	"rook": preload("res://assets/chess/pieces/rook.tscn"),
	"knight": preload("res://assets/chess/pieces/knight.tscn"),
	"bishop": preload("res://assets/chess/pieces/bishop.tscn"),
	"queen": preload("res://assets/chess/pieces/queen.tscn"),
	"king": preload("res://assets/chess/pieces/king.tscn"),
}

## Shape lookup: an arriving piece identity maps to a scene.
##
## Does not declare which piece types exist. `application_core.md` puts piece
## identity in Rust's `chess_core`; the six keys below are the shapes this
## project can draw, not the pieces a game may contain. A shape the core sends
## that is not here returns null, and `ChessPieceView.configure` refuses it
## rather than substituting a placeholder.

## Null when there is no shape for this identity, which is a refusal rather than
## a placeholder: a missing shape must be visible, not approximated.
static func scene_for(piece_type: String) -> PackedScene:
	if not SCENES.has(piece_type):
		return null
	var scene: PackedScene = SCENES[piece_type]
	return scene

static func contains(piece_type: String) -> bool:
	return SCENES.has(piece_type)
