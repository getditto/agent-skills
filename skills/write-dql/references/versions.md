---
title: Ditto SDK version compatibility
description: Single-pane compatibility matrix for DQL features across Ditto SDK 4.14.x, 5.0.x, 5.1.x and 5.2.0. Every reference file's version tags ladder up to this matrix.
---

# Ditto SDK version compatibility

## Contents

- [1. Supported SDK versions](#1-supported-sdk-versions)
- [2. What shipped in v5.1.0](#2-what-shipped-in-v510)
- [3. How features land across versions](#3-how-features-land-across-versions)
- [4. Feature matrix (summary)](#4-feature-matrix-summary)
- [8. Why this matters](#8-why-this-matters)
- [9. See also](#9-see-also)

> All examples in this file query the `movies` / `reviews` schema documented in [`schema.md`](schema.md).

This file is the **single source of truth** for "which SDK do I need?" Every version annotation in [`operators.md`](operators.md), [`functions.md`](functions.md), [`expressions.md`](expressions.md), [`statements.md`](statements.md), [`select.md`](select.md), [`types-mutators.md`](types-mutators.md), and [`indexing.md`](indexing.md) ladders up to the tables on this page.

If you are debugging a parse error or a behavior change after upgrading, start here.

---

## 1. Supported SDK versions

| SDK version | Status                | `dql_strict_mode` default | Notes                                                                                  |
| -------- | --------------------- | ------------------------- | -------------------------------------------------------------------------------------- |
| 4.14.x   | LTS (long-term)       | `true` (strict)           | Bare object values store as `REGISTER` (last-write-wins on the whole object).          |
| 5.0.x    | Supported             | `false` (lenient)         | Bare object values store as `MAP` (per-field merge). `DO MERGE` remains an alias for `DO UPDATE`; `XOR` is unavailable. |
| 5.1.x    | Supported                | `false` (lenient)         | Adds `JOIN` (inner/left/right/multi/self), composite (multi-column) indexes, `RETURNING` on `INSERT`/`UPDATE`/`DELETE`/`EVICT`, `EXPLAIN` on DML, `INSERT … SELECT`, and `ADVISE` / `ADVISE AND PROVISION`. |

5.1.x adds `JOIN` on top of the shared `Statement` enum (`SELECT`, `INSERT`, `RETURNING`-mutations, `EXPLAIN`, `ALTER SYSTEM`, `SHOW`, `SYNC CONTEXT`, `CREATE INDEX`, `DROP INDEX`, `ADVISE`). The differences are catalogued below.

---

## SDK 5.2.0

Latest known baseline: **5.2.0**, with lenient strict-mode default (`false`).
The 5.1 features below remain available. [sdk-5.2.md](sdk-5.2.md) covers corrected
`DELETE`/`EVICT USE IDS`, index/quantifier fixes, system diagnostics and startup
configuration. Compatibility tables include 5.2.0; historical execution claims keep
their original versions. Source: <https://docs.ditto.live/sdk/latest/release-notes-hub/swift> (5.2.0 common changes).

## 2. What shipped in v5.1.0

Verified against `@dittolive/ditto@5.1.0` by the repository's DQL test harness:

- **`JOIN`** — `INNER JOIN` / `LEFT [OUTER] JOIN`, multi-join chains, self-joins, MAP-membership `ON` conditions, joins combined with `GROUP BY` / `HAVING` / aggregates. **Requires the right-side match key to be `_id` or indexed** — otherwise the engine rejects the statement and points you at `ADVISE`. See [`select.md`](select.md) §14.
- **Composite (multi-column) `CREATE INDEX`** — e.g. `CREATE INDEX movies_year_imdb ON movies (year ASC, ratings.imdb DESC)`. See [`indexing.md`](indexing.md) §§1, 8.
- **`RETURNING`** on `INSERT`, `UPDATE`, `DELETE` and `EVICT`. See [`statements.md`](statements.md) §§1.8, 2.5, 4.4, 5.4.
- **`ADVISE` / `ADVISE AND PROVISION`** — index-recommendation surface. See [`indexing.md`](indexing.md) §9.
- **`EXPLAIN` on mutations** — `EXPLAIN INSERT/UPDATE/DELETE/EVICT`. On 4.14.x and 5.0.x these raise `Explain DML is not supported`; only `EXPLAIN SELECT` works there. See [`statements.md`](statements.md) §6.
- **`INSERT INTO <coll> SELECT …`** — insert-from-select. See [`statements.md`](statements.md) §1.9.
- **`SHOW ALL LIKE / ILIKE … [ESCAPE]`** — the filter clause on `SHOW ALL`. See [`statements.md`](statements.md) §8.
- **`RIGHT [OUTER] JOIN`** alongside `INNER` / `LEFT [OUTER]`. See [`select.md`](select.md) §14.
- **`round()`, `array_sort()`, `serialize_json()`, `object_size()`** scalars. See [`functions.md`](functions.md).
- **`USE IDS` on `UPDATE` / `DELETE` / `EVICT`** — parses on mutations in 5.1.x, but `DELETE`/`EVICT USE IDS` do not remove documents on 5.1.0. Fixed in 5.2.0; use `WHERE _id IN (…)` when supporting older releases.

Still **not** supported in 5.1.0 (verified): `XOR` (parse error on every SDK version — see §6), structured `PROFILE` output, the parenthesised-tuple `USE IDS ('a', 'b')` spelling (see §4.7), `EXCLUDE MISSING` index keys, `TOMBSTONE` in any form on a Small Peer, and `FULL OUTER` / `CROSS` joins.

---

## 3. How features land across versions

Version annotations appear throughout the reference files:

1. **Always supported** — no tag. The feature works identically on 4.14.x, 5.0.x, 5.1.x and 5.2.0. Example: `LIKE`, `array_contains()`, almost every scalar in [`functions.md`](functions.md), every aggregate.
2. **SDK 4.YZ+** — the feature landed in a specific 4.x dot release and requires that release or newer. The cookbook never assumes a 4.x release older than the floor noted on the feature. Example: `COUNTER` (4.14+), `PN_COUNTER` (4.11+), `DO UPDATE_LOCAL_DIFF` (4.12+).
3. **SDK 5.0+** — the feature landed in v5 and is **not** available in v4 at all. Example: quantifier expressions (`ANY/EVERY ... SATISFIES`), comprehensions (`ARRAY/OBJECT ... FOR ... END`), recursive descent via `WITHIN`, `BETWEEN`, `IN UNNEST`, hex literals, the `PROFILE` leading keyword, the `#profile` directive.
4. **SDK 5.1+** — the feature landed in 5.1.x. Example: `JOIN`, composite indexes, `RETURNING`, `ADVISE`, `EXPLAIN` on DML, `INSERT … SELECT`, `round()` / `array_sort()` / `serialize_json()` / `object_size()`.
5. **Unavailable in the tested SDK versions** — the syntax may appear in older or forward-looking documentation but is rejected by 4.14.6, 5.0.3, and 5.1.0. `XOR`, `TOMBSTONE`, `EXCLUDE MISSING` and the `USE IDS ('a','b')` tuple spelling are all in this category.

When you see a tag like "SDK 4.12+" it means: works on 4.12 through 4.14.x **and** on 5.0.x and 5.1.x. "SDK 5.0+" means 5.0.x and newer only — it will parse-error on any 4.x release. "SDK 5.1+" includes 5.1.x and 5.2.0. “SDK 5.2+” requires 5.2.0 or newer.

---

## 4. Feature matrix (summary)

> **How to read the ✓/✗ columns.** A ✓ means the statement is accepted *and does what it says* on a local Small Peer. Where a feature parses but misbehaves, the cell is marked ⚠ and the Notes column says why — a parse-level ✓ that silently corrupts your data is worse than a ✗.

### 4.1 Top-level statements

See [compatibility-statements.md](compatibility-statements.md#41-top-level-statements) for this topic.

### 4.2 `INSERT ... ON ID CONFLICT` actions

See [compatibility-statements.md](compatibility-statements.md#42-insert--on-id-conflict-actions) for this topic.

### 4.3 Expressions

See [compatibility-expressions.md](compatibility-expressions.md#43-expressions) for this topic.

### 4.4 CRDT types

See [compatibility-types-sync.md](compatibility-types-sync.md#44-crdt-types) for this topic.

### 4.5 Operators with cross-version differences

See [compatibility-expressions.md](compatibility-expressions.md#45-operators-with-cross-version-differences) for this topic.

### 4.6 Scalar and aggregate functions

See [compatibility-expressions.md](compatibility-expressions.md#46-scalar-and-aggregate-functions) for this topic.

### 4.7 Indexing and planner directives

See [compatibility-statements.md](compatibility-statements.md#47-indexing-and-planner-directives) for this topic.

### 4.8 Subscription-query restrictions

See [compatibility-types-sync.md](compatibility-types-sync.md#48-subscription-query-restrictions) for this topic.

### 7.1 Check the Ditto SDK package version

The most reliable signal is the Ditto SDK dependency version in your host application. Where to look:

- **Swift / iOS:** `Package.swift` (the `DittoSwift` / `DittoObjC` dependency) or your `Podfile`.
- **Android / Kotlin:** `build.gradle.kts` or `build.gradle` — the `com.ditto:ditto-kotlin` dependency (v5) or `live.ditto:ditto` (v4), including version catalogs.
- **JavaScript / TypeScript:** `package.json` — the `@dittolive/ditto` entry.
- **Rust:** `Cargo.toml` — the `dittolive-ditto` crate version.
- **C# / .NET:** the `Ditto` NuGet package version.
- **C / C++:** the `ditto.h` header or the library build artifact.

A version starting with `4.` (e.g. `4.14.3`) means 4.x lenient/strict surface as described above. A version starting with `5.0.` means v5.0.x with all the v5-only features (`PROFILE`, quantifiers, comprehensions, `#profile`) and **without** `XOR`; `DO MERGE` remains an alias for `DO UPDATE`.

### 7.2 Detect the strict-mode flip from inside DQL

`dql_strict_mode` is queryable and settable at runtime, and its default is the most user-visible cross-version difference:

```sql
-- See what the engine is using right now
SHOW dql_strict_mode;

-- Returns one row: { "dql_strict_mode": <boolean> }
--   true  on a 4.14.x default install
--   false on a 5.0.x or 5.1.x default install
```

> The value is a **boolean**, not the string `"true"`. Compare with `=== true` / `== true`, not `=== "true"`.

This is **not** a perfect version check — an operator may have explicitly flipped strict mode on either version:

```sql
-- On v4.14.x: opt into the v5-style lenient default
ALTER SYSTEM SET dql_strict_mode = false;

-- On v5.0.x: opt back into the v4-style strict default
ALTER SYSTEM SET dql_strict_mode = true;
```

So use `SHOW dql_strict_mode` to confirm the **effective** mode in the running engine, but use the SDK package version (§7.1) to determine which **surface** of DQL features is available. The strict-mode flip is configurable; the feature surface (e.g. whether `PROFILE` or quantifiers parse) is determined by the SDK version itself.

---

## 8. Why this matters

Three reasons portability is worth thinking about up front.

1. **Mixed-version mesh.** Ditto peers sync directly. A document inserted by a 5.0.x peer (where a bare object becomes `MAP`) replicates to a 4.14.x peer (which would have stored it as `REGISTER` had it inserted the same document). The on-disk representation is decided by the peer that wrote it — so the same field can be `REGISTER` on one peer and `MAP` on another, even on the same network. **Always declare CRDT types explicitly** on writes that touch non-register fields.
2. **Write to the lowest common denominator.** Use the older SDK's feature surface as the baseline. Avoid `ANY/EVERY ... SATISFIES`, comprehensions, `WITHIN`, `BETWEEN`, `PROFILE`, and `#profile` unless every peer that will execute the query is on 5.0+; avoid `JOIN`, `RETURNING`, composite indexes and `ADVISE` unless every peer is on 5.1+. Rewrite `XOR` using portable logical operators. `DO MERGE` is portable, but `DO UPDATE` is the canonical spelling.
3. **Defaults are not contracts.** The flip from `dql_strict_mode = true` (v4) to `false` (v5.0) is the kind of silent behavior change that breaks code months after the upgrade, when the first concurrent write hits a field that's now a `MAP` instead of a `REGISTER`. The way to immunise your mesh is to set `dql_strict_mode = false` on 4.x peers *before* upgrading — behavior then stays identical across the jump — and to declare types on statements that still-strict peers execute during the transition.

---

## 9. See also

- [`operators.md`](operators.md) — operator precedence, comparison/logical semantics, the `XOR` cross-version note in §11.
- [`functions.md`](functions.md) — every scalar function (all three SDK versions) and aggregate, plus the 5.1+ scalars.
- [`expressions.md`](expressions.md) — literals, quantifiers (`ANY`/`EVERY ... SATISFIES`), comprehensions (`ARRAY/OBJECT ... FOR ... END`), `WITHIN`.
- [`statements.md`](statements.md) — `DO UPDATE_LOCAL_DIFF` (4.12+), `COUNTER` (4.14+), `PN_COUNTER` (4.11+), `PROFILE` (5.0+), `RETURNING` / `INSERT … SELECT` / DML `EXPLAIN` (5.1+), the `DO MERGE` cross-version note.
- [`select.md`](select.md) — `JOIN` (5.1+) and the subscription restrictions.
- [`types-mutators.md`](types-mutators.md) — the canonical writeup of the strict-mode flip.
- [`indexing.md`](indexing.md) — `#profile` (5.0+), composite indexes and `ADVISE` (5.1+).
