# SDKS-4838: Make agent-skills repo tool-agnostic

Linear: https://linear.app/ditto/issue/SDKS-4838/restructure-the-repo-to-work-with-any-ai-agent

Parent issue: [SDKS-3600](https://linear.app/ditto/issue/SDKS-3600/define-skill-template-and-contributor-guide) — defines the skill template and contributor guide (Phase 4 deliverables).

## Goal

Restructure this repo so its skills work with any AI coding tool that
supports the `SKILL.md` convention (opencode, Claude Code, Codex, Gemini,
etc.), not just the Claude Code plugin marketplace.

## Guiding principles

- `plugins/<name>/skills/<skill>/SKILL.md` + `references/` + `examples/` is
  the portable unit. YAML frontmatter (`name`, `description`) is the
  cross-tool standard.
- Tool-specific tooling (marketplaces, manifests, installer configs) lives in
  thin per-tool layers that reference the canonical skills — never the other
  way around.
- `AGENTS.md` is source of truth for agent-facing repo guidance. `CLAUDE.md`,
  `GEMINI.md`, etc. become one-line pointers to it.
- Minimal changes to the existing DQL skill content and test harness.

## Target structure

```
agent-skills/
├── AGENTS.md                      # canonical agent guidance (new)
├── CLAUDE.md                      # 1-line pointer to AGENTS.md
├── CONTRIBUTING.md                # contributor guide + skill authoring rules
├── README.md                      # tool-agnostic overview + install matrix
├── skills/
│   └── dql/                       # moved from plugins/ditto-dql/skills/dql (unchanged content)
│       ├── SKILL.md
│       ├── references/
│       ├── examples/
│       └── best-practices.md
├── tests/                         # moved from plugins/ditto-dql/tests (unchanged)
│   └── ...
├── tools/
│   ├── claude/
│   │   └── .claude-plugin/
│   │       └── marketplace.json   # moved from repo root; entries point at ../../skills
│   └── install.sh                 # (optional) symlinks skills/ into per-tool dirs
├── .claude-plugin/
│   └── marketplace.json           # kept temporarily as redirect, or removed in favor of tools/claude
└── docs/
    └── SKILLS-TEMPLATE.md         # canonical SKILL.md template (part of SDKS-3600)
```

## Phases

### Phase 1 — Move skills to canonical location
1. `git mv plugins/ditto-dql/skills/dql skills/dql`
2. `git mv plugins/ditto-dql/tests tests/dql` (keep it namespaced per-skill so
   future skills get their own test dirs, e.g. `tests/<skill>/`)
3. `git mv plugins/ditto-dql/agents agents/` (agents are also portable markdown)
4. Remove now-empty `plugins/ditto-dql/` shell once nothing references it.

### Phase 2 — Fix every reference to the old layout
- `.github/workflows/dql-skill-tests.yml` and `ci.yml` paths
- `plugins/ditto-dql/README.md`, `tests/README.md` internal paths
- Root `README.md` and `CLAUDE.md`
- `.claude-plugin/marketplace.json` `source` fields

### Phase 3 — Per-tool integrations
- **Claude Code**: keep marketplace support. Entry `source` points at the skill
  folder; verify whether a bare skill dir satisfies the plugin schema or
  whether a minimal `.claude-plugin/plugin.json` shim per skill is needed.
- **opencode**: document `skills.paths: ["./skills"]` in project
  `opencode.json`, or copying/symlinking into `~/.agents/skills`.
- **Codex / Gemini / others**: document install path per tool (copy vs.
  symlink); add `tools/install.sh` to automate if more than two tools need it.

### Phase 4 — Documentation (the SDKS-3600 deliverables)
1. `docs/SKILLS-TEMPLATE.md` — canonical skill template: required frontmatter,
   directory layout, description-writing rules, how to add per-version
   reference docs and tests.
2. `CONTRIBUTING.md` — how to add a new skill end-to-end: scaffold from
   template, local validation, test harness usage, PR checklist.
3. Rewrite `README.md`:
   - remove Claude-marketplace-only framing
   - add a per-tool install/usage matrix
   - keep the "private now, public later" customer-appropriateness note.
4. Create `AGENTS.md` as source of truth; reduce `CLAUDE.md` to a pointer.
5. Update `.github/CODEOWNERS` paths if affected.

### Phase 5 — Validation
- CI green on the new paths.
- Manual smoke test: load `skills/dql` in opencode and in Claude Code and
  confirm the skill surfaces.

## Decisions made during implementation

- **Claude marketplace**: kept `.claude-plugin/marketplace.json` at the repo
  root (required by `/plugin marketplace add`); `plugins/ditto-dql/` is now a
  thin wrapper (`.claude-plugin/plugin.json` + `skills`/`agents` symlinks into
  the canonical dirs). Existing install instructions unchanged.
- **root `.mcp.json`**: kept at root (Claude-format); other tools get the same
  endpoints documented in the README.
- **Tests layout**: `tests/<skill>/` with per-skill subdirs (not colocated).
- **Install**: documented copy/symlink per tool in README; no `install.sh`
  (avoid extra maintenance surface; symlink caveats documented for Windows).
- **Catalog IDs**: extractor hashes repo-relative paths (stable across
  machines/moves); the catalog was fully regenerated as part of this work.

## Open questions to resolve during implementation

- Does Claude Code's marketplace accept a `source` pointing directly at a
  bare skill directory, or does each skill need a `.claude-plugin/plugin.json`
  wrapper? (determines whether Phase 3 needs shims)
- Do we keep the root `.mcp.json` (repo-scoped MCP) or move it under
  `tools/claude/`? Other tools have their own MCP config mechanisms.
- One repo-level `tests/` with per-skill subdirs, vs. tests colocated inside
  each skill folder — pick one convention and document it in the template.
- Symlink-based install script vs. copy-based (Windows contributor support
  argues for copy).

## Out of scope

- Changing the DQL skill content itself.
- Publishing to any public registry.
