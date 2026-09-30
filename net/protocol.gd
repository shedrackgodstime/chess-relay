class_name Protocol
extends RefCounted

## Message shapes for the P2P link. No I/O, no sockets, no Godot multiplayer.
##
## This is the entire contract between the game and whatever transport carries
## it. Every message is a plain Dictionary, so any transport can encode it as
## JSON, msgpack, protobuf-by-hand or raw JSON-over-TCP, and the game never
## learns which.
##
## Design rule: the game never trusts a peer's claimed outcome. A MOVE carries
## only intent (a ChessMove) plus the sender's sequence number; the receiver
## applies it through its own Game, exactly as it would apply a local move.
## If the two boards ever disagree, SYNC carries a full position and repairs
## it. That keeps peers symmetric — neither one is authoritative — which is
## what P2P implies and what makes the checksum worth having.

const VERSION := 1

enum Kind {
	## Sent on connect in both directions: version, display name, which side
	## the sender plays, and a hash of the position the sender believes it has.
	HELLO,
	## Intent to move: seq + the move itself. Applied locally, never trusted
	## for its outcome.
	MOVE,
	## Full position, used to repair divergence. seq + hash + board array.
	SYNC,
	## Polite decline of a MOVE, e.g. the receiver's board refused it.
	REJECT,
	## Session over.
	BYE,
}

const KIND_NAMES := {
	Kind.HELLO: "hello",
	Kind.MOVE: "move",
	Kind.SYNC: "sync",
	Kind.REJECT: "reject",
	Kind.BYE: "bye",
}


static func kind_name(kind: int) -> String:
	return KIND_NAMES.get(kind, "unknown")


## Opens a session. side is BoardState.LIGHT/DARK; position_hash lets the peer
## notice immediately if it is joining a game already in progress.
static func hello(name: String, side: int, position_hash: int) -> Dictionary:
	return {
		"t": "hello",
		"v": VERSION,
		"name": name,
		"side": side,
		"hash": position_hash,
	}


## A move intent. seq is the sender's own monotonically increasing counter so
## the receiver can spot gaps and gaps trigger a resync request.
static func move(seq: int, chess_move: ChessMove) -> Dictionary:
	var payload := {
		"t": "move",
		"v": VERSION,
		"seq": seq,
	}
	payload.merge(chess_move.to_dict())
	return payload


## A full position snapshot for repairing a desync.
static func sync(seq: int, state: BoardState) -> Dictionary:
	return {
		"t": "sync",
		"v": VERSION,
		"seq": seq,
		"hash": state.hash(),
		"board": state.to_array(),
	}


static func reject(seq: int, reason: String) -> Dictionary:
	return {
		"t": "reject",
		"v": VERSION,
		"seq": seq,
		"reason": reason,
	}


static func bye() -> Dictionary:
	return {"t": "bye", "v": VERSION}


## Reads a received dictionary back into a ChessMove, or null if it is not a
## usable move message. Deliberately paranoid: a peer can send anything.
static func read_move(message: Dictionary) -> ChessMove:
	if String(message.get("t", "")) != KIND_NAMES[Kind.MOVE]:
		return null
	if int(message.get("v", -1)) != VERSION:
		return null
	return ChessMove.from_dict(message)


## Reads a SYNC payload into a BoardState, or null if unusable.
static func read_sync(message: Dictionary) -> BoardState:
	if String(message.get("t", "")) != KIND_NAMES[Kind.SYNC]:
		return null
	if int(message.get("v", -1)) != VERSION:
		return null
	var board: Array = message.get("board", [])
	var state := BoardState.new()
	if not state.from_array(board):
		return null
	return state
