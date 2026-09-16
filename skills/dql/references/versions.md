---
title: Ditto SDK version compatibility
description: Single-pane compatibility matrix for DQL features across Ditto SDK 4.14.x, 5.0.x, and 5.1.x. Every reference file's version tags ladder up to this matrix.
---

# Ditto SDK version compatibility

> All examples in this file query the `movies` / `reviews` schema documented in [`schema.md`](schema.md).

This file is the **single source of truth** for "which SDK do I need?" Every version annotation in [`operators.md`](operators.md), [`functions.md`](functions.md), [`expressions.md`](expressions.md), [`statements.md`](statements.md), [`select.md`](select.md), [`types-mutators.md`](types-mutators.md), and [`indexing.md`](indexing.md) ladders up to the tables on this page.

If you are debugging a parse error or a behavior change after upgrading, start here.

---

## 1. Supported SDK versions

| SDK version | Status                | `dql_strict_mode` default | Notes                                                                                  |
| -------- | --------------------- | ------------------------- | -------------------------------------------------------------------------------------- |
| 4.14.x   | LTS (long-term)       | `true` (strict)           | Bare object values store as `REGISTER` (last-write-wins on the whole object).          |
| 5.0.x    | Supported             | `false` (lenient)         | Bare object values store as `MAP` (per-field merge). `DO MERGE` remains an alias for `DO UPDATE`; `XOR` is unavailable. |
| 5.1.x    | Latest                | `false` (lenient)         | Adds `JOIN` (inner/left/right/multi/self), composite (multi-column) indexes, `RETURNING` on `INSERT`/`UPDATE`/`DELETE`/`EVICT`, `EXPLAIN` on DML, `INSERT … SELECT`, and `ADVISE` / `ADVISE AND PROVISION`. |

5.1.x adds `JOIN` on top of the shared `Statement` enum (`SELECT`, `INSERT`, `RETURNING`-mutations, `EXPLAIN`, `ALTER SYSTEM`, `SHOW`, `SYNC CONTEXT`, `CREATE INDEX`, `DROP INDEX`, `ADVISE`). The differences are catalogued below.

---

## 2. What shipped in v5.1.0

Verified against `@dittolive/ditto@5.1.0` by the test harness (`tests/dql/`):

- **`JOIN`** — `INNER JOIN` / `LEFT [OUTER] JOIN`, multi-join chains, self-joins, MAP-membership `ON` conditions, joins combined with `GROUP BY` / `HAVING` / aggregates. **Requires the right-side match key to be `_id` or indexed** — otherwise the engine rejects the statement and points you at `ADVISE`. See [`select.md`](select.md) §14.
- **Composite (multi-column) `CREATE INDEX`** — e.g. `CREATE INDEX movies_year_imdb ON movies (year ASC, ratings.imdb DESC)`. See [`indexing.md`](indexing.md) §§1, 8.
- **`RETURNING`** on `INSERT`, `UPDATE`, `DELETE` and `EVICT`. See [`statements.md`](statements.md) §§1.8, 2.5, 4.4, 5.4.
- **`ADVISE` / `ADVISE AND PROVISION`** — index-recommendation surface. See [`indexing.md`](indexing.md) §9.
- **`EXPLAIN` on mutations** — `EXPLAIN INSERT/UPDATE/DELETE/EVICT`. On 4.14.x and 5.0.x these raise `Explain DML is not supported`; only `EXPLAIN SELECT` works there. See [`statements.md`](statements.md) §6.
- **`INSERT INTO <coll> SELECT …`** — insert-from-select. See [`statements.md`](statements.md) §1.9.
- **`SHOW ALL LIKE / ILIKE … [ESCAPE]`** — the filter clause on `SHOW ALL`. See [`statements.md`](statements.md) §8.
- **`RIGHT [OUTER] JOIN`** alongside `INNER` / `LEFT [OUTER]`. See [`select.md`](select.md) §14.
- **`round()`, `array_sort()`, `serialize_json()`, `object_size()`** scalars. See [`functions.md`](functions.md).
- **`USE IDS` on `UPDATE` / `DELETE` / `EVICT`** — parses on mutations in 5.1.x, but `USE IDS` remains documented as a SELECT-only feature; use `WHERE _id IN (…)` for mutations on every SDK version.

Still **not** supported in 5.1.0 (verified): `XOR` (parse error on every SDK version — see §6), structured `PROFILE` output, the parenthesised-tuple `USE IDS ('a', 'b')` spelling (see §4.7), `EXCLUDE MISSING` index keys, `TOMBSTONE` in any form on a Small Peer, and `FULL OUTER` / `CROSS` joins.

---

## 3. How features land across versions

Four categories of version annotation appear throughout the reference files:

1. **Always supported** — no tag. The feature works identically on 4.14.x, 5.0.x, and 5.1.x. Example: `LIKE`, `array_contains()`, almost every scalar in [`functions.md`](functions.md), every aggregate.
2. **SDK 4.YZ+** — the feature landed in a specific 4.x dot release and requires that release or newer. The cookbook never assumes a 4.x release older than the floor noted on the feature. Example: `COUNTER` (4.14+), `PN_COUNTER` (4.11+), `DO UPDATE_LOCAL_DIFF` (4.12+).
3. **SDK 5.0+** — the feature landed in v5 and is **not** available in v4 at all. Example: quantifier expressions (`ANY/EVERY ... SATISFIES`), comprehensions (`ARRAY/OBJECT ... FOR ... END`), recursive descent via `WITHIN`, `BETWEEN`, `IN UNNEST`, hex literals, the `PROFILE` leading keyword, the `#profile` directive.
4. **SDK 5.1+** — the feature landed in 5.1.x. Example: `JOIN`, composite indexes, `RETURNING`, `ADVISE`, `EXPLAIN` on DML, `INSERT … SELECT`, `round()` / `array_sort()` / `serialize_json()` / `object_size()`.
5. **Unavailable in the tested SDK versions** — the syntax may appear in older or forward-looking documentation but is rejected by 4.14.4, 5.0.0, and 5.1.0. `XOR`, `TOMBSTONE`, `EXCLUDE MISSING` and the `USE IDS ('a','b')` tuple spelling are all in this category.

When you see a tag like "SDK 4.12+" it means: works on 4.12 through 4.14.x **and** on 5.0.x and 5.1.x. "SDK 5.0+" means 5.0.x and newer only — it will parse-error on any 4.x release. "SDK 5.1+" means 5.1.x only.

---

## 4. Feature matrix (summary)

> **How to read the ✓/✗ columns.** A ✓ means the statement is accepted *and does what it says* on a local Small Peer. Where a feature parses but misbehaves, the cell is marked ⚠ and the Notes column says why — a parse-level ✓ that silently corrupts your data is worse than a ✗.

### 4.1 Top-level statements

| Statement                                | 4.14.x | 5.0.x | 5.1.x | Notes                                                                                             |
| ---------------------------------------- | :----: | :---: | :---: | ------------------------------------------------------------------------------------------------- |
| `SELECT` / `WITH`                        |   ✓    |   ✓   |   ✓   | Identical surface.                                                                                |
| `INSERT INTO COLLECTION`                 |   ✓    |   ✓   |   ✓   | `INITIAL DOCUMENTS` and standard `DOCUMENTS` both supported.                                      |
| `INSERT INTO <coll> SELECT …`            |   ✗    |   ✗   |   ✓   | Insert-from-select. Parse error (`expected DOCUMENTS or VALUES`) on 4.14.x / 5.0.x. See [`statements.md`](statements.md) §1.9. |
| `UPDATE COLLECTION ... SET/UNSET/APPLY`  |   ✓    |   ✓   |   ✓   | See [`statements.md`](statements.md) §2 and [`types-mutators.md`](types-mutators.md).             |
| `EVICT FROM`                             |   ✓    |   ✓   |   ✓   | Local-only purge; no tombstone.                                                                   |
| `DELETE FROM`                            |   ✓    |   ✓   |   ✓   | Logical delete; produces tombstone.                                                               |
| `TOMBSTONE FROM`                         |   ✗    |   ✗   |   ✗   | **Rejected on every tested SDK version** with `Tombstone is not supported` — it is a deprecated Big-Peer-only statement and the Small Peer refuses it after parsing. Use `DELETE`. |
| `ALTER SYSTEM SET/RESET <param>`         |   ✓    |   ✓   |   ✓   | Used to flip `dql_strict_mode` and other engine flags.                                            |
| `SHOW <param>` / `SHOW ALL`              |   ✓    |   ✓   |   ✓   | `SHOW INDEXES` is **not** present on any SDK version.                                                    |
| `SHOW ALL LIKE/ILIKE … [ESCAPE …]`       |   ✗    |   ✗   |   ✓   | The filter clause is 5.1-only; parse error on 4.14.x / 5.0.x. Case-sensitive. See [`statements.md`](statements.md) §8. |
| `SYNC CONTEXT ... SELECT/SHOW`           |   ✓    |   ✓   |   ✓   | Remote query wrapper. Big Peer only — not executable from a Small Peer.                           |
| `CREATE INDEX [IF NOT EXISTS]`           |   ✓    |   ✓   |   ✓   | Single-column and nested-path. Composite is 5.1-only — see §4.7.                                  |
| `DROP INDEX [IF EXISTS]`                 |   ✓    |   ✓   |   ✓   |                                                                                                   |
| `EXPLAIN SELECT`                         |   ✓    |   ✓   |   ✓   | Plan inspection without execution.                                                                |
| `EXPLAIN` on DML (`INSERT`/`UPDATE`/`DELETE`/`EVICT`) | ✗ | ✗ |   ✓   | 4.14.x / 5.0.x raise `Explain DML is not supported`. See [`statements.md`](statements.md) §6.     |
| `PROFILE <stmt>`                         |   ✗    |   ✓   |   ✓   | **SDK 5.0+**. Leading keyword form; sets `#profile` on the request.                               |
| `ADVISE <stmt>` / `ADVISE AND PROVISION` |   ✗    |   ✗   |   ✓   | Parse error on 4.14.x / 5.0.x. See [`indexing.md`](indexing.md) §9.                               |
| `INNER JOIN` / `LEFT [OUTER] JOIN`       |   ✗    |   ✗   |   ✓   | Right-side match key must be `_id` or indexed. See [`select.md`](select.md) §14.                  |
| `RIGHT [OUTER] JOIN`                     |   ✗    |   ✗   |   ✓   | Works and is fully functional on 5.1.x. `FULL OUTER` and `CROSS` are rejected on every SDK version.       |
| `RETURNING` on `INSERT` / `UPDATE`       |   ✗    |   ✗   |   ✓   | See [`statements.md`](statements.md) §§1.8, 2.5.                                                  |
| `RETURNING` on `DELETE` / `EVICT`        |   ✗    |   ✗   |   ✓   | See [`statements.md`](statements.md) §§4.4, 5.4.                                                  |

### 4.2 `INSERT ... ON ID CONFLICT` actions

| Action                          | 4.14.x | 5.0.x | 5.1.x | Notes                                                            |
| ------------------------------- | :----: | :---: | :---: | ---------------------------------------------------------------- |
| `FAIL` (default)                |   ✓    |   ✓   |   ✓   | Default when omitted.                                            |
| `DO NOTHING`                    |   ✓    |   ✓   |   ✓   |                                                                  |
| `DO UPDATE`                     |   ✓    |   ✓   |   ✓   | Canonical name.                                                  |
| `DO UPDATE_LOCAL_DIFF`          |   ✓    |   ✓   |   ✓   | **SDK 4.12+**. AST variant `DoUpdateDifferent`.                  |
| `DO MERGE`                      |   ✓    |   ✓   |   ✓   | Alias for `DO UPDATE` on every tested SDK version; not a distinct mode. |

### 4.3 Expressions

| Construct                                  | 4.14.x | 5.0.x | 5.1.x | Notes                                                                       |
| ------------------------------------------ | :----: | :---: | :---: | ----------------------------------------------------------------------------- |
| Literals (string, number, bool, null)      |   ✓    |   ✓   |   ✓   |                                                                             |
| Hex integer literal `0xff`                 |   ✗    |   ✓   |   ✓   | **SDK 5.0+**. 4.14.x raises `X'ff' is not supported`.                        |
| Array literal `[1, 2, …]`                  |   ✓    |   ✓   |   ✓   |                                                                             |
| Object literal `{'k': v, …}`               |   ✓    |   ✓   |   ✓   |                                                                             |
| Identifiers, backticked identifiers        |   ✓    |   ✓   |   ✓   |                                                                             |
| Path expressions `a.b.c`, `arr[i]`         |   ✓    |   ✓   |   ✓   |                                                                             |
| Parameter binding `:name`                  |   ✓    |   ✓   |   ✓   |                                                                             |
| `CAST` / `TRY_CAST` / `SAFE_CAST`          |   ✓    |   ✓   |   ✓   |                                                                             |
| `CASE` (simple + searched)                 |   ✗    |   ✓   |   ✓   | **SDK 5.0+** only. v4 raises "… is not supported".                          |
| `EXISTS (SELECT …)` / scalar subquery      |   ✓    |   ✓   |   ✓   |                                                                             |
| `ARRAY(SELECT …)` array subquery           |   ✓    |   ✓   |   ✓   |                                                                             |
| `EXTRACT`, `POSITION`, `SUBSTRING`, `TRIM`, `OVERLAY` | ✓ | ✓ |   ✓   | Standard SQL string forms.                                                  |
| `INTERVAL` literals                        |   ✓    |   ✓   |   ✓   |                                                                             |
| `AT TIME ZONE 'tz'`                        |   ✓    |   ✓   |   ✓   |                                                                             |
| `ANY … IN … SATISFIES … END`               |   ✗    |   ✓   |   ✓   | **SDK 5.0+**. Existential quantifier. v4 alternative: `array_contains()`.    |
| `EVERY … IN … SATISFIES … END`             |   ✗    |   ✓   |   ✓   | **SDK 5.0+**. Universal quantifier (empty source is vacuously true).         |
| `ANY AND EVERY … IN … SATISFIES … END`     |   ✗    |   ✓   |   ✓   | **SDK 5.0+**. Like `EVERY` but empty source returns `FALSE`.                 |
| `WITHIN` in a quantifier                   |   ✗    |   ✓   |   ✓   | **SDK 5.0+**. Recurses into nested arrays/objects.                           |
| `WITHIN` in a comprehension (`ARRAY x FOR x WITHIN …`) | ✗ | ✗ |   ✓   | **SDK 5.1+** — later than the quantifier form.                              |
| `ARRAY expr FOR var IN src [WHEN c] END`   |   ✗    |   ✓   |   ✓   | **SDK 5.0+**. Array comprehension.                                          |
| `OBJECT k:v FOR var IN src [WHEN c] END`   |   ✗    |   ✓   |   ✓   | **SDK 5.0+**. Object comprehension.                                         |

### 4.4 CRDT types

| Type          | Min SDK | 4.14.x | 5.0.x | 5.1.x | Notes                                                                            |
| ------------- | ------- | :----: | :---: | :---: | -------------------------------------------------------------------------------- |
| `REGISTER`    | 4.x     |   ✓    |   ✓   |   ✓   | Default for scalars; default for objects under `dql_strict_mode = true`.         |
| `MAP`         | 4.x     |   ✓    |   ✓   |   ✓   | Default for objects under `dql_strict_mode = false` (5.x default).               |
| `ATTACHMENT`  | 4.x     |   ✓    |   ✓   |   ✓   | Binary blob; handle merges as `REGISTER`, bytes content-addressed.               |
| `COUNTER`     | 4.14+   |   ✓    |   ✓   |   ✓   | Mutators: `APPLY … INCREMENT BY` / `APPLY … RESTART [WITH]`. Declarable on `INSERT`. |
| `PN_COUNTER`  | 4.11+   |   ✓    |   ✓   |   ✓   | Mutator: `APPLY … PN_INCREMENT BY`. No `RESTART`. **Cannot be declared on an inline `INSERT`** on any SDK version — see [`types-mutators.md`](types-mutators.md) §4. |

See [`types-mutators.md`](types-mutators.md) for full semantics and the "COUNTER vs PN_COUNTER" decision table.

### 4.5 Operators with cross-version differences

| Operator                                | 4.14.x | 5.0.x | 5.1.x | Notes                                                                                |
| --------------------------------------- | :----: | :---: | :---: | -------------------------------------------------------------------------------------- |
| `XOR` (binary logical)                  |   ✗    |   ✗   |   ✗   | **Rejected on every tested SDK version.** 4.14.x: `XOR is not supported`; 5.0.x / 5.1.x: `No infix parser for token XOR`. Decompose: `a XOR b` ≡ `(a OR b) AND NOT (a AND b)`. See [`operators.md`](operators.md) §11. |
| `BETWEEN` / `NOT BETWEEN`               |   ✗    |   ✓   |   ✓   | **SDK 5.0+**. 4.14.x raises "… is not supported" — rewrite as `>= low AND <= high`.    |
| `IN UNNEST([…])`                        |   ✗    |   ✓   |   ✓   | **SDK 5.0+**.                                                                          |
| Bitwise `&` / `\|` / `^` (as binary ops) |   ✗    |   ✗   |   ✗   | Intentionally **not** documented in the cross-version reference files.                  |

All other operators (`+`, `-`, `*`, `/`, `%`, comparison family, `LIKE` / `ILIKE` / `SIMILAR TO`, `IN`, `IS NULL` / `IS MISSING` / `IS DISTINCT FROM` / `IS TRUE` / `IS FALSE` / `IS UNKNOWN`, `AND`, `OR`, `NOT`, string concat `||`) are identical on all three SDK versions.

### 4.6 Scalar and aggregate functions

| Group                                                                | 4.14.x | 5.0.x | 5.1.x | Notes                                                                       |
| -------------------------------------------------------------------- | :----: | :---: | :---: | ----------------------------------------------------------------------------- |
| Every scalar catalogued in [`functions.md`](functions.md) §11         |   ✓    |   ✓   |   ✓   | All 74 catalogued names resolve on all three SDK versions (harness-verified).      |
| All aggregates (`count`, `sum`, `min`, `max`, `avg`, `mid`, `median`) |   ✓    |   ✓   |   ✓   | Identical on all three SDK versions.                                               |
| `round()`                                                            |   ✗    |   ✗   |   ✓   | **5.1.x only.** Not in the §11 catalogue.                                   |
| `array_sort()`                                                       |   ✗    |   ✗   |   ✓   | **5.1.x only.** Not in the §11 catalogue.                                   |
| `serialize_json()`                                                   |   ✗    |   ✗   |   ✓   | **5.1.x only.** Until then, render JSON in the application layer.            |
| `object_size()`                                                      |   ✗    |   ✗   |   ✓   | **5.1.x only.**                                                             |

### 4.7 Indexing and planner directives

| Feature                                            | 4.14.x | 5.0.x | 5.1.x | Notes                                                                       |
| -------------------------------------------------- | :----: | :---: | :---: | ----------------------------------------------------------------------------- |
| `CREATE INDEX [IF NOT EXISTS]`, single-column      |   ✓    |   ✓   |   ✓   | Both `… name ON coll (keys)` and `… coll.name (keys)` spellings work.        |
| `CREATE INDEX` on a nested path (`ratings.imdb`)   |   ✓    |   ✓   |   ✓   |                                                                             |
| `CREATE INDEX` composite (multi-column)            |   ✗    |   ✗   |   ✓   | 4.14.x / 5.0.x: `not implemented yet : composite indexes` (runtime, not parse). |
| `INCLUDE MISSING` / `EXCLUDE MISSING` index keys   |   ✗    |   ✗   |   ✗   | **Rejected on every tested SDK version** (`not implemented yet`). See [`indexing.md`](indexing.md) §1.2. |
| `DROP INDEX [IF EXISTS]`                           |   ✓    |   ✓   |   ✓   | Both spellings.                                                             |
| `#index`, `#max_scans`, `#max_inlist`, `#intersects`, `#prefer_order`, `#disable_index_scan` | ✓ | ✓ | ✓ | The six directives present in the 4.14 planner.                             |
| `#max_serial_ranges`, `#disable_covering`, `#disable_special`, `#disable_intersect_eo`, `#auto_use_ids`, `#reprepare` | ✗ | ✓ | ✓ | **SDK 5.0+.** Absent from the 4.14 planner registry — see the warning below. |
| `#profile` planner directive                       |   ✗    |   ✓   |   ✓   | 4.14 defines the key but emits no profile row; 5.0+ emits `~request_profile`. |
| `USE IDS 'a'` / `USE IDS 'a', 'b'` on `SELECT`     |   ✓    |   ✓   |   ✓   | Comma-separated multi-id **works on every SDK version**.                           |
| `USE IDS ('a', 'b')` (parenthesised tuple)         |   ✗    |   ✗   |   ✗   | Rejected everywhere — it parses as one tuple expression. Use the comma form. |
| `USE IDS LIST ['a', 'b']`                          |   ✗    |   ✓   |   ✓   | **SDK 5.0+**.                                                               |
| Automatic `_id` equality rewrite                   |   ✗    |   ✓   |   ✓   | 5.0+: `WHERE _id = '…'` rewrites to `idScan`. 5.1.x also rewrites `WHERE _id IN (…)`. |
| `USE IDS` on `UPDATE`                              |   ✗    |   ✗   |   ✓   | 5.1.x only, and **only before `SET`** (`UPDATE coll USE IDS 'x' SET …`). Applies correctly. |
| `USE IDS` on `DELETE` / `EVICT`                    |   ✗    |   ✗   |   ✗   | Parse error on 4.14.x / 5.0.x; not supported on mutations. Use `WHERE _id IN (…)`. |
| `USE IDS` on `TOMBSTONE`                           |   ✗    |   ✗   |   ✗   | `TOMBSTONE` itself is unavailable on every SDK version.                            |
| `ADVISE` / `ADVISE AND PROVISION`                  |   ✗    |   ✗   |   ✓   | See [`indexing.md`](indexing.md) §9.                                        |

> **Planner directives fail silently.** An unrecognised directive — including a misspelling, an unknown collection name, or a wrong-typed value — is **accepted without error and ignored** on every version. "It didn't error" therefore proves nothing about support. The only reliable check is to diff `EXPLAIN` plans against the same query without the directive: a honoured directive changes the plan shape, an ignored one leaves it byte-identical.

### 4.8 Subscription-query restrictions

Subscriptions are validated at `registerSubscription()` time, synchronously, before sync starts.

| Restriction                                   | 4.14.x | 5.0.x | 5.1.x | Effect                                                                            |
| --------------------------------------------- | :----: | :---: | :---: | ----------------------------------------------------------------------------------- |
| V1 surface only (`SELECT *`, one collection, no `DISTINCT` / `GROUP BY` / `HAVING` / `USE IDS` / JOIN) | ✓ | ✓ | ✓ | Always on for `registerSubscription`. |
| `ORDER BY` / `LIMIT` rejected                 |   ✗    |   ✓   |   ✓   | **SDK 5.0+**. `OFFSET` alone stays legal on every SDK version. See [`select.md`](select.md) §12. |

> These restrictions are **not** settable engine parameters. `DQL_RESTRICT_TO_ORIGINAL_SYNTAX` and `DQL_RESTRICT_LIMIT_ORDER_BY` are internal Rust bitflags (`crates/ditto-dql/src/engine/mod.rs`) set by the subscription code path — `SHOW` and `ALTER SYSTEM SET` both reject those names on every version. The user-facing knob is **`dql_restrict_subscriptions`** (default `true`), which exists on 5.0.x and 5.1.x and **not** on 4.14.x.

---

## 5. Defaults that flip between versions

This is the most user-visible cross-version difference and the most likely cause of "it worked on my old SDK, why is it different now?" — see [`types-mutators.md`](types-mutators.md) §7 for the full discussion.

| Behavior                                   | 4.14.x default                            | 5.0.x default                             | 5.1.x default                             |
| ------------------------------------------ | ----------------------------------------- | ----------------------------------------- | ----------------------------------------- |
| `dql_strict_mode` (user-facing knob)       | `true` (strict)                           | `false` (lenient)                         | `false` (lenient)                         |
| Bare object value on `INSERT` / `UPDATE`   | stored as `REGISTER` (whole-object LWW)   | stored as `MAP` (per-field merge)         | stored as `MAP` (per-field merge)         |
| `DQL_MUTATOR_OBJECTS_AS_MAPS` (internal flag, derived from strict mode) | OFF (`false`)            | ON (`true`)                               | ON (`true`)                               |
| Explicit type definition required for `MAP`? | Yes — without it, strict mode picks `REGISTER` | No — lenient picks `MAP` by default, but declaring is still recommended | No — same as 5.0.x |

**Portability rule:** the recommended end-state is `dql_strict_mode = false` on every peer (the 5.x default) — flip 4.x peers before upgrading them. While strict 4.x peers remain in a mixed mesh, declare types explicitly with the `INTO COLLECTION coll (field MAP, …)` syntax on every statement those peers execute that touches a non-`REGISTER` field; strict peers can't see undeclared non-REGISTER fields, on reads either.

---

## 6. `XOR` is unavailable; `DO MERGE` aliases `DO UPDATE`

- **`XOR` operator.** The docs once listed `XOR` as v4-only; the harness shows 4.14.4, 5.0.0, **and** 5.1.0 all reject it (`XOR is not supported` / `No infix parser`). Treat `XOR` as unavailable everywhere until it actually ships. **Workaround:** `a XOR b` ≡ `(a OR b) AND NOT (a AND b)`. See [`operators.md`](operators.md) §11.
- **`INSERT ... ON ID CONFLICT DO MERGE`.** SDK 4.14.4, 5.0.0, and 5.1.0 all accept `MERGE` and map it to the same action as `DO UPDATE`. It is a portable alias, not a distinct merge mode. Prefer `DO UPDATE` as the canonical spelling. See [`statements.md`](statements.md) §1.6.

---

## 7. Detecting your SDK version

Two angles. Combine them when you're not sure.

### 7.1 Check the Ditto SDK package version

The most reliable signal is the Ditto SDK dependency version in your host application. Where to look:

- **Swift / iOS:** `Package.swift` (the `DittoSwift` / `DittoObjC` dependency) or your `Podfile`.
- **Android / Kotlin:** `build.gradle.kts` or `build.gradle` — the `live.ditto:ditto` dependency line.
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
- [`functions.md`](functions.md) — every scalar function (all three SDK versions) and aggregate, plus the 5.1-only scalars.
- [`expressions.md`](expressions.md) — literals, quantifiers (`ANY`/`EVERY ... SATISFIES`), comprehensions (`ARRAY/OBJECT ... FOR ... END`), `WITHIN`.
- [`statements.md`](statements.md) — `DO UPDATE_LOCAL_DIFF` (4.12+), `COUNTER` (4.14+), `PN_COUNTER` (4.11+), `PROFILE` (5.0+), `RETURNING` / `INSERT … SELECT` / DML `EXPLAIN` (5.1+), the `DO MERGE` cross-version note.
- [`select.md`](select.md) — `JOIN` (5.1+) and the subscription restrictions.
- [`types-mutators.md`](types-mutators.md) — the canonical writeup of the strict-mode flip.
- [`indexing.md`](indexing.md) — `#profile` (5.0+), composite indexes and `ADVISE` (5.1+).
