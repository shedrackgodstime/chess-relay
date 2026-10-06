#!/usr/bin/env sh
# Builds the Android .so files and stages them for the Godot export.
# Usage: ./build_android.sh [debug|release]  (default: debug)
# Requires: cargo-ndk, ANDROID_NDK_HOME, Rust android targets.
set -eu
mode="${1:-debug}"
root="$(cd "$(dirname "$0")" && pwd)"
cd "$root"

if [ "$mode" = "release" ]; then
  cargo_args="--release"
  build_dir="release"
else
  cargo_args=""
  build_dir="debug"
fi

# shellcheck disable=SC2086
cargo ndk -t arm64-v8a -t armeabi-v7a -P 24 build $cargo_args

for abi in arm64-v8a armeabi-v7a; do
  case "$abi" in
    arm64-v8a) target="aarch64-linux-android" ;;
    armeabi-v7a) target="armv7-linux-androideabi" ;;
  esac
  dest="$root/../godot/android/libs/$abi"
  mkdir -p "$dest"
  cp "$root/target/$target/$build_dir/libchess_relay_core.so" "$dest/"
  echo "staged $dest/libchess_relay_core.so"
done
