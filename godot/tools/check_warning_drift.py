"""Fail when Godot registers a GDScript warning key this project has not decided about.

Godot adds warning keys over time. Without a gate, a new key arrives at its
default level, nobody notices, and the escalation set quietly rots -- the
fragility called out in godotengine/godot-proposals#12922 ("this breaks easily
when changing editor version").

Two ways to be explicit about a key: set it in project.godot (the project has
an opinion), or record it in warning_baseline.txt with a reason (the project
has decided to leave it alone). An unlisted key is a gap.

Usage:
    python3 godot/tools/check_warning_drift.py <godot-binary>

Exit: 0 no drift / 1 drift / 2 usage error / 3 godot unavailable.
"""

from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
PROJECT_FILE = PROJECT_DIR / "project.godot"
BASELINE_FILE = PROJECT_DIR / "tools" / "warning_baseline.txt"

# Full setting name as the engine registers it.
PREFIX = "debug/gdscript/warnings/"
# How it is written inside project.godot's [debug] section: the section name is
# the first path component, so the file spells it without the `debug/` prefix.
IN_FILE_PREFIX = "gdscript/warnings/"

# Keys the engine owns that are not warning categories with Ignore/Warn/Error
# levels, so they can never carry a level of 2.
ALWAYS_IGNORED = {"enable", "directory_rules", "renamed_in_godot_4_hint"}


def read_configured() -> set[str]:
    """Warning keys given an explicit value in project.godot."""
    keys: set[str] = set()
    in_debug = False
    for line in PROJECT_FILE.read_text(encoding="utf-8").splitlines():
        line = line.split(";", 1)[0].strip()
        if line.startswith("[") and line.endswith("]"):
            in_debug = line == "[debug]"
            continue
        if not in_debug or "=" not in line:
            continue
        key = line.split("=", 1)[0].strip()
        if key.startswith(IN_FILE_PREFIX):
            keys.add(key[len(IN_FILE_PREFIX) :])
    return keys


def read_baseline() -> set[str]:
    """Keys deliberately left alone, from warning_baseline.txt."""
    if not BASELINE_FILE.exists():
        return set()
    keys: set[str] = set()
    for line in BASELINE_FILE.read_text(encoding="utf-8").splitlines():
        stripped = line.split("#", 1)[0].strip()
        if stripped:
            keys.add(stripped)
    return keys


def registered_keys(godot: str) -> set[str]:
    """Warning keys the engine actually registers, queried from the engine."""
    script = (
        "extends SceneTree\n"
        "func _init() -> void:\n"
        "\tfor property in ProjectSettings.get_property_list():\n"
        "\t\tvar name: String = str(property.get(\"name\", \"\"))\n"
        "\t\tif name.begins_with(\"%s\"):\n"
        "\t\t\tprint(name)\n"
        "\tquit(0)\n" % PREFIX
    )
    with tempfile.TemporaryDirectory() as workdir:
        (Path(workdir) / "project.godot").write_text(
            'config_version=5\n\n[application]\n\nconfig/name="drift-probe"\n',
            encoding="utf-8",
        )
        (Path(workdir) / "probe.gd").write_text(script, encoding="utf-8")
        try:
            proc = subprocess.run(
                [godot, "--headless", "--path", workdir, "--script", "probe.gd"],
                capture_output=True,
                text=True,
                timeout=120,
                check=False,
            )
        except (OSError, subprocess.SubprocessError):
            return set()
    keys: set[str] = set()
    pattern = re.compile(r"^" + re.escape(PREFIX) + r"(\w+)$")
    for line in proc.stdout.splitlines():
        match = pattern.match(line.strip())
        if match:
            keys.add(match.group(1))
    return keys


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    godot = sys.argv[1]
    if not Path(godot).exists() and not shutil_which(godot):
        print(f"godot binary not found: {godot}")
        return 3

    registered = registered_keys(godot)
    if not registered:
        print("::error::could not query registered warning keys from the engine.")
        return 3

    configured = read_configured()
    baselined = read_baseline()
    decided = configured | baselined

    drifted = sorted(registered - decided - ALWAYS_IGNORED)
    stale = sorted(baselined - registered)
    unknown = sorted(decided - registered)

    if drifted:
        print("::error::Godot registers GDScript warning keys this project has not "
              "decided about:")
        for key in drifted:
            print(f"  {key}")
        print("")
        print("Set the key in godot/project.godot under [debug], or record it in "
              "godot/tools/warning_baseline.txt with a reason.")

    if stale:
        print("::error::warning_baseline.txt lists keys Godot no longer registers:")
        for key in stale:
            print(f"  {key}")

    if unknown:
        print("::error::project.godot sets warning keys Godot does not register "
              "(dead settings, the failure mode that hid "
              "treat_warnings_as_errors):")
        for key in unknown:
            print(f"  {key}")

    if drifted or stale or unknown:
        return 1

    print(
        f"warning drift OK: {len(registered)} registered keys, "
        f"{len(configured)} escalated in project.godot, "
        f"{len(baselined)} baselined, {len(ALWAYS_IGNORED)} engine-internal."
    )
    return 0


def shutil_which(name: str) -> bool:
    import shutil

    return shutil.which(name) is not None


if __name__ == "__main__":
    sys.exit(main())