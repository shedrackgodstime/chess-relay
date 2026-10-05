# Game setup UI

The first setup screen is the VS Computer presentation. It is UI-only: choices
update the participant side labels, custom clock fields, and configuration
summary, while Play emits `play_requested`. It does not start a match or own
chess/network state.

## Header menu

The shared header emits `menu_requested`; the screen supplies the available
actions. On Game Setup, the button opens a centered action card over a dimmed,
input-blocking backdrop. Tapping outside or pressing Escape closes it. The
menu offers Settings and a contextual exit: Return to Home for VS Computer,
Leave game for P2P. Leaving P2P asks for confirmation before returning to
Multiplayer. The same header is used for both setup modes. The eventual in-game
menu can use the same centered presentation with game-specific actions, without
putting those actions into the reusable header itself.

## Screen structure

1. The participant row summarizes the local player and computer opponent.
2. The setup grid contains side selection, time control, and match options.
3. Match options currently include Standard/Chess960 and Easy/Medium/Hard.
   Difficulty is the VS Computer-specific choice and can be hidden or replaced
   when another setup mode is introduced.
4. The status strip summarizes the selected configuration; the footer owns the
   primary Play action.

Casual/Ranked is omitted from this pass. Its product meaning and consequences
are not defined in the setup notes, while variant and AI difficulty are
explicitly named there. Add a ranked choice when its meaning is settled.

## Reusable pieces

- `src/ui/components/participant_card/participant_card.tscn` presents one
  participant and can be configured by a screen.
- `src/ui/components/choice_group/choice_group.tscn` builds a labeled,
  exclusive group of toggle buttons and emits `selection_changed`.
- `src/ui/components/card/card.tscn` supplies the common panel shell.
- `src/ui/components/game_header/game_header.tscn` supplies the top header.

Keep mode-specific content inside the setup screen's match-options area. When
P2P setup is added, the screen can configure the participant cards and replace
the AI difficulty control with the appropriate P2P presentation. Shared
choices remain in the same locations. The app root continues to own screen
navigation.
