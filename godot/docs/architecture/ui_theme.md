# UI theme

The project-wide theme is `src/ui/theme/chess_relay_theme.tres`, configured in
`project.godot`. `theme_preview.tscn` is a small editor preview for its shared
panel and control variations, not an application screen.

The reusable card scene is `src/ui/components/card/card.tscn`. It composes a
`PanelContainer` with a vertical content container and uses the `Card` theme
variation. Add card content beneath its `Content` node. The 10 px vertical gap
and the panel padding, surface, border, and corner radius are carried from the
prototype's `Card` hierarchy and `StyleBox` in `ref/chess-relay/main.tscn`.

The game setup UI adds named theme variations for its workspace, participant
cards, option buttons, status strip, and primary action. Option buttons reuse
the shared button surfaces and `CHOSEN` selection style. Their keyboard-focus
outline uses the existing title gold. These are setup-specific variations;
the rest of the shared theme keeps its established styling.

## Traceable source values

The initial values below are carried from the reference prototype's
`ref/chess-relay/ui/screen_style.gd`:

- Button text and default label text: `TEXT`; button hover: `TEXT_HOVER`.
- Button surfaces: `PANEL`, `PANEL_HOVER`, `PANEL_PRESSED`; selection:
  `CHOSEN`.
- Button and panel borders: `BORDER`, `BORDER_WIDTH`, and `CORNER`.
- Card style: `PANEL`, `BORDER`, and `BORDER_WIDTH`, plus the card's 18 px
  content margins and 14 px corner radius from its prototype `StyleBox` in
  `ref/chess-relay/main.tscn`.
- Screen titles: `TITLE`, `OUTLINE`, and `OUTLINE_SIZE`.
- Quiet labels: `MUTED` and `OUTLINE_SIZE_SMALL`.
- Captions and choice text: `CAPTION`.
- Font sizes come from the prototype's existing call sites: button 22,
  quiet button 16, choice 20, screen title 40, home title 44, code display 46,
  caption 13, and quiet label 15.

The prototype does not include a font file, so the project theme keeps Godot's
fallback font. Values not established by the reference are left to Godot's
default theme. The theme does not add new palette colors or font assets.

## Theme variations

- `QuietButton` is based on `Button` and uses the reference's flat and faint
  hover treatment.
- `ChoiceButton` is based on `Button` and uses the reference's flat, hover, and
  selected treatments. A control using it must enable toggle mode if its
  pressed state represents a persistent selection.
- `Card` is based on `PanelContainer` and supplies the reference card surface.
- `ScreenTitle`, `HomeTitle`, and `CodeDisplay` are label variations for the
  title sizes already used by the prototype.
- `Caption` and `QuietLabel` centralize the corresponding label styles.
- `ModalDialog`, `ModalSecondaryButton`, and `ModalDangerButton` provide the
  shared confirmation/settings dialog surface and action hierarchy. Dialog
  button dimensions come from `AcceptDialog` theme constants, as required by
  Godot; individual dialogs should not force button minimum sizes.

Use a theme variation for a repeated appearance and local theme overrides for
layout-specific values or true one-off exceptions. Keep layout margins and
container separation close to the scene that owns that layout. The preview
scene intentionally shows the theme variations without defining navigation or
screen behavior.
