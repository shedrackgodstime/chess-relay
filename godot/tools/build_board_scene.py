#!/usr/bin/env python3
"""Writes src/game/board/board_view.tscn as the editor would.

The board is 64 instances of one square scene, plus a frame and a plinth. Typing
64 instance blocks by hand is not reviewable, so they are generated here once
and the generated scene is committed and edited in the editor like any other.

The generator is an authoring tool. Nothing loads it at runtime. Re-run it after
changing the square scenes' paths, not after changing the board's design — at
that point the scene is a file and is edited as one.

    python3 godot/tools/build_board_scene.py
"""

import re
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
OUT = PROJECT / "src" / "game" / "board" / "board_view.tscn"

SQUARE_SIZE = 1.0
BOARD_SIZE = 8
THICKNESS = 0.07
SURFACE_Y = 0.0
FRAME_MARGIN = 0.38
FRAME_LIP = 0.025
FRAME_DEPTH = 0.16
PLINTH_DEPTH = 0.26
PLINTH_INSET = 0.12

LIGHT_SQUARE = Color(0.76, 0.67, 0.52, 1) if False else None  # marker only

FILES = "abcdefgh"
SQUARE_GAP = 0.035


def transform(x: float, y: float, z: float) -> str:
    """A Transform3D line, in the order the editor writes it."""
    return "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %g, %g, %g)" % (x, y, z)


def square_scene(file_index: int, rank: int) -> str:
    """a1 is a dark square, so parity decides which of the two scenes to use."""
    return "3_dark" if (file_index + rank) % 2 else "2_light"


def position(file_index: int, rank: int) -> tuple[float, float]:
    """Matches square_to_world in board_view.gd: file a is -x, rank 1 is +z."""
    return ((file_index - 3.5) * SQUARE_SIZE, (3.5 - rank) * SQUARE_SIZE)


def main() -> int:
    out: list[str] = []
    out.append('[gd_scene load_steps=4 format=3]\n')
    out.append(
        '[ext_resource type="Script" '
        'path="res://src/game/board/board_view.gd" id="1_board"]\n'
    )
    out.append(
        '[ext_resource type="PackedScene" path="res://src/game/board/square.tscn" '
        'id="2_light"]\n'
    )
    out.append(
        '[ext_resource type="PackedScene" '
        'path="res://src/game/board/square_dark.tscn" id="3_dark"]\n'
    )
    out.append(
        '[sub_resource type="BoxMesh" id="5_plinth_mesh"]\n'
        f"size = Vector3({BOARD_SIZE * SQUARE_SIZE + FRAME_MARGIN * 2 - PLINTH_INSET * 2:.3f}, "
        f"{PLINTH_DEPTH:.3f}, {BOARD_SIZE * SQUARE_SIZE + FRAME_MARGIN * 2 - PLINTH_INSET * 2:.3f})\n\n"
    )
    out.append('[node name="ChessBoardView" type="Node3D"]\n')
    out.append('script = ExtResource("1_board")\n\n')
    # Squares sit directly under the root rather than under an extra Board node, so
    # that the authored squares and the frame, which the script still builds, are
    # siblings and the node paths stay one level shorter.
    out.append('[node name="Squares" type="Node3D" parent="."]\n\n')

    for rank in range(1, BOARD_SIZE + 1):
        for file_index, name in enumerate(FILES):
            x, z = position(file_index, rank)
            out.append(
                f'[node name="{name}{rank}" parent="Squares" '
                f'instance=ExtResource("{square_scene(file_index, rank)}")]\n'
            )
            out.append(f"{transform(x, SURFACE_Y, z)}\n\n")

    # The frame and plinth are still built by board_view.gd. The generator does not
    # replace them with a slab, because a slab is not the raised border they build and
    # quietly changing the board's silhouette to suit a generator would be worse than
    # leaving it where it is. They move when they move as four rails, not as one box.

    OUT.write_text("".join(out), encoding="utf-8")
    print(f"wrote {OUT.relative_to(PROJECT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())