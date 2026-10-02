# Chess Relay — VS Computer Lobby UI

## Context

The current Chess Relay home screen is a landscape-first interface with:

- A full-screen photographic chess background.
- A strong dark overlay for readability.
- A centered composition.
- A large centered `CHESS RELAY` title.
- Wide, shallow outlined buttons.
- Warm cream/gold typography and borders.
- Significant empty space around the central UI.

The VS Computer lobby should feel like the **next screen of the same application**, not like a generic settings page.

## Recommended Composition

Do **not** use one long vertical stack for every control. The screen is landscape, so use its width while keeping the overall hierarchy centered.

```text
                    VS COMPUTER


             DIFFICULTY              PLAY AS

                Easy                  ♔ White
              ● Medium               ♚ Black
                Hard                    Random


                    ───────────


                         PLAY
```

### Structure

1. **Title**
   - Centered: `VS COMPUTER`
   - Similar visual weight to the home-screen title, but slightly smaller is acceptable.
   - Keep generous space below it.

2. **Configuration**
   - Two vertically stacked option groups placed side-by-side:
     - `DIFFICULTY`
     - `PLAY AS`
   - Each group is vertically aligned internally.
   - Keep both groups visually balanced around the center axis.
   - Do not place them inside a large card/panel.

3. **Difficulty**
   ```text
   DIFFICULTY

   Easy
   ● Medium
   Hard
   ```

   Options:
   - Easy
   - Medium
   - Hard

4. **Play As**
   ```text
   PLAY AS

   ♔ White
   ♚ Black
   ? Random
   ```

   Options:
   - White
   - Black
   - Random

5. **Selection**
   - Gold remains the selected-state color, matching the existing chess UI.
   - Use a subtle indicator such as `●` plus brighter text.
   - Do not use large radio controls, cards, sliders, or dropdowns.
   - Each option should still have a sufficiently large clickable/touch area.

6. **Action**
   - Separate configuration from the action with a subtle horizontal divider.
   - `PLAY` sits below the configuration.
   - Keep it on the central axis.
   - It can use the same outlined-button language as the home screen, but does not need to be as wide as the home-menu buttons.

## Visual Rules

### Preserve the Home Screen Language

The lobby should reuse:

- The same background treatment.
- The same dark overlay.
- The same typography.
- The same warm cream/gold palette.
- The same subtle outlined-border language.
- The same restrained visual density.

The lobby should look like a continuation of Chess Relay rather than a separate interface.

### Avoid

- Large cards around each option.
- Three horizontal difficulty cards.
- A long narrow form occupying the entire vertical center.
- Excessive borders.
- Heavy panels that obscure the photographic background.
- Large icons for every option.
- Unnecessary explanatory text.
- Extra controls that are not currently part of the game.

## Suggested Landscape Dimensions

For a 1536×864 reference screen:

- Main content width: approximately **700–850 px**.
- Two option columns: approximately **220–280 px** each.
- Gap between columns: approximately **100–150 px**.
- Keep the entire composition comfortably within the center of the screen.
- The lobby should occupy less vertical space than the home screen.

These are visual starting points, not strict pixel requirements. The composition should scale proportionally for other landscape resolutions.

## Interaction Model

The lobby is a configuration screen:

```text
Home
  ↓
VS Computer
  ↓
Choose difficulty
  ↓
Choose side
  ↓
PLAY
  ↓
Chess Board
```

The user should be able to change either setting before pressing `PLAY`.

The default selection should be visually obvious.

Once `PLAY` is activated, transition directly to the chess game using the selected difficulty and side.

## Final Design Principle

The key distinction is:

> **Vertically stacked choices, horizontally arranged groups.**

The content remains minimal and easy to scan, but the landscape layout is used properly.

The final lobby should feel like:

**Chess Relay home screen → same visual language → more focused configuration → chess board.**
