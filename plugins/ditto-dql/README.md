# ditto-dql

Claude Code plugin for Ditto Query Language (DQL) assistance. It helps developers working with the [Ditto](https://ditto.com) peer-to-peer sync platform write correct, version-aware DQL for SELECT queries, mutations, subscriptions, and indexing — across both currently supported SDK lines.

## Supported Ditto SDK versions

- Ditto SDK **4.14.x** (LTS)
- Ditto SDK **5.0.x** (current)

Every documented feature is tagged with its minimum SDK version. See [`skills/dql/references/versions.md`](skills/dql/references/versions.md) for the full compatibility matrix. v5.1.0 features are excluded until v5.1.0 ships.

## What's included

### `write-dql` skill

A routing entry point that detects your project's Ditto SDK version, then directs Claude to the relevant reference and example material. The skill lives at `plugins/ditto-dql/skills/dql/` and covers:

- SELECT queries, filtering, sorting, aggregations, and subscription patterns
- INSERT / UPDATE / DELETE / EVICT semantics
- DQL types and mutators (REGISTER, MAP, ATTACHMENT, counters, etc.)
- Indexing strategies for offline-first workloads
- Best practices for sync, conflict resolution, and CRDT-friendly schemas

### `dql-expert` agent

A subagent (`agents/dql-expert.md`) that uses the `write-dql` skill to answer DQL questions and produce production-ready queries with the correct SDK-version gating.

### Reference catalog

Located in [`skills/dql/references/`](skills/dql/references/):

| File | Covers |
|------|--------|
| [`operators.md`](skills/dql/references/operators.md) | Comparison, logical, arithmetic, and string operators |
| [`functions.md`](skills/dql/references/functions.md) | Built-in scalar and aggregate functions |
| [`expressions.md`](skills/dql/references/expressions.md) | Path expressions, literals, type coercion |
| [`statements.md`](skills/dql/references/statements.md) | INSERT, UPDATE, DELETE, EVICT statement forms |
| [`select.md`](skills/dql/references/select.md) | SELECT, projections, joins, ORDER BY, subscriptions |
| [`types-mutators.md`](skills/dql/references/types-mutators.md) | DQL type system and CRDT mutators |
| [`indexing.md`](skills/dql/references/indexing.md) | CREATE INDEX, query planning, performance |
| [`versions.md`](skills/dql/references/versions.md) | Per-feature SDK compatibility matrix |

### Movies cookbook

[`skills/dql/examples/movies-cookbook.md`](skills/dql/examples/movies-cookbook.md) — 18 worked tasks against a shared movies dataset, each annotated with the minimum SDK version required and side-by-side variants for v4.14.x vs v5.0.x where the API differs.

## Installation

```bash
# Add the marketplace
/plugin marketplace add getditto/claude-code-plugins

# Install the plugin
/plugin install ditto-dql
```

## Quick start

The `write-dql` skill activates automatically when you ask about DQL queries, Ditto database operations, or query syntax. For example:

> "Write a DQL subscription that streams incomplete tasks sorted by priority, compatible with SDK 4.14."

Claude will detect your SDK version, consult the relevant reference files, and produce a version-correct query.

## Links

- [Ditto documentation](https://docs.ditto.com)
- [DQL reference](https://docs.ditto.com/dql)
- [Ditto SDK release notes](https://docs.ditto.com/release-notes)
