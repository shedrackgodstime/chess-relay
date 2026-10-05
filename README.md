# Chess Relay workspace

This repository contains the Chess Relay Godot client and a separate Rust
workspace for future native/networking work.

- [`godot/`](godot/) — the active Godot project and UI implementation.
- [`rust/`](rust/) — Rust workspace, currently initialized only; its build
  output is ignored while its source remains available for later work.
- [`ref/`](ref/) — local Godot documentation, official demo projects, and the
  prototype used as reference material. It is not part of either runtime.

The cross-runtime boundary is documented in
[application core architecture](docs/architecture/application_core.md).
Godot-specific architecture remains under [`godot/docs/`](godot/docs/).

Open `godot/project.godot` in Godot. The current development scope is the UI
lifecycle; the board and game behavior will be added after that foundation is
complete.

Run the current UI smoke checks from this workspace with:

```sh
godot --headless --path godot --script res://tests/ui_smoke_test.gd
```
