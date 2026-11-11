#!/usr/bin/env python3
"""Copy tested code from tests/ into skill Markdown, so installed skills hold the code.

Installed skills (the release archive, `dittosh skills add`, plugin installs) contain
only skills/. Code that CI runs lives in tests/. This script copies marked code from
tests/ into the skill Markdown that documents it, so the code is local to the skill
and still the exact code CI runs.

In a source file under tests/, mark a region with a comment in the file's own syntax:

    // snippet:start kotlin-store-test
    ...code...
    // snippet:end kotlin-store-test

Markers must be comment lines (`//`, `#`, `<!--`, `/*` or `--`). The marker lines
themselves are not copied. A name may have several regions in one file; they are
joined in order with one blank line between them, or none when the next region
starts with a closing bracket. Each region's common leading indentation is removed.

In a Markdown file under skills/, place a block where the code belongs:

    <!-- snippet: kotlin-store-test -->
    <!-- /snippet -->

or copy a whole file (path from the repository root):

    <!-- snippet-file: tests/kotlin-sdk/minimal-app/build.gradle.kts -->
    <!-- /snippet -->

Everything between the opening and closing comments is generated: a note naming the
source, then a fenced code block. Edit the source, then run this script.

Run from the repository root:

    python3 scripts/sync-snippets.py           # rewrite stale blocks
    python3 scripts/sync-snippets.py --check   # CI: fail if any block is stale
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import textwrap
from pathlib import Path

SKILLS_DIR = "skills"
SOURCE_DIRS = ("tests",)
SKIP_DIRS = {"node_modules", "build", "dist", ".gradle", ".generated", ".build", "__pycache__", ".venv"}
SOURCE_SUFFIXES = {
    ".kt": "kotlin",
    ".kts": "kotlin",
    ".swift": "swift",
    ".ts": "ts",
    ".tsx": "tsx",
    ".js": "javascript",
    ".mjs": "javascript",
    ".cjs": "javascript",
    ".jsx": "jsx",
    ".py": "python",
    ".sh": "bash",
    ".xml": "xml",
    ".json": "json",
    ".properties": "properties",
    ".toml": "toml",
    ".yml": "yaml",
    ".yaml": "yaml",
    ".md": "markdown",
    ".dql": "sql",
}

NAME = r"[a-z0-9][a-z0-9-]*"
# A marker is a comment line: //, #, <!--, /* or -- (SQL/DQL), then the marker.
COMMENT = r"^\s*(?://|#|<!--|/\*|--)\s*"
START_RE = re.compile(rf"{COMMENT}snippet:start\s+({NAME})\b")
END_RE = re.compile(rf"{COMMENT}snippet:end\s+({NAME})\b")
BLOCK_RE = re.compile(
    rf"(?P<open><!-- snippet(?P<kind>-file)?: (?P<ref>[^\s>]+) -->\n)"
    r"(?P<body>.*?)"
    r"(?P<close><!-- /snippet -->)",
    re.S,
)
OPEN_RE = re.compile(r"<!-- snippet(-file)?: ")


class SnippetError(Exception):
    pass


def source_files(root: Path):
    for top in SOURCE_DIRS:
        base = root / top
        if not base.is_dir():
            continue
        for directory, dirs, files in os.walk(base):
            dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS and not d.startswith("."))
            for name in sorted(files):
                path = Path(directory) / name
                if path.suffix in SOURCE_SUFFIXES:
                    yield path


def collect_snippets(root: Path) -> dict[str, tuple[str, str, str]]:
    """Return snippet name -> (code, source path relative to root, fence language)."""
    found: dict[str, tuple[list[list[str]], Path]] = {}
    for path in source_files(root):
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except UnicodeDecodeError:
            continue
        rel = path.relative_to(root)
        current: str | None = None
        for number, line in enumerate(lines, 1):
            start, end = START_RE.search(line), END_RE.search(line)
            if start:
                if current:
                    raise SnippetError(f"{rel}:{number}: snippet:start {start.group(1)} inside open snippet {current}")
                current = start.group(1)
                if current in found and found[current][1] != rel:
                    raise SnippetError(
                        f"{rel}:{number}: snippet '{current}' is already defined in {found[current][1]}"
                    )
                found.setdefault(current, ([], rel))[0].append([])
            elif end:
                if current != end.group(1):
                    raise SnippetError(
                        f"{rel}:{number}: snippet:end {end.group(1)} does not match "
                        f"{'snippet:start ' + current if current else 'any open snippet'}"
                    )
                current = None
            elif current:
                found[current][0][-1].append(line)
        if current:
            raise SnippetError(f"{rel}: snippet '{current}' has no snippet:end")
    snippets = {}
    for name, (regions, rel) in found.items():
        code = ""
        for region in regions:
            part = textwrap.dedent("\n".join(region)).strip("\n")
            if code:
                code += "\n" if part.lstrip()[:1] in ")]}" else "\n\n"
            code += part
        code = code.strip("\n")
        if not code:
            raise SnippetError(f"{rel}: snippet '{name}' is empty")
        snippets[name] = (code, rel.as_posix(), SOURCE_SUFFIXES[rel.suffix])
    return snippets


def whole_file(root: Path, ref: str, where: str) -> tuple[str, str, str]:
    path = (root / ref).resolve()
    if not any(path.is_relative_to((root / top).resolve()) for top in SOURCE_DIRS):
        raise SnippetError(f"{where}: snippet-file {ref} must be under {', '.join(SOURCE_DIRS)}/")
    if not path.is_file():
        raise SnippetError(f"{where}: snippet-file {ref} does not exist")
    if path.suffix not in SOURCE_SUFFIXES:
        raise SnippetError(f"{where}: snippet-file {ref} has an unsupported type")
    return path.read_text(encoding="utf-8").strip("\n"), Path(ref).as_posix(), SOURCE_SUFFIXES[path.suffix]


def render(code: str, source: str, language: str) -> str:
    fence = "```"
    while fence in code:
        fence += "`"
    return (
        f"<!-- Generated from {source} by scripts/sync-snippets.py. "
        "Edit the source, not this block. -->\n"
        f"{fence}{language}\n{code}\n{fence}\n"
    )


def sync(root: Path, check: bool) -> tuple[list[str], set[str]]:
    """Rewrite (or check) every block. Returns (stale files, snippet names used)."""
    snippets = collect_snippets(root)
    stale: list[str] = []
    used: set[str] = set()
    for path in sorted((root / SKILLS_DIR).rglob("*.md")):
        if path.is_symlink():
            continue
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(root).as_posix()
        if len(OPEN_RE.findall(text)) != len(BLOCK_RE.findall(text)):
            raise SnippetError(f"{rel}: a snippet block has no matching <!-- /snippet -->")

        def replace(match: re.Match) -> str:
            ref = match.group("ref")
            if match.group("kind"):
                code, source, language = whole_file(root, ref, rel)
            else:
                if ref not in snippets:
                    raise SnippetError(f"{rel}: unknown snippet '{ref}' (no snippet:start {ref} under tests/)")
                used.add(ref)
                code, source, language = snippets[ref]
            return match.group("open") + render(code, source, language) + match.group("close")

        updated = BLOCK_RE.sub(replace, text)
        if updated != text:
            stale.append(rel)
            if not check:
                path.write_text(updated, encoding="utf-8")
    unused = sorted(set(snippets) - used)
    if unused:
        raise SnippetError(
            "snippets marked in tests/ but used by no skill: "
            + ", ".join(f"{n} ({snippets[n][1]})" for n in unused)
        )
    return stale, used


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="fail if any block differs from its source")
    args = parser.parse_args()
    root = Path.cwd()
    if not (root / SKILLS_DIR).is_dir():
        print("ERROR: run this from the repository root", file=sys.stderr)
        return 2
    try:
        stale, used = sync(root, args.check)
    except SnippetError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    if args.check and stale:
        for rel in stale:
            print(f"ERROR: {rel}: snippet blocks are out of date", file=sys.stderr)
        print("Run: python3 scripts/sync-snippets.py", file=sys.stderr)
        return 1
    verb = "checked" if args.check else ("updated " + ", ".join(stale) if stale else "up to date")
    print(f"Snippets {verb} ({len(used)} named snippet(s) in use)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
