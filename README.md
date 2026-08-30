# Agent Skills for Ditto

AI agent skills for [Ditto](https://ditto.com) — the peer-to-peer sync platform.
Skills follow the cross-tool [`SKILL.md`](docs/SKILLS-TEMPLATE.md) convention and
work with **Claude Code, opencode, Codex, Gemini**, and any other agent tool that
loads skills.

**Note: This repo is currently private, but we intend to make it PUBLIC for
customer use. Do not add skills or content that are not appropriate for
customer use.**

## Available skills

| Skill | Description |
|-------|-------------|
| [dql](skills/dql) (`write-dql`) | DQL (Ditto Query Language) assistance for queries, subscriptions, and data operations. Covers Ditto SDK 4.14.x (LTS), 5.0.x, and 5.1.x (JOINs, composite indexes, RETURNING, ADVISE). |
| [sync-subscriptions](skills/sync-subscriptions) (`sync-subscriptions`) | How Ditto sync subscriptions work: query rules and limitations, mesh propagation, multi-hop flooding, and troubleshooting missing documents. Covers Ditto SDK 4.14.x (LTS), 5.0.x, and 5.1.x. |

## Repository layout

```
skills/          Canonical skills (the portable unit: SKILL.md + references/ + examples/)
agents/          Portable agent definitions (markdown)
tests/<skill>/   Executable verification for each skill's documented examples
plugins/         Thin per-tool packaging (Claude Code plugin wrappers w/ symlinks)
docs/            Contributor docs (SKILLS-TEMPLATE.md, plans)
```

Skill content lives exactly once in `skills/`. Everything tool-specific wraps
or points at it.

## Installation by tool

### Claude Code

Install via the bundled plugin marketplace (backed by thin wrappers in
`plugins/`):

```bash
/plugin marketplace add getditto/claude-code-plugins
/plugin install ditto-dql
```

`.claude-plugin/marketplace.json` → `plugins/ditto-dql/.claude-plugin/plugin.json`
→ symlinks into `skills/` and `agents/`.

### opencode

The repo ships `.opencode/opencode.json` with `skills.paths: ["./skills"]`,
so opening this repo in opencode loads the skills automatically.

For global use, copy or symlink the skill into `~/.agents/skills/` or set
`skills.paths` in `~/.config/opencode/opencode.jsonc`:

```bash
ln -s "$(pwd)/skills/dql" ~/.agents/skills/dql
```

### Codex / Gemini / other tools

Any tool that supports the `SKILL.md` convention (a directory of skills, each
with YAML `name` + `description` frontmatter) can load these. Point the tool's
skills directory at this repo's `skills/` folder, or copy/symlink the
individual skill directory into the tool's expected location, e.g.:

```bash
# Codex
ln -s "$(pwd)/skills/dql" ~/.codex/skills/dql
```

Consult your tool's documentation for its skills directory location.

**Windows contributors:** use copy instead of symlink unless your Git install
has symlink support enabled.

## MCP servers

The repo provides MCP server endpoints for enhanced Ditto assistance:

| Server | Endpoint | Description |
|--------|----------|-------------|
| `ditto-docs` | <https://docs.ditto.com/mcp> | Access Ditto documentation directly |

- **Claude Code / Claude-format tools**: `.mcp.json` at the repo root is
  picked up automatically (via `mcp-remote`).
- **Other tools**: add the same endpoints using your tool's MCP config
  ([example opencode config](https://opencode.ai/docs/mcp-servers/)).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add a new skill and
[docs/SKILLS-TEMPLATE.md](docs/SKILLS-TEMPLATE.md) for the skill template.

## About Ditto

Ditto is a mobile database with built-in edge device connectivity and
resiliency. It enables apps to synchronize without relying on a central
server or constant cloud connectivity using:

- **CRDTs** for automatic conflict resolution
- **Peer-to-peer mesh** networking
- **DQL** — a SQL-like query language
- **Offline-first** architecture

Learn more at [docs.ditto.com](https://docs.ditto.com).

## License

MIT
