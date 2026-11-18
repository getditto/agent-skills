#!/usr/bin/env python3
"""Assemble the Flutter minimal app from the skill's Markdown, for CI to build.

The skill ships generated copies of marked regions of this harness (see
scripts/sync-snippets.py). A region can be identical to its source and still not
build on its own, for example if it relies on a fixture file outside the markers.
This script builds a project from `flutter create` plus only the code and platform
configuration an agent gets from skills/flutter-sdk, so CI can analyze it and build it for Android, the iOS Simulator and the web.

    python3 tests/flutter-sdk/build-from-skill.py <out-dir>

From the skill:
  lib/minimal_app.dart            examples/minimal-app.md  flutter-minimal-app
  pubspec.yaml dependencies       examples/minimal-app.md  flutter-minimal-pubspec
  ios/Podfile platform            references/setup.md      flutter-podfile-ios
  ios/Podfile post_install        references/setup.md      flutter-podfile-ios-simulator-arch
  ios/Runner/Info.plist keys      references/setup.md      flutter-ios-info-plist
  android/app/build.gradle.kts    references/setup.md      flutter-android-gradle (defaultConfig)
  android/build.gradle.kts        references/setup.md      flutter-android-compilesdk-override
  android/.../AndroidManifest.xml references/setup.md      flutter-android-manifest
  macos/Runner/*.entitlements     references/setup.md      flutter-macos-entitlements (missing keys)

From this harness, not the skill: lib/main.dart (the widget that runs the program, like
the Kotlin script's activity), minimal_app/pubspec.lock (so pub starts from the
age-checked fixture resolution), and Flutter's own CocoaPods Podfile template, since
`flutter create` on 3.50 writes no Podfile.

Flutter: $FLUTTER if set, else `fvm flutter`, else `flutter` on PATH; it must be the
version pinned in versions.json.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SKILL = ROOT / "skills/flutter-sdk"
HARNESS = ROOT / "tests/flutter-sdk"
FIXTURE = HARNESS / "minimal_app"
ORG = "live.ditto.skills"
NAME = "minimal_app"


def snippet(markdown: Path, name: str) -> str:
    text = markdown.read_text(encoding="utf-8")
    match = re.search(
        rf"^<!-- snippet: {re.escape(name)} -->\n<!--[^\n]*-->\n(`{{3,}})[\w-]*\n(.*?)\n\1\n<!-- /snippet -->$",
        text,
        re.S | re.M,
    )
    if not match:
        sys.exit(f"{markdown}: no generated snippet '{name}'")
    return match.group(2) + "\n"


def replace_once(path: Path, pattern: str, replacement: str, flags: int = re.S | re.M) -> None:
    text = path.read_text(encoding="utf-8")
    new, count = re.subn(pattern, lambda _: replacement, text, count=1, flags=flags)
    if count != 1:
        sys.exit(f"{path}: expected to find {pattern!r}")
    path.write_text(new, encoding="utf-8")


def indent(text: str, prefix: str) -> str:
    return "".join(prefix + line if line.strip() else line for line in text.splitlines(True))


def flutter_command() -> list[str]:
    if os.environ.get("FLUTTER"):
        return [os.environ["FLUTTER"]]
    if shutil.which("fvm"):
        return ["fvm", "flutter"]
    found = shutil.which("flutter")
    if not found:
        sys.exit("no flutter: set FLUTTER, or install fvm or flutter")
    return [found]


def flutter_root(command: list[str]) -> Path:
    result = subprocess.run(command + ["--version", "--machine"], cwd=HARNESS, capture_output=True, text=True,
                            check=True)
    info = json.loads(result.stdout[result.stdout.index("{"):])
    pin = json.loads((HARNESS / "versions.json").read_text())["flutter"]
    if info["frameworkVersion"] != pin:
        sys.exit(f"Flutter {info['frameworkVersion']} is not the pinned {pin}")
    return Path(info["flutterRoot"])


def plist_pairs(fragment: str) -> list[tuple[str, str]]:
    """Split a plist fragment into (key, the key line plus its value) pairs."""
    pairs = []
    for match in re.finditer(r"^([ \t]*<key>([^<]+)</key>\n.*?)(?=^[ \t]*<key>|\Z)", fragment, re.S | re.M):
        pairs.append((match.group(2), match.group(1)))
    if not pairs:
        sys.exit("a plist snippet has no <key> entries")
    return pairs


def add_plist_keys(path: Path, fragment: str) -> None:
    """Insert the fragment's keys before the top-level </dict>, skipping keys already set."""
    text = path.read_text(encoding="utf-8")
    missing = [body for key, body in plist_pairs(fragment) if f"<key>{key}</key>" not in text]
    if not missing:
        return
    # The snippet is unindented; the plist's top-level dict is one tab deep.
    block = indent("".join(missing), "\t")
    head, sep, tail = text.rpartition("</dict>")
    if not sep:
        sys.exit(f"{path}: no </dict>")
    path.write_text(head + block + sep + tail, encoding="utf-8")


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    out = Path(sys.argv[1]).resolve()
    if out.exists():
        sys.exit(f"{out} already exists")
    command = flutter_command()
    templates = flutter_root(command) / "packages/flutter_tools/templates/cocoapods"
    subprocess.run(command + ["create", "--project-name", NAME, "--org", ORG, "--platforms", "android,ios,macos,web",
                              "--no-pub", str(out)], cwd=HARNESS, check=True, stdout=subprocess.DEVNULL)

    example = SKILL / "examples/minimal-app.md"
    setup = SKILL / "references/setup.md"

    (out / "lib/minimal_app.dart").write_text(snippet(example, "flutter-minimal-app"), encoding="utf-8")
    shutil.copy2(FIXTURE / "lib/main.dart", out / "lib/main.dart")
    shutil.rmtree(out / "test", ignore_errors=True)  # the template's widget test targets its counter app

    # The whole top-level dependencies: section, up to the next top-level key.
    replace_once(out / "pubspec.yaml", r"^dependencies:\n(?:[ \t][^\n]*\n|\n)*",
                 snippet(example, "flutter-minimal-pubspec") + "\n", flags=re.M)
    shutil.copy2(FIXTURE / "pubspec.lock", out / "pubspec.lock")

    podfile = out / "ios/Podfile"
    podfile.write_text((templates / "Podfile-ios").read_text(encoding="utf-8"), encoding="utf-8")
    replace_once(podfile, r"\A# Uncomment this line to define a global platform for your project\n# platform :ios, '[\d.]+'\n",
                 snippet(setup, "flutter-podfile-ios"))
    replace_once(podfile, r"^post_install do \|installer\|\n.*\Z", snippet(setup, "flutter-podfile-ios-simulator-arch"))
    add_plist_keys(out / "ios/Runner/Info.plist", snippet(setup, "flutter-ios-info-plist"))
    for name in ("Release.entitlements", "DebugProfile.entitlements"):
        add_plist_keys(out / "macos/Runner" / name, snippet(setup, "flutter-macos-entitlements"))

    replace_once(out / "android/app/build.gradle.kts", r"^    defaultConfig \{\n.*?^    \}\n",
                 indent(snippet(setup, "flutter-android-gradle"), "    "))
    replace_once(out / "android/build.gradle.kts", r"^(?=subprojects \{\n    project\.evaluationDependsOn)",
                 snippet(setup, "flutter-android-compilesdk-override"))
    replace_once(out / "android/app/src/main/AndroidManifest.xml", r"(?<=<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\">\n)",
                 indent(snippet(setup, "flutter-android-manifest"), "    "))
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
