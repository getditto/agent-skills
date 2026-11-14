#!/usr/bin/env python3
"""Fail when a published C# block in the skill drifts from the code that is compiled and run.

Every ```csharp (or ```cs) block in skills/csharp-sdk/**/*.md, except the minimal app
(which verify-minimal.py and validate-sdk-skills.py byte-compare), must be preceded by
one marker line:

  <!-- snippet: NAME -->   the region "// <snippet name="NAME">" ... "// </snippet>" in
                           tests/csharp-sdk/Core/ReferenceSnippetTests.cs (executed tests)
  <!-- source: PATH -->    contiguous lines of PATH, relative to skills/csharp-sdk
                           (a starter source file the generator builds)

Indentation is normalized; everything else must match exactly. A region that no
published block uses is also an error, so dead examples cannot accumulate.

--write replaces each <!-- snippet: --> block with its current region (after you edit
the tested code), then checks as usual. <!-- source: --> blocks are never rewritten.
"""
import re
import sys
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SKILL = ROOT / "skills/csharp-sdk"
SNIPPETS = ROOT / "tests/csharp-sdk/Core/ReferenceSnippetTests.cs"
EXCLUDED = {SKILL / "examples/minimal-app.md"}
FENCE = re.compile(r"^```(csharp|cs)\s*$")
MARKER = re.compile(r"^<!--\s*(snippet|source):\s*(\S+)\s*-->$")
START = re.compile(r'^\s*// <snippet name="([a-z0-9-]+)">\s*$')
END = re.compile(r"^\s*// </snippet>\s*$")


def normalize(lines):
    return textwrap.dedent("\n".join(line.rstrip() for line in lines)).strip("\n")


def regions():
    found, name, body = {}, None, []
    for number, line in enumerate(SNIPPETS.read_text().splitlines(), 1):
        start, end = START.match(line), END.match(line)
        if start:
            if name: raise SystemExit(f"{SNIPPETS.name}:{number}: nested snippet {start.group(1)}")
            name, body = start.group(1), []
        elif end:
            if not name: raise SystemExit(f"{SNIPPETS.name}:{number}: snippet end without start")
            if name in found: raise SystemExit(f"{SNIPPETS.name}: duplicate snippet {name}")
            found[name], name = normalize(body), None
        elif name:
            body.append(line)
    if name: raise SystemExit(f"{SNIPPETS.name}: snippet {name} is not closed")
    return found


def blocks(path):
    lines = path.read_text().splitlines()
    index = 0
    while index < len(lines):
        if FENCE.match(lines[index]):
            close = next((j for j in range(index + 1, len(lines)) if lines[j].strip() == "```"), None)
            if close is None: raise SystemExit(f"{path}:{index + 1}: unclosed code fence")
            previous = next((lines[j].strip() for j in range(index - 1, -1, -1) if lines[j].strip()), "")
            yield index + 1, MARKER.match(previous), normalize(lines[index + 1:close])
            index = close
        index += 1


def contains(path, block):
    lines = path.read_text().splitlines()
    size = len(block.splitlines())
    return any(normalize(lines[i:i + size]) == block for i in range(len(lines) - size + 1))


def write(available):
    for path in sorted(SKILL.rglob("*.md")):
        if path in EXCLUDED: continue
        lines, out, index, changed = path.read_text().splitlines(), [], 0, False
        while index < len(lines):
            out.append(lines[index])
            marker = MARKER.match(lines[index].strip())
            if marker and marker.group(1) == "snippet" and index + 1 < len(lines) and FENCE.match(lines[index + 1]):
                close = next(j for j in range(index + 2, len(lines)) if lines[j].strip() == "```")
                name = marker.group(2)
                if name in available:
                    out.append(lines[index + 1])
                    out.extend(available[name].splitlines())
                    out.append("```")
                    changed = changed or lines[index + 2:close] != available[name].splitlines()
                    index = close + 1
                    continue
            index += 1
        if changed:
            path.write_text("\n".join(out) + "\n")
            print("updated " + str(path.relative_to(ROOT)))


def main():
    available, used, errors = regions(), set(), []
    if "--write" in sys.argv[1:]:
        write(available)
    for path in sorted(SKILL.rglob("*.md")):
        if path in EXCLUDED: continue
        relative = path.relative_to(ROOT)
        for line, marker, block in blocks(path):
            if not marker:
                errors.append(f"{relative}:{line}: C# block has no <!-- snippet: --> or <!-- source: --> marker")
            elif marker.group(1) == "snippet":
                name = marker.group(2)
                used.add(name)
                if name not in available:
                    errors.append(f"{relative}:{line}: unknown snippet {name}")
                elif available[name] != block:
                    errors.append(f"{relative}:{line}: block differs from snippet {name}")
            else:
                source = (SKILL / marker.group(2)).resolve()
                if not source.is_relative_to(SKILL.resolve()) or not source.is_file():
                    errors.append(f"{relative}:{line}: source {marker.group(2)} is not a file in the skill")
                elif not contains(source, block):
                    errors.append(f"{relative}:{line}: block is not a contiguous excerpt of {marker.group(2)}")
    for name in sorted(set(available) - used):
        errors.append(f"{SNIPPETS.relative_to(ROOT)}: snippet {name} is not used by any published block")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"C# reference snippets match their executed sources ({len(used)} snippets).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
