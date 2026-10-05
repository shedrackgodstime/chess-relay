# Pre game screen foundation audit

**Scope:** project setup, UI source layout, reusable scenes, theme, screen
lifecycle, mock multiplayer boundary, responsive layout, accessibility, assets,
and architecture notes. The board, chess rules, and real networking are outside
this UI foundation audit.

**Reference set:** the checked-in local Godot documentation and official demo
projects in `ref/godot-docs/` and `ref/godot-demo-projects-master/`. The project
uses Godot 4.7.2; the configuration targets the 4.7 feature set.

## Audit results

| Area | Result | Notes |
| --- | --- | --- |
| Project entry and configuration | Pass | `project.godot` has a named app, explicit main scene, UI theme, 4.7 feature level, a 1440×900 design viewport, and the app root enforces a 960×640 minimum window. |
| Folder and file organization | Pass | Runtime UI is grouped by app, screens, components, theme, and mock service. File and node naming follow Godot's snake_case/PascalCase guidance. |
| Reference isolation | Pass | `ref/.gdignore` keeps the local docs, demos, and prototype out of the runtime filesystem/import workflow; `ref/` is ignored by Git. Runtime resources use `res://` paths under project-owned folders. |
| VCS hygiene | Pass | `.godot/`, import cache, and export state are ignored; `.gitattributes` normalizes text line endings. |
| App/screen boundary | Improved | The app root owns navigation and service coordination. Its screen and mock-service events now use typed signal connections and direct typed method calls instead of unchecked string-based `connect`/`call`. |
| Screen scene ownership | Improved; keep one follow-up | Home, Game Setup, and the stable Multiplayer Hub layout now have authored scene trees. The hub script keeps runtime rows and changing invite-flow content dynamic. A dedicated reusable player-row scene can be extracted later if that row is reused outside the hub. |
| Reusable UI | Partial | Card, choice group, participant card, and game header are reusable scenes. The multiplayer player row and common dialog/menu patterns are still assembled inside screens. Extract a player-row scene/API when the hub composition is reworked; do not create a general component framework without concrete reuse. |
| Theme ownership | Partial | A project-wide Theme and preview scene are in place. Some hub visuals bypass it with script color/font overrides, and layout numbers are distributed through scripts/scenes. Move repeated presentation values into named theme variations or shared layout constants during the hub refactor. |
| Responsive layout | Pass | Setup and hub switch their multi-column sections at a viewport breakpoint, all screen roots use full-rect anchors, and the app declares a 960×640 minimum window. The header and footers use anchored layouts. |
| Input and accessibility | Pass for current UI scope | The passive connection indicator ignores pointer input, shared buttons have a visible gold focus style, the home screen starts keyboard focus on its first action, and screen roots, icon controls, actions, choices, and modal actions have accessible names/tooltips. |
| Multiplayer UI/backend seam | Pass for UI prototype | The hub emits user intent and the app root routes mock outcomes. `MockMultiplayerService` is explicitly local-only; its fixture names and outcomes are not product behavior. Keep transport and identity outside screen controls. |
| Documentation | Pass | Architecture notes explain the current theme, header, setup, multiplayer lifecycle, and this complete pre-board audit. |
| Asset/license traceability | Pass | Component icons stay with the header; `icons/LICENSE.txt` records the Lucide and Feather-derived licenses. The shared chess knight is under `assets/ui/icons/`. |
| Automated UI checks | Pass | `tests/ui_smoke_test.gd` loads every runtime screen/component contract, checks reusable header, choice-group, and participant-card behavior, exercises setup/menu/modal and create/join invite states, checks responsive breakpoints and theme invariants, and verifies Home → Game Setup/Multiplayer Hub lifecycle transitions. It exits non-zero on failure. |

## Changes made during this audit

- `app_root.gd` now instantiates typed screen classes, connects their declared
  signals directly, and holds a typed `MockMultiplayerService` reference. This
  makes a broken signal or renamed method visible to the script analyzer rather
  than hiding it behind a string.
- The passive network indicator now uses `MOUSE_FILTER_IGNORE`, matching the
  official `Control` guidance for decorative controls that should not consume
  GUI input.

## Pre-board work gate

The pre-board gate is green. The stable hub composition is in
`multiplayer_hub_screen.tscn`; runtime rows and invite-flow states remain
dynamic by design. The app has a declared minimum window, shared focus styling,
typed app/service boundaries, and accessible names for the current controls.
The UI lifecycle and mock backend boundary can remain in place while the board
screen is added.

## Official local references consulted

- `ref/godot-docs/tutorials/best_practices/project_organization.rst` — folder,
  naming, and asset proximity guidance.
- `ref/godot-docs/tutorials/best_practices/scene_organization.rst` —
  self-contained scenes, loose coupling, and signal-based boundaries.
- `ref/godot-docs/tutorials/best_practices/autoloads_versus_regular_nodes.rst`
  — keep functionality scene-scoped until it needs application-wide lifetime.
- `ref/godot-docs/tutorials/ui/gui_using_theme_editor.rst` and
  `ref/godot-docs/tutorials/ui/size_and_anchors.rst` — project themes, preview
  scenes, anchors, and layout behavior.
- `ref/godot-docs/classes/class_control.rst` — GUI input filtering and theme
  inheritance.
- `ref/godot-docs/tutorials/best_practices/version_control_systems.rst` —
  ignore generated Godot state.
- `ref/godot-demo-projects-master/gui/multiple_resolutions/` — official
  multiple-resolution and aspect-ratio configuration example.
- `ref/godot-demo-projects-master/gui/accessibility/` — official accessibility
  control examples for a future full-screen audit.

The current UI smoke suite can be run from the workspace root with:

```sh
godot --headless --log-file /tmp/chess-relay-ui-smoke.log \
  --path godot --script res://tests/ui_smoke_test.gd
```

Chess legality and move-generation checks will be added with the future game
model; they do not belong in UI scene tests.
