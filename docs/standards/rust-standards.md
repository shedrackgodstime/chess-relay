# Rust Standards — chess-relay-core

Binding engineering standard for all Rust work in this project.
No code lands unless it meets this doc.

## Sources

- Primary: [Microsoft Pragmatic Rust Guidelines](https://microsoft.github.io/rust-guidelines/agents/all.txt)
  (`M-*` rule IDs below come from there). Local cache (git-ignored):
  `ref/rust-guidelines-all.txt`.
- Secondary: [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/checklist.html)
  (via M-UPSTREAM-GUIDELINES).
- Behaviour oracle: `ref/shakmaty` (commit `0658940`, 2026-10-03).
  **GPL-3.0 — learn from it, never copy from it, never depend on it.**
  See [Reference policy](#reference-policy).

Our crate is a **library** (consumed via GDExtension FFI + Iroh network),
not an application. App-only relaxations do **not** apply.

## Hard rules (every phase, every review)

### Design for humans and agents (M-DESIGN-FOR-AI, M-UPSTREAM-GUIDELINES)

- Idiomatic public APIs that look like the rest of the Rust ecosystem.
- Every module and public item documented; every public API has a runnable
  example that compiles under `cargo test` (C-EXAMPLE, C-QUESTION-MARK).
- Strong types over primitives (M-STRONG-TYPES): `Square`, `Piece`,
  `Move` are newtypes guarding their invariants (M-STRONG-TYPES-GUARD),
  not bare `u8`s or tuples.
- Everything testable without hardware: no Godot, no network, no phone
  needed for unit/integration tests (M-MOCKABLE-SYSCALLS for storage
  and transport seams).

### Port the domain, not the code (M-RUST-SHAPED)

- Port **chess semantics** from `ref/chess-relay/chess/` and cross-check
  against `ref/shakmaty`. Do **not** port GDScript technical constructs:
  no signals, no Nodes, no Dictionaries, no `throw_if_null`-style helpers.
- Striking technical similarity to the GDScript is a defect, not fidelity.

### Errors are values, panics are bugs

- Invalid input (illegal move, wrong turn, game not ready) returns
  `Result<_, _>`, never panics (M-PANIC-IS-STOP).
- Panics only for broken internal invariants, with a message stating what
  went wrong plus relevant values (M-PANIC-ON-BUG, M-PANIC-MESSAGE).
  Rationale: the Godot bridge must never crash the game on bad input.
- Errors are situation-specific structs with `Backtrace`, contextual
  accessors, `Display` + `std::error::Error` impls (M-ERRORS-CANONICAL-STRUCTS).
  One error type per layer (`IllegalMove`, `GameNotReady`, `LogMismatch`,
  `PeerUnavailable`, `InvalidProtocolMessage`) — no universal error enum.
- Convert with `From`, not `map_err` (M-FROM-ERROR).
- Private `ErrorKind` + public `is_xxx()` predicates where one struct
  covers multiple causes; never expose the kind enum.
- No `anyhow`/`eyre` in the library (M-APP-ERROR is app-only).

### FFI boundary discipline (M-FFI-TRANSLATES, M-ISOLATE-DLL-STATE)

- All logic lives in `chess-relay-core` as safe, idiomatic, testable Rust.
  The Godot bridge translates only (plain data in, plain data out).
- Only portable data crosses the `.so` boundary: event kind + simple
  payloads. No Rust structs, no `String`/`Vec` ownership transfer, no
  `TypeId`-dependent types, no shared statics across the boundary.
- No `unsafe` in chess/session/contract code. `unsafe` exists only where
  FFI forces it, with written safety reasoning (M-UNSAFE); unsound
  abstractions are never acceptable (M-UNSOUND, M-UNSAFE-IMPLIES-UB).

### API surface hygiene

- One public path per item (M-SINGLE-ITEM-PATH); no glob re-exports
  (M-NO-GLOB-REEXPORTS); no preludes (M-NO-PRELUDE).
- Re-exports that must exist use `#[doc(inline)]` (M-DOC-INLINE).
- Short names, no weasel words (`M-SHORT-NAMES`, `M-WEASEL-WORDS`):
  `pos`, not `chessPositionManager`.
- All public types are `Debug` (M-PUBLIC-DEBUG); user-facing ones
  (FEN strings, results) are also `Display` (M-PUBLIC-DISPLAY).
- Don't leak dependency types through public signatures
  (M-DONT-LEAK-TYPES): no `shakmaty::`, `iroh::`, or `godot::` types
  in `chess_core`/`session`/`app` APIs.
- Core types are `Send` so the bridge thread can own them (M-TYPES-SEND).
- No `Arc`/wrappers in APIs unless shared ownership is proven needed
  (M-AVOID-WRAPPERS, M-AVOID-INDIRECTION).

### Docs without journals (M-CANONICAL-DOCS, M-MODULE-DOCS, M-FIRST-DOC-SENTENCE, M-NO-META-DESIGN-DOCUMENTATION)

- Crate docs + `//!` on every module; first sentence ≤ ~15 words.
- Public fns carry `# Errors` / `# Panics` sections where applicable.
- Docs describe the end-state (what it is, when to use it, examples),
  never the design journey (no "why we picked X over Y" essays).

### Tests prove behaviour (M-TAUTOLOGICAL-TESTS, M-INTEGRATION-TESTS)

- Tests assert properties outsiders care about: perft node counts,
  FEN round-trips, repetition/50-move/insufficient-material outcomes,
  log compare-and-replay after a gap. Never mirror the implementation.
- Behaviour tests live in `tests/` as integration tests, not only
  inline unit tests.
- Known-answer vectors come from two independent sources: our GDScript
  prototype's perft numbers **and** shakmaty's. Agreement of both is
  the gate; disagreement stops the line.

## Explicitly out of scope

- `mimalloc`, `target-cpu` (M-MIMALLOC-APPS, M-TARGET-CPU): app-only,
  we ship a library.
- Macros of any kind until a proven need (M-MACRO-LAST-RESORT); then
  macro-by-example first (M-EXAMPLE-OVER-PROC).
- Performance optimization before the hot path is identified and
  benchmarked (M-HOTPATH). Correctness first; perft speed is a
  cross-check, not a target.
- Workspace split before a real boundary forces it (M-SMALLER-CRATES
  cuts both ways — see plan). When we split: flat sibling crates,
  workspace-owned versions (M-CARGO-WORKSPACE, M-CRATES-FLAT-FOLDER,
  M-CRATES-IN-WORKSPACE), edition 2024 (M-LATEST-EDITION).

## Reference policy

1. `ref/shakmaty` and `ref/chess-relay` are oracles, not sources.
   Read, run its tests, compare numbers. Copy nothing.
2. shakmaty is GPL-3.0; our core stays MIT/Apache-compatible.
   Depending on it or pasting from it would infect the crate.
3. `ref/` is git-ignored: reference material never ships, never gets
   imported, never appears in `Cargo.toml`.
4. Every ported behaviour cites its oracle: prototype test name and/or
   shakmaty module + perft vector.

## Gate checklist (applies to each plan phase)

- [ ] `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, `cargo test` green.
- [ ] New public items: docs + example + `Debug` (+ `Display` if user-facing).
- [ ] New fallible paths: canonical error struct, `From` conversions, `is_xxx()` where kinds vary.
- [ ] No new `unsafe`, no dependency types in public signatures (`cargo public-api` once adopted).
- [ ] Oracle citations present for ported behaviour.
