#!/usr/bin/env python3
"""Copy tested code from tests/ into skill Markdown, so installed skills hold the code.

Installed skills (the release archive, `dittosh skills add`, plugin installs) contain
only skills/. Code that CI runs lives in tests/. This script copies marked code from
tests/ into the skill Markdown that documents it, so the code is local to the skill
and is the exact code CI runs. The generated Markdown is committed; CI and the
Release workflow run this script with --check.

In a source file under tests/, mark a region with comment lines in the file's own
syntax (`//`, `#`, `<!--`, `/*` or `--`):

    // snippet:start kotlin-store-test
    ...code...
    // snippet:end kotlin-store-test

Marker lines are not copied. To copy a whole file, put the start marker after any
header comment and the end marker on the last line. A name may have several regions
in one file. They are joined in order with a blank line between them, or with no
blank line when the next region continues the code (it starts with `)`, `]`, `}`,
`?:` or `.`). The joined code's common leading indentation is removed.

In a Markdown file under skills/, place a block where the code belongs:

    <!-- snippet: kotlin-store-test -->
    <!-- /snippet -->

Everything between the two comments is generated. Blocks inside fenced code are left
alone, so documentation can show the syntax. Edit the source, then run this script.

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
    ".dql": "sql",
}

NAME = r"[a-z0-9][a-z0-9-]*"
COMMENT = r"^\s*(?://|#|<!--|/\*|--)\s*"
# Any comment line that mentions a marker; checked strictly so a typo fails.
MARKER_LINE_RE = re.compile(rf"{COMMENT}snippet:(start|end)\b(.*)$")
MARKER_BYTES_RE = re.compile(rb"(?m)^\s*(?://|#|<!--|/\*|--)\s*snippet:(start|end)")
STRICT_ARG_RE = re.compile(rf"^\s+({NAME})\s*(?:-->|\*/)?\s*$")
OPEN_RE = re.compile(r"<!-- */?snippet\b")
FENCE_RE = re.compile(r"^\s{0,3}(`{3,}|~{3,})")
CONTINUES = (")", "]", "}", "?:", ".")


class SnippetError(Exception):
    pass


def candidate_files(root: Path):
    for top in SOURCE_DIRS:
        base = root / top
        if not base.is_dir():
            continue
        for directory, dirs, files in os.walk(base):
            dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS and not d.startswith("."))
            for name in sorted(files):
                yield Path(directory) / name


def collect_snippets(root: Path) -> dict[str, tuple[str, str, str]]:
    """Return snippet name -> (code, source path relative to root, fence language)."""
    found: dict[str, tuple[list[list[str]], Path]] = {}
    for path in candidate_files(root):
        raw = path.read_bytes()
        if not MARKER_BYTES_RE.search(raw):
            continue
        rel = path.relative_to(root)
        if path.suffix not in SOURCE_SUFFIXES:
            raise SnippetError(
                f"{rel}: has snippet markers but its type ({path.suffix or 'no suffix'}) is not "
                "supported; add it to SOURCE_SUFFIXES in scripts/sync-snippets.py"
            )
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            raise SnippetError(f"{rel}: has snippet markers but is not UTF-8") from None
        current: str | None = None
        for number, line in enumerate(text.splitlines(), 1):
            marker = MARKER_LINE_RE.match(line)
            if not marker:
                if current and ("snippet:start" in line or "snippet:end" in line):
                    raise SnippetError(f"{rel}:{number}: malformed snippet marker inside snippet '{current}'")
                if current:
                    found[current][0][-1].append(line)
                continue
            kind, rest = marker.groups()
            arg = STRICT_ARG_RE.match(rest)
            if not arg:
                raise SnippetError(
                    f"{rel}:{number}: malformed snippet marker; names use lowercase letters, digits and -"
                )
            name = arg.group(1)
            if kind == "start":
                if current:
                    raise SnippetError(f"{rel}:{number}: snippet:start {name} inside open snippet {current}")
                if name in found and found[name][1] != rel:
                    raise SnippetError(f"{rel}:{number}: snippet '{name}' is already defined in {found[name][1]}")
                current = name
                found.setdefault(name, ([], rel))[0].append([])
            else:
                if current != name:
                    raise SnippetError(
                        f"{rel}:{number}: snippet:end {name} does not match "
                        f"{'snippet:start ' + current if current else 'any open snippet'}"
                    )
                current = None
        if current:
            raise SnippetError(f"{rel}: snippet '{current}' has no snippet:end")

    snippets = {}
    for name, (regions, rel) in found.items():
        code = ""
        for region in regions:
            part = "\n".join(region).strip("\n")
            if not part.strip():
                continue
            if code:
                code += "\n" if part.lstrip().startswith(CONTINUES) else "\n\n"
            code += part
        code = textwrap.dedent(code).strip("\n")
        if not code:
            raise SnippetError(f"{rel}: snippet '{name}' is empty")
        snippets[name] = (code, rel.as_posix(), SOURCE_SUFFIXES[rel.suffix])
    return snippets


def render(code: str, language: str) -> str:
    fence = "```"
    while fence in code:
        fence += "`"
    return (
        "<!-- Generated by scripts/sync-snippets.py from code CI runs. "
        "Edit the marked source, not this block. -->\n"
        f"{fence}{language}\n{code}\n{fence}\n"
    )


OPEN_LINE_RE = re.compile(rf"^<!-- snippet: ({NAME}) -->$")
CLOSE_LINE = "<!-- /snippet -->"


def find_blocks(text: str, where: str) -> list[tuple[int, int, str]]:
    """(start, end, name) of each block outside fenced code. `end` is after the close line.

    Fences are tracked only outside blocks: a block's generated body is itself a fence.
    """
    blocks: list[tuple[int, int, str]] = []
    offset = 0
    fence: str | None = None
    block: tuple[int, str] | None = None
    for number, line in enumerate(text.splitlines(keepends=True), 1):
        bare = line.rstrip("\n")
        if block:
            if bare == CLOSE_LINE:
                blocks.append((block[0], offset + len(line), block[1]))
                block = None
            elif OPEN_LINE_RE.match(bare):
                raise SnippetError(f"{where}:{number}: snippet block opened inside another block")
        elif fence:
            match = FENCE_RE.match(line)
            if match and match.group(1)[0] == fence[0] and len(match.group(1)) >= len(fence) \
                    and not line.strip()[len(match.group(1)):].strip():
                fence = None
        else:
            match = FENCE_RE.match(line)
            opened = OPEN_LINE_RE.match(bare)
            if match:
                fence = match.group(1)
            elif opened:
                block = (offset, opened.group(1))
            elif OPEN_RE.search(bare):
                raise SnippetError(f"{where}:{number}: malformed snippet comment: {bare.strip()}")
        offset += len(line)
    if block:
        raise SnippetError(f"{where}: snippet '{block[1]}' has no {CLOSE_LINE}")
    return blocks


def skill_names(root: Path) -> set[str]:
    base = root / SKILLS_DIR
    return {p.name for p in base.iterdir() if (p / "SKILL.md").is_file()} if base.is_dir() else set()


def sync(root: Path, check: bool) -> tuple[list[str], set[str]]:
    """Rewrite (or check) every block. Returns (stale files, snippet names used)."""
    snippets = collect_snippets(root)
    skills = skill_names(root)
    stale: list[str] = []
    used: set[str] = set()
    for path in sorted((root / SKILLS_DIR).rglob("*.md")):
        if path.is_symlink():
            continue
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(root).as_posix()

        def replace(name: str) -> str:
            if name not in snippets:
                raise SnippetError(f"{rel}: unknown snippet '{name}' (no snippet:start {name} under tests/)")
            code, source, language = snippets[name]
            # Installers such as dittosh treat `../<skill>/` in a skill's files as a link
            # to that skill and install it too.
            for other in re.findall(r"\.\./([a-z0-9][a-z0-9-]*)/", code):
                if other in skills:
                    raise SnippetError(
                        f"{source}: snippet '{name}' contains `../{other}/`, which installers "
                        "read as a link to that skill"
                    )
            used.add(name)
            return render(code, language)

        pieces: list[str] = []
        cursor = 0
        for begin, end, name in find_blocks(text, rel):
            pieces.append(text[cursor:begin])
            pieces.append(f"<!-- snippet: {name} -->\n" + replace(name) + CLOSE_LINE + "\n")
            cursor = end
        pieces.append(text[cursor:])
        updated = "".join(pieces)
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
