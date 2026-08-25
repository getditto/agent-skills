# dql skill ("write-dql")

AI agent skill for Ditto Query Language (DQL) assistance — works with any agent tool that supports the `SKILL.md` convention (Claude Code, opencode, Codex, Gemini, etc.). It helps developers working with the [Ditto](https://ditto.com) peer-to-peer sync platform write correct, version-aware DQL for SELECT queries, mutations, subscriptions, and indexing — across both currently supported SDK lines.

## Supported Ditto SDK versions

- Ditto SDK **4.14.x** (LTS)
- Ditto SDK **5.0.x**
- Ditto SDK **5.1.x** (current — adds JOINs, composite indexes, RETURNING, ADVISE)

Every documented feature is tagged with its minimum SDK version. See [`references/versions.md`](references/versions.md) for the full compatibility matrix. v5.1.0 features are excluded until v5.1.0 ships.

## What's included

### `write-dql` skill

A routing entry point that detects your project's Ditto SDK version, then directs the agent to the relevant reference and example material. The skill lives at `skills/dql/` in this repo and covers:

- SELECT queries, filtering, sorting, aggregations, and subscription patterns
- INSERT / UPDATE / DELETE / EVICT semantics
- DQL types and mutators (REGISTER, MAP, ATTACHMENT, counters, etc.)
- Indexing strategies for offline-first workloads
- Best practices for sync, conflict resolution, and CRDT-friendly schemas

### `dql-expert` agent

A subagent (`agents/dql-expert.md`) that uses the `write-dql` skill to answer DQL questions and produce production-ready queries with the correct SDK-version gating.

### Reference catalog

Located in [`references/`](references/):

| File | Covers |
|------|--------|
| [`operators.md`](references/operators.md) | Comparison, logical, arithmetic, and string operators |
| [`functions.md`](references/functions.md) | Built-in scalar and aggregate functions |
| [`expressions.md`](references/expressions.md) | Path expressions, literals, type coercion |
| [`statements.md`](references/statements.md) | INSERT, UPDATE, DELETE, EVICT statement forms |
| [`select.md`](references/select.md) | SELECT, projections, ORDER BY, subscriptions |
| [`types-mutators.md`](references/types-mutators.md) | DQL type system and CRDT mutators |
| [`indexing.md`](references/indexing.md) | CREATE INDEX, query planning, performance |
| [`versions.md`](references/versions.md) | Per-feature SDK compatibility matrix |

### Movies cookbook

[`examples/movies-cookbook.md`](examples/movies-cookbook.md) — 23 worked tasks against a shared movies dataset, each annotated with the minimum SDK version required. Includes JOIN tasks (inner/outer/anti-join, aggregates, HAVING) for SDK 5.1+.
- [`examples/retail-cookbook.md`](examples/retail-cookbook.md) — those same cross-collection questions answered without JOINs (two-query patterns, IN-list resolution, denormalization); runs on every supported SDK.
- [`examples/retail-joins-cookbook.md`](examples/retail-joins-cookbook.md) — the identical retail tasks rewritten with SDK 5.1 JOINs (INNER/LEFT/anti-join, composite-index examples). Compare the two files task-by-task.

## Installation

**Claude Code** (via the marketplace wrapper in `plugins/ditto-dql/`):

```bash
/plugin marketplace add getditto/claude-code-plugins
/plugin install ditto-dql
```

**Other agent tools**: see the [repo root README](../../README.md) for per-tool install instructions.

## Quick start

The `write-dql` skill activates automatically when you ask about DQL queries, Ditto database operations, or query syntax. For example:

> "Write a DQL subscription that streams incomplete tasks sorted by priority, compatible with SDK 4.14."

The agent will detect your SDK version, consult the relevant reference files, and produce a version-correct query.

## Testing

The plugin ships with an automated test harness that runs every documented DQL example against actual Ditto Node SDK installations. Each example is verified to work on the SDK version it claims to support.

```bash
cd tests/dql
# One-time setup
(cd sdks/v4.14.4 && npm install)
(cd sdks/v5.0.0 && npm install)
(cd sdks/v5.1.0 && npm install)
npm run transform               # produce pedagogical-schema test dataset (one-time)

# Run against both SDK versions
DITTO_OFFLINE_LICENSE="$DITTO_LICENSE" npm test
npm run report
```

Current status: **174 PASS / 46 PASS-AS-EXPECTED-FAIL** on `@dittolive/ditto@4.14.4`; **191 PASS / 29 PASS-AS-EXPECTED-FAIL** on `@dittolive/ditto@5.0.0`; **211 PASS / 9 PASS-AS-EXPECTED-FAIL** on `@dittolive/ditto@5.1.0` (220 catalog entries). PASS-AS-EXPECTED-FAIL is the runner correctly identifying features that aren't available on the running version (e.g., `XOR` everywhere, `JOIN`/composite indexes/`RETURNING`/`ADVISE` pre-5.1, `CASE`/`BETWEEN` pre-5.0).

See [`tests/dql/README.md`](../../tests/dql/README.md) for the harness internals.

## Links

- [Ditto documentation](https://docs.ditto.com)
- [DQL reference](https://docs.ditto.com/dql)
- [Ditto SDK release notes](https://docs.ditto.com/release-notes)
