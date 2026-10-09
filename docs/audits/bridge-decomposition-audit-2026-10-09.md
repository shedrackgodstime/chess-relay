# Bridge decomposition audit — 2026-10-09

**Question:** can voice land on this codebase, and if not, what exactly has
to move first?

**Answer:** no. `rust/src/bridge.rs` is 5,072 lines — 4× the next largest
file — and the blocker is not line count but lock topology: one 25-field
`CoreState` under one mutex serializes the scene thread, all network tasks,
and the AI thread. Voice would add a fourth contender (a realtime audio
path) to the same lock. This audit measures the structure, judges it
against the docs, judges what the docs miss as an enterprise codebase, and
gives the concrete module plan with voice insertion.

## 1. Measurements (today, current worktree)

| Subsystem in `bridge.rs` | Lines | Owner per docs | Actual owner |
| --- | --- | --- | --- |
| GDExtension node + 20 signals + ~45 `#[func]`s | ~1320 (impl block) | translation only | translation + orchestration |
| Session driver (`accept_task`, `drive_session`, `on_msg` 502 lines, invite/join tasks, resume, rematch dance) | ~1500 | transport/session | bridge |
| Presence map, profile IO, recent-peer paths, setup revisions, snapshots | ~600 | bridge (presence) / session (the rest) | bridge |
| AI worker mgmt + scheduling | ~250 | `ai/` engine exists; worker glue in bridge | bridge |
| Pure predicates/snapshots (terminal, routing, naming, rematch gates) | ~300 | histories differ | bridge file |
| Tests | ~1155 | — | inline (correct) |
| Identity/seed/file helpers | ~150 | storage seam | bridge file |

Dependency direction holds: **nothing imports `bridge`** (verified by
grep). `app`/`session`/`chess_core` are clean. The rot is inward, not
outward — which is exactly why a split is safe to attempt.

Sharp edges found while measuring:

- 1 `unsafe`: only the gdext `ExtensionLibrary` impl. Clean.
- 2 non-test `expect()`: both "just stored" internal invariants. Acceptable.
- 6 `block_on` sites on the scene thread (AUDIT-STARTUP-001 and friends).
- `NetNote::Disconnected` carries `#[allow(dead_code)]` — it is NOT dead
  (emitted on every transport loss); the attribute and its "Slice C"
  comment are stale leftovers. Remove the attribute when touching the enum.
- "Slice A/B/C" phase terminology in comments was never a decomposition
  design. Do not follow it; the plan below replaces it.

## 2. Against the docs

What the docs already require (no new permission needed):

- `application_core.md` §Godot integration: *"Avoid one giant GameManager
  that mixes chess, UI, voice, discovery, Iroh and storage."* The bridge
  is that manager, minus chess. Decomposition is compliance, not taste.
- Same doc: *"Start with a few modules and split only when a real boundary
  forces it."* F-05 recorded the forcing; voice (a second subsystem needing
  the same endpoint, runtime, and event path) is the second forcing.
- `rust-standards.md` M-SMALLER-CRATES "cuts both ways": split now; flat
  sibling modules first, workspace only when build flags diverge (they
  nearly do: Android ABI handling vs pure-logic flags; audio deps will
  finish the argument).
- `cross-layer-correctness.md`: *"The bridge translates commands, queries,
  snapshots, and events; it owns no domain truth."* It currently owns
  presence truth, profile truth, setup-revision truth, and rematch-dance
  truth. Each must move into a named owning module, not just another file.
- Remediation 3.1 already orders it: network service extraction first.
- `rust-core-plan.md`: voice arrives *"as a capability around the frozen
  contract, never growth inside `chess_core`"*. The contract freeze (Phase
  3) named commands/queries/events — voice needs an **extension
  mechanism**, not an edit: additive commands/events with version-gated
  acceptance, so old peers ignore what they do not speak.

Where the docs are silent or wrong (judgment call, stated as such):

- No doc addresses **lock topology**. Cross-layer demands one authority
  per state but says nothing about one mutex per authority. A single
  `CoreState` lock means a slow filesystem write stalls input, network
  notes, and AI results together. The deadlock fixed this week (rematch
  gate noting under lock) is the warning, not the disease.
- No doc addresses **scene-thread budget**. `#[func]`s do endpoint binds,
  relay waits, file IO, and Ed25519 signing on the render thread.
  STARTUP-001 names one instance; the rule should be general: scene
  thread does translation + queue handoff, never IO/crypto/network waits.
- No doc versions the **bridge API surface**. 45 string-dispatched
  `#[func]`s with no inventory test: a rename breaks GDScript silently.
  (Concrete ask below: a `#[func]`-inventory test.)
- No doc covers **audio at all** beyond "verify the backend on device
  first" — correct as far as it goes, but voice needs a threading,
  codec, and state-machine design before any code (see §4).

## 3. Enterprise findings beyond the docs

| ID | Severity | Finding |
| --- | --- | --- |
| DECOMP-LOCK-001 | High | One 25-field `CoreState` + one mutex for scene/network/AI/presence/profile. Split state per subsystem with fine-grained locks; the Godot node keeps handles, not the world. |
| DECOMP-THREAD-001 | High | Crypto (sign/co-sign per move), file IO, and `block_on` network waits run on the scene thread. Move to worker paths with explicit completion notes; bound the scene-thread budget (translate + enqueue only). |
| DECOMP-API-001 | Medium | No inventory of the 45-method FFI surface. Add a test asserting the `#[func]` list (names + arities) so renames break loudly, not silently in GDScript. |
| DECOMP-ERR-001 | Medium | `NetNote::Error(String)` flattens protocol/transport/session failures. Godot routes by flow flags instead of error kind. Introduce typed error kinds across the boundary (retryable vs fatal vs input). |
| DECOMP-BACKPRESSURE-001 | Medium | Unbounded channels (`mpsc::unbounded`, `VecDeque` outbox) everywhere. On a phone, reconnect + resume + quality ticks can grow memory without bound. Bounded channels with a documented drop-oldest/overflow policy. |
| DECOMP-IDENTITY-001 | Medium | `CoreState::default()` carries a zero `PeerId` that renders as a real-looking `Player 00000000`. Zero identity must be unrepresentable (`Option<PeerId>`) or an explicit `Unbound` state — the project's own "no silent fallback" law applies. |
| DECOMP-SEC-001 | Medium | Identity seed file written with default umask permissions. Restrict to `0600` on creation (Unix) + test. Five-line fix, do it with the storage extraction. |
| DECOMP-VOICE-001 | Design | Voice needs: realtime audio thread (neither tokio nor scene thread), bounded jitter buffers, Opus-or-equivalent decision, echo-cancellation story, relay-bandwidth adaptation, Android permission/routing/focus verification FIRST, and an independent state machine (Idle/Connecting/Live/Muted/Failed) with contract commands/events. None exists. |

## 4. Concrete module plan (order matters)

Each step ships independently gated with zero behavior change; tests move
with their modules.

1. **Pure first** (`bridge_rules.rs` or per-domain homes): predicates
   (`terminal_outcome`, `redial_resumes_game`, rematch gates,
   `session_is_finished`), snapshots (`result_snapshot`), naming
   (`player_name`, `clean_player_name`), profile/seed/key/file helpers.
   Mechanical moves; the new unit tests already live at the right layer
   and move verbatim.
2. **Storage + profile** (`profile.rs`, on the `session::store` seam):
   identity seed (with `0600`), profile file, save paths, recent-peer
   path derivation. Kills the ad-hoc path helpers in the bridge.
3. **Network service** (`net/`): tasks, `drive_session`, `on_msg`,
   resume/sync, rematch dance, presence transitions, generations —
   behind a narrow handle (`NetHandle { cmd_tx, ... }`) owned by the
   node. The only genuinely risky step: keep the `note()`/lock
   discipline (lock, operate, drop, then emit) under review in every hunk.
4. **AI glue** (`ai_bridge.rs` or into `ai/`): worker spawn/retire,
   scheduling, drain. Engine untouched.
5. **Thin bridge** (`bridge.rs` ≈ node + `#[func]` translation + signals,
   target <1000 lines): scene-thread budget enforced by construction
   (translate + enqueue; the compiler-visible shape is "no `block_on`,
   no fs, no signing" in `#[func]` bodies — add a `rg` gate for it).
6. **Workspace split** only if/when audio deps force divergent flags
   (M-SMALLER-CRATES cuts both ways; decide with measurements, not upfront).

Gates per step: existing suites green throughout (they run against the
public surface, which does not change), plus the new `#[func]`-inventory
test from step 1 onward so the FFI contract is pinned while its
implementation moves.

## 5. Voice insertion (after step 4 minimum, device work first)

1. Audio backend selection + Android permission/routing/focus/audio-focus
   verification on hardware. No Rust voice code before this report exists.
2. Contract extension (additive, version-gated): e.g. `SetMicrophoneMuted`,
   `VoiceStateChanged{state}`, voice snapshot query. Old peers ignore
   unknown kinds; never rename existing frozen items.
3. `voice/` subsystem: state machine, ALPN sessions on the shared
   endpoint, codec, jitter buffers, all behind the transport trait for
   loopback tests. Rust owns mute/speaking/connected; Godot renders an
   indicator, nothing else.
4. Bridge signals + indicator-only UI. No voice policy in GDScript
   (retry, codec, routing stay in Rust).

## 6. What NOT to do

- Do not add voice commands/events to the current 5k-line file, even
  "temporarily". Temporary is how the forge, the theater controls, and
  the dead setting each started.
- Do not split by moving code into files without moving ownership
  (a `net.rs` that still shares `CoreState`'s lock changes nothing).
- Do not introduce the workspace split before audio deps force it.
- Do not "fix" the zero-`PeerId` by special-casing display strings;
  make it unrepresentable.
