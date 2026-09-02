# ditto-dql (Claude Code plugin wrapper)

This directory exists only to satisfy the Claude Code plugin/marketplace
layout — the skill content lives once, canonically, in the repo-root
[`skills/dql/`](../../skills/dql/) directory.

The wrapper symlinks **only the skills and agents this plugin ships**, so
installing `ditto-dql` gives you DQL assistance and nothing else.

| Item | Where |
|---|---|
| Skill (write-dql) | [`skills/dql/SKILL.md`](../../skills/dql/SKILL.md) |
| Agent (dql-expert) | [`agents/ditto-dql/dql-expert.md`](../../agents/ditto-dql/dql-expert.md) |
| Human-facing docs | [`skills/dql/README.md`](../../skills/dql/README.md) |
| Test harness | [`tests/dql/`](../../tests/dql/) |

Do not add skill content here. See [`CONTRIBUTING.md`](../../CONTRIBUTING.md)
for how skills are packaged per tool.
