# Chess Relay

> **Starting here?** Read [`docs/HANDOVER.md`](docs/HANDOVER.md) first. It records the
> project's working laws, the live flags on the current implementation, and the
> environment quirks that will otherwise cost you an afternoon.

Chess Relay is a UI-led chess experience built with Godot 4.7.2. The current
foundation focuses on the interface: reusable controls, shared visual styling,
and a clear screen lifecycle. Game rules and match behavior are intentionally
outside the current scope.

## Open the project

Open this directory in Godot 4.7.2 stable or a later stable release. The
project starts at `src/ui/app/app_root.tscn`, which currently hosts the home
screen and handles its transition to the VS Computer setup screen.

## Project map

- `src/ui/app/` — application root and UI lifecycle coordination.
- `src/ui/components/` — reusable UI controls and composed components.
- `src/ui/components/card/` — the shared card shell.
- `src/ui/components/choice_group/` — reusable single-choice option groups.
- `src/ui/components/game_header/` — the reusable, state-driven game header.
- `src/ui/components/participant_card/` — reusable participant summary cards.
- `src/ui/screens/` — full screens and screen-specific presentation.
- `src/ui/screens/home/` — home screen and its outward action signals.
- `src/ui/screens/game_setup/` — shared setup presentation, currently configured
  for VS Computer.
- `src/ui/theme/` — shared theme resources and design tokens.
- `assets/ui/` — UI-specific artwork, fonts, and audio when introduced.
- `docs/architecture/` — project structure and UI architecture decisions.
- `../ref/` — read-only inspiration, prototype, and reference material; not
  part of the runtime project.

Keep reusable scenes self-contained and close to their scripts and supporting
assets. Use `snake_case` for files and folders, and `PascalCase` for scene node
names. Add shared components only when there is a clear reuse case; avoid
building a component framework before the UI needs one.

## References

See [Project structure](docs/architecture/project_structure.md) for the
organization rules and local reference sources.
See [Reusable game header](docs/architecture/game_header.md) for its public
configuration, signals, and state API.
See [Game setup UI](docs/architecture/game_setup.md) for the setup structure
and its current UI-only behavior.
