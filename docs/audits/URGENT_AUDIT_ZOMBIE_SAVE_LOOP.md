# [URGENT] Audit & Architectural Directive: Zombie Save Loop & Win State Lockout

**Audit Date:** 2026-10-08  
**Priority:** URGENT / BLOCKER  
**Target:** Executing Agent / Architect  
**Scope:** Investigation into why leaving a game and restarting a new game resumes the previous game, why winning locks out the player, and gap analysis against `ref/chess-relay`.  
**Constraint Notice:** The executing agent is actively modifying the codebase; no code edits or test executions are performed by the auditor in this step.

---

## 1. Executive Summary & Root Problem

### The Symptom
When a player leaves an ongoing or finished game and subsequently navigates to start a new game (AI or local hotseat), the new game **never starts**. Instead, the player is dropped back into the previous game.
- If the previous game was in progress, the old board position and moves remain.
- If the previous game ended in a **WIN / LOSS / DRAW** (e.g., Checkmate, Resignation, Stalemate), the screen immediately opens in `_finished = true` state displaying `"Checkmate · White wins"` (or `"Resignation · game over"`), disabling all pieces and permanently freezing the player out of playing until the user manually deletes the save files from disk (`user://chess_relay_save.bin` and `user://chess_relay_ai_save.bin`).

---

## 2. Cross-Check Against Existing Audit Writeups

Did any of the prior audits mention or identify this defect?

**Result: NO. None of the existing audit writeups identified this defect.**

1. `docs/audits/game_setup_and_network_audit.md`:
   - Mentions **F-07: Broken Reconnect and Resume Path in Bridge**, but F-07 was scoped strictly to dropped network transport packets over Iroh (`Tip` / `Hello` / `Fen` handling).
2. `docs/audits/connection-and-source-of-truth-audit.md`:
   - Notes that `Session::resume()` reconstructs `Session.open_offer`, but `App::restore()` only emits `Event::GameEnded`. It did not identify that finished sessions trap the player in an inescapable resume loop.
3. `docs/audits/player_visible_defects.md`:
   - Identified capture input bugs (§1b), setup container heights (§2b), and in-game leave mid-turn (N-1), but did **not** trace save persistence behavior across game re-entry.
4. `rust/src/session/store.rs`:
   - Line 378 contains a test named `resume_rejects_empty_and_finished`. In reality, that test asserts that `Session::resume()` **succeeds** on a resigned session and returns `SessionState::Finished`. This false assumption codified the bug into the test suite.

---

## 3. Deep Root Cause Analysis (Code Level)

The bug is caused by a broken persistence contract spanning Godot and Rust:

### 1. In Godot (`godot/src/ui/screens/game/game_screen.gd`)
- `_start_bridge()` (lines 126–138) unconditionally attempts to restore from disk:
  ```gdscript
  if _is_ai:
      restored = _bridge.start_ai(_abs(IDENTITY_FILE), _abs(AI_SAVE_FILE), _ai_side, _ai_difficulty)
  else:
      restored = _bridge.start_resumable(_abs(IDENTITY_FILE), _abs(SAVE_FILE))
  ```
  There is no concept of "Start New Game" vs "Resume Existing Game".
- `_save_if_local()` (lines 443–446) saves every move to `save_path`.
- When a game ends (`_on_core_game_ended`, line 452), it calls `_save_if_local()`, writing the terminal log entry (checkmate, resignation, etc.) to disk.
- When the player leaves mid-game (`_confirm_leave`, line 590), it calls `_bridge.resign()`, which emits `game_ended` and writes the resignation to disk.
- **The save file is NEVER deleted or cleared upon game termination or new game selection.**

### 2. In Rust Bridge (`rust/src/bridge.rs`)
- In `start_resumable` (lines 205–215) and `start_ai` (lines 274–283):
  ```rust
  let restored_events =
      match crate::session::FileStore::new(std::path::Path::new(&save_path)).load() {
          Ok(entries) if !entries.is_empty() => app.restore(entries).ok(),
          _ => None,
      };
  if let Some(events) = restored_events {
      core.app = Some(app);
      core.me = local_peer;
      (events, Vec::new(), true) // <--- Unconditionally adopts restored session!
  } else {
      // Fresh game logic only runs if load() failed or file is empty!
  }
  ```
- Because the file still exists, `FileStore::load()` succeeds every single time.

### 3. What happens when we have a WIN?
- When a game reaches Checkmate, Resignation, or Abort:
  1. `SessionState::Finished(reason)` is written to the signed log on disk.
  2. The next time the user selects "Play Computer" or "Start Game", `FileStore::load()` reads that finished log.
  3. `Session::resume(entries)` replays the log, sees `Finished(reason)`, and returns `Ok(session)` in `SessionState::Finished`.
  4. `App::restore(entries)` matches `SessionState::Finished(reason)` and emits `vec![Event::GameEnded { reason }]`.
  5. The bridge emits `game_ended(reason)` on initialization frame 0.
  6. Godot's `GameScreen` sets `_finished = true` and updates the header to `"Checkmate · White wins"`.
  7. All piece clicks are ignored because `if _finished: return`.
  8. **The player is trapped in a zombie match forever.**

---

## 4. Gap Analysis Against `ref/chess-relay`

Inspecting `ref/chess-relay/main.gd`:

1. **How `ref/chess-relay` handles new games:**
   ```gdscript
   func start_new_game() -> void:
       game.reset()
       _deselect()
       ...
       hud.set_game_over("")
       hud.set_turn(game.state.side_to_move, game.history.size())
       _rebuild_pieces()
   ```
   In `ref/chess-relay`, every game launch from the lobby explicitly resets the board state, clears historical data, and instantiates 32 fresh piece views.
2. **The Architectural Gap:**
   - `ref/chess-relay` had **no persistence**, meaning it was safe from zombie saves, but could not survive crashes or app restarts.
   - Current `chess-relay` added `FileStore` persistence as mandated by `application_core.md`, but implemented it as a **forced resume trap** with no lifecycle clearing.
   - Specifically:
     - `application_core.md` states: *"If a game must survive an app restart, each peer saves the move log to a local file and loads it on resume. That's the only storage v1 needs."*
     - The intention was **crash recovery**, not replacing the ability to start a new game!
     - When a match is completed or when a player explicitly starts a new match from Game Setup, the previous save file must be deleted or archived.

---

## 5. Architectural Directives for the Executing Agent

The executing agent must implement the following changes to eliminate this defect:

### Directive 1: Add Save File Purging / Archiving on Game Termination
In [`rust/src/bridge.rs`](file:///home/kristency/Projects/chess-relay/rust/src/bridge.rs):
- Expose a method `#[func] fn clear_saved_game(&mut self, save_path: String) -> bool` that removes the file at `save_path`.
- Alternatively, when `Command::Resign`, `Command::Abort`, or rules-based game end occurs, provide an explicit method or automatic trigger to delete or archive the in-progress `save_path`.

### Directive 2: Distinguish Between Fresh Games and Resumed Games
In [`godot/src/game/bridge/chess_core_bridge.gd`](file:///home/kristency/Projects/chess-relay/godot/src/game/bridge/chess_core_bridge.gd) & [`godot/src/ui/screens/game/game_screen.gd`](file:///home/kristency/Projects/chess-relay/godot/src/ui/screens/game/game_screen.gd):
- When a user selects "Play Computer" or clicks "Play" in `GameSetupScreen`, they have explicitly configured a **new match** (with specific side and difficulty).
- `GameScreen` must NOT call `start_ai` with an expectation of resuming an old finished game.
- If a fresh match is requested:
  - Delete `AI_SAVE_FILE` / `SAVE_FILE` prior to starting, OR pass a `fresh: bool` flag to the bridge.
  - If a save exists on startup, provide a user-visible "Resume Game" option on the Home screen rather than silently hijacking every new game request.

### Directive 3: `Session::resume` / `App::restore` Must Not Treat Finished Sessions as Active Games
In [`rust/src/app.rs`](file:///home/kristency/Projects/chess-relay/rust/src/app.rs):
- If `app.restore()` encounters a session that is already in `SessionState::Finished`, it should either:
  1. Return an error indicating `"cannot resume finished session"` when invoked via a resume-for-play pathway, OR
  2. The bridge must check if the restored session is finished; if finished, it must discard it, delete the stale save file, and start fresh.

## 6. Implementation status

The fresh-start contract is now implemented:

- `start_resumable()` and `start_ai()` accept an explicit `fresh` flag.
- A fresh start removes the previous save before constructing the new session.
- `GameScreen.configure_ai()` marks setup-launched computer games as fresh;
  explicit restart/resume paths retain their resume behavior.
- The typed Godot facade and AI bridge test pass the flag through the boundary.
- The regression test saves an AI position, starts the same configured flow
  fresh, and verifies the initial position instead of the old one.
- Startup observers are attached before bridge startup, so startup facts cannot
  be hidden by signal order.
- Resume paths reject restored `GameEnded` events as stale-for-play, purge the
  finished save, and create a fresh session instead of adopting a terminal
  board.

Verification on 2026-10-08:

- Rust: 84 unit tests, 26 integration tests, 21 doctests; Clippy with warnings
  denied passed.
- Godot: all 26 scripts parsed, warning drift passed, and 156/156 UI checks
  passed. The AI bridge suite includes the fresh-start regression.

Residual product decision: a dedicated user-facing “Resume Game” action is not
yet implemented. Resume remains an explicit bridge API for in-progress saves;
finished saves are never resumed as playable sessions, and newly configured
games cannot silently adopt the old save.
