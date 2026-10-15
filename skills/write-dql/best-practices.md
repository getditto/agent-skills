# DQL Best Practices - Data Modeling, Optimization, and Schema Versioning

## Contents

- [Data Modeling Best Practices](#data-modeling-best-practices)
- [Schema Versioning Best Practices](#schema-versioning-best-practices)
- [Query Optimization](#query-optimization)
- [Strict Mode](#strict-mode)
- [Query Safety](#query-safety)
- [Timestamp Best Practices](#timestamp-best-practices)
- [Performance Checklist](#performance-checklist)
- [Related Reference Files](#related-reference-files)
- [Official Documentation](#official-documentation)

**Read this file ONLY when:** You need guidance on data modeling, query optimization, schema versioning, timestamps, soft delete, or understanding strict mode.

**For basic queries:** Use `SKILL.md` instead.

**For canonical syntax and per-version (4.14.x vs 5.0.x) behavior:** Use the files under `references/` — see the [Related Reference Files](#related-reference-files) list at the bottom of this file.

---

## Data Modeling Best Practices

See [modeling-patterns.md](references/modeling-patterns.md#data-modeling-best-practices) for this topic.

## Schema Versioning Best Practices

See [modeling-patterns.md](references/modeling-patterns.md#schema-versioning-best-practices) for this topic.

## Query Optimization

See [query-performance.md](references/query-performance.md#query-optimization) for this topic.

## Strict Mode

See [strict-mode-safety.md](references/strict-mode-safety.md#strict-mode) for this topic.

## Query Safety

See [strict-mode-safety.md](references/strict-mode-safety.md#query-safety) for this topic.

## Timestamp Best Practices

See [timestamps.md](references/timestamps.md#timestamp-best-practices) for this topic.

## Performance Checklist

See [query-performance.md](references/query-performance.md#performance-checklist) for this topic.

## Related Reference Files

This best-practices file covers the cross-cutting "how should I think about this?" advice. For canonical syntax, grammar, and per-version behavior:

- [`references/statements.md`](references/statements.md) — `INSERT`/`UPDATE`/`EVICT`/`TOMBSTONE`/`DELETE`/`ALTER SYSTEM`/`SHOW`/`SYNC CONTEXT`/`PROFILE` grammar, including TOMBSTONE TTL specifics.
- [`references/select.md`](references/select.md) — full `SELECT` grammar, `USE IDS`, system datasources.
- [`references/expressions.md`](references/expressions.md) — literals, path expressions (`a.b.c`, `arr[i]`), `CASE`, quantifiers, comprehensions.
- [`references/operators.md`](references/operators.md) — comparison, logical, arithmetic, string, set operators.
- [`references/functions.md`](references/functions.md) — scalar and aggregate function catalog.
- [`references/types-mutators.md`](references/types-mutators.md) — `REGISTER`/`MAP`/`COUNTER`/`PN_COUNTER`/`ATTACHMENT` types, `SET`/`UNSET`/`APPLY` mutators, the `dql_strict_mode` parameter.
- [`references/indexing.md`](references/indexing.md) — `CREATE INDEX`/`DROP INDEX`, `EXPLAIN`, `#profile`, planner directives, covering plans, `USE IDS`.
- [`references/versions.md`](references/versions.md) — SDK 4.14.x vs 5.0.x compatibility matrix.

## Official Documentation

- **Data Modeling:** https://docs.ditto.live/best-practices/data-modeling
- **Schema Versioning:** https://docs.ditto.live/best-practices/schema-versioning
- **Access Paths:** https://docs.ditto.live/dql/access-paths
- **Strict Mode:** https://docs.ditto.live/dql/strict-mode
- **Timestamps:** https://docs.ditto.live/best-practices/timestamps
- **DQL Overview:** https://docs.ditto.live/dql/dql
