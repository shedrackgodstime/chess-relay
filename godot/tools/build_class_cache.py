#!/usr/bin/env python3
"""Rebuilds .godot/global_script_class_cache.cfg.

Godot normally writes this when the editor opens or on `--import`, by scanning the
project for `class_name` declarations. Both of those crash on some headless
Android/Termux builds with `free(): invalid size`, and without the file the
project will not parse: every script that mentions another script's `class_name`
fails with "Could not find type ... in the current scope".

So the cache is generated here instead, from the same declarations the editor
would read. It is a development tool, not part of a build.

    python3 godot/tools/build_class_cache.py

Run it after adding a script with a new `class_name`. The editor will rewrite the
file with the same contents on its own; this exists so a headless machine is not
forced to open the editor to add one class.
"""

import re
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
CACHE = PROJECT / ".godot" / "global_script_class_cache.cfg"

CLASS_NAME = re.compile(r"^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)
EXTENDS = re.compile(r"^\s*extends\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)


def entry(path: Path) -> str | None:
    """One cache entry for a script, or None when it declares no class."""
    text = path.read_text(encoding="utf-8", errors="replace")
    name = CLASS_NAME.search(text)
    if name is None:
        return None
    base = EXTENDS.search(text)
    base_name = base.group(1) if base else "RefCounted"
    res_path = path.relative_to(PROJECT).as_posix()
    return (
        "{\n"
        f'"base": &"{base_name}",\n'
        f'"class": &"{name.group(1)}",\n'
        '"icon": "",\n'
        '"is_abstract": false,\n'
        '"is_tool": false,\n'
        '"language": &"GDScript",\n'
        f'"path": "res://{res_path}"\n'
        "}"
    )


def main() -> int:
    entries = [
        found
        for path in sorted((PROJECT / "src").rglob("*.gd"))
        if (found := entry(path)) is not None
    ]
    if not entries:
        print("no class_name declarations found", file=sys.stderr)
        return 1
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text("list=[" + ", ".join(entries) + "]\n", encoding="utf-8")
    print(f"wrote {len(entries)} classes to {CACHE.relative_to(PROJECT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())