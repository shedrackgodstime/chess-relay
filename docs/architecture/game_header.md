# Reusable game header

`src/ui/components/game_header/game_header.tscn` is a reusable header for game
and setup screens. It owns presentation only. A containing screen decides
which elements to show, supplies center text, and forwards network or voice
presentation state. The component has no dependency on a chess model or
network service.

## Public interface

- Configure `show_network_indicator`, `show_voice_control`,
  `show_center_text`, `show_menu_button`, and `center_text` in the Inspector,
  or call `set_visibility(show_network, show_voice, show_center, show_menu)`.
- Call `set_center_text(text)` with screen-owned presentation text. Setup can
  use a screen title; gameplay can show whose turn it is and the move count.
- Call `set_network_state(GameHeader.NetworkState)` with `IDLE`, `CONNECTING`,
  `DEGRADED`, `GOOD`, or `LOST`.
- Call `set_voice_state(GameHeader.VoiceState)` with `OFF`, `REQUESTING`, or
  `LIVE`; call `set_remote_speaking(bool)` to show the remote-speaker marker.
- Handle `menu_requested` and `voice_toggle_requested` in the owning screen.
  These signals express user intent; the owner performs navigation or voice
  work and updates presentation through the setters.

The default scene shows network, center text, and menu; voice is hidden. The
connection meter is a passive `Control`, while menu and microphone controls
are buttons. Hiding voice resets its presentation to `OFF` and clears the
remote-speaker marker.

## Visual source

The small menu and microphone SVGs are copied from the prototype's UI icon
set to preserve the established visual reference. They remain local to this
component. The Lucide ISC notice and the MIT notice for the Feather-derived
more-vertical menu icon are included in `icons/LICENSE.txt`, following the
[upstream license](https://github.com/lucide-icons/lucide/blob/main/LICENSE).
