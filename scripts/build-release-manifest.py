#!/usr/bin/env python3
"""Build skills-manifest.json for release packaging.

Walks skills/<name>/SKILL.md, pulls name + description from the YAML frontmatter
(tolerant, stdlib-only — no PyYAML dependency), and writes a manifest that the
dittosh CLI and docs tooling can consume without downloading the archive.

Usage: build-release-manifest.py [output-path]   (default: ./skills-manifest.json)
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKILLS = ROOT / "skills"

FOLD_MARKERS = (">", "|", ">-", "|-", ">+", "|+")


def frontmatter(text):
    """Return the SKILL.md YAML frontmatter as a flat dict of strings.

    Handles single-line values and folded/literal multi-line scalars (``>``, ``|``)
    by joining indented continuation lines. Nested structure is ignored — skills
    only need ``name`` and ``description``.
    """
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    if end == -1:
        return {}
    data = {}
    key = None
    for line in text[3:end].splitlines():
        m = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", line)
        if m and not line.startswith((" ", "\t")):
            key = m.group(1)
            value = m.group(2).strip()
            data[key] = "" if value in FOLD_MARKERS else value
        elif key and line.strip():
            data[key] = (data[key] + " " + line.strip()).strip()
    return data


def main():
    out_path = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "skills-manifest.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)

    skills = []
    for skill_md in sorted(SKILLS.glob("*/SKILL.md")):
        fm = frontmatter(skill_md.read_text(encoding="utf-8"))
        dir_name = skill_md.parent.name
        name = fm.get("name") or dir_name
        if name != dir_name:
            print(
                f"warning: {skill_md}: frontmatter name {name!r} != directory {dir_name!r}",
                file=sys.stderr,
            )
        skills.append(
            {
                "name": name,
                "path": f"skills/{dir_name}",
                "description": " ".join((fm.get("description") or "").split()),
            }
        )

    if not skills:
        sys.exit("no skills found under skills/*/SKILL.md")

    out_path.write_text(json.dumps({"skills": skills}, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {out_path} with {len(skills)} skills")


if __name__ == "__main__":
    main()
