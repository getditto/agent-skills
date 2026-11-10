---
name: write-dql
description: Use when writing or reviewing Ditto DQL queries, mutations, subscriptions, CRDT declarations, indexes, EXPLAIN/ADVISE or system configuration. Covers SDK 4.14.x, 5.0.x, 5.1.x and 5.2.0; confirm the target version because JOINs and other features are version-gated. Schema design belongs to data-modeling.
allowed-tools: Read, Grep, Glob, Edit, Write
---

# DQL — Ditto Query Language

DQL is Ditto's SQL-like language for querying and mutating documents in a CRDT-aware, peer-to-peer database. It looks like SQL, but the semantics are different in three ways that matter every day:

1. **SQL compatibility is version-gated.** Check the target SDK before using a SQL construct; JOINs require 5.1+.
2. **`NULL` and `MISSING` are distinct.** `NULL` = field exists, value is null. `MISSING` = field is absent. They behave differently in every operator.
3. **Every field is a CRDT.** The CRDT type (REGISTER, MAP, COUNTER, PN_COUNTER, ATTACHMENT) controls how concurrent edits merge.

Scope: this skill covers DQL syntax and semantics. For schema design — CRDT type selection, embed-vs-split decisions, document size budgets, reviewing raw JSON models — use the `data-modeling` skill.

## First: which SDK version is the user on?

DQL features land version by version. **Before answering a non-trivial DQL question, confirm the SDK version.** If the user has not said which Ditto SDK they're on, ask:

> "Which Ditto SDK version is this for? I support guidance for 4.14.x, 5.0.x, 5.1.x, and 5.2.0."

If they don't know, ask them to check the SDK package version in their project (`Ditto.swift` / `build.gradle` / `package.json`) — or to run `SHOW dql_strict_mode` to identify the v4 strict-default vs v5 lenient-default behavior. Then filter the rest of the conversation to features available in that version (see `references/versions.md`).

**Strict mode:** this skill assumes `dql_strict_mode = false` (lenient) on every peer — the 5.x default and the migration target for 4.14.x meshes. Examples therefore use no `MAP`/`REGISTER` keywords on reads or writes (objects infer MAP; reads see every type). If a 4.x user reports fields missing from query results or whole-object overwrites on merge, suspect an un-migrated strict peer first — see `references/types-mutators.md` §7 and `best-practices.md` "Strict Mode".

For “latest” or a new POC, resolve the latest stable SDK through the language’s package manager.
**5.2.0 is the latest version this skill knows about**, not a permanent dependency
recommendation. Check release notes and validate queries if the resolved release is newer.

## Where to look

Read only the reference section matching the task. For a long file, read its contents
first, then the selected section; do not load every reference or the README. In large
matrices or catalogs, find the relevant feature row and its version notes. Open
[`references/schema.md`](references/schema.md) only when adapting the movies/reviews
examples and their field names or types are unclear; it is not needed for a query
against the user's own schema.

| Task | Read |
|---|---|
| Identify fields in supplied examples | [schema.md](references/schema.md) only when needed |
| 5.2.0 diagnostics, USE IDS fixes, startup parameters | [sdk-5.2.md](references/sdk-5.2.md) |
| Version overview/defaults | [versions.md](references/versions.md) |
| Statement/index compatibility | [compatibility-statements.md](references/compatibility-statements.md) |
| Expression/operator/function compatibility | [compatibility-expressions.md](references/compatibility-expressions.md) |
| CRDT/subscription compatibility | [compatibility-types-sync.md](references/compatibility-types-sync.md) |
| SELECT, filtering, sorting, grouping | [select-basics.md](references/select-basics.md) |
| JOIN queries (5.1+) | [joins.md](references/joins.md) |
| SELECT USE IDS/INDEX/DIRECTIVES | [select-access.md](references/select-access.md) |
| Subscription query restrictions | [subscription-queries.md](references/subscription-queries.md) |
| INSERT/UPDATE/EVICT/DELETE/TOMBSTONE | [statements.md](references/statements.md) |
| ALTER SYSTEM/SHOW/SYNC CONTEXT/PROFILE | [system-statements.md](references/system-statements.md) |
| Operator precedence or NULL/MISSING | [operators.md](references/operators.md) |
| Scalar/aggregate functions | [functions.md](references/functions.md) |
| String functions | [string-functions.md](references/string-functions.md) |
| Date/time/duration functions | [date-time-functions.md](references/date-time-functions.md) |
| CASE, quantifiers, comprehensions, parameters | [expressions.md](references/expressions.md) |
| REGISTER/MAP/COUNTER/ATTACHMENT | [types-mutators.md](references/types-mutators.md) |
| PN_COUNTER or strict-mode declarations | [legacy-types.md](references/legacy-types.md) |
| CREATE/DROP INDEX or index strategy | [indexing.md](references/indexing.md) |
| Planner directives/hints | [planner-hints.md](references/planner-hints.md) |
| EXPLAIN, #profile, ADVISE | [query-diagnostics.md](references/query-diagnostics.md) |
| Schema evolution and model patterns | [modeling-patterns.md](references/modeling-patterns.md); use data-modeling for a complete design |
| Query performance | [query-performance.md](references/query-performance.md) |
| Strict-mode migration or query safety | [strict-mode-safety.md](references/strict-mode-safety.md) |
| Timestamp design | [timestamps.md](references/timestamps.md) |
| Worked movie reads or mutations | [movie-reads.md](examples/movie-reads.md) or [movie-mutations.md](examples/movie-mutations.md) |
| Complete movie dataset/setup and JOIN/performance tasks | [movies-cookbook.md](examples/movies-cookbook.md) |
| Compare retail tasks with/without JOIN | [retail-cookbook.md](examples/retail-cookbook.md) or [retail-joins-cookbook.md](examples/retail-joins-cookbook.md) |

## Five things that bite people

1. **Use `AND` / `OR` / `NOT` keywords**, not `&&` / `||` / `!`.
2. **Single and double quotes both delimit strings**; backticks delimit identifiers. `WHERE title = "x"` and `WHERE title = 'x'` are equivalent. Prefer single quotes for consistency with JSON-style examples.
3. **`= NULL` is always NULL**, not TRUE. Use `IS NULL` / `IS NOT NULL` / `IS MISSING`.
4. **`INSERT` requires an explicit `ON ID CONFLICT`** for upserts. Default is FAIL.
5. **`EVICT` is local-only and reversible** (other peers will re-sync). **`DELETE` is mesh-wide and permanent** (subject to TTL) — it writes a replicating tombstone, and is the mesh-wide delete available from an Edge SDK. Don't mix them up.

## Compatibility

This skill covers **Ditto SDK 4.14.x, 5.0.x, 5.1.x, and 5.2.0**. Every feature in the reference files is tagged with its minimum SDK version. See `references/versions.md` for the full matrix.

Rejected on every tested SDK version (verified against 4.14.6 / 5.0.3 / 5.1.0): `XOR`, `TOMBSTONE` (Big-Peer-only), `EXCLUDE MISSING` index keys, the parenthesised `USE IDS ('a', 'b')` tuple, inline `PN_COUNTER` declarations on `INSERT`, and structured `PROFILE` output. Note that multi-id `USE IDS` **does** work everywhere in its comma form (`USE IDS 'a', 'b'`).

On 4.14.x under its default strict mode, `APPLY ... INCREMENT BY` on a not-yet-existing field silently does nothing.

`DO MERGE` is supported on every tested SDK version as an alias for `DO UPDATE`. See `references/versions.md` for the full matrix.

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
└── Removing?         → EVICT (local) or DELETE (mesh) (references/statements.md)

Need to make it fast?
├── See the plan?     → EXPLAIN (references/indexing.md)
├── See timing?       → #profile directive (references/indexing.md, 5.0+)
└── Add an index?     → CREATE INDEX (references/indexing.md)
```
