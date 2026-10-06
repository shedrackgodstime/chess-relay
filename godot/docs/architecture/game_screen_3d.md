# 3D game screen plan

The main game screen will use a 3D board world with a 2D Godot HUD layered
above it. This preserves the reusable screen and header lifecycle while giving
the chessboard its own camera, lighting, geometry, and visual components.

## Composition

```text
GameScreen (Control)
├── World (Node3D)
│   ├── Camera3D
│   ├── Environment
│   ├── KeyLight
│   ├── BoardView (Node3D)
│   └── Pieces (Node3D)
└── HUD (CanvasLayer)
    ├── GameHeader
    ├── Player information
    ├── Clocks
    ├── Turn/move status
    └── Menus and dialogs
```

The board world owns 3D presentation. The HUD owns 2D presentation. Neither
part should become responsible for the other part's layout.

## Implementation stages

1. Build a reusable board shell with square geometry, frame, materials, and
   square-to-world coordinate conversion.
2. Add a stable camera, environment, and light setup.
3. Add reusable piece visuals and a mock starting position.
4. Add square picking and visual highlights without adding chess rules.
5. Add the game HUD using the existing reusable header and shared theme.
6. Add visual movement animation and last-move/check presentation.
7. Replace the mock position with the application state contract when the game
   model is ready.

## Scene ownership

- `board_view.tscn` renders the board and emits `square_pressed`.
- `piece_view.tscn` renders one piece and exposes a board-square position.
- `game_screen.tscn` composes the world and HUD and owns screen navigation.
- The board does not decide legal moves or game results.
- The piece view does not own a board registry or game state.
- The camera exposes presentation controls such as orientation and framing.

## Coordinate contract

**The board is centered at the world origin.** Files run along local X and ranks
run along local negative Z from the camera-facing side. The board view is the
single owner of conversion between algebraic squares and world positions. This
keeps picking, piece placement, highlights, and camera framing consistent.

**Coordinate labels are part of the physical frame.** They are not floating HUD
elements. Their placement is calculated from the frame geometry:

```text
board half-width  = (8 × 1.0) / 2 = 4.00
frame half-width  = 4.00 + 0.42 = 4.42
label center      = (4.00 + 4.42) / 2 = 4.21
label height      = board top + 0.025
```

**Any future board resize must use these same calculations.** Do not replace
the calculated frame midpoint with viewport offsets or screen-space labels.

**The playing surface is `y = 0`.** Squares use a `0.07` thickness and a
`0.035` gap. The frame is four separate rails with a `0.38` margin, a `0.16`
depth, and a `0.025` top lip. A separate plinth provides the solid base below
the rails. Pieces rest from the playing surface rather than from the camera or
screen layout.

## Rendering choices

- Use simple procedural meshes for the first shell so geometry can be tested
  without external art.
- Keep materials in the board/piece scenes until a shared art resource exists.
- Use one camera and deliberate lighting before adding room decoration.
- Keep the HUD in the project theme and use the existing header component.

The game camera uses a dedicated `Camera3D` orbit controller. It receives drag
input through `_unhandled_input`, so normal UI controls get first refusal. The
camera stores yaw, pitch, and distance, then applies a
`Transform3D.looking_at()` transform around the board target.

**Camera distance is clamped.** Wheel zoom changes distance within the camera
contract instead of allowing the view to pass through the board or drift away
from the playable surface.

The **Board view** control provides deterministic rotate-left, rotate-right,
flip, and reset actions for users who do not want to drag the camera.

## Verification plan

- Headless checks load the board, piece, and game scenes.
- Board checks verify 64 squares, square coordinate round-trips, and a centered
  footprint.
- Interaction checks verify square selection and highlight state.
- Layout checks verify the HUD remains present over the 3D world at the minimum
  supported window size.
- Visual review is performed at the project viewport and minimum window size
  before adding decorative surroundings.

The first implementation deliberately stops at a readable 3D board shell and
mock position. It does not introduce game rules or connection behavior.
