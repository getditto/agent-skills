# Ditto Plugins for AI Code Assistants

Skills and plugins for [Ditto](https://ditto.com) — the peer-to-peer sync platform. Use these to get expert help with Ditto's offline-first database, CRDTs, mesh networking, DQL query language, and SDK migrations directly inside your AI code assistant.

## Available Plugins

| Plugin | Description |
|--------|-------------|
| [ditto-dql](./plugins/ditto-dql) | DQL (Ditto Query Language) assistance for queries, subscriptions, and data operations |
| [ditto-v5-migration](./plugins/ditto-v5-migration) | Per-platform skills for migrating Ditto SDK applications from v4.14 to v5.0 (Swift, Kotlin, C++, Rust, Flutter, JavaScript/TypeScript, .NET, Go) |

## Installation

### Claude Code

```bash
# Add the marketplace
/plugin marketplace add getditto/claude-code-plugins

# Install a plugin
/plugin install ditto-dql
/plugin install ditto-v5-migration
```

### Codex CLI

Add the plugin's skills directory as a source in your Codex configuration:

```bash
codex install getditto/claude-code-plugins/plugins/ditto-dql
```

### Cursor / Windsurf / Other Tools

You can reference the skill files directly by adding them to your project's rules or context:

1. Clone this repository (or add it as a submodule)
2. Point your tool's configuration to the relevant skill files under `plugins/<plugin-name>/skills/`

For example, in Cursor you can add the skill markdown files to your `.cursor/rules/` directory.

### ChatGPT, Gemini, and Other AI Assistants

The [skills/](./skills/) directory contains pre-packaged system prompts and setup instructions for non-code-editor AI assistants. See the [skills README](./skills/README.md) for details.

## MCP Servers

Plugins include MCP (Model Context Protocol) servers for enhanced Ditto assistance:

| Server | Description |
|--------|-------------|
| `ditto-docs` | Access Ditto documentation directly |
| `ditto-inkeep` | Ditto AI assistant for questions and troubleshooting |

MCP server configuration is defined in each plugin's `.mcp.json` file.

## About Ditto

[Ditto](https://ditto.com) is a mobile database with built-in edge device connectivity and resiliency. It enables apps to synchronize without relying on a central server or constant cloud connectivity using:

- **CRDTs** for automatic conflict resolution
- **Peer-to-peer mesh** networking
- **DQL** — a SQL-like query language
- **Offline-first** architecture

Learn more at [docs.ditto.com](https://docs.ditto.com).

## Contributing

Ditto employees looking to add a new skill - here's how to add a new plugin or improve existing ones.

### Adding a New Plugin

1. **Create the plugin directory:**

   ```
   plugins/your-plugin-name/
   ├── .claude-plugin/
   │   └── plugin.json       # Plugin manifest (required)
   ├── .mcp.json              # MCP server config (optional)
   ├── skills/                # Skills — markdown files with YAML frontmatter
   │   └── your-skill/
   │       └── SKILL.md
   ├── commands/              # Slash commands (optional)
   ├── agents/                # Custom agent definitions (optional)
   └── README.md              # Plugin documentation (required)
   ```

2. **Define `plugin.json`:**

   ```json
   {
     "name": "your-plugin-name",
     "version": "1.0.0",
     "description": "What this plugin does",
     "author": { "name": "Your Name", "email": "you@example.com" },
     "license": "MIT",
     "keywords": ["ditto", "your-topic"]
   }
   ```

3. **Create skills** in `plugins/your-plugin-name/skills/<skill-name>/SKILL.md` with YAML frontmatter:

   ```yaml
   ---
   name: skill-name
   description: When to use this skill (this triggers activation)
   allowed-tools: Read, Grep, Glob, Edit, Write
   ---

   # Skill content here
   Your instructions, examples, and reference material.
   ```

4. **Register the plugin** by adding an entry to `.claude-plugin/marketplace.json`:

   ```json
   {
     "name": "your-plugin-name",
     "description": "What this plugin does",
     "version": "1.0.0",
     "author": { "name": "Your Name", "email": "you@example.com" },
     "source": "./plugins/your-plugin-name",
     "category": "development"
   }
   ```

5. **Add a README.md** to your plugin directory with installation and usage instructions.

6. **Submit a pull request.**

### Adding Skills for Non-Claude AI Assistants

To add support for tools like ChatGPT, Gemini, or others, see the [skills/ directory](./skills/README.md).

## License

MIT
