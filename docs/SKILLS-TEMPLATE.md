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

Discovery loads names/descriptions; activation loads the entire `SKILL.md` body.
References and examples cost context when read. Keep that distinction explicit:
Codex, Claude Code and OpenCode support progressive loading, but a model can still
choose to read an oversized file in full.

Repository budgets (authoring policy, not vendor limits):

| Surface | Target | Enforced limit |
|---|---|---|
| Description | ≤500 characters, concrete triggers first | 1,024 characters |
| SKILL.md body | ≤10,000 characters | 12,000 characters |
| Supporting file | One focused task or intact program | ≤20,000 characters; contents above 8,000 characters **or** 200 lines |

At four characters per token, a 10,000-character body is roughly 2,500 tokens.
This is an estimate: code, punctuation and different tokenizers change the ratio.
Do not present a character check as a guarantee that a file fits a model's context.

- Keep core constraints, symptoms and task routing in `SKILL.md`; put worked code,
  detailed tables and conditional explanations in references.
- Tell agents to choose a task row, preview a long file's contents, then read only
  the matching section. Do not require every reference, the README or a full example
  before answering an ordinary question. Load another skill only for its actual task.
- Give long references/examples/READMEs a linked `## Contents` near the top, including
  dense tables that are short in lines but large in characters. Keep references one
  level deep. Split by independently useful task, not an arbitrary number of lines.
- Do not split one skill into many just to reduce body size: each new description
  adds discovery overhead. Keep trigger descriptions brief and discriminating.

`python3 scripts/validate-sdk-skills.py --context-report` checks every skill's
entry-point budget, supporting-file navigation and local links, and lists every
Markdown file's size. It rejects oversized resources so a full-file read stays within the repository
budget. These are policy choices; even a passing file is not guaranteed to fit every model. SDK skills also have the stricter contract in
[SDK-SKILL-TEMPLATE.md](SDK-SKILL-TEMPLATE.md) §11.

Source guidance: [Agent Skills specification](https://agentskills.io/specification#progressive-disclosure),
[Codex skill loading](https://learn.chatgpt.com/docs/build-skills),
[Claude Code supporting files](https://code.claude.com/docs/en/skills#add-supporting-files),
[OpenCode skill loading](https://opencode.ai/docs/skills/).
These describe host loading, not behavioral validation on every underlying model.

## Tests

If the skill documents executable statements (queries, commands), add a
harness under `tests/<skill-name>/` that verifies the documented examples
really work, and extend CI. See `tests/dql/README.md` for the reference
implementation.
