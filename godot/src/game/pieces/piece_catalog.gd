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

static func scene_for(piece_type: String) -> PackedScene:
	return SCENES.get(piece_type) as PackedScene

static func contains(piece_type: String) -> bool:
	return SCENES.has(piece_type)
