# Ditto Plugins for Claude Code

A Claude Code plugin marketplace for [Ditto](https://ditto.com) - the peer-to-peer sync platform.

## Available Plugins

| Plugin | Description |
|--------|-------------|
| [ditto-dql](./plugins/ditto-dql) | DQL (Ditto Query Language) assistance for queries, subscriptions, and data operations |

## Installation

### 1. Add the marketplace

```bash
/plugin marketplace add getditto/claude-code-plugins
```

### 2. Install a plugin

```bash
/plugin install ditto-dql
```

## About Ditto

Ditto is a mobile database with built-in edge device connectivity and resiliency. It enables apps to synchronize without relying on a central server or constant cloud connectivity using:

- **CRDTs** for automatic conflict resolution
- **Peer-to-peer mesh** networking
- **DQL** - a SQL-like query language
- **Offline-first** architecture

Learn more at [docs.ditto.com](https://docs.ditto.com).

## MCP Servers

Plugins include these MCP servers for enhanced Ditto assistance:

| Server | Description |
|--------|-------------|
| `ditto-docs` | Access Ditto documentation directly |
| `ditto-inkeep` | Ditto AI assistant for questions and troubleshooting |

## Contributing

To add a new plugin:

1. Create a directory under `plugins/`
2. Add `.claude-plugin/plugin.json` with plugin metadata
3. Add skills, commands, or agents as needed
4. Update `marketplace.json` to include the plugin
5. Submit a pull request

## Plugin Structure

```
plugins/your-plugin/
├── .claude-plugin/
│   └── plugin.json       # Plugin manifest
├── skills/               # Skills (SKILL.md files)
├── commands/             # Slash commands
├── agents/               # Custom agents
└── README.md             # Plugin documentation
```

## License

MIT
