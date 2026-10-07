#!/usr/bin/env sh
# One script, single run: rebuild release .so files, export the APK,
# verify it, overwrite-install on the attached device, launch.
# Usage: ./scripts/android.sh   (from the workspace root)
# Requires: Godot 4.7.2, 4.7.2 export templates, debug keystore,
#           one adb device. ANDROID_HOME and ADB may override defaults.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="$ROOT/godot"
APK=/tmp/opencode/chess-relay-spike.apk
PKG=org.chessrelay.spike
ADB="${ADB:-/opt/android-sdk/platform-tools/adb}"
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="${GODOT_ANDROID_KEYSTORE_DEBUG_PATH:-$HOME/.android/debug.keystore}"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android

# 1. Stage a fresh release .so for both ABIs.
"$ROOT/rust/build_android.sh" release

# 2. Export.
rm -f "$APK"
godot --headless --path "$GODOT" --export-debug "Android-Spike" "$APK"
test -s "$APK" || { echo "EXPORT FAIL: APK missing or empty"; exit 1; }

# 3. Verify artifact before touching the phone (prototype CI pattern).
unzip -l "$APK" | grep -q "lib/arm64-v8a/libchess_relay_core.so" \
  || { echo "EXPORT FAIL: bridge .so missing from APK"; exit 1; }
unzip -l "$APK" | grep -q "AndroidManifest.xml" \
  || { echo "EXPORT FAIL: manifest missing"; exit 1; }
APKSIGNER="$(ls -1 "$ANDROID_HOME"/build-tools/*/apksigner | sort -V | tail -1)"
"$APKSIGNER" verify "$APK" || { echo "EXPORT FAIL: signature invalid"; exit 1; }
echo "artifact verified"

# 4. Install (force-stop first: Android keeps old code running in a
# backgrounded process across reinstalls) and launch.
"$ADB" shell am force-stop "$PKG"
"$ADB" install -r "$APK"
"$ADB" logcat -c
"$ADB" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null
sleep 12
ERRORS="$("$ADB" logcat -d 2>/dev/null | grep -a 'godot   :' | grep -av 'godotengine.editor' | grep -aiE 'error|fatal|script error' | head -10 || true)"
if [ -n "$ERRORS" ]; then
  echo "$ERRORS"
  echo "PHONE LAUNCH: errors on boot"
  exit 1
fi
echo "PHONE LAUNCH: clean boot, on glass now"
