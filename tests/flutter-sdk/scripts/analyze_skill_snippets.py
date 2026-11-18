#!/usr/bin/env python3
"""Compile and lint the Dart code fences published in a skill.

Fences generated from tests/ by scripts/sync-snippets.py (the `<!-- snippet: -->`
blocks) are already compiled by the fixtures and are ignored here. Every other
```dart fence is handled by the marker comment(s) on the lines right before it:

  (none)                           written as a whole library; must compile alone
  <!-- dart-prelude: ditto -->     wrapped in `import 'package:ditto_live/ditto_live.dart';
                                   Future<void> snippet(Ditto ditto) async { ... }`
  <!-- dart-prelude: ditto-flutter -->  the same, also importing
                                   package:flutter/foundation.dart (kIsWeb, kDebugMode)
  <!-- dart-version: 4.14|5.0|5.1 -->  analyzed against that ditto_live line instead of
                                   the default (5.2) line; combinable with the prelude
  <!-- dart-fragment: pseudo-diff|v4-rename-table|partial-class-member -->
                                   skipped; no other reason is accepted, and a fragment
                                   that names a member of `ditto` or `Ditto` fails

Fences are written one file per fence into a copy of tests/flutter-sdk/snippet_check
(re-pinned per `dart-version:` from versions.json; the committed package is never
modified), checked with `dart format --output=none --set-exit-if-changed` and
`flutter analyze --fatal-infos`. Fences are batched into one run per pin. Each
failure is reported as `file.md:line`, the line inside the fence.

A re-pinned copy keeps the committed pubspec.lock, so pub changes only what the new
ditto_live pin needs, and the resulting lock then goes through the same pub.dev age
and checksum check as committed locks (scripts/check-dependency-age.py `pub_check`):
packages pub resolved fresh are never analyzed unchecked. That check needs network
access to pub.dev; `--no-age-check` skips it for offline runs.

Prelude fences are indented two spaces inside the wrapper, so they are format-checked
at --line-length 82, which is an 80-column limit for the published code.

Flutter lookup (must match "flutter" in versions.json; the global Flutter is never
used unless it is that version):
  1. $FLUTTER, a path to a flutter executable (CI sets this from the pinned install)
  2. tests/flutter-sdk/.fvm/flutter_sdk, then the FVM cache
     ($FVM_CACHE_PATH, $FVM_HOME/versions or ~/fvm/versions) for the .fvmrc version
  3. `flutter` on PATH (CI: subosito/flutter-action installs the pin)

Run from the repository root:

    python3 tests/flutter-sdk/scripts/analyze_skill_snippets.py [--skill skills/flutter-sdk]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta, timezone
import importlib.util
from dataclasses import dataclass, field
from pathlib import Path

HARNESS = Path(__file__).resolve().parents[1]
REPO_ROOT = HARNESS.parents[1]
PACKAGE = HARNESS / "snippet_check"
DEFAULT_LINE = "5.2"
FRAGMENT_REASONS = {"pseudo-diff", "v4-rename-table", "partial-class-member"}
# A fragment that names a member of a Ditto value (`ditto.store`, `Ditto.open`,
# `_ditto.sync`, `myDitto.store`) must compile instead. Any identifier ending in
# ditto/Ditto counts; a sentence ending in "Ditto." does not.
DITTO_CALL_RE = re.compile(r"[Dd]itto\.[A-Za-z_]")
_WRAPPER = "Future<void> snippet(Ditto ditto) async {\n"
PRELUDES = {
    # The body of `snippet(Ditto ditto)`, with ditto_live imported.
    "ditto": "import 'package:ditto_live/ditto_live.dart';\n\n" + _WRAPPER,
    # The same, plus package:flutter/foundation.dart (kIsWeb, kDebugMode, ...).
    "ditto-flutter": "import 'package:ditto_live/ditto_live.dart';\n"
    "import 'package:flutter/foundation.dart';\n\n" + _WRAPPER,
}
PRELUDE_VALUES = set(PRELUDES)

MARKER_RE = re.compile(r"^\s*<!--\s*(dart-[a-z]+):\s*([^>]*?)\s*-->\s*$")
OPEN_BLOCK_RE = re.compile(r"^<!-- snippet: [a-z0-9][a-z0-9-]* -->$")
CLOSE_BLOCK = "<!-- /snippet -->"
FENCE_RE = re.compile(r"^\s{0,3}(`{3,}|~{3,})\s*([^\s`]*)")
ISSUE_RE = re.compile(r"^\s*(error|warning|info) • (.*) • (lib/[\w.]+\.dart):(\d+):\d+ • (\S+)\s*$")


class Failure(Exception):
    """A problem with the inputs or toolchain, not with a fence (exit 2)."""


@dataclass
class Fence:
    path: Path
    line: int  # 1-based line of the first line of code in the fence
    code: str
    markers: dict[str, str] = field(default_factory=dict)


def parse_markdown(path: Path, errors: list[str]) -> list[Fence]:
    fences: list[Fence] = []
    pending: dict[str, str] = {}
    pending_line = 0
    in_block = False
    open_fence: str | None = None
    current: Fence | None = None
    body: list[str] = []

    def drop_pending(number: int) -> None:
        nonlocal pending
        if pending:
            errors.append(f"{path}:{pending_line}: {', '.join(pending)} is not followed by a dart fence")
            pending = {}

    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        bare = line.rstrip()
        if open_fence:
            match = FENCE_RE.match(line)
            if match and match.group(1)[0] == open_fence[0] and len(match.group(1)) >= len(open_fence) \
                    and not line.strip()[len(match.group(1)):].strip():
                if current:
                    current.code = "\n".join(body)
                    fences.append(current)
                open_fence, current, body = None, None, []
            else:
                body.append(line)
            continue
        if in_block:
            in_block = bare != CLOSE_BLOCK
            continue
        if OPEN_BLOCK_RE.match(bare):
            drop_pending(number)
            in_block = True
            continue
        marker = MARKER_RE.match(line)
        if marker:
            name, value = marker.groups()
            if not pending:
                pending_line = number
            if name in pending:
                errors.append(f"{path}:{number}: duplicate {name} marker")
            pending[name] = value
            continue
        fence = FENCE_RE.match(line)
        if fence:
            open_fence = fence.group(1)
            if fence.group(2) == "dart":
                current = Fence(path, number + 1, "", pending)
                pending = {}
            else:
                drop_pending(number)
            body = []
            continue
        if bare:
            drop_pending(number)
    if open_fence:
        errors.append(f"{path}: a code fence is never closed")
    return fences


def classify(fence: Fence, lines: dict[str, str], errors: list[str]) -> str | None:
    """Return the pin line to analyze the fence against, or None to skip it."""
    where = f"{fence.path}:{fence.line}"
    known = {"dart-prelude", "dart-version", "dart-fragment"}
    for name in fence.markers:
        if name not in known:
            errors.append(f"{where}: unknown marker {name}")
            return None
    fragment = fence.markers.get("dart-fragment")
    if fragment is not None:
        if len(fence.markers) > 1:
            errors.append(f"{where}: dart-fragment cannot be combined with other markers")
        elif fragment not in FRAGMENT_REASONS:
            errors.append(
                f"{where}: unknown dart-fragment reason '{fragment}'; accepted: "
                + ", ".join(sorted(FRAGMENT_REASONS))
            )
        elif DITTO_CALL_RE.search(fence.code):
            errors.append(f"{where}: a dart-fragment fence calls Ditto, so it must compile; remove the marker")
        return None
    prelude = fence.markers.get("dart-prelude")
    if prelude is not None and prelude not in PRELUDE_VALUES:
        errors.append(f"{where}: unknown dart-prelude '{prelude}'; accepted: {', '.join(sorted(PRELUDE_VALUES))}")
        return None
    version = fence.markers.get("dart-version", DEFAULT_LINE)
    if version not in lines:
        errors.append(f"{where}: unknown dart-version '{version}'; accepted: {', '.join(lines)}")
        return None
    return version


def run(cmd: list[str], cwd: Path, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True)


def executable_candidates(path: Path, windows: bool | None = None) -> list[str]:
    """path, plus path.bat and path.exe first on Windows (the Flutter SDK ships
    bin/flutter.bat and bin/dart.bat there)."""
    if not (os.name == "nt" if windows is None else windows):
        return [str(path)]
    return [str(path) + suffix for suffix in (".bat", ".exe", "")]


def sibling_tool(flutter: str, name: str) -> str:
    """The `name` executable next to `flutter` (dart.bat on Windows)."""
    for candidate in executable_candidates(Path(flutter).with_name(name)):
        if os.access(candidate, os.X_OK) or (os.name == "nt" and Path(candidate).is_file()):
            return candidate
    return str(Path(flutter).with_name(name))


def age_check(lockfile: Path) -> None:
    """Run scripts/check-dependency-age.py's pub check on a generated lock."""
    scripts = REPO_ROOT / "scripts"
    sys.path.insert(0, str(scripts))
    try:
        spec = importlib.util.spec_from_file_location("check_dependency_age", scripts / "check-dependency-age.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    finally:
        sys.path.remove(str(scripts))
    cutoff = datetime.now(timezone.utc) - timedelta(days=3)
    try:
        module.pub_check(lockfile, cutoff)
    except ValueError as error:
        raise Failure(f"dependency age check failed for {lockfile.name} of a re-pinned copy:\n{error}") from error


def flutter_version(executable: str) -> str | None:
    result = run([executable, "--version", "--machine"], HARNESS)
    try:
        return json.loads(result.stdout[result.stdout.index("{"):])["frameworkVersion"]
    except (ValueError, KeyError):
        return None


def find_flutter(pin: str) -> str:
    candidates: list[str] = []
    if os.environ.get("FLUTTER"):
        candidates.append(os.environ["FLUTTER"])
    else:
        candidates += executable_candidates(HARNESS / ".fvm/flutter_sdk/bin/flutter")
        fvmrc = HARNESS / ".fvmrc"
        if fvmrc.is_file():
            version = json.loads(fvmrc.read_text())["flutter"]
            cache = os.environ.get("FVM_CACHE_PATH") or (
                str(Path(os.environ["FVM_HOME"]) / "versions") if os.environ.get("FVM_HOME")
                else str(Path.home() / "fvm/versions")
            )
            candidates += executable_candidates(Path(cache) / version / "bin/flutter")
        found = shutil.which("flutter")
        if found:
            candidates.append(found)
    mismatched = []
    for candidate in candidates:
        if not os.access(candidate, os.X_OK):
            continue
        version = flutter_version(candidate)
        if version == pin:
            return candidate
        mismatched.append(f"{candidate} is {version}")
    raise Failure(
        f"no Flutter {pin} found ({'; '.join(mismatched) or 'nothing installed'}). "
        f"Run `fvm install {pin}` in tests/flutter-sdk, or set FLUTTER to a Flutter {pin} executable."
    )


def prepare_project(work: Path, line: str, pins: dict, flutter: str, check_age: bool = True) -> Path:
    """Copy snippet_check into work/line-<line>, re-pin ditto_live, and run pub get.

    A re-pinned copy's lock is age-checked unless check_age is False."""
    project = work / f"line-{line}"
    shutil.copytree(PACKAGE, project, ignore=shutil.ignore_patterns(".dart_tool", "build", "lib"))
    (project / "lib").mkdir()
    pubspec = project / "pubspec.yaml"
    text = pubspec.read_text()
    pin = pins["lines"][line]
    if line == DEFAULT_LINE:
        match = re.search(r"^  ditto_live: (\S+)$", text, re.M)
        if not match or match.group(1) != pin:
            raise Failure(
                f"snippet_check/pubspec.yaml pins ditto_live {match.group(1) if match else '?'} "
                f"but versions.json pins the {line} line at {pin}"
            )
    else:
        # Keep the committed lock: pub changes only what the new pin needs.
        text = re.sub(r"^(  ditto_live: )\S+$", rf"\g<1>{pin}", text, flags=re.M)
        pubspec.write_text(text)
    result = run([flutter, "pub", "get"], project)
    if result.returncode != 0:
        raise Failure(f"flutter pub get failed for the {line} line (ditto_live {pin}):\n{result.stdout}{result.stderr}")
    if line != DEFAULT_LINE and check_age:
        age_check(project / "pubspec.lock")
    return project


def write_fence(project: Path, index: int, fence: Fence) -> tuple[str, int, bool]:
    """Write lib/f<index>.dart. Returns (relative path, fence line offset, wrapped)."""
    wrapped = "dart-prelude" in fence.markers
    name = f"lib/f{index}.dart"
    if wrapped:
        body = "\n".join(("  " + line) if line.strip() else "" for line in fence.code.split("\n"))
        prelude = PRELUDES[fence.markers["dart-prelude"]]
        source = prelude + body + "\n}\n"
        first = prelude.count("\n") + 1  # 1-based line of the first fence line
    else:
        source = fence.code + "\n"
        first = 1
    (project / name).write_text(source, encoding="utf-8")
    return name, first, wrapped


def check_group(project: Path, fences: list[Fence], flutter: str, errors: list[str]) -> None:
    dart = sibling_tool(flutter, "dart")
    files: dict[str, tuple[Fence, int, bool]] = {}
    for index, fence in enumerate(fences):
        name, first, wrapped = write_fence(project, index, fence)
        files[name] = (fence, first, wrapped)

    for wrapped in (False, True):
        names = [n for n, (_, _, w) in files.items() if w is wrapped]
        if not names:
            continue
        cmd = [dart, "format", "--output=none", "--set-exit-if-changed"]
        if wrapped:
            cmd += ["--line-length", "82"]
        result = run(cmd + names, project)
        if result.returncode == 0:
            continue
        changed = {m.group(1) for m in re.finditer(r"^Changed (lib/\S+\.dart)$", result.stdout, re.M)}
        if not changed:
            errors.append(f"dart format failed:\n{result.stdout}{result.stderr}")
        for name in sorted(changed):
            fence = files[name][0]
            errors.append(f"{fence.path}:{fence.line}: not formatted; run `dart format` on the fence")

    result = run([flutter, "analyze", "--fatal-infos", "--no-pub"], project)
    if result.returncode == 0:
        return
    reported = False
    for text in result.stdout.splitlines():
        match = ISSUE_RE.match(text)
        if not match:
            continue
        severity, message, name, number, code = match.groups()
        fence, first, _ = files[name]
        errors.append(f"{fence.path}:{fence.line + int(number) - first}: {severity}: {message} [{code}]")
        reported = True
    if not reported:
        errors.append(f"flutter analyze failed:\n{result.stdout}{result.stderr}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--skill", default="skills/flutter-sdk", help="skill directory to check")
    parser.add_argument("--no-age-check", action="store_true",
                        help="skip the pub.dev age check of re-pinned locks (offline runs)")
    args = parser.parse_args()
    skill = Path(args.skill)
    if not skill.is_dir():
        print(f"ERROR: {skill} is not a directory", file=sys.stderr)
        return 2
    pins = json.loads((HARNESS / "versions.json").read_text())
    errors: list[str] = []
    groups: dict[str, list[Fence]] = {}
    total = 0
    for path in sorted(skill.rglob("*.md")):
        if path.is_symlink():
            continue
        for fence in parse_markdown(path, errors):
            total += 1
            line = classify(fence, pins["lines"], errors)
            if line is not None:
                groups.setdefault(line, []).append(fence)
    try:
        if groups:
            flutter = find_flutter(pins["flutter"])
            with tempfile.TemporaryDirectory(prefix="flutter-fences-") as temp:
                for line, fences in sorted(groups.items()):
                    project = prepare_project(Path(temp), line, pins, flutter, not args.no_age_check)
                    check_group(project, fences, flutter, errors)
    except Failure as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    for message in errors:
        print(f"ERROR: {message}")
    checked = sum(len(f) for f in groups.values())
    print(f"{checked} of {total} dart fence(s) analyzed, {len(errors)} problem(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
