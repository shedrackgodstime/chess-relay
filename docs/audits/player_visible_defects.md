# Player-visible defects: what is already audited, and what is new

**Date:** 2026-10-08
**Trigger:** a player reported two symptoms on a real device — captures of AI
pieces not registering, and the P2P setup screen showing section titles with
nothing under them.
**Scope:** root-cause identification only. No fixes proposed or applied here.
**Authority:** [`application_core.md`](../architecture/application_core.md),
[`game_setup_and_network_audit.md`](game_setup_and_network_audit.md),
[`ai-integration-divergence.md`](ai-integration-divergence.md),
[`godot/docs/HANDOVER.md`](../../godot/docs/HANDOVER.md).

---

## The short answer

**Both reported symptoms are already written down, and both are F-01.** Neither
is a new bug. Two further defects found while tracing are *not* in any audit and
are recorded below as new. One claim I made during the initial investigation was
**wrong and is corrected in §5**.

The root problem is not any individual defect. It is that **no gate covers the
setup screen's visual contract**, which is why F-01 could be marked complete
while it is still visible from the player's seat.

---

## 1. Symptom: captures of AI pieces do not register

**Two candidate causes. Which one is live could not be determined from source
alone, and the check that would answer it cannot run on the available device.**

### 1a. Already audited, already fixed — `ai-integration-divergence.md`

That audit recorded precisely this failure: a legal capture target tapped, the
piece surface firing before the board surface, the multiplayer ownership guard
returning "Waiting for opponent" before routing to `SubmitMove`. The fix is
present at `godot/src/ui/screens/game/game_screen.gd:324-328`:

```gdscript
# A tap on an occupied target square is a capture, not a new selection:
# the piece surface sits above the board surface and fires first.
if not _selected_piece_square.is_empty() and square in _legal_targets:
    _on_square_pressed(square)
    return
```

If the symptom persists, this path is being reached and is not sufficient.

### 1b. Not audited: `legal_moves` is generated for the side to move, not for the tapped square

`rust/src/chess_core/game.rs:107`:

```rust
pub fn legal_moves(&self) -> Vec<Move> {
    legal_moves(&self.board, self.board.side_to_move())
}
```

`Query::LegalMoves { from }` (`rust/src/app.rs:595-604`) filters that list by
origin square. So `legal_moves_from("e4")` answers *"what can the side to move do
from e4"* — it is **not** *"what could the piece standing on e4 do"*.

`_select_square` (`game_screen.gd:342`) populates `_legal_targets` from it
regardless of who owns the square. Consequences:

- Tap an **opponent or AI piece** when it is not that piece's turn:
  `_legal_targets` is empty → the capture shortcut at line 324 does not fire →
  the tap falls through to the ownership guard at line 329 → **"Waiting for
  opponent"**.
- The same tap in **local/hotseat mode** works, because `_is_multiplayer` and
  `_is_ai` are both false and the guard never runs.

That asymmetry — identical gesture, different outcome by mode — matches what was
reported, and it is the same *shape* as `ai-integration-divergence.md` but a
different mechanism, three layers down.

**Why it is not merely cosmetic:** `game_screen.gd:541` applies the identical
guard to `_offer_draw`, so offering a draw is likewise refused on the opponent's
turn. F-03 says that is a bug. It is worse than F-03 states — F-03 scopes it to
`resign()` and `offer_draw()` in the bridge; the same turn-ownership assumption
is also load-bearing in the client, in two places, and neither is written down.

### 1c. The gate cannot distinguish them

`godot/tests/game_scenarios_test.gd` (43 checks) is the suite that would settle
it. It does not execute here: **71 of 147 checks across the Godot suites are
blocked** because this device cannot `dlopen` a GDExtension library
(`HANDOVER.md` §4). So the AI capture path is unverified on the only machine
available, and the divergence audit's fix is unverified too.

**Cheapest gate that would have caught 1b**, and it is headless-checkable:

- tap an opponent piece that is **not** a legal capture → expect selection or
  "not your piece", **never** "Waiting for opponent"
- tap an opponent piece that **is** a legal capture → expect `SubmitMove`
- assert the same two outcomes in AI, multiplayer, and local modes

The third assertion is the one that matters. A guard that exists in two modes
and not the third is exactly what 1b is.

---

## 2. Symptom: P2P setup cards show titles only

**This is F-01 rendering exactly as the audit describes. Not a new bug.**

### 2a. Root cause: the game is already live before the screen opens

`rust/src/bridge.rs:1263` starts the session inside the network link task:

```rust
Command::StartGame { white: me, black: guest }
```

No user intent is involved. By the time a player reaches `GameSetupScreen` the
session is in `Playing` and the sides are committed. The audit's summary is
verbatim: *"The Game Setup screen is reduced to a hollow shell ('theater
controls')."*

`godot/src/ui/screens/game_setup/game_setup_screen.gd:113` is the hollow shell:

```gdscript
func _apply_net_lobby() -> void:
    _side_choice.hide()
    _time_choice.hide()
    _variant_choice.hide()
    _custom_time_controls.hide()
```

with `_difficulty_choice.hide()` one level up at line 95. The button becomes
"Enter game", which opens the board of a match that is already running.

### 2b. Why it looks *broken* rather than merely empty — new, not in any audit

The three `PanelContainer`s in `game_setup_screen.tscn` all carry a hard-coded
minimum height:

| Panel | Line | Value |
| --- | --- | --- |
| `SideOptions` | 104 | `Vector2(0, 202)` |
| `TimeOptions` | 118 | `Vector2(0, 202)` |
| `MatchOptions` | 165 | `Vector2(0, 202)` |

Hiding the children does **not** shrink a container below its
`custom_minimum_size`. So all three cards reserve 202px of empty space while
their contents are gone. `MatchOptions` retains its `"Match Options"` title
label — a sibling of the hidden groups, not inside them — which is precisely the
reported appearance: **section titles with nothing under them.**

This is a distinct defect from F-01. F-01 says the controls are hidden because
the session is already live. It does not say that hiding them leaves fixed-height
holes in the layout, which is why the screen reads as *broken* rather than
merely *pointless*. No audit covers authored layout responding to runtime state.

**Recorded as a rule:** a container whose contents can be hidden at runtime must
not carry a `custom_minimum_size` that assumes those contents are present. The
height belongs to the content, not to the card.

---

## 3. The wider pattern: what the UI claims versus what exists

Requested, and the honest answer is that **this is not a separate bug class. It
is F-09, listed.**

| What a player sees | Reality | Audit |
| --- | --- | --- |
| Setup section titles, empty cards | F-01 lifecycle inversion; §2 | F-01 |
| "Enter game" on a live game | Session started in Rust, not on click | F-01 |
| Clock counting 10:00 → 09:58 | Local `Timer`, no core sync | F-09 |
| Opponent named "MORGAN" | Hard-coded string in `game_screen.tscn` | F-09 |
| Time control presets | Never read by anything | F-09 |
| "Chess960" | 0% support in `chess_core` | F-09 |
| Discovery toggles | Write a local label only | F-09 |
| Invite code | Now real (`transport_rendezvous.rs`, commit `8a25602`) | closed |

**Every one of these was written down before being reported.** The `ai`
divergence audit, `game_setup_and_network_audit.md`, and `HANDOVER.md` §3 between
them name all of them.

So the direct answer to the question asked: **yes, much of what the UI displays
is placeholder, and yes, it is documented — but it was documented and then
shipped anyway.** That is the finding. Not that the defects are unknown.

`application_core.md` requires that commands and events *"never contain UI
instructions"* and that Godot renders facts the core supplies. A clock
synthesised in GDScript and a "Chess960" option with no core support are not
boundary violations in the narrow sense — the core is not being asked for
something it cannot do. They are **presentation asserting capabilities that do
not exist**, which is the failure mode `HANDOVER.md` §1 names: a control that is
visible, interactive, and discarded.

---

## 4. New findings from this investigation

Three, none present in any existing audit.

### N-1 — The leave path inherits F-03, so leaving mid-game can kill the opponent's game

`game_screen.gd:583`:

```gdscript
if not _is_multiplayer or _bridge.turn() == _bridge.my_side():
    _bridge.resign()
```

The guard is correct in intent: only your own side may resign. But `resign()`
resolves its peer from `turn_peer(&core)` (`bridge.rs:575-584`, unchanged, and
F-03's subject). So when the guard passes — it is your turn — the peer matches.
When it correctly refuses, nothing happens.

**The gap is that leaving is silently treated as a non-action on the opponent's
turn.** The comment at `game_screen.gd:580-582` documents the choice, so it is
deliberate. But a player who leaves mid-game while the opponent is thinking gets
**no signal at all**: no resignation, no disconnect event, no result. The
opponent's game sits there. F-06 covers the setup-screen leak; this is the
in-game equivalent and is not written down.

### N-2 — `setup_kind` is a bare string compared in two files, with a duplicated condition

`godot/src/ui/app/app_root.gd:156`:

```gdscript
if (setup_kind == "create" or setup_kind == "join") and _net_if_live() != null:
```

`godot/src/ui/screens/game_setup/game_setup_screen.gd:100`:

```gdscript
if _peer_kind == "create" or _peer_kind == "join":
```

Same condition, verbatim, in two files, with no shared constant and no enum.
Three producers pass a third spelling: `"peer"` (`app_root.gd:172`,
`_show_game_screen`). A typo in any producer silently changes which branch runs,
and nothing fails — the screen just configures differently. The escalating
warnings-as-errors gate cannot catch this: both strings are well-typed.

Cheap gate: assert `setup_kind` is one of the known values at entry, the same
shape as the warning-drift gate. Cheap fix: one `const` or an enum.

### N-3 — `_net_game_active` is a guard that cannot fail

`app_root.gd:170-174`:

```gdscript
_net_game_active = false
if is_multiplayer:
    game.configure_peer(_net_if_live())
    _net_game_active = _net_bridge != null
```

and `183-184`:

```gdscript
if _net_game_active:
    _net_game_active = false
    _leave_network()
```

`_net_game_active` is read in exactly one place and set in exactly two. After the
first game it is always `false` on entry and can only become `true` when
`_net_bridge` is non-null. So it reduces to "is there a bridge", which
`_net_if_live()` already answers, and it carries no information the reader does
not have.

Not a bug — it is currently harmless. Recorded because a flag named
`*_active` that cannot distinguish two states is the shape that later grows a
third state nobody tests. `_leave_network()` being idempotent is what makes it
safe, and that is documented at `app_root.gd:245-248`.

---

## 5. Corrections to my own initial reading

Two things I stated during the investigation that were wrong on checking the
code, recorded because a handover that hides its own mistakes is the pattern
this whole project is trying to stop.

**I named a function that does not exist.** I referred to `_net_if_live()` as
"re-creates the bridge if null, so a player who leaves and returns gets a fresh
bridge with no session." It does not. `app_root.gd:242` is a plain getter:

```gdscript
func _net_if_live() -> ChessCoreBridge:
    return _net_bridge
```

The lazy creator is a separate `_net()` at line 90. So there is **no stale-
bridge bug**, and N-3 above is the corrected, much smaller version of what I
first claimed.

**I said the "capture" symptom might be the documented 1a or the undocumented
1b, and could not tell them apart.** That remains true and is why §1c proposes a
gate rather than declaring a cause. Stating two candidate causes is honest;
picking one because it sounds right would repeat the failure this audit exists
to document.

---

## 6. Why this shipped, stated plainly

The gates are green on the Rust side and the Godot gate cannot run on this
device. But the deeper reason is structural and it is worth recording without
softening:

- `f89b9c5` "Promotion picker with 3D piece previews" and `e12a9bf` "**Phase 6
  complete: every core capability visible and proven live**" landed on
  2026-10-07.
- On the same day, `game_setup_and_network_audit.md` recorded F-01 as
  **Critical** — the setup screen has no authority over the match it configures.
- And `2af12d4` reads "Repair gates and a promotion regression found against the
  audit tree", which shows the audit was known and was being worked through at the
  time.

So the commit message "every core capability visible and proven live" is true of
the promotion picker and the board, and false of the setup screen and the
networked lifecycle. It was written about the part that was finished.

**This is the fifth occurrence of the handover's law**, and the first where the
violation is inside a commit message rather than only in a doc:

> **Mark a phase done only with the gate that proves it, run and green.**
> Not with the intent to run it. Not with the suite that exists to run it.
> The gate, run.

The gate for F-01 cannot run on the available device. It should have blocked the
completion claim, or the claim should have said which parts were verified.

---

## 7. What would make this class of defect impossible to ship again

Gates, in the order they would have caught what is above. None of these are
proposed as fixes to the individual defects; they are the checks whose absence is
the finding.

| Gate | Would have caught |
| --- | --- |
| A test asserting every `ChoiceGroup` option on `game_setup_screen.tscn` is read by something | 3 of the 4 remaining F-09 phantoms |
| Assert the same gesture produces the same outcome in AI, multiplayer, and local modes | §1b |
| Assert `setup_kind` ∈ known values at entry | N-2 |
| A container-minimum-height check: no fixed height where contents are hidden at runtime | §2b |
| Assert a networked leave produces an opponent-visible event | N-1 |
| `grep -rE 'TEMP-DIAG\|NET-TRACE' rust/src godot/src` must return nothing | 20 committed diagnostic prints, none gated |

The first and last are a dozen lines each. Both would have changed what a player
saw.

---

## 8. Relationship to the remediation plan

Cross-references so this is not a competing document:

- **§1b** extends **F-03** from the bridge into the client. It is not in
  [`remediation-plan.md`](../plans/remediation-plan.md).
- **§2a** *is* **F-01**, Phase 2 of the plan. **§2b** is new and belongs with it.
- **N-1** extends **F-06** from setup-leave to in-game-leave.
- **N-2**, **N-3**, and §7 are new.
- **§3** is **F-09**, Phase 3 of the plan.

The plan's phases are unchanged. This document adds detail to three of its
findings and names five things it does not yet cover.