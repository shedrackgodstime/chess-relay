#!/usr/bin/env bash
# Runs the UI checks headlessly and fails on a non-zero exit.
#
# Kept in the project, and tracked, rather than living in a temp directory: the
# checks are the only way to know a screen still loads, so the thing that runs
# them should not be the first thing to disappear. It is a development tool and
# has no part in an exported build.
#
#   bash godot/tests/run_ui_checks.sh
#
# Godot is whatever `godot-headless` resolves to on PATH.

set -euo pipefail

# The project root is the directory above this one, because --path wants the
# folder that holds project.godot rather than the folder that holds the test.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

godot-headless --headless --path "$root" --script res://tests/ui_smoke_test.gd