# Piece models

Six glTF models, one per piece type. There is no white and dark variant: **a piece is
a shape and a colour is the other axis**, so a full set is six models and two
materials. See `../piece_meshes.gd`, which is the lookup.

| Piece | Vertices |
| --- | --- |
| knight | 1,049 |
| rook | 2,128 |
| pawn | 2,213 |
| bishop | 2,772 |
| queen | 3,330 |
| king | 4,047 |

About 15,000 vertices for a full set. Each model is one mesh with one primitive and one
material, and **no textures**, which is what makes a flat colour override safe: there
is no map for the override to throw away.

## Where these came from

`Godot-Chess-Prototype` by Daniel from Saber C++, <https://www.youtube.com/@sabercpp>.
Copied from that project, which is BSD 3-Clause; the licence is beside these files as
`LICENSE-SaberCpp-BSD3.txt`.

BSD 3-Clause permits redistribution and modification provided the copyright notice is
retained. That is what the file beside them is for, and it must travel with them.

**One thing to confirm before release:** the licence covers "source and binary forms"
of the project. Whether that was the author's intent for the models specifically is not
stated separately in the repository, and it is worth a question to them rather than an
assumption here.

## Import settings worth keeping

Each `.glb.import` carries:

```ini
meshes/ensure_tangents = true
meshes/generate_lods = true
meshes/light_baking = 1
```

Tangents are needed for normal maps and are harmless without them. LODs are arguably
overkill for a chess piece and are left because they were the author's choice and cost
nothing at this size.

## What was deliberately not copied

The prototype scales every piece by `new Vector3(10, 10, 10)`. That is a magic number
tied to whatever units the artist used, and it hides a real problem rather than
solving one.

**These six are not a consistent set.** Measured from the glTF position accessors,
their heights as imported are 0.58 for a knight, 0.79 for a pawn, 0.93 for a rook,
1.16 for a bishop, 1.43 for a queen and 1.67 for a king — against a board square that
is 1.0 unit. Scaling all six by the same factor leaves a knight that is the smallest
piece on a board and a king nearly two squares tall.

So each is scaled separately, by the table in `../piece_meshes.gd`. Those targets are a
starting point chosen to be plausible, not a measurement of how these particular models
ought to look: proportion is judged by looking, which is the same lesson as the camera
pitch and the occlusion behind a piece. **Expect these numbers to change once the
pieces are on the board.**

The prototype also frees and rebuilds all thirty-two pieces on every board update,
which is fine for a prototype and wrong beside movement animation: it would destroy a
glide half way through. Pieces here are created once and moved.