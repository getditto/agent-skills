---
name: write-dql
description: Use when writing DQL (Ditto Query Language) — SELECT/INSERT/UPDATE/EVICT/TOMBSTONE/DELETE statements, subscriptions, CRDT types, query optimization (EXPLAIN/#profile), or ALTER SYSTEM/SHOW config. Covers Ditto SDK 4.14.x, 5.0.x, and 5.1.x (5.1 adds JOIN, composite indexes, RETURNING, ADVISE). Confirm the user's SDK version before answering — feature support varies.
allowed-tools: Read, Grep, Glob, Edit, Write
---

# DQL — Ditto Query Language

DQL is Ditto's SQL-like language for querying and mutating documents in a CRDT-aware, peer-to-peer database. It looks like SQL, but the semantics are different in three ways that matter every day:

1. **No joins, no subqueries, no UNION.** One `FROM` per statement.
2. **`NULL` and `MISSING` are distinct.** `NULL` = field exists, value is null. `MISSING` = field is absent. They behave differently in every operator.
3. **Every field is a CRDT.** The CRDT type (REGISTER, MAP, COUNTER, PN_COUNTER, ATTACHMENT) controls how concurrent edits merge.

Scope: this skill covers DQL syntax and semantics. For schema design — CRDT type selection, embed-vs-split decisions, document size budgets, reviewing raw JSON models — use the `data-modeling` skill.

## First: which SDK version is the user on?

DQL features land version by version. **Before answering a non-trivial DQL question, confirm the SDK version.** If the user has not said which Ditto SDK they're on, ask:

> "Which Ditto SDK version is this for? I support guidance for 4.14.x, 5.0.x, and 5.1.x."

If they don't know, ask them to check the SDK package version in their project (`Ditto.swift` / `build.gradle` / `package.json`) — or to run `SHOW dql_strict_mode` to identify the v4 strict-default vs v5 lenient-default behavior. Then filter the rest of the conversation to features available in that version (see `references/versions.md`).

**Strict mode:** this skill assumes `dql_strict_mode = false` (lenient) on every peer — the 5.x default and the migration target for 4.14.x meshes. Examples therefore use no `MAP`/`REGISTER` keywords on reads or writes (objects infer MAP; reads see every type). If a 4.x user reports fields missing from query results or whole-object overwrites on merge, suspect an un-migrated strict peer first — see `references/types-mutators.md` §7 and `best-practices.md` "Strict Mode".

If the user explicitly says "give me the latest" or "use the newest" without picking a version, default to 5.1.x and say so.

## Where to look

> **First time reading an example?** Every operator, function, statement, expression, and cookbook task in this skill queries the same two collections (`movies`, `reviews`). The full schema — field names, types, and CRDT designations — lives in [`references/schema.md`](references/schema.md). Open that alongside any reference file the first time you read it.

| If you're doing this... | Read |
|---|---|
| Wondering what a field in an example means | `references/schema.md` |
| Picking which features apply to your SDK version | `references/versions.md` |
| Writing a `SELECT` | `references/select.md` |
| Writing `INSERT` / `UPDATE` / `EVICT` / `TOMBSTONE` / `DELETE` / `ALTER SYSTEM` / `SHOW` / `SYNC CONTEXT` | `references/statements.md` |
| Looking up an operator's precedence or NULL/MISSING behaviour | `references/operators.md` |
| Looking up a built-in function | `references/functions.md` |
| Writing `CASE`, `ANY ... SATISFIES`, `ARRAY FOR`, parameter binding | `references/expressions.md` |
| Declaring CRDT types in `INSERT`, picking COUNTER vs PN_COUNTER, using ATTACHMENT | `references/types-mutators.md` |
| `CREATE INDEX`, `EXPLAIN`, profiling with `#profile`, planner directives | `references/indexing.md` |
| Designing schemas, schema versioning, strict mode, timestamps | `best-practices.md` |
| Want a runnable end-to-end example | `examples/movies-cookbook.md` |
| Compare non-JOIN vs JOIN implementations of the same retail tasks | `examples/retail-cookbook.md` and `examples/retail-joins-cookbook.md` |

## Five things that bite people

1. **Use `AND` / `OR` / `NOT` keywords**, not `&&` / `||` / `!`.
2. **Single and double quotes both delimit strings**; backticks delimit identifiers. `WHERE title = "x"` and `WHERE title = 'x'` are equivalent. Prefer single quotes for consistency with JSON-style examples.
3. **`= NULL` is always NULL**, not TRUE. Use `IS NULL` / `IS NOT NULL` / `IS MISSING`.
4. **`INSERT` requires an explicit `ON ID CONFLICT`** for upserts. Default is FAIL.
5. **`EVICT` is local-only and reversible** (other peers will re-sync). **`TOMBSTONE` is mesh-wide and permanent** (subject to TTL). Don't mix them up.

## Compatibility

This skill covers **Ditto SDK 4.14.x, 5.0.x, and 5.1.x**. Every feature in the reference files is tagged with its minimum SDK version. See `references/versions.md` for the full matrix.

Not in the tested SDK lines (verified against 4.14.4 / 5.0.0 / 5.1.0): `XOR` (parser-rejected everywhere), structured `PROFILE` output, `DO MERGE`, multi-id `USE IDS` lists, and `USE IDS` on mutations. See `references/versions.md` for details.

## Decision tree for query problems

```
Need to read documents?
├── By known id(s)?         → USE IDS on SELECT (references/select.md)
├── With aggregation?       → GROUP BY + aggregates (references/select.md)
├── Across array elements?  → ANY ... IN ... SATISFIES (references/expressions.md, v5.0+)
└── Otherwise               → WHERE clause (references/select.md, references/operators.md)

Need to write documents?
├── Adding new?       → INSERT (references/statements.md)
├── Modifying?        → UPDATE with SET / UNSET / APPLY (references/statements.md)
└── Removing?         → EVICT (local) or TOMBSTONE (mesh) (references/statements.md)

Need to make it fast?
├── See the plan?     → EXPLAIN (references/indexing.md)
├── See timing?       → #profile directive (references/indexing.md, 5.0+)
└── Add an index?     → CREATE INDEX (references/indexing.md)
```
