# One build surface: every target rebuilds what it ships first, so a
# stale .so can never reach the device again. Cargo itself no-ops when
# sources are unchanged; the stamp files below only solve mode
# switching (debug vs release share one staging dir, so each recipe
# deletes the other track's stamp).
#
#   make run              desktop lib + run the game locally
#   make android          device debug APK (build, export, install, launch)
#   make android-release  device release APK (same flow, release track)
#   make android-prod     alias of android-release
#   make check            all gates (Rust + Godot), no artifacts
#
# Environment overrides: GODOT (default: godot), ADB (default: adb on
# PATH, else /opt/android-sdk/...), ANDROID_HOME (for apksigner).
# android-release additionally needs a signing keystore:
#   GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD.

GODOT ?= godot
ADB ?= $(shell command -v adb 2>/dev/null || echo /opt/android-sdk/platform-tools/adb)
PKG := org.chessrelay.spike
DEBUG_APK := /tmp/opencode/chess-relay-debug.apk
RELEASE_APK := /tmp/opencode/chess-relay-release.apk
RUST_SRCS := $(shell find rust/src rust/Cargo.toml rust/Cargo.lock -type f 2>/dev/null)

.PHONY: help run android android-release android-prod check _launch _require-keystore
.DEFAULT_GOAL := help

help:
	@echo "Targets:"
	@echo "  make run              rebuild desktop lib, run the game"
	@echo "  make android          rebuild + debuggable APK to the attached device"
	@echo "  make android-release  rebuild + release APK to the attached device"
	@echo "  make android-prod     alias of android-release"
	@echo "  make check            fmt + clippy + test + doc + Godot checks"

run: godot/bin/libchess_relay_core.so
	$(GODOT) --path godot

godot/bin/libchess_relay_core.so: $(RUST_SRCS)
	cargo build --manifest-path rust/Cargo.toml --lib
	mkdir -p godot/bin
	cp rust/target/debug/libchess_relay_core.so godot/bin/
	touch godot/bin/libchess_relay_core.so

check:
	cargo fmt --manifest-path rust/Cargo.toml -- --check
	cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
	cargo test --manifest-path rust/Cargo.toml
	RUSTDOCFLAGS="-D warnings" cargo doc --manifest-path rust/Cargo.toml --no-deps
	GODOT_BIN=$(GODOT) bash godot/tests/run_all_checks.sh

android: .build/android-debug.stamp
	rm -f $(DEBUG_APK)
	$(GODOT) --headless --path godot --export-debug "Android-Spike" "$(DEBUG_APK)"
	$(MAKE) _launch APK=$(DEBUG_APK)

android-release: .build/android-release.stamp
	rm -f $(RELEASE_APK)
	$(GODOT) --headless --path godot --export-release "Android-Release" "$(RELEASE_APK)"
	$(MAKE) _launch APK=$(RELEASE_APK)

android-prod: android-release

_require-keystore:
	@if [ -z "$${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}" ]; then \
		echo "release keystore missing:"; \
		echo "  export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/path/to/release.keystore"; \
		echo "  export GODOT_ANDROID_KEYSTORE_RELEASE_USER=<key-alias>"; \
		echo "  export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=<password>"; \
		exit 1; \
	fi

# Not a public target: verifies, installs, launches, and fails the
# build on boot errors. Force-stop first: Android keeps old code alive
# in a backgrounded process across reinstalls.
_launch:
	test -s "$(APK)" || { echo "EXPORT FAIL: APK missing or empty"; exit 1; }
	unzip -l "$(APK)" | grep -q "lib/arm64-v8a/libchess_relay_core.so" \
		|| { echo "EXPORT FAIL: bridge .so missing from APK"; exit 1; }
	APKSIGNER="$$(ls -1 "$$ANDROID_HOME"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1)"; \
	if [ -z "$$APKSIGNER" ]; then echo "apksigner missing: set ANDROID_HOME"; exit 1; fi; \
	"$$APKSIGNER" verify "$(APK)" || { echo "EXPORT FAIL: signature invalid"; exit 1; }
	"$(ADB)" shell am force-stop "$(PKG)"
	"$(ADB)" install -r "$(APK)"
	"$(ADB)" logcat -c
	"$(ADB)" shell monkey -p "$(PKG)" -c android.intent.category.LAUNCHER 1 > /dev/null
	sleep 12
	@ERRORS="$$("$(ADB)" logcat -d 2>/dev/null | grep -a 'godot   :' | grep -aiE 'error|fatal|script error' | head -10 || true)"; \
	if [ -n "$$ERRORS" ]; then echo "$$ERRORS"; echo "PHONE LAUNCH: errors on boot"; exit 1; fi
	@echo "PHONE LAUNCH: clean boot, on glass now"

.build/android-debug.stamp: $(RUST_SRCS)
	rust/build_android.sh debug
	mkdir -p .build
	touch $@
	rm -f .build/android-release.stamp

.build/android-release.stamp: $(RUST_SRCS) | _require-keystore
	rust/build_android.sh release
	mkdir -p .build
	touch $@
	rm -f .build/android-debug.stamp
