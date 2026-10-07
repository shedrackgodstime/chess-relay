#!/usr/bin/env sh
# Install the spike APK on the attached Android device and launch it.
# Force-stops first: Android keeps old code running across reinstalls.
# Usage: ./scripts/install_android.sh [path-to.apk]
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADB="${ADB:-/opt/android-sdk/platform-tools/adb}"
APK="${1:-/tmp/opencode/chess-relay-spike.apk}"
PKG=org.chessrelay.spike

if [ ! -f "$APK" ]; then
  echo "APK not found: $APK" >&2
  echo "Export one first (see phone_spike.sh), or pass its path." >&2
  exit 1
fi
if ! "$ADB" get-state 1>/dev/null 2>&1; then
  echo "No Android device attached (adb get-state failed)." >&2
  exit 1
fi
"$ADB" shell am force-stop "$PKG"
"$ADB" install -r "$APK"
"$ADB" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
echo "installed and launched $PKG"
