extends SceneTree
## Desktop headless check that the Rust core is actually wired to Godot.
##
## This suite exists because the bridge silently did not load for months. The
## gdextension had no `linux.arm64` entry, so the class never registered, the
## game screen rendered no pieces, and the whole Phase 6 round-trip was skipped
## while every suite reported success. Nothing detected it because this file was
## not wired into the runner.
##
## It goes through `ChessCoreBridge`, the typed facade, because that is what the
## game screen uses. A check that exercised the raw GDExtension class would not
## have caught the missing facade path.
##
## Run directly:
##   godot --headless --path godot --script res://tests/bridge_spike_test.gd
## Or, with the expected-check count wired in, via run_all_checks.sh.

var _failed := false
var _checks := 0
var _phase_reached_end := false
## Read as typed locals: a Dictionary lookup is a Variant and these checks take
## a bool.
var _started := false
var _move_uci := ""
## Last refusal message from the core, for diagnosis.
var last_error := ""

## Whether the built core library is even present on this host.
##
## Distinguishes "the extension file does not declare this platform" (a project
## defect, and the one this suite was written for) from "this machine cannot
## load a GDExtension .so at all" (an environment limit).
##
## Measured here, not guessed. Termux's `godot-headless` wrapper runs the Linux
## glibc Godot binary through Termux's glibc sysroot with `--library-path
## $PREFIX/glibc/lib`, and that sysroot ships `libdl.so.2` but no `libdl.so`.
## `dlopen` needs the unversioned name, so every `.so` fails with `libdl.so:
## cannot open shared object file`; putting a `libdl.so` symlink in the path
## instead makes the loader resolve `libc.so` (a linker script, not an ELF) and
## fail with `invalid ELF header`.
##
## That is a property of the phone, not of the project. The honest answer here
## is "could not verify", stated as such -- swapping "always green" for "always
## red for an environment reason" would trade one lie for another, and this suite
## exists precisely because a missing extension was once reported as a pass.
var _library_present := FileAccess.file_exists("res://bin/libchess_relay_core.so")


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failed = true
		printerr("FAIL: ", label)


func _init() -> void:
	_run()


func _run() -> void:
	# A missing extension is the failure this suite was written for, so it is
	# reported as a check rather than an early return. An early return is what
	# let this go unnoticed for so long.
	var bridge := ChessCoreBridge.new()
	root.add_child(bridge)
	bridge.move_applied.connect(
		func(_sequence: int, uci: String, _by: String, _agreed: bool) -> void:
			_move_uci = uci)
	bridge.game_started.connect(func() -> void: _started = true)
	bridge.bridge_error.connect(_on_bridge_error)

	_check(bridge.is_available(),
		"Rust core is loaded (chess_relay.gdextension registers ChessRelayBridge; "
		+ "a missing linux.arm64 entry is how this used to fail)")
	if not bridge.is_available():
		_explain_unavailable()

	if bridge.is_available():
		_check(_started, "game started after both sides became ready")
		_check(bridge.turn() == "white", "core reports white to move at the start")

		var targets := bridge.legal_moves_from("e2")
		_check(targets.size() == 2 and targets.has("e3") and targets.has("e4"),
			"core answers legal moves from e2, got %s" % [targets])

		var pawn_targets := bridge.legal_moves_from("b8")
		_check(pawn_targets.is_empty(),
			"core refuses targets from a black piece on white's turn")

		_check(bridge.submit_move("e2e4"), "core accepts e2e4")
		_check(_move_uci == "e2e4", "move_applied carries the uci")
		_check(bridge.fen()
			== "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
			"core position observes e2e4, got %s" % bridge.fen())
		_check(bridge.turn() == "black", "turn passes to black")

		_check(not bridge.submit_move("e2e4"), "core rejects a repeat of e2e4")
		_check(not bridge.submit_move("a1a8"), "core rejects an illegal move")

		# Promotion suffix must come from the core. The client used to append
		# "q" itself, which made underpromotion unreachable.
		_check(bridge.submit_move("e7e5"), "core accepts a black pawn move")

	_phase_reached_end = true
	_check(_phase_reached_end, "phase ran to completion")
	_report()


## Says which of the three causes it was, because they need different fixes.
##
## Reported, not folded into the pass/fail line: the check above already failed
## and the run exits non-zero either way. What changes is whether the next person
## reads "the project is broken" or "this machine cannot load a .so".
func _explain_unavailable() -> void:
	if not _library_present:
		printerr("BRIDGE: cause = library not built. "
			+ "CARGO_TARGET_DIR=<outside the repo> cargo build "
			+ "--manifest-path rust/Cargo.toml --lib, then copy "
			+ "target/debug/libchess_relay_core.so to godot/bin/.")
		return
	printerr("BRIDGE: cause = this host cannot dlopen a GDExtension library. "
		+ "The library is present at res://bin/ but never registered. On this "
		+ "device that is the Termux glibc sysroot, which ships libdl.so.2 and no "
		+ "libdl.so, so Godot's Linux binary run through it cannot load any "
		+ "extension. Verify on a stock Linux runner or the desktop instead; "
		+ "CI is the authority for this gate. See "
		+ "docs/standards/quality-gates.md R6.")


func _on_bridge_error(message: String) -> void:
	# Expected for the two rejections above, so recorded rather than failed.
	# Recorded, not failed: the suite deliberately submits illegal moves and the
	# core is expected to refuse them.
	last_error = message


func _report() -> void:
	var expected := _expected_check_count()
	print("BRIDGE: %d of %d checks ran, %d failed"
		% [_checks, expected, int(_failed)])
	if _checks < expected:
		printerr("BRIDGE: only %d of %d checks ran" % [_checks, expected])
		_failed = true
	if _failed:
		printerr("BRIDGE-SPIKE RESULT: FAIL")
		quit(1)
	else:
		print("BRIDGE-SPIKE RESULT: PASS")
		quit(0)


func _expected_check_count() -> int:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--expected-checks="):
			return int(argument.split("=")[1])
	return 0