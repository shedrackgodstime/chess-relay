# Foundation tightening

Four gaps found by auditing the current foundation against the official Godot
documentation, in the order they should be closed. This is not a wish list; each
item names the rule it is failing and where the failure is.

The board, chess rules, networking, and the piece system are out of scope here.
The piece system in particular depends on item 2 being closed first, which is
why this document exists.

References are the Godot 4.7 documentation at
`docs.godotengine.org/en/stable`, section names given per item. The local
checkout under `ref/` is not present on every machine, so citations are written
out rather than only pointing at a path.

## 1. Warnings are a convention with nothing behind them

Status: **done.**

`project_structure.md` says to "treat engine warnings as issues to resolve,
not noise to suppress project-wide." `project.godot` has no `[debug]` section,
so nothing enforces it.

The setting is `debug/gdscript/warnings/treat_warnings_as_errors`, a boolean
that defaults to `false` (ProjectSettings class reference).

Enabling it turns the stated convention into a property of the project rather
than a property of whoever is reading it.

It is set, and the engine reports it as `true`, but it is **not verified**. A
deliberately unused signal and a deliberately unused local both compiled clean
under `--script --check-only`, while a syntax error in the same file failed as
expected. So the harness works and the setting is valid, but warnings did not
escalate in a headless script run. The editor is where warnings surface, and this
has to be confirmed there before the project relies on it.

## 2. The multiplayer hub builds its UI in script

Status: **done.**

`src/ui/screens/multiplayer_hub/multiplayer_hub_screen.gd` is 511 lines and
constructs its own controls with `PanelContainer.new()`, `HBoxContainer.new()`,
`VBoxContainer.new()`, `AcceptDialog.new()`, `LineEdit.new()`, and
`CheckButton.new()`.

The rule, from *Best practices > When to use scenes versus scripts*:

> If one wishes to create a concept that is particular to their game, then it
> should always be a scene. Scenes are easier to track/edit and provide more
> security than scripts.

The same page notes the cost in terms that describe this case closely:

> As the size of objects increases, the scripts' necessary size to create and
> initialize them grows much larger. Creating node hierarchies demonstrates
> this. Each Node's logic could be several hundred lines of code in length.

It also notes that scenes are faster to instantiate, because a `PackedScene` is
processed in batch on the back end rather than through the scripting API.

What this costs today, concretely: the invite rows, the join field, and the
dialog are not visible or editable in the editor, and they carry no `.tscn` that
could be reused. `pre_game_screen_audit.md` already records this as **Partial**
under *Reusable UI*, and names the player row as the piece to extract.

Why it is second and not lower: the planned piece work needs one piece rendered
in more than one place, on the board and in the trays. That is exactly the case
the rule above is written for, and it will be built in whichever style the
project is currently in. Closing this first means the piece is a scene.

### The player row

Done. `src/ui/components/player_row/player_row.tscn` plus its script, configured
with `configure(name, presence, is_recent)` and reporting through one
`invite_pressed` signal. The hub now instantiates it instead of building seven
nodes per person, and keeps a list of rows rather than a list of their Invite
buttons so the row stays the thing that knows how.

All six theme variations the row uses already existed in the shared theme, so the
extraction changed how the row is made and not how it looks. Worth checking that
in the editor, since a headless run cannot compare pixels.

### The flow card

Done. `src/ui/components/invite_flow_card/`, instantiated into the hub's scene in
place of the panel and content box it used to build at runtime. It carries the
heading, the detail line, a body, and an action row, and the screen asks it for
what it needs rather than reaching into it.

Five flows use it — create a code, join with a code, invite a listed player, respond
to an invitation, and recover from a declined one — which is what made it worth
extracting. Two helpers in the hub became dead when the flows moved and were
removed; the screen is 511 lines down to 438.

Extracting the card also removed a subtle problem. Each flow used to clear the
content box by queueing its children for deletion and then immediately adding the
next flow's, so for a frame the card held both. The card now removes and frees in
one step.

### The discovery settings dialog

Done. `src/ui/components/discovery_dialog/`, an `AcceptDialog` scene holding its
title, its message and its two answers. The hub builds one and keeps it, rather than
building a fresh dialog on each opening and copying two booleans in — which is how
those two answers could drift from the profile line beside the button that opens it.

The dialog reports `discovery_changed(nearby, online)` and decides nothing about what
that means; the hub still owns the profile line.

### What is left in the hub, and why

The hub script is 511 lines down to **434**. Two `new()` calls remain and both are
correct:

- `RandomNumberGenerator.new()` for the invite code. A generator is not interface.
- `LineEdit.new()` in `_code_field`. Deliberately still a method: only the join flow
  needs one, and a control with a single caller is not yet reusable. The note above
  it says so, so it reads as a decision rather than an oversight. It becomes a scene
  when a second caller appears.

Everything with layout in it is now a scene.

### The headless class cache

The cache is worth writing down here, because it cost an hour and will cost it
again. Godot writes `.godot/global_script_class_cache.cfg` when the editor opens
or on `--import`, by scanning for `class_name`. Both of those abort on this
build with `free(): invalid size`, which is a fault in the headless binary rather
than in the project: it reproduces on a pristine checkout with no changes.

The consequence is that deleting the cache by hand cannot be undone from the
command line, and without it every script that names another script's
`class_name` fails to parse. `tools/build_class_cache.py` regenerates it from the
same declarations the editor would read. Run it after adding a `class_name`:

    python3 godot/tools/build_class_cache.py

The editor will rewrite the same file with the same contents on its own. This
exists so that adding one class does not require opening the editor. It is a
development tool and has no part in a build.

## 3. A screen owns a colour the theme already defines

Status: **done.**

`multiplayer_hub_screen.gd` declared `const TEXT := Color(1.0, 0.9, 0.72, 1.0)`,
which `ui_theme.md` already lists as a theme item traced from the reference palette.

The rule, from *UI > Introduction to GUI skinning*:

> Local overrides are less useful for the visual flair of your user interface,
> especially if you aim for consistency.

and:

> Whenever a control has a local theme item override, this is the value that it
> uses. Values provided by the theme are ignored.

The same section is explicit that this is **not** a blanket rule, and the
distinction is worth keeping: local overrides are called "essential" for layout
constants such as `BoxContainer` separation and `MarginContainer` margins. So
`add_theme_constant_override("separation", ...)` is correct as written and is
**not** part of this item. Four remain in the UI and all four are separations.

### What moved

- **`TEXT` in the hub** — it lost its last caller when the flows moved into the
  flow card, so it was deleted rather than moved. The duplicate colour is gone
  because nothing wanted it.
- **The modal backdrop wash**, in `game_setup_screen.gd`, was a `ColorRect` with a
  hard-coded colour. A `ColorRect` takes its colour from the node and nowhere
  else, so it became a `Panel` with a `ModalBackdrop` theme variation.
- **The opponent's dimmed piece icon**, in `participant_card.gd`, was a
  `modulate` assignment and is now a `MutedPieceIcon` variation on the `TextureRect`.
- **The connection meter's five colours**, in `network_indicator.gd`, were
  constants. That control draws its own bars, so it cannot take them from a
  built-in type, and the section above says what to do instead:

  > Because built-in controls have no knowledge of your custom theme types, you
  > must utilize scripts to access those items.

  They are now the custom theme type `NetworkBars`, read through
  `get_theme_color(item, &"NetworkBars")`.

### Proving a theme item is real

A theme item name the engine does not recognise is ignored **without complaint**.
A misspelled variation therefore looks perfectly correct in the theme file and
changes nothing at run time, which means "the theme has the item" is not
evidence that anything reads it.

Each of the three new items is asserted in the UI checks by reading the resolved
value back off a live control and comparing it to the expected colour. If a name
stops being valid, the check fails instead of the styling quietly reverting.

## 4. Three-dimensional colours have no shared source

Status: **not started, and deliberately not yet.**

`src/game/board/board_view.gd` declares seven colour constants and
`src/game/pieces/piece_view.gd` declares two.

This is **not** a theme violation. `Theme` is a `Control` resource and does not
apply to 3D materials, so these cannot simply move into `chess_relay_theme.tres`.

It is recorded because it becomes a real problem at the piece stage: one piece
has to be drawn on the board, in a tray, and possibly in a preview, and a colour
list duplicated per file will drift. `pre_game_screen_audit.md` already notes
that layout and presentation numbers are "distributed through scripts/scenes",
which is the same issue for the UI half.

To do: decide alongside the piece system whether the 3D palette is a shared
script resource, a set of exported colours on one scene, or project settings.
Deciding it before the piece is written is cheaper than retrofitting it after.

## Not findings

Recorded so they are not re-audited later.

- **`app_root` owning navigation.** *Scene organization* requires that a GUI be
  "either a singleton, a transitory part of the World, or manually added as a
  direct child of the root. Otherwise the GUI nodes would also delete themselves
  during scene transitions." The app root adds screens beneath `%ScreenHost` and
  removes them, which satisfies this. Replacing it with per-screen scene changes
  would be a regression.
- **No autoloads.** Consistent with the project rule that autoloads are for
  services that demonstrably need application-wide lifetime. The mock service is
  app-scoped and lives under the app root. Revisit when the Rust `session` and
  `identity` work starts, which is where the bar is actually met.
- **`card.tscn` having no script.** A declarative panel shell with behaviour is
  the intended shape, not an omission.
- **`ref/` being git-ignored.** Correct, and required by the rule that it must
  stay out of the runtime import path. It does mean the audit trail lives only
  where the checkout exists, which is why this document writes its citations out
  in full.