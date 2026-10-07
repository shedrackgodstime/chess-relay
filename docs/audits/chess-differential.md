# Chess-core differential audit vs shakmaty

Date: 2026-10-07. Oracle: `ref/shakmaty` at `0658940` (independent
implementation, GPL-3.0 — studied and executed, never copied or
depended on). Harness lives outside the repo (license hygiene) and is
re-runnable: a scratch crate depending on both engines by path, fixed
seed `0xC0FFEE`, release mode.

## Method

1500 random games from the start position. After every ply, compared:
FEN (placement, side, castling, clocks exact; en-passant FIDE-lenient),
the full legal move set as sorted UCI, check flag, checkmate, stalemate,
insufficient material, halfmove clock, terminal outcome, and threefold
detection timing (our auto-draw vs their detection, counted independently
via zobrist hashes).

Then a crafted suite: insufficient-material shapes and FEN edge cases,
each asserted against both engines.

## Result

**1500 games, 507,485 plies, zero mismatches.** Ending split: 237 mates,
309 fifty-move, 827 insufficient-material, 39 threefold, 79 stalemate.

Crafted suite: all agree, except one documented simplification below.
Three of my own test vectors were illegal positions (shakmaty refused
them with `OPPOSITE_CHECK` etc.); the engines were right, the vectors
were fixed, which is itself a data point for strict setup validation.

## Known divergence (intentional, documented in `game.rs`)

Two knights vs bare king: we declare a draw (casual simplification,
matches the GDScript prototype); FIDE and shakmaty play on (a helpmate
exists). Everything else — including same-colour bishop endings,
fifty-move timing, and threefold detection timing — agrees exactly.
