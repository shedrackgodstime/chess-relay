# Project structure

This repository is being initialized for a UI-only development phase. The
prototype in `ref/chess-relay/` is a visual and interaction reference; its
scenes, scripts, and assets are not runtime dependencies and are not being
ported as part of initialization.

## Boundaries

- `src/ui/app/` owns the application UI root, screen transitions, and shared UI
  coordination.
- `src/ui/screens/` contains navigable full-screen experiences. Each screen
  should own its presentation and expose a small, deliberate interface to the
  app layer.
- `src/ui/components/` contains reusable controls and composed UI pieces such
  as buttons, cards, fields, and dialogs. Prefer reusable scenes with clear
  inputs and signals over controls coupled to particular screens.
- `src/ui/theme/` contains shared Godot Theme resources and theme-related
  design tokens. A project-wide theme should be applied at the UI root; local
  exceptions should be deliberate.
- `assets/ui/` holds UI assets. Keep assets near a component or screen when
  they are exclusive to it; shared assets belong in this common directory.
- `docs/architecture/` records decisions that affect structure or long-term
  maintenance.
- `ref/` is source material only. It must not be referenced by `res://` runtime
  paths.

## Conventions

- Use lowercase `snake_case` for directories and files, including scene and
  script filenames. Use `PascalCase` for nodes.
- Keep tightly related scenes, scripts, and assets together where doing so
  makes ownership clear.
- Prefer composition and small scenes with one clear responsibility. Keep
  screen navigation decisions in the app layer rather than reusable controls.
- Add autoloads only for services that demonstrably need application-wide
  lifetime; do not make screen state global by default.
- Use typed GDScript for new code and treat engine warnings as issues to
  resolve, not noise to suppress project-wide.
- Keep editor-generated `.godot/` cache data out of version control. Commit
  source resources such as scenes, scripts, themes, and import sidecar files.

## Local reference material

The `ref/` directory contains a checkout of the Godot documentation and demo
projects. The project setup follows the official guidance on [project
organization](https://docs.godotengine.org/en/stable/tutorials/best_practices/project_organization.html),
[version control](https://docs.godotengine.org/en/stable/tutorials/best_practices/version_control_systems.html),
[scene organization](https://docs.godotengine.org/en/stable/tutorials/best_practices/scene_organization.html),
and [themes](https://docs.godotengine.org/en/stable/tutorials/ui/gui_using_theme_editor.html).

The available local docs checkout was current to 2026-09-29. The installed
editor is Godot 4.7.2 stable; use the latest stable patch in the 4.7 series
for project work and avoid development builds for this foundation.
