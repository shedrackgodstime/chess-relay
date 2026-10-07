#!/usr/bin/env bash
# Every Godot gate, in one command. Non-zero exit if any of them fail.
#
#   bash godot/tests/run_all_checks.sh
#
# This replaces run_ui_checks.sh. Three gates, in order of cost:
#
#   1. parse     every first-party .gd parses, with the project's warning keys
#                escalated to errors (quality-gates.md R1)
#   2. drift     Godot registers no warning key this project has not decided
#                about (R2)
#   3. suites    every SceneTree script in godot/tests/, each on its own, with
#                stderr treated as a failure (R5, R6)
#
# Two things this script exists to stop, both measured on 2026-10-07:
#
#   - The UI suite reported success while 68 of its 146 checks had never run. A
#     GDScript runtime error does not propagate, so a phase that crashed looked
#     exactly like one that finished. Hence the per-phase sentinels inside the
#     suite, the `--expected-checks` count passed in below, and the stderr gate.
#
#   - The Rust core has never loaded on a machine without a `linux.arm64` entry
#     in chess_relay.gdextension, so the board rendered nothing and every
#     bridge-dependent check was skipped. bridge_spike_test.gd detects exactly
#     that and now runs as part of this, so it cannot be silently unwired again.
#
# Godot is whatever `$GODOT_BIN` names, default `godot-headless` on PATH.
#
# The bridge suites additionally need the Rust core built and its library in
# godot/bin/, because a missing library means chess_relay.gdextension registers
# nothing and the board renders no pieces. Without it those suites report a
# genuine failure rather than quietly skipping, which is the point:
#
#   CARGO_TARGET_DIR=/somewhere/outside/the/repo \
#     cargo build --manifest-path rust/Cargo.toml --lib
#   mkdir -p godot/bin
#   cp /somewhere/outside/the/repo/debug/libchess_relay_core.so godot/bin/
#
# CARGO_TARGET_DIR must be outside the repository on Android shared storage,
# which is mounted noexec; an in-tree rust/target cannot run build scripts.

set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot-headless}"
findings="$(mktemp)"
trap 'rm -f "$findings"' EXIT

failed=0

section() { printf '\n== %s ==\n' "$1"; }

if ! command -v "$GODOT_BIN" >/dev/null 2>&1 && [ ! -x "$GODOT_BIN" ]; then
  echo "godot binary not found: $GODOT_BIN (set GODOT_BIN)" >&2
  exit 3
fi

# ---------------------------------------------------------------------------
# Gate 1: parse, per file, warnings-as-errors.
#
# Per file rather than whole project: a single project run says "something is
# wrong", this says "game_screen.gd:83". It also reaches scripts no scene
# references, which a project-load run would skip.
#
# No --debug: --check-only --debug drops Godot into an interactive debugger that
# can hang the runner forever (godotengine/godot#117123). Escalating the keys to
# level 2 in project.godot is what surfaces warnings without that flag, and it
# gives a real non-zero exit code instead of text to grep for.
# ---------------------------------------------------------------------------
section "parse (warnings-as-errors)"
checked=0
while IFS= read -r file; do
  rel="${file#"$root"/}"
  checked=$((checked + 1))
  output="$("$GODOT_BIN" --headless --path "$root" --check-only --script "res://${rel#godot/}" 2>&1)"
  status=$?
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" | grep -E 'Parse Error|SCRIPT ERROR|ERROR:|at: ' \
      | sed "s|^|[$rel] |" >>"$findings" || true
    printf 'FAIL %s (exit %d)\n' "$rel" "$status"
    failed=1
  fi
done < <(find "$root/src" "$root/tests" -name '*.gd' -type f | sort)
echo "scripts checked: $checked"

# ---------------------------------------------------------------------------
# Gate 2: warning-key drift.
#
# Catches both directions: a new key Godot registers that this project has not
# decided about, and a key this project sets that Godot does not register. The
# second direction is the one that let a dead `treat_warnings_as_errors` setting
# sit in project.godot looking correct for months.
# ---------------------------------------------------------------------------
section "warning drift"
python3 "$root/tools/check_warning_drift.py" "$GODOT_BIN" || failed=1

# ---------------------------------------------------------------------------
# Gate 3: every suite, each alone, stderr gated.
#
# Discovered, not listed: nobody edits a list to add a test, so a new suite
# cannot be written and then not run.
# ---------------------------------------------------------------------------
section "suites"
for suite in $(find "$root/tests" -maxdepth 1 -name '*_test.gd' -type f | sort); do
  rel="${suite#"$root"/}"
  res="res://${rel#godot/}"

  # The expected check count is the number of _check( call sites in the suite.
  # Passed in so the suite can compare declared against executed, which is what
  # catches a truncated run. Counted from source rather than maintained by hand,
  # so it cannot drift.
  expected="$(grep -c '_check(' "$suite" || true)"

  output="$("$GODOT_BIN" --headless --path "$root" --script "$res" \
    -- --expected-checks="$expected" 2>&1)"
  status=$?
  printf '%s\n' "$output" | sed -n 's/^PASS: /  ok   /p'
  printf '%s\n' "$output" | sed -n 's/^FAIL: /  FAIL /p'
  printf '%s\n' "$output" | sed -n 's/^UI SMOKE: /  /p'
  printf '%s\n' "$output" | grep -E 'BRIDGE-SPIKE' | sed 's/^/  /'

  if [ "$status" -ne 0 ]; then
    printf '  FAIL %s exited %d\n' "$rel" "$status"
    printf '%s\n' "$output" | grep -E 'FAIL|SCRIPT ERROR|ERROR:|at: ' \
      | sed "s|^|  |" >>"$findings" || true
    failed=1
  fi

  # R5.1, belt and braces: a suite can exit 0 while printing an engine error.
  # The exit code and the count check catch most of it; this catches the rest.
  errors="$(printf '%s\n' "$output" | grep -cE 'SCRIPT ERROR|Parse Error' || true)"
  if [ "$errors" -gt 0 ]; then
    printf '  FAIL %s printed %s engine error(s) despite exit %d\n' "$rel" "$errors" "$status"
    printf '%s\n' "$output" | grep -E 'SCRIPT ERROR|Parse Error' -A1 \
      | sed "s|^|  |" >>"$findings" || true
    failed=1
  fi
done

# ---------------------------------------------------------------------------
section "findings"
if [ -s "$findings" ]; then
  cat "$findings"
  echo
  echo "RESULT: NOT CLEAN"
  exit 1
fi

if [ "$failed" -ne 0 ]; then
  echo "RESULT: NOT CLEAN"
  exit 1
fi

echo "RESULT: all gates green"