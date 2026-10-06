#!/usr/bin/env sh
# One-shot Phase 5 phone gate: export the spike APK, install it on the
# attached device, run the bridge scene, and verdict from logcat.
# Usage: ./phone_spike.sh   (from the workspace root)
# Requires: Godot 4.7.2, 4.7.2 export templates, debug keystore,
#           one adb device, release or debug .so files staged already.
set -eu
ROOT="$(dirname "$0")"
GODOT="$ROOT/godot"
APK=/tmp/opencode/chess-relay-spike.apk
PKG=org.chessrelay.spike
ADB=/opt/android-sdk/platform-tools/adb
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="${GODOT_ANDROID_KEYSTORE_DEBUG_PATH:-$HOME/.android/debug.keystore}"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android

# 0. Spike scene must be the export target (reverted at the end).
if ! grep -q 'bridge_spike_scene.tscn' "$GODOT/project.godot"; then
  echo "SKIP: project.godot main scene is not the spike scene; refusing to export the real game."
  exit 2
fi

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

# 4. Install and run.
"$ADB" install -r "$APK"
"$ADB" logcat -c
"$ADB" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null
sleep 15
LOGCAT="$("$ADB" logcat -d | grep -E 'BRIDGE-SPIKE|godot-rust' || true)"
echo "$LOGCAT"
echo "$LOGCAT" | grep -q "BRIDGE-SPIKE RESULT: PASS" \
  && echo "PHONE GATE: PASS" \
  || { echo "PHONE GATE: FAIL"; exit 1; }
