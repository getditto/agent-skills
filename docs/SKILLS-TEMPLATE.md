# Skill Template

The canonical structure for every skill in this repo. A skill is the portable
unit that all supported agent tools (Claude Code, opencode, Codex, Gemini, …)
load.

> **Writing a per-language SDK skill?** Read
> [`SDK-SKILL-TEMPLATE.md`](SDK-SKILL-TEMPLATE.md) as well. It specializes this
> template for `skills/<lang>-sdk/` and adds a twenty-item capability contract that
> every language skill must satisfy, so that all nine SDK skills stay comparable. A
> fillable skeleton lives at [`templates/sdk-skill/`](templates/sdk-skill).

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
- Keep `SKILL.md` small — see [Token budget](#token-budget). Long material goes
  in `references/` or `examples/`, which cost nothing until read.

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

- **Description: 1–3 sentences, ≤ ~500 chars.** Claude Code budgets the whole
  skill listing at 1% of the model's context window and caps each entry at
  1,536 characters, dropping least-used descriptions when it overflows. A long
  description crowds out other skills' trigger keywords and loses its own tail.
- **SKILL.md body: aim ≤ 14,000 characters (~3,500 tokens).** Anthropic's
  published ceiling is 500 lines, but that is a ceiling, not a target: Apple's
  published Xcode skills run 16–37 line `SKILL.md` files routing to 1,000–3,400
  lines of references. The operative constraint is that Claude Code re-attaches
  only the first 5,000 tokens of each invoked skill after auto-compaction, so a
  larger body silently loses its tail — usually the routing section.
- **Promote the punchline, demote the explanation.** The one clause that changes
  what an agent emits, plus the observable symptom, belongs in `SKILL.md`. The
  worked code and the reference tables belong behind a link.
- One `references/<topic>.md` file per concern; an agent should rarely need
  to load all of them at once. Give any reference over 200 lines a
  `## Contents` list, so a partial read still shows its full scope.
- **Do not split one skill into several to make each smaller.** More skills means
  more listing entries competing for that 1% budget, which makes discovery worse
  for every skill. Fan out *within* a skill instead. A new skill is justified by a
  different task mode, not by a file having grown long.

Per-language SDK skills have stricter, CI-enforced versions of these numbers:
[`SDK-SKILL-TEMPLATE.md`](SDK-SKILL-TEMPLATE.md) §11.

## Tests

If the skill documents executable statements (queries, commands), add a
harness under `tests/<skill-name>/` that verifies the documented examples
really work, and extend CI. See `tests/dql/README.md` for the reference
implementation.
