# DQL Best Practices - Data Modeling, Optimization, and Schema Versioning

## Contents

- [Related Reference Files](#related-reference-files)
- [Official Documentation](#official-documentation)

Covered in other files: [Data Modeling Best Practices](references/modeling-patterns.md#data-modeling-best-practices), [Schema Versioning Best Practices](references/modeling-patterns.md#schema-versioning-best-practices), [Query Optimization](references/query-performance.md#query-optimization), [Strict Mode](references/strict-mode-safety.md#strict-mode), [Query Safety](references/strict-mode-safety.md#query-safety), [Timestamp Best Practices](references/timestamps.md#timestamp-best-practices), [Performance Checklist](references/query-performance.md#performance-checklist).

**Read this file ONLY when:** You need guidance on data modeling, query optimization, schema versioning, timestamps, soft delete, or understanding strict mode.

**For basic queries:** Use `SKILL.md` instead.

**For canonical syntax and per-version (4.14.x vs 5.0.x) behavior:** Use the files under `references/` — see the [Related Reference Files](#related-reference-files) list at the bottom of this file.

---

## Related Reference Files

This best-practices file covers the cross-cutting "how should I think about this?" advice. For canonical syntax, grammar, and per-version behavior:

- [`references/statements.md`](references/statements.md) — `INSERT`/`UPDATE`/`EVICT`/`TOMBSTONE`/`DELETE`/`ALTER SYSTEM`/`SHOW`/`SYNC CONTEXT`/`PROFILE` grammar, including TOMBSTONE TTL specifics.
- [`references/select-basics.md`](references/select-basics.md) — full `SELECT` grammar, `USE IDS`, system datasources.
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
