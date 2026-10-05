# UI checks

Run the dependency-free UI smoke suite from the repository root:

```sh
godot --headless --path godot --script res://tests/ui_smoke_test.gd
```

The suite checks that the runtime scenes load, reusable header, choice-group,
and participant-card APIs behave as configured, setup and invite interactions
update their states, modal actions exist, responsive breakpoints choose the
expected columns, theme focus/badge styles exist, and the app can move through
Home, Game Setup, and Multiplayer Hub. It uses Godot's `SceneTree` and exits
with a non-zero status if any check fails.

This is a UI lifecycle suite. Chess legality, move generation, clocks, and
transport behavior belong to future model/service test suites rather than UI
scenes.
