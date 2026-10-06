# Piece models

Two candidate sets, swappable by one constant, because proportion cannot be judged from
numbers. A knight that measures the right height can still read as a lump, and that is
a thing to look at.

`PieceMeshes.ACTIVE_SET` picks which one the game draws with.

## oga — active

OpenGameArt, **CC0 1.0**. Public domain dedication: commercial use, modification,
remix, no attribution and no royalties. Six glTF models, plus the `.blend` source it
came in.

| Piece | Verts |
| --- | --- |
| knight | 386 |
| king | 720 |
| rook | 736 |
| pawn | 1,250 |
| queen | 1,664 |
| bishop | 2,462 |
| **Total** | **7,218** |

254 KB for the set. No textures, so the flat colour override is safe — there is no map
for it to throw away.

**It is a consistent set.** Every base footprint is 0.045, and the heights are already
tournament proportion: pawn 0.53, rook 0.58, knight 0.63, bishop 0.74, queen 0.89 of
the king. Those match the proportions a second, unrelated CC0 pack documents, which is
the best evidence available that they are right.

Which means **one scale for the whole set** is correct, and `SET_SCALE` says so.

## saber

From `Godot-Chess-Prototype` by Daniel from Saber C++, <https://www.youtube.com/@sabercpp>.
**BSD 3-Clause**, so the notice has to travel with them; it is kept at
`LICENSE-SaberCpp-BSD3.txt`. Six glTF models, no textures.

15,539 verts, 622 KB — **2.2× the geometry and 2.4× the size** of the oga set.

**It is not a consistent set**, and that is the reason it is here rather than chosen.
Base footprints run from 0.536 to 0.948, and the knight is **0.35 of the king's
height**, which makes it the smallest piece on a board. Its original project scales all
six by `Vector3(10, 10, 10)`, which makes the inconsistency uniformly wrong rather than
removing it. So this one needs a factor per piece.

Kept because it is a genuinely different sculpt, and the low-poly knight in oga at 386
verts may read as blocky up close. **That is a judgement to make by looking, and it is
why both are here.**
