#!/usr/bin/env python3
"""Structural validation for per-language SDK skills (skills/<lang>-sdk/).

Implements the mechanical half of docs/SDK-SKILL-TEMPLATE.md §12.1 so that nine
near-identical skills cannot drift. Everything here is checkable without judgement;
the judgement items in §14 stay with the reviewer.

Also enforces the two repo-wide skill rules from §12.1 items 1-2 against *every*
skill, not only SDK skills.

Run from the repository root:

    python3 scripts/validate-sdk-skills.py
"""

from __future__ import annotations

import os
import re
import sys

SKILLS_DIR = "skills"
SPEC = "docs/SDK-SKILL-TEMPLATE.md"

# §4 — the only keys CONTRIBUTING.md permits in skill frontmatter.
PERMITTED_FRONTMATTER_KEYS = {
    "name",
    "description",
    "license",
    "compatibility",
    "allowed-tools",
    "metadata",
}

# Frontmatter `name` values that predate the directory-name rule. Adding to this
# list is a deliberate act; new skills must match their directory.
GRANDFATHERED_NAMES = {
    "dql": "write-dql",
}

# §5 — exactly these H2 headings, in this order, spelled exactly this way.
REQUIRED_SKILL_HEADINGS = [
    "What this skill does",
    "When to use this skill",
    "Supported versions and packages",
    "Capability exceptions",
    "Minimum viable app",
    "Concurrency and threading model",
    "Object lifetimes and retention",
    "Anti-patterns",
    "Version differences",
    "References",
]

# §6 — verbatim capability titles. Do not renumber, rename, reorder or reword.
CAPABILITIES = [
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

SUPPORT_VALUES = {"yes", "partial", "preview", "no"}
EVIDENCE_VALUES = {"executed", "docs-sample", "api-dump", "source", "inference"}

# §3 — required files.
REQUIRED_FILES = [
    "SKILL.md",
    "README.md",
    "best-practices.md",
    "examples/minimal-app.md",
    "references/setup.md",
    "references/connect.md",
    "references/transports.md",
    "references/sync.md",
    "references/store.md",
    "references/observers.md",
    "references/attachments.md",
    "references/presence.md",
    "references/observability.md",
    "references/errors.md",
    "references/testing.md",
    "references/versions.md",
    "references/preview.md",
]

SKILL_BODY_HARD_LIMIT = 400  # §11
REFERENCE_HARD_LIMIT = 400  # §3 / §11 — split instead of exceeding

errors: list[str] = []
warnings: list[str] = []


def fail(message: str) -> None:
    errors.append(message)


def warn(message: str) -> None:
    warnings.append(message)


def read(path: str) -> str:
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def split_frontmatter(text: str, path: str) -> tuple[dict[str, str], str]:
    """Return (frontmatter keys, body). Only top-level keys are parsed; values may
    be YAML block scalars, which this deliberately does not interpret."""
    if not text.startswith("---\n"):
        fail(f"{path}: does not start with YAML frontmatter")
        return {}, text
    end = text.find("\n---\n", 3)
    if end == -1:
        fail(f"{path}: frontmatter is not terminated by a closing ---")
        return {}, text
    block = text[4:end]
    body = text[end + 5 :]

    keys: dict[str, str] = {}
    for line in block.split("\n"):
        if not line or line.startswith((" ", "\t", "#")):
            continue
        match = re.match(r"^([A-Za-z][A-Za-z0-9_-]*):\s*(.*)$", line)
        if match:
            keys[match.group(1)] = match.group(2).strip()
    return keys, body


def heading_anchor(heading: str) -> str:
    """GitHub's slug rules, for the subset of characters headings here use."""
    slug = heading.strip().lower()
    slug = re.sub(r"[^\w\s-]", "", slug)
    slug = re.sub(r"\s+", "-", slug)
    return slug


def collect_anchors(text: str) -> set[str]:
    anchors: set[str] = set()
    for line in text.split("\n"):
        match = re.match(r"^(#{1,6})\s+(.*?)\s*$", line)
        if match:
            anchors.add(heading_anchor(match.group(2)))
    return anchors


LINK_RE = re.compile(r"\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")


def check_links(skill_dir: str, relative_path: str) -> None:
    path = os.path.join(skill_dir, relative_path)
    text = read(path)
    base = os.path.dirname(path)
    for target in LINK_RE.findall(text):
        if target.startswith(("http://", "https://", "mailto:")):
            continue
        if target.startswith("#"):
            anchor = target[1:]
            if anchor not in collect_anchors(text):
                fail(f"{path}: link '#{anchor}' does not match any heading in this file")
            continue
        file_part, _, anchor = target.partition("#")
        resolved = os.path.normpath(os.path.join(base, file_part))
        if not os.path.exists(resolved):
            fail(f"{path}: link target does not exist: {target}")
            continue
        if anchor and resolved.endswith(".md"):
            if anchor not in collect_anchors(read(resolved)):
                fail(f"{path}: anchor '#{anchor}' not found in {file_part}")


# §12.1 item 9 says "grep for `skills/` or `../..` in a citation". Markdown links are
# navigation and are allowed; everything else that names a path inside this repository is
# a citation, whether or not it is in backticks.
CITATION_RE = re.compile(r"(?<![\w/(])(skills/[\w./-]+|\.\./\.\.(?:/[\w./-]+)?)")
MARKDOWN_LINK_TARGET_RE = re.compile(r"\]\([^)]*\)")


def check_no_self_citation(skill_dir: str, relative_path: str) -> None:
    """§12.1 item 9 — no file in this repository may be cited as a source.

    Markdown links into the repo are navigation, not evidence, and are allowed.
    A backticked path is how CONTRIBUTING.md §4 formats a citation, so those are
    what this checks.
    """
    path = os.path.join(skill_dir, relative_path)
    for line_number, line in enumerate(read(path).split("\n"), 1):
        # Strip markdown link targets before looking for citations.
        line = MARKDOWN_LINK_TARGET_RE.sub("](…)", line)
        for match in CITATION_RE.findall(line):
            fail(
                f"{path}:{line_number}: cites a path inside this repository as a "
                f"source: `{match}`. Cite the SDK or the documentation instead."
            )


def all_markdown(skill_dir: str) -> list[str]:
    found: list[str] = []
    for root, dirs, files in os.walk(skill_dir):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        found.extend(os.path.join(root, f) for f in files if f.endswith(".md"))
    return found


def validate_every_skill() -> None:
    """§12.1 items 1-2, applied to every skill in the repository."""
    for name in sorted(os.listdir(SKILLS_DIR)):
        skill_dir = os.path.join(SKILLS_DIR, name)
        skill_md = os.path.join(skill_dir, "SKILL.md")
        if not os.path.isfile(skill_md):
            continue

        keys, _ = split_frontmatter(read(skill_md), skill_md)

        declared = keys.get("name")
        expected = GRANDFATHERED_NAMES.get(name, name)
        if declared != expected:
            fail(
                f"{skill_md}: frontmatter name '{declared}' does not match the "
                f"directory name '{name}'"
            )

        unknown = set(keys) - PERMITTED_FRONTMATTER_KEYS
        if unknown:
            fail(
                f"{skill_md}: frontmatter has keys CONTRIBUTING.md does not permit: "
                f"{', '.join(sorted(unknown))}"
            )

        if "description" not in keys:
            fail(f"{skill_md}: frontmatter is missing 'description'")


def validate_sdk_skill(name: str) -> None:
    skill_dir = os.path.join(SKILLS_DIR, name)

    # §3 — required files.
    for relative in REQUIRED_FILES:
        if not os.path.isfile(os.path.join(skill_dir, relative)):
            fail(f"{skill_dir}/{relative}: required by {SPEC} §3 but missing")

    # §3 — references/ is exactly one level deep.
    references = os.path.join(skill_dir, "references")
    if os.path.isdir(references):
        for entry in sorted(os.listdir(references)):
            if entry.startswith("."):
                continue
            if os.path.isdir(os.path.join(references, entry)):
                fail(f"{references}/{entry}: references/ must be exactly one level deep")

    skill_md = os.path.join(skill_dir, "SKILL.md")
    if not os.path.isfile(skill_md):
        return
    keys, body = split_frontmatter(read(skill_md), skill_md)

    # §4 — allowed-tools present, exclusion gate present, description length.
    if "allowed-tools" not in keys:
        fail(f"{skill_md}: frontmatter is missing 'allowed-tools' ({SPEC} §4)")

    description = re.search(
        r"^description:\s*(.*?)(?=^[A-Za-z][A-Za-z0-9_-]*:|\Z)",
        read(skill_md).split("\n---\n", 1)[0],
        re.S | re.M,
    )
    description_text = " ".join((description.group(1) if description else "").split())
    if "Use ONLY for" not in description_text:
        fail(f"{skill_md}: description must lead with the 'Use ONLY for' exclusion gate")
    if len(description_text) > 1024:
        fail(f"{skill_md}: description is {len(description_text)} characters (limit 1024)")

    # §5 — the ten H2 headings, in order, spelled exactly.
    found = [line[3:].strip() for line in body.split("\n") if line.startswith("## ")]
    if found != REQUIRED_SKILL_HEADINGS:
        fail(
            f"{skill_md}: H2 headings do not match {SPEC} §5.\n"
            f"    expected: {REQUIRED_SKILL_HEADINGS}\n"
            f"    found:    {found}"
        )

    # §11 — SKILL.md body size.
    body_lines = len(body.strip("\n").split("\n"))
    if body_lines > SKILL_BODY_HARD_LIMIT:
        fail(
            f"{skill_md}: body is {body_lines} lines, over the {SKILL_BODY_HARD_LIMIT}-line "
            f"hard limit in {SPEC} §11"
        )
    elif body_lines > 300:
        warn(f"{skill_md}: body is {body_lines} lines; {SPEC} §11 targets 300")

    # §11 — reference size.
    if os.path.isdir(references):
        for entry in sorted(os.listdir(references)):
            if not entry.endswith(".md"):
                continue
            path = os.path.join(references, entry)
            line_count = len(read(path).rstrip("\n").split("\n"))
            if line_count > REFERENCE_HARD_LIMIT:
                fail(
                    f"{path}: {line_count} lines, over the {REFERENCE_HARD_LIMIT}-line "
                    f"limit in {SPEC} §3 — split it instead"
                )

    # §6/§7 — the capability map in README.md.
    readme = os.path.join(skill_dir, "README.md")
    exceptions_in_map: set[str] = set()
    if os.path.isfile(readme):
        exceptions_in_map = validate_capability_map(readme)

    # §5 — SKILL.md §4 lists exactly the non-`yes` rows.
    exceptions_section = extract_section(body, "Capability exceptions")
    listed = set(re.findall(r"\|\s*(CAP-\d\d)\s*\|", exceptions_section))
    if listed != exceptions_in_map:
        fail(
            f"{skill_md}: 'Capability exceptions' lists {sorted(listed) or 'nothing'} but "
            f"README.md's map has non-yes Support for {sorted(exceptions_in_map) or 'nothing'}"
        )

    # §12.1 items 7 and 9 — over EVERY markdown file in the skill. §3 permits extra
    # references/ and examples/ files, and an unchecked extra file is exactly where a
    # broken link or a self-citation hides.
    for path in sorted(all_markdown(skill_dir)):
        relative = os.path.relpath(path, skill_dir)
        check_links(skill_dir, relative)
        check_no_self_citation(skill_dir, relative)


def extract_section(body: str, heading: str) -> str:
    lines = body.split("\n")
    try:
        start = lines.index(f"## {heading}")
    except ValueError:
        return ""
    for index in range(start + 1, len(lines)):
        if lines[index].startswith("## "):
            return "\n".join(lines[start:index])
    return "\n".join(lines[start:])


ROW_RE = re.compile(r"^\|\s*(CAP-\d\d)\s*\|(.*)$")
TARGETS_VOCAB_RE = re.compile(r"\*\*Targets vocabulary for this SDK:\*\*\s*(.+)")
# §7: api-dump / source / inference evidence "each require the path and ref inline".
EVIDENCE_NEEDS_CITATION = {"api-dump", "source", "inference"}
CITATION_TOKEN_RE = re.compile(r"[\w./-]+\.(swift|kt|kts|java|ts|js|cs|cpp|h|rs|dart|go|mdx|md|api)\b|sdk-release-[\w.-]+")


def validate_capability_map(readme: str) -> set[str]:
    """Check the twenty rows and their enum values; return the non-`yes` CAP IDs."""
    rows: list[tuple[str, list[str]]] = []
    for line in read(readme).split("\n"):
        match = ROW_RE.match(line.strip())
        if not match:
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) != 5:
            continue  # a prose table that happens to start with a CAP id
        rows.append((cells[0], cells))

    text = read(readme)

    # The Targets vocabulary is declared once, in README.md, and every row must use it.
    vocabulary: set[str] = set()
    match = TARGETS_VOCAB_RE.search(text)
    if match:
        vocabulary = {
            token.strip().strip("`")
            for token in re.split(r"[|,]", match.group(1).split(".")[0])
            if token.strip().strip("`") and " " not in token.strip().strip("`")
        }
    if not vocabulary:
        fail(f"{readme}: no '**Targets vocabulary for this SDK:**' line found ({SPEC} §7)")

    if len(rows) != len(CAPABILITIES):
        fail(
            f"{readme}: capability map has {len(rows)} rows, expected "
            f"{len(CAPABILITIES)} ({SPEC} §6)"
        )
        return set()

    exceptions: set[str] = set()
    for (expected_id, expected_title), (_, cells) in zip(CAPABILITIES, rows):
        cap_id, title, support, evidence, targets = cells
        if cap_id != expected_id:
            fail(f"{readme}: capability rows are out of order at {cap_id}; expected {expected_id}")
            continue
        if title != expected_title:
            fail(
                f"{readme}: {cap_id} title is '{title}'; {SPEC} §6 requires the verbatim "
                f"'{expected_title}'"
            )
        if support not in SUPPORT_VALUES:
            fail(f"{readme}: {cap_id} Support '{support}' is not one of {sorted(SUPPORT_VALUES)}")
        if evidence not in EVIDENCE_VALUES:
            fail(f"{readme}: {cap_id} Evidence '{evidence}' is not one of {sorted(EVIDENCE_VALUES)}")
        if not targets:
            fail(f"{readme}: {cap_id} has an empty Targets value")
        elif vocabulary and targets not in vocabulary:
            fail(
                f"{readme}: {cap_id} Targets '{targets}' is not in the vocabulary this "
                f"skill declares ({', '.join(sorted(vocabulary))})"
            )

        # §7: a non-`yes` Support and citation-bearing Evidence each owe extra detail.
        # The detail lives in prose below the map, keyed by the capability ID.
        detail = capability_detail(text, cap_id)
        if support != "yes":
            exceptions.add(cap_id)
            if len(detail) < 80:
                fail(
                    f"{readme}: {cap_id} has Support '{support}' but no explanation "
                    f"below the map. {SPEC} §7 requires the reason, and for 'preview' "
                    f"the opt-in mechanism, the version, and the stability warning."
                )
        if evidence in EVIDENCE_NEEDS_CITATION and not CITATION_TOKEN_RE.search(detail):
            fail(
                f"{readme}: {cap_id} has Evidence '{evidence}', which {SPEC} §7 requires "
                f"to carry the path and ref inline; none found in its explanation."
            )
    return exceptions


def capability_detail(text: str, cap_id: str) -> str:
    """Prose about one capability outside the map row itself — the bullets under the map
    where §7's extra-information requirements live.

    A bullet is multi-line, and only its first line names the capability, so collect
    from each mention until the next bullet or blank line.
    """
    lines = text.split("\n")
    detail: list[str] = []
    index = 0
    while index < len(lines):
        line = lines[index]
        if cap_id in line and not line.strip().startswith("|"):
            detail.append(line)
            index += 1
            while index < len(lines):
                following = lines[index]
                if not following.strip():
                    break
                if following.lstrip().startswith(("- ", "* ", "|", "#")):
                    break
                detail.append(following)
                index += 1
            continue
        index += 1
    return " ".join(detail)


def main() -> int:
    if not os.path.isdir(SKILLS_DIR):
        print("ERROR: run this from the repository root", file=sys.stderr)
        return 2

    validate_every_skill()

    sdk_skills = sorted(
        name
        for name in os.listdir(SKILLS_DIR)
        if name.endswith("-sdk") and os.path.isfile(os.path.join(SKILLS_DIR, name, "SKILL.md"))
    )
    for name in sdk_skills:
        validate_sdk_skill(name)

    for message in warnings:
        print(f"WARNING: {message}")
    for message in errors:
        print(f"ERROR: {message}")

    if errors:
        print(f"\n{len(errors)} structural error(s).")
        return 1

    checked = ", ".join(sdk_skills) if sdk_skills else "none"
    print(f"SDK skill structure OK (checked: {checked})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
