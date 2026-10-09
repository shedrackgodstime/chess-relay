# Implementation audit — 2026-10-09 (second pass: identity, results, and every prior finding)

**Scope:** the uncommitted identity/result/profile work (`rust/src/bridge.rs`,
`godot/.../chess_core_bridge.gd`, `game_screen.gd`, `multiplayer_hub_screen.gd`,
`app_root.gd`, `game_setup_screen.gd`), measured against every binding doc:
`docs/architecture/application_core.md`, `docs/standards/` (all four),
`docs/plans/` (all three), all eleven `docs/audits/`, `godot/docs/HANDOVER.md`,
`godot/docs/architecture/` (project_structure, multiplayer_ui_lifecycle,
game_setup, board_build_order), `ref/chess-relay/` (lobby note, BACKLOG),
`ref/godot-iroh/README.md`. Third-party bulk under `ref/` (demo projects,
engine docs, shakmaty changelogs) is not project authority and was excluded;
`ref/shakmaty` policy (GPL, oracle-only) was observed — nothing copied,
nothing depended on.

**Method:** full read of the binding set, then source trace of every prior
finding ID plus line-by-line review of the new diff. Status language follows
`docs/standards/definition-of-done.md`. Nothing below is "done" that is not
`Protected`; live two-process/device evidence remains open throughout.

## 1. Prior findings re-verified (today, in current source)

| ID | Status today | Evidence |
| --- | --- | --- |
| AUDIT-STARTUP-001 (scene-thread network startup) | Confirmed, open | `start_network()` still `block_on`s bind + 10s `wait_online`; `host_game` still `block_on(publish_once)`. Untouched. |
| AUDIT-RESUME-001 (no network session restore) | Confirmed, open | `start_network()` still always `App::with_local(secret)`. Untouched. |
| AUDIT-INVITE-RECONNECT-001 (invite accept loops back to invite mode) | **Fixed → Protected (local)** | `accept_task` promotes an accepted invitation (`game_peer`) and routes that peer's redials into `drive_session`; routing predicate tested; loopback-Iroh accept-loop test still open. |
| AUDIT-REMATCH-001 (rematch not terminal-gated) | **Fixed → Protected (local)** | `request_rematch`, `respond_to_rematch`, `on_msg` request/response-accept now require `session_is_finished`; live-device proof still open. Tests below. |
| AUDIT-PRESENCE-001 (disconnect keeps stale online) | **Fixed → Protected (local)** | `note()` now emits `PeerOffline` for the known peer on `Disconnected`; reconnect re-marks online via `PeerAddress`. Test below. |
| AUDIT-AUTH-001 (Ready/Setup trust claimed fields) | **Fixed → Protected (local)** | `on_msg` Ready now requires `peer == remote_peer`; Setup rejected when `host_role`. `session.note_peer_ready` already rejected non-participants, so the remaining hole was cross-side impersonation. Tests below. |
| AUDIT-TIME-001 (selectable time controls, no clock) | Implemented (labelled preview) | Choices remain but are labelled preview/untimed; core starts untimed; strip is static `MOCK`. Full hiding awaits clock design. |
| AUDIT-FEN-001 (GDScript FEN metadata parse) | **Fixed → Protected** | New `en_passant_square()` bridge query; `_capture_squares` reads it, no FEN decode left in GDScript. Covered by the en-passant scenario. |
| AUDIT-DOC-001 (stale claims) | Fixed this pass | Closure plan Phase 7 still claimed runner exit `139`; quality-gates still called `protocol.rs` an empty placeholder. Both corrected in place. Remaining `treat_warnings_as_errors` mentions verified historical-correct. |
| AUDIT-LIVE-001 (live evidence) | Unavailable, open | One CLI↔Android session exists only as uncommitted helper + transcript, not a gate. |
| F-01 lifecycle inversion | Implemented (per SETUP-001/C-SOT-07) | No `StartGame` in link tasks; host-driven `start_network_game`, guest observer. Re-verified by grep. |
| F-02 remote lifecycle crash | Closed, live-proven | Remediation Phase 1 done; this session's live resign Entry ingested cleanly (guest showed the result modal, no sever). |
| F-03 turn-bound resign | Closed | `resign`/`offer_draw`/`abort` use `core.me` for net/AI; hotseat keeps turn peer by design. |
| F-04 self-answering draw | Closed | Dialog opens on the receiver (`_on_core_draw_offered` non-mine branch); offerer gets header text. |
| F-05 monolithic bridge | Open, grew | `bridge.rs` gained profile/result/presence/rematch-gate code (~4700 lines). Decomposition (remediation 3.1) untouched. |
| F-06 setup leak | Closed | Retire-on-leave paths per C-SOT-06; unchanged this pass. |
| F-07 resume | Implemented, device proof open | Unchanged this pass. |
| F-08 uni-stream per message | Confirmed, open | `transport_iroh.rs` still `open_uni()` per message. Receiver validates order (a reorder stops the game per arch doc) — the hazard is live, not theoretical. |
| F-09 phantoms | Partial | Chess960 removed from options; discovery removed; short codes live; time controls + MOCK clock remain (see AUDIT-TIME-001). |
| F-10 teardown/FEN | Partial | Full piece rebuild per move remains; FEN decode removed (see AUDIT-FEN-001). |
| N-1 in-game leave silence | Closed by mechanism | `_confirm_leave` resigns unconditionally; net/AI resign via `core.me` (any turn); LEAVE-001 `Msg::Leave` + `peer_left` distinct from disconnect. Verified in code. |
| N-2 bare setup_kind strings | **Fixed → Protected** | Single `SETUP_KINDS/HOST/GUEST` consts + `is_*` helpers in `game_setup_screen.gd`; `app_root` uses `is_network_setup`; unknown kinds show "Unknown setup mode · waiting for host" instead of silently taking the guest branch. |
| N-3 un-failable flag | Confirmed, harmless | `_net_game_active` still mirrors bridge existence; `_leave_network` idempotent. Left as documented. |
| Two-knights draw (remediation §6a) | **Fixed → Protected** | Rule removed as FIDE error (red test first); `dead_positions_draw` pins KNNK `Ongoing`; differential updated; shakmaty agreement restored. |
| AI signing key (remediation §5d) | Closed | `ai_key = derive_role_key(&seed, AI_SPIKE_LABEL)`; no committed keys outside doctests/test vectors. |
| Debug prints (§5e) | None present | `TEMP-DIAG|NET-TRACE|DBG ` grep over `rust/src godot/src` returns nothing. The suggested grep-gate itself is still not wired — recorded below. |
| Makefile `--locked` (§5g/§4a) | **Fixed** | `check` now uses `cargo fmt --check`, `--locked` on clippy/test/doc. |
| Committed spike seeds | Closed | Only doctest/test vectors use `[1u8]/[2u8]`; bridge derives all roles. |

## 2. New-implementation audit (the identity/result diff)

| ID | Status | Detail |
| --- | --- | --- |
| NEW-001 resignation modal inversion | **Fixed → Protected** | Root cause: `_player_won` checked whether our side-name appeared in a Rust `Debug` string (`Resignation { by: PeerId(..) }`) that never names a side. Replaced by `terminal_outcome()` mapping session → (reason, actor, winner, loser) by `PeerId`, rendered from the `game_result` Dictionary. Rust regression test + 3 new Godot card assertions (title `Resignation · White wins`, subtitle names actor). |
| NEW-002 `_opponent_peer` fallback | Fixed | Returned `_opponent_name` (a name) where a peer ID was required, producing `Player Opponent` labels. Returns `""` now; clock strip only resolves non-empty peers. |
| NEW-003 clock-strip vacuous gate | Fixed | `if not local_name.is_empty()` was always true (`my_player_name` never empty). Removed; peer-emptiness is the real guard. |
| NEW-004 stale SPIKE-ONLY comment | Fixed | Claimed committed spike keys still forge the opponent; roles are installation-derived since the compliance pass. Comment rewritten to the true hotseat model. |
| NEW-005 unused `turn` in result snapshot | Fixed | No consumer; terminal-time turn is stale trivia next to the live turn query. Removed; remaining keys (reason, actor/winner/loser peer+name, sides, local peer/won, white/black names) documented on the `game_result` signal per the cross-layer event-schema rule. |
| NEW-006 hub profile on failed presence | Fixed | Failure branch configured the profile from an unbound bridge (`Player 00000000`). Hub now keeps neutral `Guest player` unless presence started. |
| NEW-007 profile I/O on scene thread | Accepted limitation | `set_player_name` does one tiny file write in `#[func]`. Same thread already `block_on`s network startup (AUDIT-STARTUP-001); a write smaller than the existing blocks changes no budget. Revisit with STARTUP-001. |
| NEW-008 `bridge_error` unwired for name rejection | Accepted, covered | `_net()` does not connect `bridge_error`; invalid names surface by echo (field snaps back to authority). No destructive path exists, so no silent harm. Revisit if `bridge_error` gets a global route. |
| NEW-009 remote names are fallbacks | Open, by design | No wire metadata yet (irosh audit §5: separate authenticated snapshot, explicitly future). Every remote renders `Player <8-hex>`: stable, deterministic, never a real person's name. Matches the audit's verification list. |
| NEW-010 edit-tool tab damage | Caught by gate | A batch string replace stripped one tab in `_on_play_pressed`, breaking parse. R1 (per-file parse gate) caught it before anything else ran. Lesson kept: never batch-replace across indentation boundaries without re-running parse immediately. |
| NEW-011 `game_ended` retained | Kept deliberately | Still emitted alongside `game_result`; no in-tree consumer, but it is the documented terminal string other/future clients may use. Removing it would break the facade contract silently. |
| NEW-012 `git checkout <file>` in a dirty tree | Process rule | A red-proof probe reverted the app_root wiring via `git checkout`; restored from the recorded diff and re-verified by gate. Never restore single files from the index while the tree holds uncommitted work — back the hunk up first. |

Mode-matrix review for the touched GDScript (per ai-integration-divergence §review-checks): resignation titles are mode-aware (AI → Victory/Defeat via `local_won`; shared-board → winning side); clock-strip branch is multiplayer-gated; hub editor is hub-local and session-independent; setup helpers preserve every branch outcome (unknown kinds keep the safe guest-observe default plus a visible status). No `_is_multiplayer or _is_ai` widening was introduced.

## 3. Fixes applied in this audit pass (with protection)

| Fix | Tests (all red-proven by temporary mutation) |
| --- | --- |
| `terminal_outcome` resignation winner by identity | `resignation_names_winner_by_identity` |
| Ready bound to transport peer | `forged_readiness_is_rejected` (+legit control) |
| Setup rejected when `host_role` | `guest_setup_is_rejected` (+guest-accepts control) |
| Rematch requires finished game (send/receive/accept) | `rematch_request_requires_a_finished_game`; existing rematch tests updated to finish-then-rematch |
| Disconnect marks peer offline | `disconnect_marks_known_peer_offline` |
| `clean_player_name` shared save/load rule | `player_name_rule_trims_and_rejects` |
| N-2 setup-kind helpers + unknown status | Godot scenarios suite (parse + full run) |
| Result-card winner attribution | 3 new scenario assertions (title, subtitle, card presence) |
| Makefile `--locked` | `make check` shape; gates below |

One process note, kept honest: a first version of the rematch-receive gate
called `note()` while holding the core mutex and deadlocked the driver
(`note()` locks internally). The new test hung instead of failing — found by
running the single test directly, fixed by scoping locks before notes, with a
comment at the site. The module rule ("lock, operate, drop, then emit") now
has a demonstrated violation-and-fix, not just a statement.

## 4. Verification performed (this machine, 2026-10-09)

| Check | Result |
| --- | --- |
| `cargo fmt --check` | clean |
| `cargo clippy --locked --all-targets -- -D warnings` | clean (forced re-check via `touch`) |
| `cargo test --locked` | 95 lib (incl. 9 new) + 8/3/4/3/4/5/21 integration, 0 failed |
| `cargo doc --locked --no-deps -D warnings` | clean |
| `GODOT_BIN=godot run_all_checks.sh` (rebuilt `.so`) | scenarios expect 53 (50+3 new), smoke 151/151, `all gates green`, exit 0 |
| `git diff --check` | clean |
| R9 red-proofs | 5/5 new gates demonstrated red under mutation, restored, green |

Environment note: mid-pass the disks filled (24G in-tree debug cache, 7.6G
/tmp cargo cache) and persistence/link gates failed for that reason alone;
cleared with the user's explicit approval after confirming the artifacts are
regenerable. The `.so` in `godot/bin` was rebuilt from current sources after
every Rust change before each Godot run.

## 5. Still open (not fixed here, with reason)

Second-pass closures (same day): AUDIT-FEN-001, AUDIT-TIME-001 (labelled
preview), two-knights rule, no-debug-prints gate, AUDIT-REMATCH-001
(incl. pure send/accept predicates), AUDIT-AUTH-001, AUDIT-PRESENCE-001,
N-2, Makefile/CI `--locked`, AI naming authority, INVITE-RECONNECT-001
redial routing (predicate-tested; loopback-Iroh accept-loop test open).

Remaining:

- F-05, F-08, AUDIT-STARTUP-001, AUDIT-RESUME-001, AUDIT-LIVE-001, N-3,
  voice/clock (out of v1 by design), remote-name exchange (needs the
  future authenticated metadata snapshot), orientation/collision
  verification (needs hardware), `request_rematch`/`respond_to_rematch`
  direct node coverage (extracted predicates covered instead).
- CLI rework: recorded in the closure plan, not started (concept changing).
- Uncommitted session artifacts: `chess_play_host` helper changes (Loaded
  handshake, no-timeout lobby) and `play-with-opencode.txt` remain review
  material, not evidence. The helper mints a fresh identity per run, so it
  cannot verify installation-stable identity.

## 6. Status counts

- Re-verified prior findings: 30 items (10 full-audit + 10 F-series + 3 N-series + 7 remediation extras).
- Fixed → Protected (local): REMATCH, PRESENCE, AUTH, INVITE-RECONNECT,
  FEN-001, TIME-001 (labelled), two-knights, debug-prints gate, DOC lines
  ×2, N-2, Makefile gates, resignation modal, AI naming (15 total).
- Fixed (code, covered by suite): 6 more (NEW-002..006 + app_root branch).
- Accepted limitations: 3 (NEW-007, NEW-008, N-3).
- Open (recorded with reason): 9. Unavailable: 1 (LIVE-001).
