# AGENTS.md

Guidance for AI coding agents working in this repository. Tool-specific
pointer files (`CLAUDE.md`, etc.) delegate to this file.

## What This Repository Is

A tool-agnostic collection of **agent skills** for [Ditto](https://ditto.com)
— the peer-to-peer sync platform. Skills follow the cross-tool `SKILL.md`
convention and work with Claude Code, opencode, Codex, Gemini, and any other
agent tool that loads skills. Topics include Ditto's offline-first database,
CRDTs, mesh networking, and the DQL query language.

**Note: this repo is intended to become PUBLIC for customer use. Do not add
skills or content that are not appropriate for customer use.**

## Repository Layout

```
skills/                        # Canonical skills — the portable unit
├── dql/
│   ├── SKILL.md               # Skill entry point (YAML frontmatter + body)
│   ├── references/            # Detailed reference docs loaded on demand
│   ├── examples/              # Worked examples
│   ├── best-practices.md
│   └── README.md              # Human-facing docs for the skill
└── mesh-networking/

agents/                        # Portable agent definitions (markdown)
└── dql-expert.md

tests/                         # Per-skill test harnesses
└── dql/                       # Skill: name-matched subdirectory
    ├── catalog/  scripts/  runner/  fixtures/  sdks/
    └── README.md

plugins/                       # Claude Code plugin wrappers (thin)
├── ditto-dql/                 # One plugin per skill it ships
│   ├── .claude-plugin/plugin.json
│   ├── skills/dql -> ../../../skills/dql              (symlink)
│   └── agents/dql-expert.md -> ../../../agents/...    (symlink)
└── ditto-mesh/
    ├── .claude-plugin/plugin.json
    └── skills/mesh-networking -> ../../../skills/...  (symlink)

.claude-plugin/marketplace.json  # Claude Code marketplace manifest
.opencode/opencode.json          # opencode project config (skills.paths)

docs/                          # Contributor-facing docs
```

## The Skill Convention

- Every skill is `skills/<name>/SKILL.md` where `<name>` is lowercase
  hyphen-separated and matches the frontmatter `name`.
- Frontmatter **must** include `name` and `description`. The description is
  the trigger: cover what the skill does and when to use it, front-loading
  concrete keywords. Third person, not "I help with...".
- Keep `SKILL.md` lean (routing + core guidance). Put long reference material
  in `references/` and `examples/`, linked from the body — agents load those
  on demand, which keeps context/token budgets small.
- See `docs/SKILLS-TEMPLATE.md` for the authoritative template and
  `CONTRIBUTING.md` for the end-to-end authoring workflow.

## Claude Code Marketplace

`.claude-plugin/marketplace.json` stays at the repo root (required by
`/plugin marketplace add`). Each entry's `source` points at a thin wrapper
under `plugins/<plugin>/` containing `.claude-plugin/plugin.json` plus a real
`skills/` (and optional `agents/`) directory holding **one symlink per item
that plugin ships**. Skill content is never duplicated in the wrapper.

**Plugins are scoped — never symlink the whole `skills/` or `agents/` tree
into a wrapper.** Users install only the skills they ask for: `ditto-dql`
ships the DQL skill and its agent; `ditto-mesh` ships the mesh-networking
skill. A new skill gets its own plugin unless it genuinely belongs to an
existing one, because adding it to an existing wrapper changes what that
plugin installs for everyone who already has it. CI enforces the scoping.

## Tests

`tests/<skill>/` holds executable verification for a skill's documented
examples. For DQL: `tests/dql` runs every ```sql block in `skills/dql/`
against real Ditto SDK versions (see `tests/dql/README.md`). CI workflows:

- `.github/workflows/ci.yml` — validates JSON manifests and SKILL.md
  frontmatter, checks marketplace `source` targets exist, and enforces that
  each plugin wrapper only symlinks the skills/agents it declares.
- `.github/workflows/dql-skill-tests.yml` — macOS matrix run of the DQL
  harness; triggers on changes to `skills/dql/**` or `tests/dql/**`.

## MCP Servers

The root `.mcp.json` (Claude-format) exposes `ditto-docs` (Ditto
documentation) and `ditto-inkeep` (Ditto AI assistant). Other tools can point
at the same remote endpoints with their own MCP config.

## Working Agreements

- Never commit directly to `main`; work on a branch tied to a Linear issue
  (e.g. `sdks-4838/...`).
- Minimal diffs; don't reformat unrelated content.
- The DQL skill documents Ditto SDK 4.14.x (LTS), 5.0.x and 5.1.x. 5.1.x
  ships JOINs, composite (multi-column) indexes, `RETURNING` on INSERT/UPDATE,
  and `ADVISE`; all are harness-verified against `@dittolive/ditto@5.1.0`.
