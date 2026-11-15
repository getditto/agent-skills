#!/usr/bin/env python3
"""Fail when a C# block in the skill is not code that is compiled and run.

scripts/sync-snippets.py generates the blocks between `<!-- snippet: NAME -->` and
`<!-- /snippet -->` from regions marked in tests/ (`// snippet:start NAME` ...
`// snippet:end NAME`), and its --check fails on drift. This script adds the C#-specific
coverage rules that it does not enforce:

- Every ```csharp (or ```cs) fence in skills/csharp-sdk/**/*.md is either inside a
  generated snippet block, or directly preceded by `<!-- source: PATH -->` and is a
  contiguous excerpt of PATH (relative to skills/csharp-sdk; starter code the generator
  builds).
- Every `csharp-*` region in tests/csharp-sdk/Core/ReferenceSnippetTests.cs is used by
  some skill block, so dead examples cannot accumulate.
"""
import re
import sys
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SKILL = ROOT / "skills/csharp-sdk"
SNIPPETS = ROOT / "tests/csharp-sdk/Core/ReferenceSnippetTests.cs"
FENCE = re.compile(r"^```(csharp|cs)\s*$")
OPEN = re.compile(r"^<!-- snippet: ([a-z0-9-]+) -->$")
CLOSE = "<!-- /snippet -->"
SOURCE = re.compile(r"^<!--\s*source:\s*(\S+)\s*-->$")
REGION = re.compile(r"^\s*// snippet:start (csharp-[a-z0-9-]+)\s*$")


def normalize(lines):
    return textwrap.dedent("\n".join(line.rstrip() for line in lines)).strip("\n")


def contains(path, block):
    lines = path.read_text(encoding="utf-8").splitlines()
    size = len(block.splitlines())
    return any(normalize(lines[i:i + size]) == block for i in range(len(lines) - size + 1))


def main():
    errors, used = [], set()
    for path in sorted(SKILL.rglob("*.md")):
        relative = path.relative_to(ROOT).as_posix()
        lines = path.read_text(encoding="utf-8").splitlines()
        inside = None
        index = 0
        while index < len(lines):
            line = lines[index].strip()
            opened = OPEN.match(line)
            if opened:
                inside = opened.group(1)
                used.add(inside)
            elif line == CLOSE:
                inside = None
            elif FENCE.match(line):
                close = next((j for j in range(index + 1, len(lines)) if lines[j].strip() == "```"), None)
                if close is None:
                    errors.append(f"{relative}:{index + 1}: unclosed code fence")
                    break
                if inside is None:
                    previous = next((lines[j].strip() for j in range(index - 1, -1, -1) if lines[j].strip()), "")
                    source = SOURCE.match(previous)
                    if not source:
                        errors.append(f"{relative}:{index + 1}: C# block is neither generated "
                                      "(<!-- snippet: -->) nor a <!-- source: --> excerpt")
                    else:
                        target = (SKILL / source.group(1)).resolve()
                        block = normalize(lines[index + 1:close])
                        if not target.is_relative_to(SKILL.resolve()) or not target.is_file():
                            errors.append(f"{relative}:{index + 1}: source {source.group(1)} is not a file in the skill")
                        elif not contains(target, block):
                            errors.append(f"{relative}:{index + 1}: block is not a contiguous excerpt of {source.group(1)}")
                index = close
            index += 1
    regions = {m.group(1) for line in SNIPPETS.read_text(encoding="utf-8").splitlines() if (m := REGION.match(line))}
    for name in sorted(regions - used):
        errors.append(f"{SNIPPETS.relative_to(ROOT).as_posix()}: region {name} is not used by any skill block")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"C# blocks are generated from tested code or excerpt the starters ({len(regions)} tested regions in use).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
