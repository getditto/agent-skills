---
title: Ditto SDK version compatibility
description: Single-pane compatibility matrix for DQL features across Ditto SDK 4.14.x, 5.0.x, and 5.1.x. Every reference file's version tags ladder up to this matrix.
---

# Ditto SDK version compatibility

> All examples in this file query the `movies` / `reviews` schema documented in [`schema.md`](schema.md).

This file is the **single source of truth** for "which SDK do I need?" Every version annotation in [`operators.md`](operators.md), [`functions.md`](functions.md), [`expressions.md`](expressions.md), [`statements.md`](statements.md), [`select.md`](select.md), [`types-mutators.md`](types-mutators.md), and [`indexing.md`](indexing.md) ladders up to the tables on this page.

If you are debugging a parse error or a behavior change after upgrading, start here.

---

## 1. Supported SDK lines

| SDK line | Status                | `dql_strict_mode` default | Notes                                                                                  |
| -------- | --------------------- | ------------------------- | -------------------------------------------------------------------------------------- |
| 4.14.x   | LTS (long-term)       | `true` (strict)           | Bare object values store as `REGISTER` (last-write-wins on the whole object).          |
| 5.0.x    | Supported             | `false` (lenient)         | Bare object values store as `MAP` (per-field merge). All v4 surface remains supported except `XOR` and `DO MERGE` (see §6). |
| 5.1.x    | Latest                | `false` (lenient)         | Adds `JOIN` (inner/outer/multi/self), composite (multi-column) indexes, `RETURNING` on `INSERT`/`UPDATE`, and `ADVISE` / `ADVISE AND PROVISION`. |

5.1.x adds `JOIN` on top of the shared `Statement` enum (`SELECT`, `INSERT`, `RETURNING`-mutations, `EXPLAIN`, `ALTER SYSTEM`, `SHOW`, `SYNC CONTEXT`, `CREATE INDEX`, `DROP INDEX`, `ADVISE`). The differences are catalogued below.

---

## 2. What shipped in v5.1.0

Verified against `@dittolive/ditto@5.1.0` by the test harness (`tests/dql/`):

- **`JOIN`** — `INNER JOIN` / `LEFT [OUTER] JOIN`, multi-join chains, self-joins, MAP-membership `ON` conditions, joins combined with `GROUP BY` / `HAVING` / aggregates. **Requires the right-side match key to be `_id` or indexed** — otherwise the engine rejects the statement and points you at `ADVISE`. See [`select.md`](select.md) §14.
- **Composite (multi-column) `CREATE INDEX`** — e.g. `CREATE INDEX movies_year_imdb ON movies (year ASC, ratings.imdb DESC)`. See [`indexing.md`](indexing.md) §§1, 8.
- **`RETURNING`** on `INSERT` and `UPDATE`. See [`statements.md`](statements.md) §§1.8, 2.5.
- **`ADVISE` / `ADVISE AND PROVISION`** — index-recommendation surface. See [`indexing.md`](indexing.md) §9.

Still **not** supported in 5.1.0 (verified): `XOR` (parse error on every line — see §6), structured `PROFILE` output, `serialize_json()` / `object_size()`, `USE IDS` on mutations, multi-id `USE IDS` lists, `RETURNING` on `TOMBSTONE` (Big Peer only anyway).

---

## 3. How features land across versions

Four categories of version annotation appear throughout the reference files:

1. **Always supported** — no tag. The feature works identically on 4.14.x, 5.0.x, and 5.1.x. Example: `LIKE`, `array_contains()`, almost every scalar in [`functions.md`](functions.md), every aggregate.
2. **SDK 4.YZ+** — the feature landed in a specific 4.x dot release and requires that release or newer. The cookbook never assumes a 4.x release older than the floor noted on the feature. Example: `COUNTER` (4.13+), `PN_COUNTER` (4.11+), `DO UPDATE_LOCAL_DIFF` (4.12+).
3. **SDK 5.0+** — the feature landed in v5 and is **not** available in v4 at all. Example: quantifier expressions (`ANY/EVERY ... SATISFIES`), comprehensions (`ARRAY/OBJECT ... FOR ... END`), recursive descent via `WITHIN`, the `PROFILE` leading keyword, the `#profile` directive, `DQL_RESTRICT_LIMIT_ORDER_BY`.
4. **Removed in v5.0** — the feature was in v4 but is **gone in v5.0** and may return in v5.1. Two members of this category: `XOR` (operator) and `INSERT ... ON ID CONFLICT DO MERGE`. Both will be first-class in v5.1.

When you see a tag like "SDK 4.13+" it means: works on 4.13 through 4.14.x **and** on 5.0.x. When you see "SDK 5.0+" it means: 5.0.x and newer only — will parse-error on any 4.x release.

---

## 4. Feature matrix (summary)

### 4.1 Top-level statements

| Statement                              | 4.14.x | 5.0.x | Notes                                                                                                |
| -------------------------------------- | :----: | :---: | ---------------------------------------------------------------------------------------------------- |
| `SELECT` / `WITH`                      |   ✓    |   ✓   | Identical surface.                                                                                   |
| `INSERT INTO COLLECTION`               |   ✓    |   ✓   | `INITIAL DOCUMENTS` and standard `DOCUMENTS` both supported.                                         |
| `UPDATE COLLECTION ... SET/UNSET/APPLY`|   ✓    |   ✓   | See [`statements.md`](statements.md) §2 and [`types-mutators.md`](types-mutators.md).                |
| `EVICT FROM`                           |   ✓    |   ✓   | Local-only purge; no tombstone.                                                                      |
| `DELETE FROM`                          |   ✓    |   ✓   | Logical delete; produces tombstone.                                                                  |
| `TOMBSTONE FROM`                       |   ✓    |   ✓   | Deprecated BP-only alias for `DELETE`. Prefer `DELETE`.                                              |
| `ALTER SYSTEM SET/RESET <param>`       |   ✓    |   ✓   | Used to flip `dql_strict_mode` and other engine flags.                                               |
| `SHOW <param>` / `SHOW ALL`            |   ✓    |   ✓   | Read engine flags (e.g. `SHOW dql_strict_mode`). `SHOW INDEXES` is **not** present in either line.   |
| `SYNC CONTEXT ... SELECT/SHOW`         |   ✓    |   ✓   | Remote query wrapper.                                                                                |
| `CREATE INDEX [IF NOT EXISTS]`         |   ✓    |   ✓   | See [`indexing.md`](indexing.md).                                                                    |
| `DROP INDEX [IF EXISTS]`               |   ✓    |   ✓   |                                                                                                      |
| `EXPLAIN <stmt>`                       |   ✓    |   ✓   | Plan inspection without execution.                                                                   |
| `PROFILE <stmt>`                       |   ✗    |   ✓   | **SDK 5.0+** only. Leading keyword form; sets `#profile` on the request.                             |
| `ADVISE <stmt>` / `ADVISE AND PROVISION` |  ✗    |   ✗   | Shipped in **5.1.0** (`✓`). Raises a parse error on 4.14.x and 5.0.x.                                 |
| `INNER JOIN` / `LEFT [OUTER] JOIN`       |   ✗    |   ✗   | Shipped in **5.1.0** (`✓`). Right-side match key must be `_id` or indexed. See [`select.md`](select.md) §14. |
| `CREATE INDEX` composite (multi-column)  |   ✗    |   ✗   | Shipped in **5.1.0** (`✓`). Single-column and nested-path indexes work everywhere.                    |
| `RETURNING` on `INSERT` / `UPDATE`       |   ✗    |   ✗   | Shipped in **5.1.0** (`✓`). See [`statements.md`](statements.md) §§1.8, 2.5.                          |

### 4.2 `INSERT ... ON ID CONFLICT` actions

| Action                          | 4.14.x | 5.0.x | Notes                                                                                                 |
| ------------------------------- | :----: | :---: | ----------------------------------------------------------------------------------------------------- |
| `FAIL` (default)                |   ✓    |   ✓   | Default when omitted.                                                                                 |
| `DO NOTHING`                    |   ✓    |   ✓   |                                                                                                       |
| `DO UPDATE`                     |   ✓    |   ✓   | Canonical name. Portable on both lines.                                                               |
| `DO UPDATE_LOCAL_DIFF`          |   ✓    |   ✓   | **SDK 4.12+**. AST variant `DoUpdateDifferent`.                                                       |
| `DO MERGE`                      |   ✓    |   ✗   | v4 undocumented alias for `DO UPDATE`; removed in v5.0; returns as first-class in v5.1. Avoid.        |

### 4.3 Expressions

| Construct                                  | 4.14.x | 5.0.x | Notes                                                                                  |
| ------------------------------------------ | :----: | :---: | -------------------------------------------------------------------------------------- |
| Literals (string, number, bool, null)      |   ✓    |   ✓   |                                                                                        |
| Array literal `[1, 2, …]`                  |   ✓    |   ✓   |                                                                                        |
| Object literal `{'k': v, …}`               |   ✓    |   ✓   |                                                                                        |
| Identifiers, backticked identifiers        |   ✓    |   ✓   |                                                                                        |
| Path expressions `a.b.c`, `arr[i]`         |   ✓    |   ✓   |                                                                                        |
| Parameter binding `:name`                  |   ✓    |   ✓   |                                                                                        |
| `CAST` / `TRY_CAST` / `SAFE_CAST`          |   ✓    |   ✓   |                                                                                        |
| `CASE` (simple + searched)                 |   ✗    |   ✓   | **SDK 5.0+** only (harness-verified). v4 raises "... is not supported". |                                                                                        |
| `EXISTS (SELECT …)` / scalar subquery      |   ✓    |   ✓   |                                                                                        |
| `ARRAY(SELECT …)` array subquery           |   ✓    |   ✓   |                                                                                        |
| `EXTRACT`, `POSITION`, `SUBSTRING`, `TRIM`, `OVERLAY` |   ✓    |   ✓   | Standard SQL string forms.                                                  |
| `INTERVAL` literals                        |   ✓    |   ✓   |                                                                                        |
| `AT TIME ZONE 'tz'`                        |   ✓    |   ✓   |                                                                                        |
| `ANY … IN … SATISFIES … END`               |   ✗    |   ✓   | **SDK 5.0+**. Existential quantifier. v4 alternative: `array_contains()`.              |
| `EVERY … IN … SATISFIES … END`             |   ✗    |   ✓   | **SDK 5.0+**. Universal quantifier (empty source is vacuously true).                   |
| `ANY AND EVERY … IN … SATISFIES … END`     |   ✗    |   ✓   | **SDK 5.0+**. Like `EVERY` but empty source returns `FALSE`.                           |
| `WITHIN` (recursive descent in quantifier) |   ✗    |   ✓   | **SDK 5.0+**. Recurses into nested arrays/objects.                                     |
| `ARRAY expr FOR var IN src [WHEN c] END`   |   ✗    |   ✓   | **SDK 5.0+**. Array comprehension.                                                     |
| `OBJECT k:v FOR var IN src [WHEN c] END`   |   ✗    |   ✓   | **SDK 5.0+**. Object comprehension.                                                    |

### 4.4 CRDT types

| Type          | Min SDK | 4.14.x | 5.0.x | Notes                                                                            |
| ------------- | ------- | :----: | :---: | -------------------------------------------------------------------------------- |
| `REGISTER`    | 4.x     |   ✓    |   ✓   | Default for scalars; default for objects under `dql_strict_mode = true`.         |
| `MAP`         | 4.x     |   ✓    |   ✓   | Default for objects under `dql_strict_mode = false` (v5.0 default).              |
| `ATTACHMENT`  | 4.x     |   ✓    |   ✓   | Binary blob; handle merges as `REGISTER`, bytes content-addressed.               |
| `COUNTER`     | 4.13+   |   ✓    |   ✓   | State-based counter. Mutator: `APPLY ... INCREMENT BY` / `APPLY ... RESTART [WITH]`. |
| `PN_COUNTER`  | 4.11+   |   ✓    |   ✓   | Legacy positive-negative counter. Mutator: `APPLY ... PN_INCREMENT BY`. No `RESTART`. |

See [`types-mutators.md`](types-mutators.md) for full semantics and the "COUNTER vs PN_COUNTER" decision table.

### 4.5 Operators with cross-version differences

| Operator                                | 4.14.x | 5.0.x | Notes                                                                                |
| --------------------------------------- | :----: | :---: | ------------------------------------------------------------------------------------ |
| `XOR` (binary logical)                  |   ✓    |   ✗   | v4 only; v5.0 tokenises the keyword but no operator AST variant exists, so it raises a parse error. v5.1 reintroduces it. Decompose: `a XOR b` ≡ `(a OR b) AND NOT (a AND b)`. See [`operators.md`](operators.md) §11. |
| Bitwise `&` / `|` / `^` (as binary ops) |   ✓    |   ✗   | v4 has `BitwiseOr` / `BitwiseAnd` AST variants; v5 has neither. Bitwise ops are intentionally **not** documented in the cross-version reference files. |

All other operators (`+`, `-`, `*`, `/`, `%`, comparison family, `LIKE` / `ILIKE` / `SIMILAR TO`, `IN`, `IS NULL` / `IS MISSING` / `IS DISTINCT FROM` / `IS TRUE` / `IS FALSE` / `IS UNKNOWN`, `AND`, `OR`, `NOT`, string concat `||`) are identical on both lines. **`BETWEEN` / `NOT BETWEEN` are SDK 5.0+** (harness-verified): v4 raises "... NOT supported" — rewrite as `>= low AND <= high` for cross-version code.

### 4.6 Scalar and aggregate functions

| Group        | 4.14.x | 5.0.x | Notes                                                                                                                       |
| ------------ | :----: | :---: | --------------------------------------------------------------------------------------------------------------------------- |
| All scalars catalogued in [`functions.md`](functions.md) |   ✓    |   ✓   | Every function in the catalog exists in both lines (audit grep-confirmed line-for-line identical scalar table). |
| All aggregates (`count`, `sum`, `min`, `max`, `avg`, `mid`, `median`) |   ✓    |   ✓   | Identical aggregate file in both lines.                                          |
| `serialize_json()`                                       |   ✗    |   ✗   | **v5.1.0** only. Until then, render JSON in the application layer.                                              |
| `object_size()`                                          |   ✗    |   ✗   | **v5.1.0** only.                                                                                                |

### 4.7 Indexing and planner directives

| Feature                                            | 4.14.x | 5.0.x | Notes                                                                          |
| -------------------------------------------------- | :----: | :---: | ------------------------------------------------------------------------------ |
| `CREATE INDEX [IF NOT EXISTS] coll.name(keys…)`    |   ✓    |   ✓   |                                                                                |
| `DROP INDEX [IF EXISTS] coll.name`                 |   ✓    |   ✓   |                                                                                |
| Per-collection planner directives (`#prefer_order`, `#intersects`, `#index`, `#max_scans`, `#max_inlist`, `#max_serial_ranges`) | ✓ | ✓ | See [`indexing.md`](indexing.md) §3. |
| Top-level planner directives (`#disable_index_scan`, `#disable_covering`, `#disable_special`, `#disable_intersect_eo`, `#auto_use_ids`, `#reprepare`) | ✓ | ✓ | |
| `#profile` planner directive                       |   ✗    |   ✓   | **SDK 5.0+**. v4 has no `PROFILE`/`profile` token in the parser.               |
| `USE IDS (…)` on `SELECT`                          |   ✓    |   ✓   |                                                                                |
| `USE IDS (…)` on `UPDATE` / `DELETE` / `EVICT` / `TOMBSTONE` | ✗ | ✗   | Parser TODO in both lines. v5.1+ may add.                                      |
| `ADVISE` / `ADVISE AND PROVISION`                  |   ✗    |   ✗   | **v5.1.0** only. See [`indexing.md`](indexing.md) §9 for today's workaround.   |

### 4.8 Subscription-query restrictions

| Engine flag                       | 4.14.x | 5.0.x | Effect                                                                                              |
| --------------------------------- | :----: | :---: | --------------------------------------------------------------------------------------------------- |
| `DQL_RESTRICT_TO_ORIGINAL_SYNTAX` |   ✓    |   ✓   | Subscriptions limited to V1 surface: `SELECT *`, no projection, no `USE IDS`, no `DISTINCT`.        |
| `DQL_RESTRICT_LIMIT_ORDER_BY`     |   ✗    |   ✓   | **SDK 5.0+**. `ORDER BY` and `LIMIT` are rejected in subscription queries. See [`select.md`](select.md) §12. |

---

## 5. Defaults that flip between versions

This is the most user-visible cross-version difference and the most likely cause of "it worked on my old SDK, why is it different now?" — see [`types-mutators.md`](types-mutators.md) §7 for the full discussion.

| Behavior                                   | 4.14.x default                            | 5.0.x default                             |
| ------------------------------------------ | ----------------------------------------- | ----------------------------------------- |
| `dql_strict_mode` (user-facing knob)       | `true` (strict)                           | `false` (lenient)                         |
| Bare object value on `INSERT` / `UPDATE`   | stored as `REGISTER` (whole-object LWW)   | stored as `MAP` (per-field merge)         |
| `DQL_MUTATOR_OBJECTS_AS_MAPS` (internal flag, derived from strict mode) | OFF (`false`)            | ON (`true`)                               |
| Explicit type definition required for `MAP`? | Yes — without it, strict mode picks `REGISTER` | No — lenient picks `MAP` by default, but declaring is still recommended for cross-version portability |

**Portability rule:** if your code must run on both 4.14.x and 5.0.x peers in the same mesh, declare types explicitly with the `INTO COLLECTION coll (field MAP, …)` syntax on every statement that touches a non-`REGISTER` field. Don't rely on the strict-mode default to do the right thing — declare and be sure.

---

## 6. `XOR` and `DO MERGE` — neither is available in the tested SDK lines

- **`XOR` operator.** The docs once listed `XOR` as v4-only; the harness shows 4.14.4, 5.0.0, **and** 5.1.0 all reject it (`XOR is not supported` / `No infix parser`). Treat `XOR` as unavailable everywhere until it actually ships. **Workaround:** `a XOR b` ≡ `(a OR b) AND NOT (a AND b)`. See [`operators.md`](operators.md) §11.
- **`INSERT ... ON ID CONFLICT DO MERGE`.** v4 accepted `MERGE` as an undocumented alias for `UPDATE` (the parser folded it to `DoUpdate`, so it produced the same effect as `DO UPDATE`). v5.0 removed the keyword; it now raises a parse error. v5.1 reintroduces `DO MERGE` as a first-class action distinct from `DO UPDATE`. **Workaround for cross-version code:** write `DO UPDATE` explicitly. See [`statements.md`](statements.md) §1.6.

The framing for both is the same: "v4 had it; v5.0 removed it; v5.1 will reintroduce." Don't rely on either until you can pin to 5.1+.

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

A version starting with `4.` (e.g. `4.14.3`) means 4.x lenient/strict surface as described above. A version starting with `5.0.` means v5.0.x with all the v5-only features (`PROFILE`, quantifiers, comprehensions, `#profile`) and **without** `XOR` and `DO MERGE`.

### 7.2 Detect the strict-mode flip from inside DQL

`dql_strict_mode` is queryable and settable at runtime, and its default is the most user-visible cross-version difference:

```sql
-- See what the engine is using right now
SHOW dql_strict_mode;

-- Result is the string "true" on a 4.14.x default install,
-- "false" on a 5.0.x default install.
```

This is **not** a perfect version check — an operator may have explicitly flipped strict mode on either line:

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
2. **Write to the lowest common denominator.** Use the older SDK's feature surface as the baseline. Avoid `ANY/EVERY ... SATISFIES`, comprehensions, `WITHIN`, `PROFILE`, and `#profile` unless every peer that will execute the query is on 5.0+. Avoid `XOR` and `DO MERGE` unless you can pin to 4.x — or wait for 5.1 to reintroduce them.
3. **Defaults are not contracts.** The flip from `dql_strict_mode = true` (v4) to `false` (v5.0) is the kind of silent behavior change that breaks code months after the upgrade, when the first concurrent write hits a field that's now a `MAP` instead of a `REGISTER`. The way to immunise your code is to declare types on every mutation — that way the default doesn't matter.

---

## 9. See also

- [`operators.md`](operators.md) — operator precedence, comparison/logical semantics, the `XOR` cross-version note in §11.
- [`functions.md`](functions.md) — every scalar function (all dual-version) and aggregate.
- [`expressions.md`](expressions.md) — quantifiers (`ANY`/`EVERY ... SATISFIES`), comprehensions (`ARRAY/OBJECT ... FOR ... END`), `WITHIN` — all v5.0+.
- [`statements.md`](statements.md) — `DO UPDATE_LOCAL_DIFF` (4.12+), `COUNTER` (4.13+), `PN_COUNTER` (4.11+), `PROFILE` (5.0+), the `DO MERGE` cross-version note.
- [`select.md`](select.md) — `DQL_RESTRICT_LIMIT_ORDER_BY` (5.0+).
- [`types-mutators.md`](types-mutators.md) — the canonical writeup of the strict-mode flip.
- [`indexing.md`](indexing.md) — `#profile` (5.0+) and the `ADVISE` workaround for 4.14.x / 5.0.x.
