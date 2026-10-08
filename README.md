# Chess Relay workspace

A Godot chess client over a Rust application core that owns the rules, the
session, and the signed move log.

- [`godot/`](godot/) — the client. Renders the board, takes input, owns no rules.
- [`rust/`](rust/) — the application core. Chess domain, session, move log,
  application contract, and the GDExtension bridge.
- [`ref/`](ref/) — local reference material, git-ignored, never a runtime
  dependency.

## Checks

Everything is one command per language, and CI runs both on every push.

### Godot

```sh
bash godot/tests/run_all_checks.sh
```

Per-file parse with warnings-as-errors, a warning-key drift gate, and every
`*_test.gd` suite with stderr treated as a failure. See
[`godot/tests/README.md`](godot/tests/README.md).

### Rust

```sh
cargo fmt     --manifest-path rust/Cargo.toml --check
cargo clippy  --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test    --manifest-path rust/Cargo.toml --locked
```

If the bridge suites fail with "the Rust core is not loaded", build it first:

```sh
CARGO_TARGET_DIR=/tmp/chess-relay-target \
  cargo build --manifest-path rust/Cargo.toml --lib
mkdir -p godot/bin
cp /tmp/chess-relay-target/debug/libchess_relay_core.so godot/bin/
```

**`CARGO_TARGET_DIR` must point outside the repository** when working on
Android shared storage. That mount is `noexec`, so an in-tree `rust/target`
cannot execute build scripts and `cargo build` fails with
`Permission denied (os error 13)`.

## Documentation

| Document | What it is |
| --- | --- |
| [application core architecture](docs/architecture/application_core.md) | Who owns what, and the contract between them |
| [quality gates](docs/standards/quality-gates.md) | The rules CI enforces, and the measurements behind them |
| [rust standards](docs/standards/rust-standards.md) | Binding standard for all Rust work |
| [cross-layer correctness](docs/standards/cross-layer-correctness.md) | Binding rules for Rust, Godot, and the bridge |
| [definition of done](docs/standards/definition-of-done.md) | Required implementation, verification, and closure states |
| [implementation and closure plan](docs/plans/implementation-closure-plan.md) | Active execution order and finding ledger |
| [rust core plan](docs/plans/rust-core-plan.md) | Phased build plan with gates |
| [foundation audit](docs/audits/foundation_audit.md) | Measured state of the code as of 2026-10-07 |
| [handover](godot/docs/HANDOVER.md) | Lessons paid for; read before the architecture docs |

Godot-specific architecture notes live in [`godot/docs/architecture/`](godot/docs/architecture/).

## Current state

Rust core through Phase 6: chess rules with perft pinned to two independent
oracles, session lifecycle, signed hash-linked move log with replay, the
application contract, a proven Iroh spike, and the Godot bridge. Tests green.

The Godot client's UI and board are working. **Its test evidence is not yet
trustworthy**, and the reason is documented rather than hidden: the suite used to
report success while 78 of 146 checks had never executed, and the Rust core had
never loaded on the machine that ran those tests. Both are fixed in the harness
now; see the foundation audit for the full accounting.
