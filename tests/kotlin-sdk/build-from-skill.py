#!/usr/bin/env python3
"""Assemble the Kotlin reference projects from the skill's Markdown, for CI to build.

The skill ships generated copies of marked regions of this harness (see
scripts/sync-snippets.py). A region set can be identical to its source and still not
build on its own, for example if a marked block uses a value defined outside the
markers. This script writes projects using only the code an agent gets from
skills/kotlin-sdk, so CI can compile them.

    python3 tests/kotlin-sdk/build-from-skill.py jvm <out-dir>
    python3 tests/kotlin-sdk/build-from-skill.py android <out-dir>

Only the Gradle wrapper and, for Android, the activity (not part of the skill's
build files) come from this harness.
"""

import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SKILL = ROOT / "skills/kotlin-sdk"
HARNESS = ROOT / "tests/kotlin-sdk"


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


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def wrapper(source: Path, out: Path) -> None:
    shutil.copy2(source / "gradlew", out / "gradlew")
    shutil.copytree(source / "gradle", out / "gradle")


def jvm(out: Path) -> None:
    projects = SKILL / "references/reference-projects.md"
    write(out / "settings.gradle.kts", snippet(projects, "kotlin-jvm-settings"))
    write(out / "build.gradle.kts", snippet(projects, "kotlin-jvm-build"))
    write(out / "src/main/kotlin/MainV5.kt", snippet(SKILL / "examples/minimal-app.md", "kotlin-minimal-app"))
    write(
        out / "src/test/kotlin/DittoStoreTest.kt",
        snippet(SKILL / "references/testing.md", "kotlin-store-test"),
    )
    wrapper(HARNESS / "minimal-app", out)


def android(out: Path, line: str) -> None:
    projects = SKILL / "references/reference-projects.md"
    write(out / "settings.gradle.kts", snippet(projects, "kotlin-android-settings"))
    write(out / "gradle.properties", snippet(projects, "kotlin-android-gradle-properties"))
    write(out / "build.gradle.kts", snippet(projects, "kotlin-android-build"))
    write(out / "src/main/AndroidManifest.xml", snippet(projects, "kotlin-android-manifest"))
    activity = HARNESS / f"android-app/src/{line}/kotlin"
    shutil.copytree(activity, out / "src/main/kotlin")
    wrapper(HARNESS / "android-app", out)


def main() -> None:
    if len(sys.argv) not in (3, 4) or sys.argv[1] not in ("jvm", "android"):
        sys.exit(__doc__)
    out = Path(sys.argv[2]).resolve()
    if out.exists():
        sys.exit(f"{out} already exists")
    out.mkdir(parents=True)
    if sys.argv[1] == "jvm":
        jvm(out)
    else:
        android(out, sys.argv[3] if len(sys.argv) == 4 else "v5")
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
