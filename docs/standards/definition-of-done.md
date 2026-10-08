# Definition of Done

Binding completion and audit-closure protocol for Chess Relay.

This document exists because “the code was changed,” “the tests were written,”
and “the issue was documented” are not the same thing. A task is done only when
its behavior is implemented, independently verified, and protected against
regression.

## The only valid completion status

### `Observed`

A possible defect, gap, inconsistency, or risk has been noticed.

Required record:

- stable finding ID;
- location or subsystem;
- observation and why it matters;
- evidence collected so far.

`Observed` is not confirmed and is not done.

### `Confirmed`

The issue is reproducible, or source inspection proves the behavior.

Required record:

- exact reproduction, trace, test, or source path;
- expected behavior;
- actual behavior;
- impact and severity;
- affected authority/boundary/state machine.

### `Assigned`

The scope and owner are explicit. The finding remains open until fixed and
verified.

### `Implemented`

The code or configuration has been changed. This status means only that the
proposed fix exists in the worktree or a commit. It does not mean the fix works.

Required record:

- changed files and commit, if committed;
- design decision or invariant being enforced;
- tests added or updated;
- known unverified behavior.

### `Verified`

The implementation has been exercised against the expected behavior and the
relevant failure paths.

Required record:

- exact command(s) run;
- exact result and date;
- test names or reproduction cases;
- environment/platform used;
- any verification that could not be performed.

If a required verifier was unavailable, the task cannot be `Verified`.

### `Protected`

The verified behavior is guarded by an automated regression test, static gate,
contract check, or equivalent repeatable mechanism. The finding may then be
closed as `Done`.

`Protected` is the only status that permits the words **done**, **fixed**, or
**complete** without qualification.

## What “done” means by area

### Rust

Rust work is done only when all applicable checks pass:

- formatting;
- Clippy/lint policy;
- locked tests;
- documentation checks;
- unit and integration behavior tests;
- boundary tests when the change affects the bridge, protocol, transport,
  persistence, or lifecycle.

If Cargo cannot provide trustworthy evidence because another agent currently has
an unrelated failing change, the result is:

> Implemented; Rust verification externally blocked by another workstream.

It is not `Verified`, `Protected`, or done. The audit finding remains open with
the exact blocked command and the reason it is excluded from the finding.

### Godot

Godot work is done only when:

- every affected script parses under the repository warning policy;
- the relevant headless tests actually execute;
- the expected test count is asserted;
- failure output produces a non-zero result;
- UI behavior is verified against real bridge/core state when the feature uses
  the bridge;
- lifecycle, scene re-entry, delayed events, and failure states are covered
  where applicable.

“The scene opens” or “the node exists” is not sufficient evidence for a
connection, session, or state-management change.

### Bridge and integration

Bridge work is done only when both sides are exercised together. At minimum,
the applicable change must prove:

- the extension loads;
- startup ordering cannot lose initial events;
- snapshots and events agree on revision/state;
- malformed or rejected commands do not crash either side;
- disconnect, reconnect, timeout, cancellation, and worker failure have
  explicit outcomes;
- stale, duplicate, and out-of-order events cannot mutate current state;
- shutdown leaves no live-looking worker or session behind.

Passing Rust-only tests or Godot-only tests cannot close an integration finding.

## Verification availability states

Verification must be reported using one of these states:

| State | Meaning | May close as done? |
| --- | --- | --- |
| `Verified` | Required check ran and passed | Yes, if protected |
| `Failed` | Required check ran and exposed a problem | No |
| `Not run` | The check was not attempted | No |
| `Unavailable` | The check could not run because a prerequisite is absent | No |
| `Externally blocked` | Another scoped workstream prevents trustworthy evidence | No |
| `Not applicable` | The check is demonstrably irrelevant to this change | Yes, with rationale |

“Ignored” is not a verification state. If a check is intentionally excluded,
record who authorized the exclusion, why it is irrelevant, and what evidence
replaces it.

## Audit finding record

Every finding that survives an audit must be tracked in this shape:

```text
ID: BRIDGE-001
Status: Confirmed | Assigned | Implemented | Verified | Protected
Owner: subsystem/person/agent
Location: file, symbol, or contract
Expected: observable required behavior
Actual: observed behavior
Impact: correctness / data loss / crash / UX / maintainability
Evidence: reproduction, trace, or source proof
Fix: commit or change description
Verification: exact commands and results
Protection: regression test or automated gate
Blocked by: prerequisite, if any
Residual risk: what remains uncertain
```

An audit summary must count findings by status. It must never report all
findings as resolved merely because they have been written down or assigned.

## Session closure protocol

Before ending a coding or audit session:

1. Re-read the current findings and worktree status.
2. Record every new observation, including findings discovered in files changed
   by another agent.
3. Separate implementation results from verification results.
4. Run every available relevant check.
5. Record unavailable or externally blocked checks explicitly.
6. Do not downgrade an open finding because its fix is inconvenient or because
   documentation now exists.
7. State the exact remaining work required for `Verified` and `Protected`.

The final session summary must include:

- completed and protected findings;
- implemented but unverified findings;
- failed checks;
- unavailable/external blockers;
- untouched or not-yet-audited scope;
- the next verification action.

## Prohibited completion language

Do not write:

- “fixed” when only the code changed;
- “tests pass” when the relevant test did not execute;
- “integration complete” after testing only one side of the boundary;
- “audit complete” while findings remain `Confirmed`, `Assigned`, or
  `Implemented`;
- “done” when verification is unavailable.

Use precise language instead: “implemented, Rust verification externally
blocked,” “Godot verified, bridge unverified,” or “confirmed and still open.”

## Why this is strict

Agents and humans both tend to confuse a plausible explanation with evidence.
This protocol makes that confusion visible. Documentation defines intent;
tests and gates provide evidence; regression protection earns closure.
