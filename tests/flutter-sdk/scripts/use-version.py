#!/usr/bin/env python3
"""Copy a Flutter fixture to a scratch directory, pinned to one ditto_live line.

    python3 tests/flutter-sdk/scripts/use-version.py <fixture> <line>

<fixture> is a directory name under tests/flutter-sdk (e.g. minimal_app); <line> is a
key of "lines" in tests/flutter-sdk/versions.json (e.g. 5.2). The fixture is copied
to $TMPDIR/flutter-fixture-<line>/<fixture>/ (build outputs, Pods and .dart_tool are
left behind), the `ditto_live:` dependency in the copy is rewritten to that line's
pin, and `fvm flutter pub get` runs there. The committed pubspec.lock is copied too, so
pub changes only what the new pin needs. The committed pubspec.yaml is never modified.

The copy's path is the last line printed on stdout.

minimal_app compiles against 5.0+ only; the 4.14 line uses tests/flutter-sdk/v4_app.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HARNESS = Path(__file__).resolve().parents[1]
IGNORE = shutil.ignore_patterns("build", ".dart_tool", "Pods", "ephemeral", "*.log",
                                ".flutter-plugins-dependencies")
DEP_RE = re.compile(r"^(\s+ditto_live:)\s*\S+\s*$", re.MULTILINE)
V5_ONLY = {"minimal_app"}


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    fixture, line = argv[1], argv[2]
    lines = json.loads((HARNESS / "versions.json").read_text())["lines"]
    if line not in lines:
        print(f"unknown line {line!r}; versions.json has {', '.join(lines)}", file=sys.stderr)
        return 2
    if fixture in V5_ONLY and line == "4.14":
        print(f"{fixture} does not compile against 4.14; use tests/flutter-sdk/v4_app", file=sys.stderr)
        return 2
    source = HARNESS / fixture
    if not (source / "pubspec.yaml").is_file():
        print(f"{source} has no pubspec.yaml", file=sys.stderr)
        return 2
    pin = lines[line]

    target_root = Path(os.environ.get("TMPDIR", tempfile.gettempdir())) / f"flutter-fixture-{line}"
    target = target_root / fixture
    if target.exists():
        # Keep build/ between runs of the same line (it is slow to rebuild); replace
        # everything else so the copy matches the fixture.
        for child in target.iterdir():
            if child.name == "build":
                continue
            if child.is_dir() and not child.is_symlink():
                shutil.rmtree(child)
            else:
                child.unlink()
    target.mkdir(parents=True, exist_ok=True)
    shutil.copytree(source, target, ignore=IGNORE, dirs_exist_ok=True, symlinks=True)

    pubspec = target / "pubspec.yaml"
    text = pubspec.read_text()
    rewritten, count = DEP_RE.subn(rf"\1 {pin}", text)
    if count != 1:
        print(f"{fixture}/pubspec.yaml: expected one `ditto_live:` line, found {count}", file=sys.stderr)
        return 1
    pubspec.write_text(rewritten)

    # The pinned Flutter: the .fvmrc next to versions.json applies to every fixture.
    shutil.copy2(HARNESS / ".fvmrc", target_root / ".fvmrc")
    flutter = os.environ.get("FLUTTER")
    command = [flutter] if flutter else ["fvm", "flutter"]
    result = subprocess.run(command + ["pub", "get"], cwd=target, stdout=sys.stderr)
    if result.returncode != 0:
        return result.returncode
    print(target)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
