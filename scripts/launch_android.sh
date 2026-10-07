#!/usr/bin/env sh
# Launch the installed spike APK without reinstalling.
# Usage: ./scripts/launch_android.sh
set -eu
ADB="${ADB:-/opt/android-sdk/platform-tools/adb}"
PKG=org.chessrelay.spike
"$ADB" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
echo "launched $PKG"
