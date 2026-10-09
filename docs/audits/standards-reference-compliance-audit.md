# Standards and reference compliance audit

Date: 2026-10-09

Scope: current worktree, `docs/standards/`, architecture and handover docs,
`ref/chess-relay`, `ref/shakmaty` policy, and the postgame/rematch changes.

## Verdict

Stages 1 and 2 are now locally verified for the available gates. The broader
implementation is still not eligible for final `Done` under
[`definition-of-done.md`](../standards/definition-of-done.md), because live
two-process/device verification and older authority findings remain open.

The postgame presentation follows the reference's terminal-result direction:
the reference emits one terminal result, presents a prominent game-over label,
and disables further play. The dedicated result card is a compatible
presentation extension. Rematch is a new protocol feature; it is not claimed
to come from the reference.

## Evidence run

Passed:

- `cargo fmt --manifest-path rust/Cargo.toml -- --check`
- `cargo test --locked --all-targets`: 86 passed, 2 ignored; integration suites
  passed.
- `cargo clippy --all-targets -- -D warnings`
- `RUSTDOCFLAGS='-D warnings' cargo doc --locked --no-deps`
- Rust protocol round-trip and existing bridge/session tests.

Previously failed and now resolved in this pass:

- `ui_smoke_test.gd` previously exited `139` because `AppRoot` teardown released
  the scene while its network bridge still owned workers. `AppRoot._exit_tree()`
  now retires that owner; the supported runner exits zero.
- Terminal UI coverage now asserts the result, leave, and disconnect cards, and
  Rust memory tests exercise rematch request/accept, decline, duplicate, stale
  ID rejection, and fresh generation handling.

Still incomplete:
- No two independent live installations have verified invite, rematch,
  reconnect, stale-generation, or Android behavior in this audit.
- `cargo audit`: no vulnerability failure; it still reports the two accepted
  transitive unmaintained crates recorded in `rust/deny.toml`.
- `cargo deny check`: passes with explicit license policy and documented
  transitive advisory exceptions; duplicate versions remain warnings.

## Confirmed remaining findings

| ID | Finding | Status | Evidence |
| --- | --- | --- | --- |
| `GATE-UI-001` | Supported Godot runner exited 139 during AppRoot teardown | Protected | `AppRoot._exit_tree()` retires the bridge; full runner now passes 151/151 assertions and exits zero |
| `REMATCH-VERIFY-001` | Rematch exchange lacked regression coverage | Protected locally | Memory transport covers request, accept, decline, duplicate, stale-ID rejection, reset, and both fresh generations; live two-process verification remains open |
| `BRIDGE-E2E-001` | Live two-process Iroh/device verification is absent | Unverified | Local tests use memory transport or single-process Godot fixtures |
| `AUTHORITY-CLOCK-001` | Godot owned a fabricated ticking clock although clock authority is out of v1 | Protected | Static `MOCK` labels; no timer or local seconds state; UI test asserts no ticking method |
| `AUTHORITY-FEN-001` | Godot parsed Rust FEN and maintained a duplicate piece table | Protected locally | Rust bridge exposes typed occupied-square facts; GameScreen renders that snapshot and uses it for capture decoration |
| `IDENTITY-SPIKE-001` | Committed spike keys existed in bridge/AI paths | Protected locally | Local spike identity is random per start; resumable/AI role keys derive from the persisted installation seed and role label |
| `SUPPLY-CHAIN-001` | Cargo deny policy could not execute with the old schema | Protected locally | `cargo deny check` passes; accepted transitive advisories and dependency license exceptions are explicit |
| `DOC-DRIFT-001` | Handover/audit documents contained historical claims that no longer matched the live implementation | Implemented, locally reconciled | Handover and historical audit headers now point to the active closure ledger; live verification gaps remain explicit |

## Reference comparison

The relevant prototype behavior was checked in:

- `ref/chess-relay/chess/game.gd`: terminal result is emitted once after a
  legal move and later moves are rejected.
- `ref/chess-relay/main.gd`: terminal result is rendered as a prominent game
  over presentation.
- `ref/chess-relay/tools/build_main_scene.gd`: the result label is intentionally
  prominent.
- `ref/chess-relay/ui/hud.gd`: terminal menu actions differ from in-game draw
  actions.

The current code matches those terminal invariants at the UI/core seam as far
as the local tests exercise them. It does not yet have evidence for the full
network rematch or live disconnect path.

## Required closure order

1. Add a bridge-level send-failure test for rematch request/response and stale
   generation suppression.
2. ~~Decide whether the v1 clock is removed or explicitly labelled as mock.~~
3. ~~Resolve the FEN/piece-table authority decision and update the architecture
   contract accordingly.~~
4. ~~Replace or explicitly isolate committed spike identities.~~
5. ~~Repair `rust/deny.toml`, rerun `cargo deny check`, and record the audit
   warnings and dependency decision.~~
6. Reconcile stale handover/audit claims, then perform two-process desktop and
   Android verification.

Until these are complete, status must remain “implemented with open audit
findings,” not “done.”
