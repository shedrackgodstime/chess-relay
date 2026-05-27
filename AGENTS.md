docs/rust-skills/AGENTS.md (chess-relay-skills)
# Chess Relay — Session Summary

## Goal
Build a multiplayer 3D chess game in Rust with Bevy 0.18 implementing all FIDE rules for desktop and mobile.

## Progress

### Done
- Bevy 0.18 project, 3D board with GLB pieces, full FIDE legal move generation (en passant, castling, promotion, check/checkmate/stalemate)
- Board interaction: raycast click → select → move with legal move highlighting
- Screen navigation: Home → Lobby/Game/Settings
- Home screen with dark JPEG background, gold title, nav buttons, settings gear
- Game screen: opponent badge, rotation controls, promotion overlay, captured pieces, turn indicator, game over overlay
- Draw conditions: 50-move rule, threefold repetition, insufficient material
- Scene rotation (Q/E keys + button), responsive camera, theme system
- AI opponent: negamax + alpha-beta at depth 3, material eval + piece-square tables
- AI execution: `AiState` machine with 1.5s "thinking" delay before move
- AGENTS.md audit: removed all `expect()` (fallback image), renamed `p`→`piece`, doc comments on all `GameState` fields/pub methods, `Board::set` returns `Option<Piece>`, `Board::remove` simplified, `depth==0` check moved before `all_legal_moves()` in negamax
- Code quality: `cargo fmt`, `cargo check`, `clippy -D warnings`, `cargo test` all clean
- Created `net.md` with P2P/libp2p + JSON serialization plan
- Android support: `android` feature (`bevy/android-native-activity`), touch input, `cdylib` crate-type, asset bundling, release signing
- `android_main` entry point in `lib.rs`, APK builds and runs at 14 MB

### In Progress
- (none)

### Fixed (this session)
- **Android crash**: `AiState` resource was removed by `teardown_game` but never re-inserted by `setup_game` — if the screen state cycled (as happens on Android lifecycle), `schedule_ai_turn` panicked with "Resource does not exist". Fix: moved `AiState` insertion into `setup_game` alongside other per-game resources.
- **Blank screen on Android**: Actually caused by the above crash — app surfaced briefly then panicked at ~7s. With the panic fixed, app renders correctly (`HAS_DRAWN`, surface visible).

### Blocked
- (none)

### Next Steps
1. Chess clock / turn timer
2. FEN export/import
3. Networking (P2P lobby, matchmaking)
4. Visual promotion UI (piece selection dialog) — currently keyboard-based

## Android Notes
- Uses `android-native-activity` (matches `NativeActivity` that `cargo-apk` generates in `AndroidManifest.xml`)
- Touch input via `Touches::iter_just_pressed().next()` alongside mouse
- `bevy_android::ANDROID_APP` global must be set in `android_main` before asset loading
- APK at `target/release/apk/chess-relay.apk`
- Debug builds not tested — release only
- `cargo apk build --release --features android`
