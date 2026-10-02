class_name MatchConfig
extends RefCounted

## What the lobby decided, handed to the game when it loads.
##
## Static rather than passed through the scene tree, because the lobby and the game
## are separate scenes and there is no object that exists in both. That is the whole
## reason the lobby is its own scene, so it is worth being explicit: this is the seam
## between them, and it holds only what was chosen rather than any game state, so the
## game still decides everything about the match itself.
##
## Kept deliberately short. Every field here is a decision the player made in the
## lobby and nothing else, because anything else would be a second source of truth for
## something the game already knows.

enum Difficulty { EASY, MEDIUM, HARD, RANDOM_SIDE }

## Label and value as pairs, in the order the buttons appear.
##
## One array of pairs rather than a label array beside a value array, because two
## parallel arrays have to be kept in step by hand and nothing enforces it. Reordering
## the labels to put Random last while the values still had it first meant choosing
## Black marked Random, and the rows were wrong in a way that looked like a marking
## bug rather than a data one.
##
## Pairs rather than a Dictionary because these have an order, and because a
## Dictionary has no reverse lookup, so matching a label back to the value it means
## would be done by hand at every call site.
const DIFFICULTIES := [
	["Easy", Difficulty.EASY],
	["Medium", Difficulty.MEDIUM],
	["Hard", Difficulty.HARD],
]
const SIDES := [
	["White", BoardState.LIGHT],
	["Black", BoardState.DARK],
	["Random", Difficulty.RANDOM_SIDE],
]


## Just the labels, for a caller that only needs to name the options.
static func labels_of(pairs: Array) -> Array:
	var out: Array = []
	for pair in pairs:
		out.append(str(pair[0]))
	return out


## The value a label means, or -1 when there is no such option.
static func value_for(pairs: Array, label: String) -> int:
	for pair in pairs:
		if str(pair[0]) == label:
			return int(pair[1])
	return -1


## The label a value means, or "" when there is no such option.
static func label_for(pairs: Array, value: int) -> String:
	for pair in pairs:
		if int(pair[1]) == value:
			return str(pair[0])
	return ""

## Which side the player takes. RANDOM_SIDE means the lobby resolves it before the
## board exists, so the board is never seen flipping after it appears.
static var side: int = BoardState.LIGHT

## How hard the opponent should play. Carried through, and not yet acted on: the AI
## plays a random legal move whatever this says. Defaults to Medium rather than the
## easiest, because a first game a player cannot win teaches them the controls faster
## than one they can.
static var difficulty: int = Difficulty.MEDIUM


## The side actually used, with RANDOM_SIDE resolved once and then fixed.
##
## Resolving here rather than in the game keeps the board from being built for one
## side and then turned around, and keeps the randomness in one place so a test can
## seed it.
static func resolve_side(rng: RandomNumberGenerator = null) -> int:
	if side != Difficulty.RANDOM_SIDE:
		return side
	var source := rng if rng != null else RandomNumberGenerator.new()
	return source.randi_range(BoardState.LIGHT, BoardState.DARK)


## Puts both back to their defaults, so a second game cannot inherit the last one's
## choices by accident.
static func clear() -> void:
	side = BoardState.LIGHT
	difficulty = Difficulty.MEDIUM