# ditto-dql

Claude Code plugin for Ditto Query Language (DQL) assistance.

## What it does

This plugin provides a `write-dql` skill that helps you write DQL queries for the Ditto platform. It covers:

- SELECT queries with filtering, sorting, and aggregations
- INSERT statements with conflict handling
- UPDATE operations including nested fields
- DELETE vs EVICT semantics
- Subscription query patterns
- Data types (REGISTER, MAP, ATTACHMENT)
- Best practices for offline-first sync

It also provides a `dql-expert` agent that will use the `write-dql` skill.

## Installation

```bash
# Add the marketplace
/plugin marketplace add getditto/claude-code-plugins

# Install the plugin
/plugin install ditto-dql
```

## Usage

The skill activates automatically when you ask about:
- Writing DQL queries
- Ditto database operations
- Query syntax help

## Examples

Ask Claude Code things like:
- "Write a DQL query to get all incomplete tasks sorted by priority"
- "How do I upsert a document in Ditto?"
- "What's the difference between DELETE and EVICT?"
- "Help me create a subscription for user-specific data"

## Links

- [Ditto Documentation](https://docs.ditto.com)
- [DQL Reference](https://docs.ditto.com/dql)
