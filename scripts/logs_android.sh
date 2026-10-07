#!/usr/bin/env sh
# Follow the device log filtered to engine output (game prints, errors).
# Usage: ./scripts/logs_android.sh [grep-pattern]
# Examples:
#   ./scripts/logs_android.sh BRIDGE-SPIKE
#   ./scripts/logs_android.sh "captured blank"
set -eu
ADB="${ADB:-/opt/android-sdk/platform-tools/adb}"
PATTERN="${1:-godot   :}"
"$ADB" logcat -c
echo "--- following '$PATTERN' (Ctrl-C to stop) ---"
"$ADB" logcat 2>/dev/null | grep -a --line-buffered "$PATTERN" | grep -av 'godotengine.editor' || true
