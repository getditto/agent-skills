#!/usr/bin/env python3
"""Structural validation for per-language SDK skills (skills/<lang>-sdk/).

Implements the mechanical half of docs/SDK-SKILL-TEMPLATE.md §12.1 so that nine
near-identical skills cannot drift. Everything here is checkable without judgement;
the judgement items in §14 stay with the reviewer.

Known limits — a green run does NOT mean these were checked:

* The §7 "extra information" checks are shape checks. An explanation long enough to pass
  the length test can still say nothing, and a citation token that looks like a path
  (`Totally.swift`) is not verified to exist or to contain what is claimed.
* Whether a claim is TRUE is never checked. Neither is whether a code sample compiles.
* Link checking resolves paths and anchors; it does not judge whether the link is apt.

Also enforces repo-wide frontmatter and context budgets against *every* skill,
not only SDK skills. --context-report lists every Markdown file's size.

Run from the repository root:

    python3 scripts/validate-sdk-skills.py
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import textwrap

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
    # Not capability files: these three hold the explanation behind the SKILL.md sections
    # that carry only a punchline inline (§5). Required for the same reason those sections
    # are — that material is where correct-looking code fails at runtime.
    "references/concurrency.md",
    "references/lifetimes.md",
    "references/anti-patterns.md",
]

# Repository authoring budgets, not model limits. Characters are reproducible without
# requiring a vendor tokenizer; token estimates are deliberately labelled approximate.
# These apply to concept skills too: several skills may share one small context window.
SKILL_BODY_CHAR_TARGET = 10_000
SKILL_BODY_CHAR_HARD_LIMIT = 12_000
DESCRIPTION_CHAR_TARGET = 500
DESCRIPTION_CHAR_HARD_LIMIT = 1024
RESOURCE_TOC_CHAR_THRESHOLD = 8_000
RESOURCE_CHAR_HARD_LIMIT = 20_000

# §3 / §11 — references cost zero context until read, so they are budgeted far more
# loosely than SKILL.md. Above TOC_REQUIRED_LINES a file needs a `## Contents` list:
# partial reads (`head -100`) must still reveal the file's full scope.
REFERENCE_LINE_TARGET = 600
REFERENCE_LINE_HARD_LIMIT = 800
TOC_REQUIRED_LINES = 200

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
    slug = re.sub(r"\s", "-", slug)
    return slug


def collect_anchors(text: str) -> set[str]:
    anchors: set[str] = set()
    counts: dict[str, int] = {}
    fence: str | None = None
    for line in text.split("\n"):
        marker = re.match(r"^\s*(`{3,}|~{3,})", line)
        if marker:
            char = marker.group(1)[0]
            if fence is None:
                fence = char
            elif fence == char:
                fence = None
            continue
        if fence:
            continue
        match = re.match(r"^(#{1,6})\s+(.*?)\s*$", line)
        if match:
            slug = heading_anchor(match.group(2))
            occurrence = counts.get(slug, 0)
            counts[slug] = occurrence + 1
            anchors.add(f"{slug}-{occurrence}" if occurrence else slug)
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
# The `(` is deliberately NOT in this lookbehind: markdown link targets are stripped
# before this runs, so excluding a leading `(` only created a bypass —
# "taken from (skills/write-dql/...)" would slip through.
CITATION_RE = re.compile(r"(?<![\w/])(skills/[\w./-]+|\.\./\.\.(?:/[\w./-]+)?)")
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
    """Frontmatter, context budgets and navigation for every skill."""
    for name in sorted(os.listdir(SKILLS_DIR)):
        skill_dir = os.path.join(SKILLS_DIR, name)
        skill_md = os.path.join(skill_dir, "SKILL.md")
        if not os.path.isfile(skill_md):
            continue

        text = read(skill_md)
        keys, body = split_frontmatter(text, skill_md)

        declared = keys.get("name")
        expected = name
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

        # The small frontmatter parser leaves block scalars uninterpreted. Unfold
        # just the description for length accounting; this is not a YAML validator.
        frontmatter = text.split("\n---\n", 1)[0]
        match = re.search(
            r"^description:\s*(.*?)(?=^[A-Za-z][A-Za-z0-9_-]*:|\Z)",
            frontmatter, re.S | re.M,
        )
        description = " ".join((match.group(1) if match else "").split())
        if description.startswith(("> ", "| ")):
            description = description[2:]
        if not description or len(description) > DESCRIPTION_CHAR_HARD_LIMIT:
            fail(f"{skill_md}: description must contain 1–1024 characters")
        elif len(description) > DESCRIPTION_CHAR_TARGET:
            warn(f"{skill_md}: description is {len(description)} characters; target ≤500")

        body_chars = len(body.strip())
        if body_chars > SKILL_BODY_CHAR_HARD_LIMIT:
            fail(
                f"{skill_md}: body is {body_chars:,} characters, over the "
                f"{SKILL_BODY_CHAR_HARD_LIMIT:,}-character limit. Move conditional "
                "detail to references/ and retain core constraints and routing."
            )
        elif body_chars > SKILL_BODY_CHAR_TARGET:
            warn(f"{skill_md}: body is {body_chars:,} characters; target ≤10,000")

        for path in all_markdown(skill_dir):
            check_links(skill_dir, os.path.relpath(path, skill_dir))
            if path == skill_md:
                continue
            resource = read(path)
            lines = len(resource.splitlines())
            needs_contents = (
                lines > TOC_REQUIRED_LINES or len(resource) > RESOURCE_TOC_CHAR_THRESHOLD
            )
            contents = extract_section(resource, "Contents")
            has_contents_links = any(target.startswith("#") for target in LINK_RE.findall(contents))
            if needs_contents and not has_contents_links:
                fail(
                    f"{path}: needs a linked '## Contents' list (over 200 lines or "
                    "8,000 characters), so agents can select a section."
                )
            if len(resource) > RESOURCE_CHAR_HARD_LIMIT:
                fail(
                    f"{path}: {len(resource):,} characters, over the repository's "
                    "20,000-character resource limit. Split independent topics; "
                    "a contents list alone does not bound a full-file read."
                )


def print_context_report() -> None:
    """Inventory includes references, examples and READMEs, without counting symlinks twice."""
    print("\nContext inventory (characters; tokens ≈ chars/4, NOT a tokenizer count)")
    print("| File | Characters | Lines | Approx. tokens |")
    print("|---|---:|---:|---:|")
    for name in sorted(os.listdir(SKILLS_DIR)):
        skill_dir = os.path.join(SKILLS_DIR, name)
        if not os.path.isfile(os.path.join(skill_dir, "SKILL.md")):
            continue
        for path in sorted(all_markdown(skill_dir)):
            text = read(path)
            print(f"| {path} | {len(text):,} | {len(text.splitlines()):,} | {len(text) / 4:,.0f} |")


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

    # §3 / §11 — reference size, and the table of contents that a long one owes.
    if os.path.isdir(references):
        for entry in sorted(os.listdir(references)):
            if not entry.endswith(".md"):
                continue
            path = os.path.join(references, entry)
            text = read(path)
            line_count = len(text.rstrip("\n").split("\n"))
            if line_count > REFERENCE_LINE_HARD_LIMIT:
                fail(
                    f"{path}: {line_count} lines, over the {REFERENCE_LINE_HARD_LIMIT}-line "
                    f"limit in {SPEC} §3 — split it instead"
                )
            elif line_count > REFERENCE_LINE_TARGET:
                warn(
                    f"{path}: {line_count} lines; {SPEC} §3 targets "
                    f"{REFERENCE_LINE_TARGET}"
                )
            if line_count > TOC_REQUIRED_LINES and not re.search(
                r"^## Contents\s*$", text, re.M
            ):
                fail(
                    f"{path}: {line_count} lines with no '## Contents' list. {SPEC} §3 "
                    f"requires one above {TOC_REQUIRED_LINES} lines, so a partial read "
                    f"still shows the file's full scope."
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

    # §3 — "A reference must never be the only path to another reference": every
    # reference has to be linked from SKILL.md or README.md, not just from a sibling.
    # Compare resolved LINK TARGETS, not substrings: a bare prose mention of a file
    # name is not a path to it. Covers examples/ as well as references/.
    linked: set[str] = set()
    for entry in ("SKILL.md", "README.md"):
        path = os.path.join(skill_dir, entry)
        if not os.path.isfile(path):
            continue
        for target in LINK_RE.findall(read(path)):
            if target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            resolved = os.path.normpath(
                os.path.join(skill_dir, target.partition("#")[0])
            )
            linked.add(resolved)

    for subdirectory in ("references", "examples"):
        directory = os.path.join(skill_dir, subdirectory)
        if not os.path.isdir(directory):
            continue
        for entry in sorted(os.listdir(directory)):
            if not entry.endswith(".md"):
                continue
            path = os.path.normpath(os.path.join(directory, entry))
            if path not in linked:
                fail(
                    f"{path}: not linked from SKILL.md or README.md. "
                    f"{SPEC} §3 requires every reference to be reachable without "
                    f"following a chain through another reference."
                )

    # §12.1 item 9 — all SDK Markdown files, including optional resources.
    # Link checks run for every skill in validate_every_skill().
    for path in sorted(all_markdown(skill_dir)):
        relative = os.path.relpath(path, skill_dir)
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


# `examples/minimal-app.md` restates its fixture rather than referencing it, because a
# plugin user has no `tests/` tree to open. §12.2 asks for a reference; this check makes
# the duplication safe by failing when the two drift.
#
# The fixture is DERIVED from the markdown's own declaration, not from a table here: a
# hard-coded map silently skips any skill nobody remembered to register, and silently
# stops checking when a fixture is renamed — both of which were demonstrated.
FIXTURE_DECL_RE = re.compile(r"This is a copy of `([^`]+)` in the fixture")


def within(root: str, path: str) -> bool:
    """True when `path` is `root` or lives underneath it.

    The paths checked here are derived from prose in the skill, so `../../../etc/passwd`
    resolves to a readable file and would otherwise be compared happily. Proven: a
    declaration of `../../../README.md` passed before this guard existed.
    """
    root = os.path.realpath(root)
    path = os.path.realpath(path)
    return root == path or path.startswith(root + os.sep)


# A fixture source may restate a type that is defined and tested elsewhere in the same
# harness, when the file has to compile standalone (the minimal app is pasted into an
# empty project, so it cannot `import` the harness's own modules). Declaring the mirror
# in prose makes the duplication checkable instead of a place for the two to drift —
# which is the failure mode this skill hit repeatedly: the tested copy was fixed and the
# pasted copy was not.
MIRROR_DECL_RE = re.compile(r"mirrors `([\w.]+)` in `([^`]+)`")

DECL_KINDS = ("actor", "struct", "final class", "class", "enum")

# Mirror claims are declaration-driven, which leaves one hole: the claim sits INSIDE the
# program text that the byte-compare protects, so a single edit can drift the code and
# delete its own guard, and the validator stays green. Proven. This is the floor — a
# mirror that must exist. Add a row when you add a mirror; it is three fields, and the
# alternative is a guard that can delete itself.
REQUIRED_MIRRORS = {
    "swift-sdk": [("Sources/MinimalApp/MinimalApp.swift", "Deadline.Gate")],
}

# Everything below this marker in the fixture is the documented program. Declared rather
# than inferred, so the boundary does not depend on Swift syntax.
PROGRAM_MARKER = "// MARK: - begin documented program"


def extract_declaration(text: str, type_name: str):
    """Returns the source of `type_name`'s declaration, including its leading keyword.

    Brace-matched rather than parsed. Braces inside string literals would confuse it, so
    a failure to extract is reported as an error rather than treated as "no mirror here".
    """
    pattern = re.compile(
        r"^[ \t]*(?:public |internal |private |fileprivate )*"
        r"(?:" + "|".join(k.replace(" ", r"\s+") for k in DECL_KINDS) + r")\s+"
        + re.escape(type_name) + r"\b[^\n{]*\{",
        re.M,
    )
    match = pattern.search(text)
    if not match:
        return None
    depth = 0
    for index in range(text.index("{", match.start()), len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return textwrap.dedent(text[match.start():index + 1])
    return None


def check_mirrored_declarations(name: str) -> None:
    """Every "mirrors `A.B` in `<path>`" claim must be byte-identical to its original."""
    harness = os.path.join("tests", name)
    if not os.path.isdir(harness):
        return

    for relative, qualified in REQUIRED_MIRRORS.get(name, []):
        required = os.path.join(harness, relative)
        if not os.path.isfile(required):
            fail(f"{required}: required by REQUIRED_MIRRORS but does not exist.")
            continue
        if f"mirrors `{qualified}` in `" not in read(required):
            fail(
                f"{required}: lost its \"mirrors `{qualified}` in `<path>`\" declaration. "
                f"That sentence is what makes the duplicated `{qualified.split('.')[-1]}` "
                f"checkable; removing it silently disables the check."
            )

    for directory, subdirectories, files in os.walk(harness):
        # `.build` holds SwiftPM's checkouts of every dependency. Walking it is slow and
        # a claim found inside a vendored source would report on a file nobody here owns.
        subdirectories[:] = [entry for entry in subdirectories if not entry.startswith(".")]
        for filename in sorted(files):
            if not filename.endswith(".swift"):
                continue
            copy_path = os.path.join(directory, filename)
            text = read(copy_path)
            for qualified, target in MIRROR_DECL_RE.findall(text):
                type_name = qualified.split(".")[-1]
                resolved = os.path.join(harness, os.path.relpath(target, harness)) \
                    if target.startswith(harness) else os.path.join(harness, target)
                if not within(harness, resolved) or not os.path.exists(resolved):
                    fail(
                        f"{copy_path}: claims to mirror `{qualified}` in `{target}`, "
                        f"which does not resolve inside {harness}/."
                    )
                    continue

                candidates = []
                if os.path.isfile(resolved):
                    candidates = [resolved]
                else:
                    for sub, nested, names in os.walk(resolved):
                        nested[:] = [entry for entry in nested if not entry.startswith(".")]
                        candidates += [
                            os.path.join(sub, entry)
                            for entry in sorted(names)
                            if entry.endswith(".swift")
                            and os.path.join(sub, entry) != copy_path
                        ]

                originals = [
                    (candidate, extract_declaration(read(candidate), type_name))
                    for candidate in candidates
                ]
                originals = [(path, decl) for path, decl in originals if decl]
                if not originals:
                    fail(
                        f"{copy_path}: claims to mirror `{qualified}`, but no "
                        f"declaration of `{type_name}` was found under {target}. A "
                        f"renamed original must not silently disable this check."
                    )
                    continue

                copy = extract_declaration(text, type_name)
                if copy is None:
                    fail(
                        f"{copy_path}: declares a mirror of `{qualified}` but has no "
                        f"`{type_name}` declaration of its own."
                    )
                    continue

                if not any(decl == copy for _, decl in originals):
                    origin = originals[0][0]
                    fail(
                        f"{copy_path}: its `{type_name}` has drifted from `{qualified}` "
                        f"in {origin}. The original is the copy that is tested — port "
                        f"the change, or drop the 'mirrors' claim."
                    )


def check_examples_match_fixture(name: str) -> None:
    """Every published example that declares a fixture copy must match it byte for byte.

    Iterates `examples/*.md` rather than naming one file: the skill grew a second example
    and a hard-coded filename would have checked the old one and silently ignored the new.
    """
    directory = os.path.join(SKILLS_DIR, name, "examples")
    if not os.path.isdir(directory):
        return
    for entry in sorted(os.listdir(directory)):
        if entry.endswith(".md"):
            check_one_example(name, os.path.join(directory, entry))


def check_one_example(name: str, example: str) -> None:
    text = read(example)

    declaration = FIXTURE_DECL_RE.search(text)
    harness = os.path.join("tests", name)
    if not declaration:
        # No declaration and no harness is fine — the skill has no fixture yet. A harness
        # with no declaration is a gap, not a pass.
        if os.path.isdir(harness) and "```swift" in text:
            fail(
                f"{example}: {harness}/ exists but the file does not declare which "
                f"fixture it copies. Add: This is a copy of `<path>` in the fixture."
            )
        return

    fixture = os.path.join(harness, declaration.group(1))
    if not within(harness, fixture):
        fail(
            f"{example}: declares a copy of `{declaration.group(1)}`, which resolves "
            f"outside {harness}/. A declaration must not be able to point this check at "
            f"an arbitrary file."
        )
        return
    if not os.path.isfile(fixture):
        fail(
            f"{example}: declares a copy of `{declaration.group(1)}`, which does not "
            f"resolve to a file ({fixture}). A renamed fixture must not silently "
            f"disable this check."
        )
        return

    match = re.search(r"## Program\n\n```\w+\n(.*?)\n```\n", text, re.S)
    if not match:
        fail(f"{example}: no '## Program' fence found to compare against {fixture}")
        return

    source = read(fixture).rstrip("\n")
    if PROGRAM_MARKER not in source:
        fail(
            f"{fixture}: missing the '{PROGRAM_MARKER}' marker that delimits the "
            f"documented program."
        )
        return
    # The marker declares "everything below is the documented program". If code sits
    # above it, the published sample silently omits a part the fixture compiled — the
    # reader gets a program that does not build. Only comments and blank lines may
    # precede it.
    preamble = source.split(PROGRAM_MARKER, 1)[0].splitlines()
    for number, line in enumerate(preamble, start=1):
        stripped = line.strip()
        if stripped and not stripped.startswith("//"):
            fail(
                f"{fixture}:{number}: code above '{PROGRAM_MARKER}' is excluded from "
                f"the published sample, so the sample would not compile: {stripped!r}"
            )
            break

    expected = source.split(PROGRAM_MARKER, 1)[1].lstrip("\n")

    if match.group(1) != expected:
        fail(
            f"{example}: the '## Program' block has drifted from {fixture}. "
            f"Regenerate it — the fixture is the copy that is compiled and run."
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--context-report", action="store_true", help="list sizes of every skill Markdown file")
    args = parser.parse_args()
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
        check_examples_match_fixture(name)
        check_mirrored_declarations(name)

    if args.context_report:
        print_context_report()

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
