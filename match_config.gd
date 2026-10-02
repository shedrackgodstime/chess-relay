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

## Label to value, in the order the buttons appear. An array rather than a Dictionary
## because a Dictionary has no reverse lookup, and matching a label back to the value
## it means would otherwise be done by hand at every call site.
const DIFFICULTY_LABELS := ["Easy", "Medium", "Hard"]
const SIDE_LABELS := ["Random", "White", "Black"]

## Values matching the label arrays above.
const DIFFICULTY_VALUES := [Difficulty.EASY, Difficulty.MEDIUM, Difficulty.HARD]
const SIDE_VALUES := [Difficulty.RANDOM_SIDE, BoardState.LIGHT, BoardState.DARK]

## Which side the player takes. RANDOM_SIDE means the lobby resolves it before the
## board exists, so the board is never seen flipping after it appears.
static var side: int = Difficulty.RANDOM_SIDE

## How hard the opponent should play. Carried through, and not yet acted on: the AI
## plays a random legal move whatever this says.
static var difficulty: int = Difficulty.EASY


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
	side = Difficulty.RANDOM_SIDE
	difficulty = Difficulty.EASY