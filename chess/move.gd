class_name ChessMove
extends RefCounted

## A chess move as pure data: no nodes, no animation, no legality.
##
## This is the unit that flows through the whole game: taps build one, the AI
## builds one, and later a network peer will send one. Everything downstream
## (Game, views, protocol) speaks ChessMove, so local, AI and remote moves
## are indistinguishable past this point. to_dict/from_dict is the future
## wire format — JSON-safe today, so the P2P protocol can adopt it as-is.


var from_square := Vector2i(-1, -1)
var to_square := Vector2i(-1, -1)
## Promoted piece type, or -1 for none. Unused until the rules engine arrives.
var promotion := -1


func _init(from := Vector2i(-1, -1), to := Vector2i(-1, -1), promote_to := -1) -> void:
	from_square = from
	to_square = to
	promotion = promote_to


func equals(other: ChessMove) -> bool:
	return other != null and from_square == other.from_square \
		and to_square == other.to_square and promotion == other.promotion


func to_dict() -> Dictionary:
	return {
		"from": [from_square.x, from_square.y],
		"to": [to_square.x, to_square.y],
		"promotion": promotion,
	}


static func from_dict(data: Dictionary) -> ChessMove:
	var from: Array = data.get("from", [-1, -1])
	var to: Array = data.get("to", [-1, -1])
	return ChessMove.new(
		Vector2i(int(from[0]), int(from[1])),
		Vector2i(int(to[0]), int(to[1])),
		int(data.get("promotion", -1))
	)


func _to_string() -> String:
	return "ChessMove(%s -> %s)" % [from_square, to_square]
