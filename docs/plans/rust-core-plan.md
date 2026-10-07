# Rust Core Plan — chess-relay-core

Phased build plan for the Rust application core.
Authority: `docs/architecture/application_core.md` (what/why),
`docs/standards/rust-standards.md` (how).
**No implementation in this doc — gates only.**

## Phase 0 — Crate foundation ✅ DONE

Rename `rust` → `chess-relay-core`, `crate-type = ["cdylib", "rlib"]`,
`godot` pinned to `api-4-7`, empty module boundaries
(`chess_core`, `session`, `app`, `protocol`).
Verified: `fmt` + `clippy` clean, `cargo test` green (0 tests).

## Phase 1 — Chess core ✅ DONE (perft agrees with both oracles)

Goal: deterministic pure-chess domain. No Godot, no Iroh, no AI.

Slices, in order (each lands separately, each gated):
1. `Move` + `Square` + `Piece` newtypes with validated constructors.
2. `Board`: 64 squares + side-to-move + castling rights + en-passant,
   FEN parse/render round-trip.
3. Move generation: pseudo-legal → legal (self-check filter), castling
   transit, en-passant pin edge case.
4. `Game`: `apply_move`, halfmove clock, repetition table,
   50-move rule, insufficient material, stalemate/checkmate, result.
5. Draw offers stay out (session concern, Phase 2).

Gates:
- Perft startpos 1–5: `20 / 400 / 8902 / 197281 / 4865609` — must match
  **both** prototype (`ref/chess-relay` perft table) and shakmaty.
- Kiwipete + position 3 perft as second opinion (prototype BACKLOG cites
  pos3; shakmaty ships standard vectors).
- Fuzz spot-check: random plies never panic, always round-trip FEN.
- Standards gate checklist green (docs, examples, error structs, no leaks).

## Phase 2 — Session and move log ✅ DONE

Goal: `Created -> SettingUp -> Ready -> Playing -> Finished`,
participants/roles/readiness, signed hash-linked log wired to chess core.

- Genesis entry: protocol version + config + both peer IDs + sides.
- Host is the peer that created the session: it sets config and sides
  (and would be timekeeper if a clock ever lands); no move power.
- Move entry: move + prev-hash + mover signature (Iroh key); agreed
  once co-signed. Opponent re-validates with chess core.
- Compare-and-replay after a gap; failed validation stops the game
  with `LogMismatch` (2 peers can't vote — detection, not resolution).
- Game and connection state stay separate machines (`Playing` +
  `Reconnecting` is valid); session never blocks on transport.
- Storage behind a trait (`M-MOCKABLE-SYSCALLS`); file persistence
  itself lands in Phase 8, in-memory + mock now.

Gates: scripted two-session divergence/convergence test (drop N moves,
replay, identical logs); expired-key and tampered-entry tests rejected.

## Phase 3 — Application contract ✅ DONE (names frozen; LegalMoves + check added in Phase 6)

Goal: `handle(command) -> Result<Vec<Event>, Error>` over Phase 2.

- Commands `StartGame/SetReady/SubmitMove/Resign/OfferDraw/AnswerDraw/Abort`;
  queries `GetGameState/Session/MoveLog`; events as named in arch doc.
- No UI instructions cross the contract (existing names are examples —
  freeze them here).
- Async-origin events (remote move, disconnect) specified as a channel;
  bridge drains it (design only, bridge built Phase 6).

Gates: command→event table test per command (valid + each rejection);
Godot team signs the frozen names.

## Phase 4 — Iroh spike ✅ DONE (2026-10-06)

Proven with throwaway `rust/examples/iroh_spike.rs` (postcard framing,
real `App` views both ends, `src/` untouched except doc-mandated serde
derives on wire types):

- Endpoint boot with `chess-relay/1` (+ reserved voice ALPN on the same
  endpoint), relay reachable, ticket dial via `EndpointTicket` strings
  (pattern borrowed from irosh's transport module).
- Full game across processes: genesis → join → readiness → moves both
  ways → co-signatures back verified → identical FENs, fully agreed logs.
- Dropout mid-game: host played on alone, guest redialled the same
  ticket, tips compared, 1-entry gap replayed, FENs asserted equal
  in-process on both sides.

Verdicts (arch doc step 4 demands):

- Contract survived unchanged: everything ran through frozen commands
  plus the three Phase 3 `note_*` methods. No fixes needed.
- Joining: ticket fallback works (initial dial and redial). Short
  human-readable code stays open; nothing blocks on it.- Transport shape for Phase 7: one endpoint, game + voice ALPNs, one
  uni stream per message, tip-compare + replay-from-log resume.

## Phase 5 — Mobile spike ✅ DONE (gate passed on real hardware)

Bridge (`rust/src/bridge.rs`, one `GodotClass` node, typed signals,
outbox drained in `process()`) loads on desktop and on-device: headless
`bridge_spike_test.gd` PASSes, both Android ABIs cross-compile
(`rust/build_android.sh`, NDK 27d, platform 24) and stage under
`godot/android/libs/`, and the spike scene went green on a real phone
(logcat verdict). `phone_spike.sh` now ships the real game (export +
apksigner verify + force-stop + install + launch) instead.

Goal: minimal `GodotClass` bridge on a **real Android device**:
call into chess core, event back as signal; then one Iroh
phone↔desktop connection.

- Export preset with `INTERNET` + `ACCESS_NETWORK_STATE` (without these
  Android blocks all sockets — established).
- Iroh-on-Android itself is proven (native builds run daily); this spike
  proves the **Godot APK packaging + gdext `.so` loading** path only.
- iOS verification handed off separately; must not block Android.

Gate: pass on real hardware, or stop — core is client-agnostic, only
the bridge/client changes. iOS result required before v1-done.

## Phase 6 — Godot integration ✅ DONE (local play complete)

Goal: full bridge per arch doc §Godot integration.

- One bridge node, `#[func]` → `Command`, `process()` drains
  `try_recv()` into a `Vec` then emits signals (never emit while
  holding the borrow).
- `start()` explicit, not `init()`; typed signals for hot events,
  `Dictionary` payloads otherwise; no Rust structs to GDScript.
- Replaces `MockMultiplayerService` wiring in `app_root`.

Gates: existing `ui_smoke_test.gd` green against real core; square-press
→ `SubmitMove` → `MoveApplied` → render round-trip on desktop + Android.
Done, plus: `Query::LegalMoves`, check square, log-derived move number,
resign/offer/answer through the bridge; `game_scenarios_test.gd` proves
captures, both castles, en passant, promotion (+picker), mate banner,
draw and resign flows through the live screen; highlight vocabulary
covers selection, quiet, capture rings, castle rings, last move, check.

## Phase 7 — Protocol and transport cleanup ✅ DONE (2026-10-07)

Abstractions pulled from the working spike, per the doc: `protocol::Msg`
(version-first Hello, postcard codec, malformed input is `ProtocolError`),
`transport` trait (connections/delivery/lifecycle/errors) with an
in-memory fake, `IrohEndpoint`/`IrohConnection` behind it, and
`src/bin/chess_relay.rs` playing full sessions across processes with
fresh keys per run (endpoint identity asserted equal to peer identity).
The spike example retired.

- `serde` + compact binary (postcard-grade) frozen with version field;
  version-bump path demonstrated (v1 message rejected-or-migrated, not
  crash).
- Transport exposes connections / reliable delivery / lifecycle / errors
  only. Iroh details stay below the boundary.
- Session and protocol structs reserve (but do not use) time-control
  config / clock-snapshot fields, so a future clock needs no breaking
  change; time is never part of signed-log validity.

Gates: swap-in-memory-transport test proves session/app never knew Iroh
existed; protocol fuzz (malformed bytes → `InvalidProtocolMessage`, never
panic).

## Phase 8 — Local persistence ✅ DONE

Goal: games survive app restart, nothing more.

- Save/load signed log to file behind the Phase-2 trait; chess core
  untouched; corrupt file → clean error, never half-loaded state.

Gate: kill mid-game on desktop + Android, resume identically.

## After v1 (not this plan)

Voice (own ALPN, Rust-owned audio, mobile permission/routing verified
first), presence/discovery, signals, clock (host-timekeeper design),
AI/MCP clients, richer identity — each a capability around the frozen
contract, never growth inside `chess_core`.

## Open questions (do not block Phase 1)

1. Short join code vs raw Iroh ticket — settled in Phase 4.
2. Single crate vs workspace split — when Godot-bridge build flags
   (Android ABIs) diverge from pure-logic flags; then flat siblings
   per M-CRATES-FLAT-FOLDER.
3. Exact frozen command/event names — Phase 3.
