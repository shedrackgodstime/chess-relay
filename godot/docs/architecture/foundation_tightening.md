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

Status: **ready to do.**

`project_structure.md` says to "treat engine warnings as issues to resolve,
not noise to suppress project-wide." `project.godot` has no `[debug]` section,
so nothing enforces it.

The setting is `debug/gdscript/warnings/treat_warnings_as_errors`, a boolean
that defaults to `false` (ProjectSettings class reference).

Enabling it turns the stated convention into a property of the project rather
than a property of whoever is reading it. It is also the cheapest item here,
which is most of the reason to do it first: every later item is easier to make
while the compiler is already objecting.

## 2. The multiplayer hub builds its UI in script

Status: **not started.**

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

To do: extract an authored `.tscn` per repeated piece of hub UI, starting with
the player row that the audit already names, then the invite card and the join
field. Keep the hub script for behaviour and intent.

## 3. A screen owns a colour the theme already defines

Status: **not started.**

`multiplayer_hub_screen.gd` declares `const TEXT := Color(1.0, 0.9, 0.72,
1.0)`. `ui_theme.md` already lists `TEXT` as a theme item traced from the
reference palette.

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
not part of this item. Only the colour overrides are, namely the constant
above, the backdrop colour in `game_setup_screen.gd`, and the icon modulate in
`participant_card.gd`.

To do: after item 2, when the affected controls are scenes and can take a theme
variation, replace each colour override with the matching theme item.

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