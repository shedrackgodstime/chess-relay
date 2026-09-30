class_name AiPlayer
extends RefCounted

## Placeholder opponent: moves a random own piece to a random square.
##
## This is deliberately dumb — there is no rules engine yet, so there is
## nothing smart to choose from. Its purpose is architectural, not sporting:
## it proves a non-tap move source flows through the exact same
## Game.apply_move funnel a network peer will use later. When move generation
## arrives, only choose_move's insides change (random among legal moves, then
## greedy, then search); every caller stays untouched.
##
## Pass a seeded RandomNumberGenerator for deterministic tests; otherwise it
## randomizes itself.


static func choose_move(game: ChessGame, side: int, rng: RandomNumberGenerator = null) -> ChessMove:
	if game == null:
		return null
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var own: Array[Vector2i] = []
	for rank in 8:
		for file in 8:
			var code := game.state.at(file, rank)
			if code != BoardState.EMPTY and BoardState.decode(code).y == side:
				own.append(Vector2i(file, rank))
	if own.is_empty():
		return null

	var from: Vector2i = own[rng.randi_range(0, own.size() - 1)]
	var to := Vector2i(rng.randi_range(0, 7), rng.randi_range(0, 7))
	var guard := 0
	while to == from and guard < 16:
		to = Vector2i(rng.randi_range(0, 7), rng.randi_range(0, 7))
		guard += 1
	if to == from:
		return null
	return ChessMove.new(from, to)
