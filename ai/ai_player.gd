class_name AiPlayer
extends RefCounted

## Placeholder opponent: picks at random from the moves that are actually legal.
##
## Still deliberately sporting-impotent. Its purpose is architectural: it proves
## a non-tap move source flows through the exact same Game.apply_move funnel a
## network peer will use. When the rules engine arrived this became
## "random among legal moves" instead of "random square and hope", which is the
## only change that was needed — every caller stays untouched as search is added.
##
## Choosing from Rules.legal_moves rather than trying a move and inspecting the
## result matters once check exists: a filter that asked the game would silently
## discard replies that were legal, because it could not tell a refusal from a
## crash.
##
## Generates for whichever side is asked, not only the one to move, so it can be
## used to produce a hypothetical reply as well as a real one. Deciding whose
## turn it is belongs to the caller.
##
## Pass a seeded RandomNumberGenerator for deterministic tests; otherwise it
## randomizes itself.

## Give up after this many rejections, so a position with no legal move returns
## null instead of spinning.
const MAX_ATTEMPTS := 200


static func choose_move(game: ChessGame, side: int, rng: RandomNumberGenerator = null) -> ChessMove:
	if game == null:
		return null
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var moves := Rules.legal_moves(game.state, side)
	if moves.is_empty():
		return null
	for _i in MAX_ATTEMPTS:
		var candidate: ChessMove = moves[rng.randi_range(0, moves.size() - 1)]
		if game.is_legal(candidate):
			return candidate
	return moves[rng.randi_range(0, moves.size() - 1)]
