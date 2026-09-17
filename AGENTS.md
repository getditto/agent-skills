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
└── ditto-mesh-networking/

agents/                        # Portable agent definitions (markdown)
└── ditto-dql/                 # Namespaced by the plugin that ships them
    └── dql-expert.md

tests/                         # Per-skill test harnesses
├── dql/                       # DQL: name-matched subdirectory
│   ├── catalog/  scripts/  runner/  fixtures/  sdks/
│   └── README.md
├── data-modeling/             # data-modeling: live-model JSON-review evals
│   ├── cases/  runner/
│   └── README.md
└── swift-sdk/                 # swift-sdk: SwiftPM fixture run against 3 SDK lines
    ├── Sources/  Tests/  scripts/
    └── README.md

plugins/                       # Claude Code plugin wrappers (thin)
├── ditto-dql/                 # One plugin per skill it ships
│   ├── .claude-plugin/plugin.json
│   ├── skills/dql -> ../../../skills/dql        (symlinked dir)
│   └── agents -> ../../agents/ditto-dql         (symlinked dir)
├── ditto-mesh/
│   ├── .claude-plugin/plugin.json
│   └── skills/ditto-mesh-networking -> ../../../skills/ditto-mesh-networking
├── ditto-subscriptions/
│   ├── .claude-plugin/plugin.json
│   └── skills/sync-subscriptions -> ../../../skills/sync-subscriptions
├── ditto-data-modeling/
│   ├── .claude-plugin/plugin.json
│   └── skills/data-modeling -> ../../../skills/data-modeling
└── ditto-swift/
    ├── .claude-plugin/plugin.json
    └── skills/swift-sdk -> ../../../skills/swift-sdk

.claude-plugin/marketplace.json  # Claude Code marketplace manifest
.opencode/opencode.json          # opencode project config (skills.paths)

docs/                          # Contributor-facing docs
├── SKILLS-TEMPLATE.md         # Template for any skill
├── SDK-SKILL-TEMPLATE.md      # Normative spec for per-language SDK skills
└── templates/sdk-skill/       # Fillable skeleton; copy to skills/<lang>-sdk/
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
- **Per-language SDK skills** (`skills/kotlin-sdk/`, `skills/swift-sdk/`, …) have a
  stricter spec: `docs/SDK-SKILL-TEMPLATE.md`. It defines a twenty-item capability
  contract (CAP-01 … CAP-20) that every language skill must address, in the same
  order, so the nine SDK skills stay comparable and unsupported capabilities are
  declared rather than silently absent. Copy `docs/templates/sdk-skill/` rather than
  scaffolding by hand.
- **Concept skills own semantics; SDK skills own syntax.** `dql`, `data-modeling`,
  `sync-subscriptions` and `ditto-mesh-networking` explain how Ditto works once,
  language-agnostically. An SDK skill explains how to express that in one language
  and links back rather than restating — duplicated concept material drifts, and
  `CONTRIBUTING.md` §4 forbids citing one file in this repo as the source for another.

## Claude Code Marketplace

`.claude-plugin/marketplace.json` stays at the repo root (required by
`/plugin marketplace add`). Each entry's `source` points at a thin wrapper
under `plugins/<plugin>/` containing `.claude-plugin/plugin.json` plus a real
`skills/` directory holding **one symlink per skill that plugin ships**, plus
— if it ships agents — an `agents` symlink pointing at that plugin's namespaced
subdirectory under `agents/`. Skill content is never duplicated in the wrapper.

**Agents must be linked as a directory, not as individual files.** Claude Code
follows a symlinked *directory* but not a symlinked *file*: an
`agents/foo.md -> ../../../agents/foo.md` link is silently dropped and the
agent never loads. Hence `agents/<plugin>/` namespacing.

**Plugins are scoped — never symlink the whole `skills/` or `agents/` tree
into a wrapper.** Users install only the skills they ask for: `ditto-dql`
ships the DQL skill and its agent; `ditto-mesh` ships the
ditto-mesh-networking skill. A new skill gets its own plugin unless it genuinely belongs to an
existing one, because adding it to an existing wrapper changes what that
plugin installs for everyone who already has it. CI enforces the scoping.

## Tests

`tests/<skill>/` holds executable verification for a skill's documented
examples. For DQL: `tests/dql` runs every ```sql block in `skills/dql/`
against real Ditto SDK versions (see `tests/dql/README.md`). For
data-modeling: `tests/data-modeling` feeds raw-JSON cases plus the skill to
live AI models and deterministically scores the recommendations against the
rubric finding IDs in `skills/data-modeling/references/workflow.md` (see
`tests/data-modeling/README.md`). CI workflows:

- `.github/workflows/ci.yml` — validates JSON manifests and SKILL.md
  frontmatter, checks marketplace `source` targets exist, and enforces that
  each plugin wrapper only symlinks the skills/agents it declares.
- `.github/workflows/dql-skill-tests.yml` — macOS matrix run of the DQL
  harness; triggers on changes to `skills/dql/**` or `tests/dql/**`.

Local harness config lives in the repo-root `.env` (gitignored; copy
`.env-sample`). Both runners auto-load it via `tests/lib/load-env.mjs`;
environment variables (and CI secrets) always take precedence. Keys:
`DITTO_OFFLINE_LICENSE` (tests/dql and tests/swift-sdk, required),
`DITTO_DATABASE_ID` (optional), `DITTO_URL` + `DITTO_TOKEN` (tests/swift-sdk,
optional — enables the server-authentication leg), `DM_MODEL_CMD`
(tests/data-modeling, required). `tests/swift-sdk/scripts/*.sh` read the same
`.env` with their own shell parser.
Overview for contributors: `testing-readme.md`.

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
