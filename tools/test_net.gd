extends SceneTree

## Headless checks for the state-sync layer.
##
## These matter more than their size suggests: they are the argument that
## symmetric P2P works for this game. The tests build two independent boards,
## push identical moves through both, and prove they stay identical — the
## property that lets neither phone be the authority.
##
##     godot-headless --headless --script res://tools/test_net.gd

var _failures := 0


func _init() -> void:
	_hash_checks()
	_snapshot_checks()
	_message_checks()
	_convergence_checks()
	if _failures == 0:
		print("net: all checks passed")
	else:
		printerr("net: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _hash_checks() -> void:
	print("State hash")
	var a := BoardState.new()
	var b := BoardState.new()
	_check("identical setups hash equal", a.hash() == b.hash(), "hash=%d" % a.hash())

	# Hash must not collide on the things that matter.
	a.set_square(4, 4, BoardState.encode(PieceProfiles.Type.QUEEN, 0))
	_check("adding a piece changes the hash", a.hash() != b.hash(), "")

	var c := BoardState.new()
	c.side_to_move = BoardState.DARK
	_check("side to move is part of the hash", c.hash() != b.hash(), "")

	# Swapping two identical pieces must not change it: the hash tracks
	# position, not identity, so it must not be over-sensitive.
	var d := BoardState.new()
	var e := BoardState.new()
	d.set_square(0, 0, BoardState.encode(PieceProfiles.Type.PAWN, 0))
	d.set_square(1, 0, BoardState.encode(PieceProfiles.Type.PAWN, 0))
	e.set_square(0, 0, BoardState.encode(PieceProfiles.Type.PAWN, 0))
	e.set_square(1, 0, BoardState.encode(PieceProfiles.Type.PAWN, 0))
	_check("same position, same hash", d.hash() == e.hash(), "")


func _snapshot_checks() -> void:
	print("Snapshots")
	var state := BoardState.new()
	var snap := state.to_array()
	# 64 squares, side to move, castling rights, and the en passant square.
	_check("snapshot carries the whole position", snap.size() == 68,
		"size=%d" % snap.size())

	var restored := BoardState.new()
	_check("snapshot restores", restored.from_array(snap), "")
	_check("restored state matches by hash", restored.hash() == state.hash(), "")

	_check("short snapshot refused", not BoardState.new().from_array([1, 2, 3]), "")
	_check("non-integer snapshot refused",
		not BoardState.new().from_array(["a", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
			0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
			0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
			0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), "")


func _message_checks() -> void:
	print("Messages")
	var move := ChessMove.new(Vector2i(4, 1), Vector2i(4, 3))
	var message := Protocol.move(7, move)
	_check("move message carries intent",
		String(message["t"]) == "move" and int(message["seq"]) == 7, "msg=%s" % message)
	_check("move round-trips", Protocol.read_move(message).equals(move), "")

	# A hostile or buggy peer can send anything; reading must survive it.
	_check("wrong kind reads as no move",
		Protocol.read_move(Protocol.hello("peer", 0, 0)) == null, "")
	_check("wrong version reads as no move",
		Protocol.read_move({"t": "move", "v": 99, "seq": 1, "from": [0, 0], "to": [1, 1]}) == null,
		"")
	_check("empty message reads as no move", Protocol.read_move({}) == null, "")

	var state := BoardState.new()
	var sync := Protocol.sync(3, state)
	_check("sync carries a hash", int(sync["hash"]) == state.hash(), "")
	var restored := Protocol.read_sync(sync)
	_check("sync restores the position", restored != null and restored.hash() == state.hash(), "")
	_check("truncated sync reads as null",
		Protocol.read_sync({"t": "sync", "v": Protocol.VERSION, "seq": 1, "hash": 0, "board": [1, 2]}) == null,
		"")


func _convergence_checks() -> void:
	print("Peer convergence")
	# Two independent peers, the same move stream applied to each: the shape
	# symmetric P2P depends on.
	var peer_a := ChessGame.new()
	var peer_b := ChessGame.new()
	peer_a.reset()
	peer_b.reset()

	var moves := [
		ChessMove.new(Vector2i(4, 1), Vector2i(4, 3)),
		# The d-pawn double step, from rank index 6. Index 7 is Black's queen on
		# d7, and asking her to jump two squares is not a move.
		ChessMove.new(Vector2i(3, 6), Vector2i(3, 4)),
		ChessMove.new(Vector2i(5, 0), Vector2i(3, 2)),
		# b1 to c3: the knight's hop. File 1 on rank index 0, which is where the
		# white knight stands. Rank indices are 0-based, so index 1 is rank 2 and
		# holds a pawn.
		ChessMove.new(Vector2i(1, 0), Vector2i(2, 2)),
		ChessMove.new(Vector2i(4, 3), Vector2i(4, 4)),
	]
	var seq := 0
	for chess_move in moves:
		# Over the wire it arrives as a dict; both peers apply it locally.
		seq += 1
		var wire := Protocol.move(seq, chess_move)
		var received := Protocol.read_move(wire)
		_check("peer A applies seq %d" % seq, peer_a.apply_move(received), "move=%s" % received)
		_check("peer B applies seq %d" % seq, peer_b.apply_move(received), "move=%s" % received)

	_check("peers converge by hash", peer_a.state.hash() == peer_b.state.hash(),
		"a=%d b=%d" % [peer_a.state.hash(), peer_b.state.hash()])
	_check("peers agree on whose turn", peer_a.state.side_to_move == peer_b.state.side_to_move, "")
	_check("peers agree on history", peer_a.history.size() == peer_b.history.size(),
		"len=%d" % peer_a.history.size())

	# Now the interesting case: a peer that missed a message. It must be
	# repairable from a snapshot without replaying anything.
	peer_b.apply_move(ChessMove.new(Vector2i(0, 1), Vector2i(0, 2)))
	_check("peers diverge after a dropped move", peer_a.state.hash() != peer_b.state.hash(), "")
	var repair := Protocol.read_sync(Protocol.sync(0, peer_a.state))
	_check("repair restores the other peer",
		repair != null and peer_b.state.from_array(repair.to_array()), "")
	_check("repaired peer matches by hash", peer_a.state.hash() == peer_b.state.hash(),
		"a=%d b=%d" % [peer_a.state.hash(), peer_b.state.hash()])

	# A late/duplicate move must not corrupt a peer that already applied it.
	var replay := Protocol.read_move(Protocol.move(2, moves[1]))
	_check("duplicate move is harmless", not peer_a.apply_move(replay)
		or peer_a.state.hash() == peer_b.state.hash(), "")


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		print("  ok   %s  %s" % [label, detail])
	else:
		_failures += 1
		printerr("  FAIL %s  %s" % [label, detail])
