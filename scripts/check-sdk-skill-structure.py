#!/usr/bin/env python3
"""Structural checks for per-language SDK skills (docs/SDK-SKILL-TEMPLATE.md §12.1).

Usage: python3 scripts/check-sdk-skill-structure.py [skills/<lang>-sdk ...]
Defaults to every skills/*-sdk directory.
"""
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PERMITTED_FRONTMATTER_KEYS = {
    "name", "description", "license", "compatibility", "allowed-tools", "metadata",
}

# §5: the ten H2 headings, exact spelling and order.
REQUIRED_H2 = [
    "## What this skill does",
    "## When to use this skill",
    "## Supported versions and packages",
    "## Capability exceptions",
    "## Minimum viable app",
    "## Concurrency and threading model",
    "## Object lifetimes and retention",
    "## Anti-patterns",
    "## Version differences",
    "## References",
]

# §3: required files and the canonical reference layout.
REQUIRED_FILES = ["SKILL.md", "README.md", "best-practices.md",
                  os.path.join("examples", "minimal-app.md")]
REQUIRED_REFERENCES = [
    "setup.md", "connect.md", "transports.md", "sync.md", "store.md",
    "observers.md", "attachments.md", "presence.md", "observability.md",
    "errors.md", "testing.md", "versions.md", "preview.md",
]

# §5 capability map: twenty rows, verbatim titles, in order.
CAP_TITLES = [
    ("CAP-01", "Prerequisites, toolchain, package install"),
    ("CAP-02", "Platform permissions, entitlements, build config"),
    ("CAP-03", "Connecting: config, opening, persistence directory"),
    ("CAP-04", "Authentication and identity"),
    ("CAP-05", "Lifecycle: start/stop sync, shutdown, ownership"),
    ("CAP-06", "Customizing transports"),
    ("CAP-07", "Sync subscriptions and sync scopes"),
    ("CAP-08", "Querying the store: executing DQL"),
    ("CAP-09", "Transactions"),
    ("CAP-10", "Indexing"),
    ("CAP-11", "Observers, diffing and back-pressure"),
    ("CAP-12", "Attachments"),
    ("CAP-13", "Presence graph and connection requests"),
    ("CAP-14", "Sync status and local commit tracking"),
    ("CAP-15", "Logging, diagnostics and stats"),
    ("CAP-16", "Error handling"),
    ("CAP-17", "Device storage management and eviction"),
    ("CAP-18", "Testing"),
    ("CAP-19", "v4 to v5 migration, API and on-disk store"),
    ("CAP-20", "Preview and platform-specific APIs"),
]

SUPPORT_ENUM = {"yes", "partial", "preview", "no"}
EVIDENCE_ENUM = {"executed", "docs-sample", "api-dump", "source", "inference"}

# §11: budgets.
DESCRIPTION_HARD_LIMIT = 1024
SKILL_HARD_LIMIT = 400
REFERENCE_LIMIT = 400


def slugify(heading: str) -> str:
    """GitHub's anchor slug rules (lowercase, strip punctuation, spaces -> -)."""
    s = heading.strip().lower()
    s = re.sub(r"[^\w\s-]", "", s)
    return s.replace(" ", "-")


def parse_frontmatter(text: str):
    """Return dict of top-level frontmatter keys -> raw value strings."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    fm, i = {}, 1
    key = None
    while i < len(lines) and lines[i].strip() != "---":
        line = lines[i]
        m = re.match(r"^([a-zA-Z-]+):\s*(.*)$", line)
        if m:
            key = m.group(1)
            fm[key] = m.group(2)
        elif key and line.startswith(" ") and fm.get(key) == ">":
            fm[key] = " ".join(l.strip() for l in lines[i:]
                               if not l.strip() == "---")  # folded scalar
            # re-accumulate properly below
        i += 1
    # Fold multi-line `description: >` values properly.
    raw = "\n".join(lines[1:i])
    m = re.search(r"^description:\s*>\s*\n((?:[ \t]+.*\n?)+)", raw, re.M)
    if m:
        fm["description"] = " ".join(l.strip() for l in m.group(1).splitlines())
    return fm


def check_skill(skill_dir: str) -> list:
    errors = []
    rel = os.path.relpath(skill_dir, REPO)
    dirname = os.path.basename(skill_dir)

    def err(msg):
        errors.append(f"{rel}: {msg}")

    # --- §3 required files -------------------------------------------------
    for f in REQUIRED_FILES:
        if not os.path.isfile(os.path.join(skill_dir, f)):
            err(f"missing required file {f} (spec §3)")

    refs_dir = os.path.join(skill_dir, "references")
    if os.path.isdir(refs_dir):
        for root, dirs, _files in os.walk(refs_dir):
            if root != refs_dir and dirs:
                err("references/ must be exactly one level deep (spec §3)")
            if root != refs_dir:
                continue
        present = {f for f in os.listdir(refs_dir) if f.endswith(".md")}
        missing = set(REQUIRED_REFERENCES) - present
        if missing:
            err(f"references/ missing: {sorted(missing)} (spec §3)")
    else:
        err("missing references/ directory (spec §3)")

    skill_path = os.path.join(skill_dir, "SKILL.md")
    if not os.path.isfile(skill_path):
        return errors
    text = open(skill_path).read()
    lines = text.splitlines()

    # --- §12.1.1 name == directory -----------------------------------------
    fm = parse_frontmatter(text)
    if fm is None:
        err("SKILL.md missing YAML frontmatter")
        fm = {}
    else:
        if fm.get("name") != dirname:
            err(f"frontmatter name '{fm.get('name')}' != directory '{dirname}' (§12.1.1)")

        # --- §12.1.2 permitted keys -----------------------------------------
        extra = set(fm) - PERMITTED_FRONTMATTER_KEYS
        if extra:
            err(f"frontmatter has non-permitted keys: {sorted(extra)} (§12.1.2)")
        if "allowed-tools" not in fm:
            err("frontmatter missing allowed-tools (spec §4)")

        # --- §12.1.3 exclusion gate in description --------------------------
        desc = fm.get("description", "")
        if len(desc) > DESCRIPTION_HARD_LIMIT:
            err(f"description is {len(desc)} chars (> {DESCRIPTION_HARD_LIMIT}, §11)")
        if "Use ONLY for" not in desc:
            err("description lacks the 'Use ONLY for' exclusion gate (§12.1.3)")

    # --- §12.1.4 exact H2 headings ------------------------------------------
    h2s = [l.rstrip() for l in lines if re.match(r"^## ", l)]
    if h2s != REQUIRED_H2:
        err("H2 headings mismatch (§12.1.4).\n  expected: "
            + repr(REQUIRED_H2) + "\n  actual:   " + repr(h2s))

    # --- §12.1.10 SKILL.md hard limit ---------------------------------------
    if len(lines) > SKILL_HARD_LIMIT:
        err(f"SKILL.md is {len(lines)} lines (> {SKILL_HARD_LIMIT} hard limit, §12.1.10)")

    # --- §11 reference budgets ----------------------------------------------
    if os.path.isdir(refs_dir):
        for f in sorted(os.listdir(refs_dir)):
            p = os.path.join(refs_dir, f)
            if f.endswith(".md") and os.path.isfile(p):
                n = sum(1 for _ in open(p))
                if n > REFERENCE_LIMIT:
                    err(f"references/{f} is {n} lines (> {REFERENCE_LIMIT}, §11)")

    # --- §12.1.5/6/7 README capability map -----------------------------------
    readme_path = os.path.join(skill_dir, "README.md")
    if os.path.isfile(readme_path):
        check_readme(readme_path, err)
    return errors


def check_readme(readme_path: str, err):
    text = open(readme_path).read()
    lines = text.splitlines()

    # Targets vocabulary, declared once (spec §7).
    m = re.search(r"Targets vocabulary.*?:\s*`([^`]+)`", text)
    targets_enum = set()
    if m:
        targets_enum = {t.strip() for t in m.group(1).split("|")}

    rows = []
    for i, line in enumerate(lines, 1):
        if re.match(r"^\| CAP-\d\d ", line):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            rows.append((i, cells))

    ids = [c[1][0] for c in rows]
    expected_ids = [cid for cid, _ in CAP_TITLES]
    if ids != expected_ids:
        err(f"capability map rows != CAP-01..CAP-20 in order (§12.1.5): {ids}")
    for (lineno, cells), (cid, title) in zip(rows, CAP_TITLES):
        if len(cells) < 5:
            err(f"README:{lineno}: capability row has {len(cells)} cells, expected 5")
            continue
        if cells[1] != title:
            err(f"README:{lineno}: {cid} title '{cells[1]}' != spec title '{title}' (§12.1.5)")
        support, evidence, targets = cells[2].lower(), cells[3].lower(), cells[4]
        if support not in SUPPORT_ENUM:
            err(f"README:{lineno}: {cid} Support '{support}' not in enum (§12.1.6)")
        if evidence not in EVIDENCE_ENUM:
            err(f"README:{lineno}: {cid} Evidence '{evidence}' not in enum (§12.1.6)")
        if targets_enum and targets not in targets_enum:
            err(f"README:{lineno}: {cid} Targets '{targets}' not in declared "
                f"vocabulary {sorted(targets_enum)} (§12.1.6)")

    # --- §12.1.7 capability-map links resolve, including anchors ------------
    skill_dir = os.path.dirname(readme_path)
    for m2 in re.finditer(r"\]\((references/[^)]+)\)", text):
        link = m2.group(1)
        path_part, _, anchor = link.partition("#")
        target = os.path.normpath(os.path.join(skill_dir, path_part))
        if not os.path.isfile(target):
            err(f"README capability-map link does not resolve: {link} (§12.1.7)")
            continue
        if anchor:
            heads = [l for l in open(target).read().splitlines() if l.startswith("#")]
            slugs = {slugify(h.lstrip("#")) for h in heads}
            if slugify(anchor) not in slugs:
                err(f"README link anchor '#{anchor}' not found in {path_part} (§12.1.7)")

    # --- §12.1.9 no skills/ path citations -----------------------------------
    for i, line in enumerate(lines, 1):
        if "skills/" in line and "agent-skills" not in line:
            err(f"README:{i}: cites a skills/ path as a source ({line.strip()[:80]}) (§12.1.9)")


def main():
    roots = sys.argv[1:]
    if not roots:
        roots = [os.path.join(REPO, "skills", d)
                 for d in sorted(os.listdir(os.path.join(REPO, "skills")))
                 if d.endswith("-sdk")
                 and os.path.isfile(os.path.join(REPO, "skills", d, "SKILL.md"))]
    if not roots:
        print("No SDK skills found (skills/*-sdk); nothing to check.")
        return 0

    all_errors = []
    for r in roots:
        all_errors.extend(check_skill(r))

    if all_errors:
        for e in all_errors:
            print(f"ERROR: {e}")
        return 1
    print(f"SDK-skill structural checks passed for {len(roots)} skill(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
