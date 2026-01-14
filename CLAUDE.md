# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Is

A Claude Code plugin marketplace for Ditto (ditto.com) - a peer-to-peer sync platform. Plugins help developers work with Ditto's offline-first database, CRDTs, mesh networking, and DQL query language.

## Architecture

```
.claude-plugin/
└── marketplace.json       # Marketplace manifest - lists all available plugins

plugins/
└── <plugin-name>/
    ├── .claude-plugin/
    │   └── plugin.json    # Plugin manifest (name, version, description, keywords)
    ├── .mcp.json          # MCP server configuration
    ├── skills/            # SKILL.md files with YAML frontmatter
    ├── commands/          # Slash command definitions (.md files)
    ├── agents/            # Custom agent definitions (.md files)
    └── README.md
```

## Adding a New Plugin

1. Create `plugins/<plugin-name>/.claude-plugin/plugin.json`:
```json
{
  "name": "plugin-name",
  "version": "1.0.0",
  "description": "What it does",
  "author": { "name": "Ditto", "email": "support@ditto.com" },
  "license": "MIT",
  "keywords": ["ditto", ...]
}
```

2. Add the plugin to `.claude-plugin/marketplace.json` in the `plugins` array

3. Create skills in `plugins/<plugin-name>/skills/<skill-name>/SKILL.md` with YAML frontmatter:
```yaml
---
name: skill-name
description: When to use this skill (triggers activation)
allowed-tools: Read, Grep, Glob, Edit, Write
---
```

## MCP Servers

Plugins include these MCP servers (configured in `.mcp.json`):
- `ditto-docs` - Ditto documentation server
- `ditto-inkeep` - Ditto AI assistant

## Ditto Reference

- Documentation: https://docs.ditto.com
- DQL (query language): https://docs.ditto.com/dql
- Key concepts: CRDTs, peer-to-peer mesh sync, offline-first, subscriptions
