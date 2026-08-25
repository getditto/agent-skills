# Skill Template

The canonical structure for every skill in this repo. A skill is the portable
unit that all supported agent tools (Claude Code, opencode, Codex, Gemini, …)
load.

## Directory layout

```
skills/<skill-name>/
├── SKILL.md            # Required. Entry point: frontmatter + lean body
├── README.md           # Human-facing docs (install, supported versions, status)
├── references/         # Detailed reference docs, loaded by the agent on demand
│   └── <topic>.md
├── examples/           # Worked, runnable examples
│   └── <name>.md
└── best-practices.md   # Optional: patterns, anti-patterns, common mistakes
```

Rules:

- `<skill-name>` is lowercase hyphen-separated and **must match** the
  frontmatter `name` in `SKILL.md`.
- `SKILL.md` is the only file every tool parses. Everything else is linked
  from it and loaded on demand.
- Keep `SKILL.md` under ~500 lines. Long material goes in `references/` or
  `examples/`.

## SKILL.md frontmatter

```yaml
---
name: <skill-name>        # required; must equal the directory name
description: >            # required; this is the trigger
  Use when <concrete situations>. <What the skill does>.
                          # Front-load literal keywords users will say.
---
```

The `description` decides whether the skill activates. It must cover both
**what** the skill does and **when** to use it, written in third person
("Use when …", not "I help with …"). Front-load concrete trigger keywords
(API names, error strings, file names). If the skill should stay quiet on
adjacent topics, gate with "Use ONLY when …".

Optional frontmatter fields some tools honor: `license`, `compatibility`,
`allowed-tools`, `metadata`. Only add `allowed-tools` if every target tool
understands it — unknown keys may error in stricter loaders.

## SKILL.md body sections

Every skill body should include:

1. **What this skill does** — 1–3 sentences.
2. **When to use / when not to use** — the routing contract.
3. **Core workflow or patterns** — the smallest set of steps the agent needs.
4. **Anti-patterns / common mistakes** — short, concrete, high-value.
5. **References** — a table or list mapping questions to files in
   `references/` and `examples/`, so the agent knows exactly which file to
   load for which question.

## Metadata conventions

- If content is version-sensitive (SDK versions, API versions), tag every
  version-specific claim minimally (e.g. "Available in: SDK 5.0.x") and keep a
  `references/versions.md` compatibility matrix.
- The skill README records supported versions and last-verified date.
- Never document unreleased features as available; mark them as
  future/not-yet-shipped.

## Token budget

Agent tools inject the skill name + description into every session; the body
is loaded when triggered, and `references/`/`examples/` on demand.

- Description: 1–3 sentences, ≤ ~500 chars.
- SKILL.md body: aim ≤ 300 lines of active guidance.
- One `references/<topic>.md` file per concern; an agent should rarely need
  to load all of them at once.

## Tests

If the skill documents executable statements (queries, commands), add a
harness under `tests/<skill-name>/` that verifies the documented examples
really work, and extend CI. See `tests/dql/README.md` for the reference
implementation.
