.PHONY: all build run check clippy test fmt compliance \
        android-debug android-release apk-install linux-deps

all: check clippy test

# ── Desktop ──────────────────────────────────────────────

build:
	cargo build

run:
	cargo run

check:
	cargo check

clippy:
	cargo clippy -D warnings

test:
	cargo test

fmt:
	cargo fmt

compliance:
	bash scripts/check_compliance.sh

linux-deps:
	sudo apt install -y pkg-config libasound2-dev libudev-dev

# ── Android ────────────────────────────────────────────

android-debug:
	cargo apk build --features android

android-release:
	cargo apk build --release --features android

apk-install: android-release
	adb install -r target/release/apk/chess-relay.apk
