---
title: DQL SELECT reference
description: SELECT clauses (projection, FROM, USE IDS/INDEX/DIRECTIVES, WHERE, GROUP BY, HAVING, ORDER BY, LIMIT/OFFSET) plus subscription constraints. Covers Ditto SDK 4.14.x, 5.0.x, and 5.1.x; version-gated features are tagged inline.
---

# DQL SELECT reference

> All examples in this file query the `movies` / `reviews` schema documented in [`schema.md`](schema.md).

Authoritative reference for the `SELECT` statement on **Ditto SDK 4.14.x, 5.0.x, and 5.1.x**. All other top-level statements (`INSERT`, `UPDATE`, `EVICT`, `TOMBSTONE`, `DELETE`, `EXPLAIN`, `ALTER SYSTEM`, `SHOW`, `SYNC CONTEXT`, `PROFILE`) live in [`statements.md`](statements.md). `CREATE INDEX` / `DROP INDEX` live in [`indexing.md`](indexing.md).

Unless a section carries an "Available in:" note, the clause works identically on 4.14.x, 5.0.x, and 5.1.x.

Cross-references:

- Expression grammar (paths, literals, quantifiers, comprehensions) → [`expressions.md`](expressions.md)
- Operators (precedence, comparison, NULL/MISSING semantics, four-valued logic) → [`operators.md`](operators.md)
- Scalar and aggregate functions → [`functions.md`](functions.md)
- CRDT type definitions and mutators (`MAP`, `COUNTER`, `APPLY`) → [`types-mutators.md`](types-mutators.md)
- Index DDL and planner hints in depth → [`indexing.md`](indexing.md)

---

## Top-level grammar

```
SELECT [ DISTINCT ] <projection>
FROM <collection_ref>
  [ USE IDS <id_list> ]
  [ USE INDEX <name> [ ASC | DESC ] ]
  [ USE DIRECTIVES '<json_object>' ]
[ WHERE     <expr> ]
[ GROUP BY  <expr> [, <expr> ...] ]
[ HAVING    <expr> ]
[ ORDER BY  <expr> [ ASC | DESC ] [, <expr> [ ASC | DESC ] ...] ]
[ LIMIT     <int_or_param> ]
[ OFFSET    <int_or_param> ]
```

Clauses must appear in the order shown. The three `USE …` clauses are mutually orderable (any order, any subset), but each may appear at most once. Inline planner directives via comments (`/*+ … */` or `--+ …`) may precede the statement — see [`indexing.md`](indexing.md).

---

## 1. Projection

```
<projection> ::= '*'
              |  <expr> [ [AS] <alias> ] [, <expr> [ [AS] <alias> ] ...]
```

- `*` projects the full document (`_id` plus every field). Wildcard expansion is presented alphabetically.
- An explicit expression list can mix paths, calculations, function calls, and aggregates.
- `DISTINCT` (before the projection) eliminates duplicate rows. It buffers all projections in memory, so it dams the pipeline — avoid it on unbounded result sets.
- Default aliasing rules:
  - Simple field reference → alias defaults to the field name (`title` → `title`).
  - Expression → default alias is `($n)`, where `n` is the 1-based position.
  - `AS` is optional; `field alias` and `field AS alias` are equivalent.
  - Aliases must be unique within a single statement.
- When aggregates appear in the projection, every non-aggregate projected expression must also appear in `GROUP BY` (see §7).

### 1.1 Wildcard

```sql
SELECT * FROM movies;
SELECT * FROM reviews;
```

### 1.2 Explicit expression list with aliases

```sql
SELECT title, year, ratings.imdb AS imdb
FROM movies;

SELECT
  title,
  year - 1900            AS years_since_1900,
  runtime_minutes / 60.0 AS runtime_hours
FROM movies;
```

### 1.3 `DISTINCT`

```sql
-- Distinct release years across the library
SELECT DISTINCT year FROM movies ORDER BY year ASC;

-- Distinct director / genre pairs (multi-column DISTINCT)
SELECT DISTINCT director.name, genres FROM movies;
```

`DISTINCT` is **redundant** when `_id` is included unchanged — every row already differs by `_id`.

---

## 2. FROM clause

```
<collection_ref> ::= [ <datasource> ':' ] <name> [ <alias> ]
<name>           ::= <identifier> | '`' <quoted_name> '`'
```

- `movies` — the default `default:` datasource, where every field defaults to `REGISTER`.
- `default:movies` — fully qualified.
- `system:collections`, `system:vitals`, etc. — virtual collections in the `system` datasource.
- `` `weird name` `` — backticks for identifiers with spaces, hyphens, or reserved words.
- `movies m` — collection alias (`m`) for use in expressions and directives.

If the document touches non-register CRDTs (`MAP`, `COUNTER`, `PN_COUNTER`, `ATTACHMENT`), pair the read with a typed reference via the appropriate CRDT type definition. See [`types-mutators.md`](types-mutators.md) for how to declare them on `INSERT` / `UPDATE` so subsequent `SELECT`s see the correct merge semantics.

```sql
-- Default datasource, default register typing
SELECT title, year FROM movies WHERE year >= 1990;

-- Explicit datasource prefix
SELECT _id, title FROM default:movies WHERE year = 1994;

-- System collection
SELECT * FROM system:collections;

-- Collection alias for use in directives or qualified paths
SELECT m.title, m.year FROM movies m WHERE m.year >= 2000;
```

---

## 3. USE IDS

> **Effectively SELECT-only.** `USE IDS` is supported on `SELECT` in 4.14.x, 5.0.x, and 5.1.x. On mutations it is a parse error on 4.14.x and 5.0.x. On 5.1.x it parses on `UPDATE` (before `SET` only, and it applies correctly) and on `DELETE` / `EVICT` — but there it **reports success and removes nothing** unless a `RETURNING` clause is present, so it must not be used. `TOMBSTONE` is unavailable on every SDK version. **For mutations targeting a known id set, use `WHERE _id IN (...)` on every version** — see [`statements.md`](statements.md).

```
USE IDS ( <id_expr> [, <id_expr> ...] )
USE IDS ( <list_param> )           -- :param holding a list of ids
```

Skips the collection scan and goes directly to the indexed-by-id path.

> **Tested-SDK note:** only the single-id form of the explicit syntax is accepted by 4.14.x / 5.0.x / 5.1.0 as shipped — the multi-id list and list-parameter forms (§§3.2–3.3) currently fail with ``(...) is not supported``.
>
> You rarely need to write `USE IDS` at all on 5.0+: the planner **automatically rewrites** `_id` equality filters into an id-direct plan when it can. Harness-verified against 4.14.4 / 5.0.0 / 5.1.0 (`EXPLAIN` shows the `idScan` operator when the rewrite fires):
>
> | Filter shape | 4.14.x | 5.0.x | 5.1.x |
> |---|---|---|---|
> | `WHERE _id = '…'` | scan | `idScan` | `idScan` |
> | `… AND _id = '…'` (any `_id=` branch) | scan | `idScan` | `idScan` |
> | `_id = 'a' OR _id = 'b'` (every OR branch has `_id=`) | scan | `idScan` on both ids | `idScan` on both ids |
> | `_id = 'a' OR year > 2000` (partial OR) | scan | scan | scan |
> | `WHERE _id IN ('a', 'b')` | scan | scan | `idScan` on the whole list |
> | `_id LIKE` / non-equality | scan | scan | scan |
>
> A residual `FILTER` operator stays in the plan, so correctness is unaffected. Use explicit `USE IDS` when you need the shortest path explicitly (e.g. to make the intent visible at 4.14.x, where the rewrite does not exist).

### 3.1 Single id

```sql
SELECT * FROM movies USE IDS ('tt0111161');
```

To see the plan pick the id path yourself (note the `idScan` operator on 5.0+; 4.14.x shows a plain `scan` — same result, the explicit `USE IDS` is how v4 gets the direct lookup):

```sql
EXPLAIN SELECT * FROM movies WHERE _id = 'tt0111161';
```

### 3.2 Id list

The explicit list form `USE IDS ('a', 'b', …)` is in the grammar but **parser-rejected on all tested versions** (`is not supported`). The supported way to fetch a known set of ids is the predicate form:

```sql
SELECT _id, title, year
FROM movies
WHERE _id IN ('tt0111161', 'tt0468569', 'tt1375666');
```

On 5.1+ this rewrites to the direct id path automatically (see the table in §3); on 5.0.x and 4.14.x it runs as scan+filter — for a hot path there, spell it as an `OR` chain so the same rewrite fires on 5.0+.

### 3.3 Parameter form

```sql
-- Bind a single id
SELECT * FROM movies USE IDS (:id);
```

Binding an *array* of ids (`USE IDS (:id_list)`) is the parser-rejected list form again — use `WHERE _id IN :id_list` instead, which the 5.1+ planner then rewrites to the direct id path.

### 3.4 Why USE IDS is SELECT-only

On 4.14.x and 5.0.x the syntax is accepted only on `SELECT`; on 5.1.x it reaches the mutation paths but is only trustworthy on `UPDATE` (see §3 above). On mutations you have two portable options:

```sql
-- 1. Filter by IN-list
DELETE FROM movies
WHERE _id IN ('tt9999990', 'tt9999991', 'tt9999992');

-- 2. Bind a parameter list
DELETE FROM movies WHERE _id IN :id_list;
```

See [`statements.md`](statements.md) §§3–5 for the full set of mutation alternatives.

---

## 4. USE INDEX

```
USE INDEX <name> [ ASC | DESC ]
```

A convenience for the `#index` directive that selects a named index for the planner. Pass an empty string (`''`) to *forbid* any index scan and force a full collection scan.

```sql
-- Use a specific index
SELECT * FROM movies USE INDEX 'movies_year_imdb' WHERE year = 2010;

-- Force descending traversal of the index
SELECT title FROM movies USE INDEX 'movies_year_imdb' DESC
WHERE year >= 1990
ORDER BY year DESC, ratings.imdb DESC
LIMIT 10;

-- Forbid index scan (force collection scan)
SELECT * FROM movies USE INDEX '' WHERE year = 2010;
```

If the named index doesn't exist or isn't applicable to the query, the hint is silently ignored. For more elaborate planner control see `USE DIRECTIVES` (§5) and the comment-style directives covered in [`indexing.md`](indexing.md).

---

## 5. USE DIRECTIVES

```
USE DIRECTIVES '<json_object>'
```

Per-collection planner directives supplied as a JSON string. Anything the comment-style form (`/*+ {...} */`) can do at the collection level can also be supplied here.

```sql
-- Steer the planner toward a named index
SELECT *
FROM movies
USE DIRECTIVES '{"#index": ["movies_year_imdb"]}'
WHERE year = 2010;

-- Multiple candidates — planner picks among them
SELECT title, ratings.imdb
FROM movies
USE DIRECTIVES '{"#index": ["movies_year_imdb", "movies_year"]}'
WHERE year >= 1990
ORDER BY ratings.imdb DESC
LIMIT 10;

-- Per-collection override of #prefer_order
SELECT *
FROM movies
USE DIRECTIVES '{"#prefer_order": true}'
WHERE year >= 2000
ORDER BY year;
```

Unknown JSON fields are silently ignored. Invalid JSON is a parse error. The directive catalogue and inline `/*+ ... */` / `--+ ...` forms are documented in [`indexing.md`](indexing.md).

---

## 6. WHERE clause

```
WHERE <expr>
```

The predicate is evaluated per document. Documents where the predicate does not evaluate to `TRUE` are excluded — this includes `FALSE`, `NULL`, `MISSING`, and evaluation-time errors (which are silently swallowed at the per-document level).

Standard portable patterns:

```sql
-- Simple comparison + IS NOT MISSING
SELECT title, year, box_office_millions
FROM movies
WHERE year >= 1990
  AND box_office_millions IS NOT MISSING;

-- Compound predicate with AND / OR
SELECT title FROM movies
WHERE (year < 1980 AND is_classic = true)
   OR ratings.imdb >= 9.0;

-- Array containment (function form; see functions.md)
SELECT title FROM movies
WHERE array_contains(genres, 'Drama');

-- IN list and IN array
SELECT title FROM movies
WHERE year IN (1994, 1999, 2010);

SELECT _id, title FROM movies
WHERE _id IN ('tt0111161', 'tt0468569');

-- Pattern match
SELECT title FROM movies WHERE title LIKE 'The %';
SELECT title FROM movies WHERE title ILIKE '%lord of the rings%';

-- NULL / MISSING
SELECT title FROM movies WHERE box_office_millions IS NULL;
SELECT title FROM movies WHERE box_office_millions IS NOT MISSING;
```

For the precedence of `AND` / `OR` / `NOT`, the difference between `=` and `IS NOT DISTINCT FROM`, and the four-valued logic semantics for `NULL` / `MISSING`, see [`operators.md`](operators.md). For the path-expression and parameter syntax see [`expressions.md`](expressions.md). For `array_contains`, `regexp_like`, type predicates, etc. see [`functions.md`](functions.md).

### 6.1 Quantifier expressions (v5.0+)

> **Available in:** SDK **5.0+** only. `ANY` / `EVERY` / `ANY AND EVERY ... SATISFIES ... END` are not present in 4.x.

```sql
-- Movies where at least one cast member played 'Cooper'
SELECT title FROM movies
WHERE ANY c IN `cast` SATISFIES c.role = 'Cooper' END;

-- Movies where every cast entry has a non-empty name
SELECT title FROM movies
WHERE EVERY c IN cast SATISFIES c.name IS NOT MISSING AND c.name <> '' END;
```

Recursive descent via `WITHIN` (e.g. `ANY x WITHIN cast SATISFIES …`) is also **v5.0+ only**. The portable v4.14.x alternative is to flatten the predicate into `array_contains` calls or use the explicit `[index]` path syntax. Both forms are documented in detail in [`expressions.md`](expressions.md).

---

## 7. GROUP BY

```
GROUP BY <expr> [, <expr> ...]
```

When `GROUP BY` is present:

- Every non-aggregate projection must also be in `GROUP BY`, otherwise the statement is rejected.
- `HAVING` and `ORDER BY` are likewise limited to grouping expressions and aggregates.
- Per-group memory grows with the cardinality of the grouping keys — keep an eye on high-cardinality keys.
- A document whose grouping expression errors out is silently skipped.

### 7.1 Single-key grouping

```sql
-- Count movies per year
SELECT year, count(*) AS n
FROM movies
GROUP BY year
ORDER BY n DESC, year DESC;

-- Average IMDB by decade (computed key)
SELECT year - (year % 10) AS decade, avg(ratings.imdb) AS avg_imdb
FROM movies
GROUP BY year - (year % 10)
ORDER BY decade ASC;
```

### 7.2 Multi-key grouping

```sql
-- Films per (year, primary genre)
SELECT year, genres[0] AS primary_genre, count(*) AS n
FROM movies
GROUP BY year, genres[0]
ORDER BY year DESC, n DESC;

-- Director × decade
SELECT
  director.name                 AS director,
  year - (year % 10)            AS decade,
  count(*)                      AS films,
  avg(ratings.imdb)             AS avg_imdb
FROM movies
GROUP BY director.name, year - (year % 10)
ORDER BY director, decade;
```

See [`functions.md`](functions.md) for the aggregate function set (`count`, `sum`, `avg`, `min`, `max`, `mid`, `median`) available on all three supported SDK versions.

---

## 8. HAVING

```
HAVING <expr>
```

Post-grouping filter. Aggregates inside `HAVING` are evaluated per group.

- **With `GROUP BY`:** the usual aggregate-filtering use case.
- **Without `GROUP BY`:** `HAVING` cannot reference aggregates and degenerates into a `WHERE`-like filter — but **without index push-down**. Prefer `WHERE` when no aggregate is needed.

```sql
-- Directors with 3+ films AND average IMDB > 8.0
SELECT
  director.name      AS director,
  count(*)           AS films,
  avg(ratings.imdb)  AS avg_imdb
FROM movies
GROUP BY director.name
HAVING count(*) >= 3
   AND avg(ratings.imdb) > 8.0
ORDER BY avg_imdb DESC;

-- Years with at least one billion-dollar box-office film
SELECT year, max(box_office_millions) AS biggest
FROM movies
GROUP BY year
HAVING max(box_office_millions) >= 1000
ORDER BY year DESC;
```

---

## 9. ORDER BY

```
ORDER BY <expr> [ ASC | DESC ] [, <expr> [ ASC | DESC ] ...]
```

- Default direction is `ASC`.
- The expression resolves against **projection aliases first**, then collection fields. To order by the underlying field when the alias differs, qualify it with the collection alias (`movies.title`).
- Documents whose ordering expression errors out are substituted with `NULL` for the comparison key.
- Sort is stable across ties — equal keys retain their input order (driven by the upstream pipeline).
- For cross-type comparisons see §11.

```sql
-- Top 10 by IMDB rating, breaking ties on title ascending
SELECT title, ratings.imdb AS imdb
FROM movies
ORDER BY imdb DESC, title ASC
LIMIT 10;

-- Most-recent five films
SELECT title, released FROM movies
ORDER BY released DESC
LIMIT 5;

-- Reviews newest-first per movie (multi-key)
SELECT movie_id, user_id, score, created_at
FROM reviews
ORDER BY movie_id ASC, created_at DESC;
```

### NULL / MISSING in ORDER BY

`NULL` sorts **before** `MISSING` and both sort **after** all real values in ascending order (see §11). To exclude documents missing the sort key, add an explicit `IS NOT MISSING` predicate:

```sql
SELECT title, box_office_millions
FROM movies
WHERE box_office_millions IS NOT MISSING
ORDER BY box_office_millions DESC
LIMIT 20;
```

---

## 10. LIMIT / OFFSET

```
LIMIT  <int_or_param>
OFFSET <int_or_param>
```

Either order works — `LIMIT 20 OFFSET 40` and `OFFSET 40 LIMIT 20` are equivalent. Both accept parameter binding.

```sql
-- First page of 20, newest first
SELECT _id, title, year FROM movies
ORDER BY released DESC
LIMIT 20;

-- Second page
SELECT _id, title, year FROM movies
ORDER BY released DESC
LIMIT 20 OFFSET 20;

-- OFFSET before LIMIT
SELECT _id, title FROM movies
ORDER BY released DESC
OFFSET 40 LIMIT 20;

-- Parameterised
SELECT _id, title FROM movies
ORDER BY released DESC
LIMIT :page_size OFFSET :page_offset;
```

`OFFSET` skips rows after sorting; deep offsets pay a per-row cost on the prefix you skip. For large datasets, keyset pagination (a `WHERE released < :cursor` cursor instead of `OFFSET`) is more efficient.

> **Subscriptions:** `ORDER BY` and `LIMIT` are restricted in subscription queries when `DQL_RESTRICT_LIMIT_ORDER_BY` is set — see §12.

---

## 11. Cross-type sort order

When `ORDER BY` compares values of different types, the engine uses a fixed type-rank order. Ascending, least to greatest:

| Rank | Type      | Notes                                                            |
| ---- | --------- | ---------------------------------------------------------------- |
| 1    | Bool      | `false` < `true`                                                 |
| 2    | Numeric   | Integers and floats interleave by value; `NaN` > `+Infinity`     |
| 3    | Binary    | Lexicographic over the byte sequence                             |
| 4    | String    | Lexicographic over the Unicode code points                       |
| 5    | Array     | Element-wise, with shorter prefixes sorting before longer ones   |
| 6    | Object    | Key-wise after sorting keys (implementation-defined within type) |
| 7    | `NULL`    | Sorts after every real value                                     |
| 8    | `MISSING` | Sorts after `NULL`                                               |

`DESC` reverses the ordering — `MISSING` becomes the first row, then `NULL`, then objects, etc.

```sql
-- Box office values that are MISSING bubble to the end ascending,
-- and to the front descending.
SELECT title, box_office_millions FROM movies
ORDER BY box_office_millions ASC;

SELECT title, box_office_millions FROM movies
ORDER BY box_office_millions DESC;
```

If you need `MISSING` and `NULL` rows to sort *before* real values, project a coalesced key:

```sql
SELECT title, box_office_millions FROM movies
ORDER BY ifmissingornull(box_office_millions, -1) DESC;
```

See [`functions.md`](functions.md) for `ifmissingornull`, `coalesce`, `nvl`, and friends.

---

## 12. Subscription patterns and constraints

DQL `SELECT` statements can be used as **subscriptions** — long-lived queries that emit incremental updates as documents change. The engine restricts the surface that subscription queries can use, to keep cache invalidation cheap. Two feature flags control that surface; when each applies is covered below.

### 12.1 Feature flags that restrict subscription syntax

> **These are internal engine bitflags, not settable parameters.** `DQL_RESTRICT_TO_ORIGINAL_SYNTAX` and `DQL_RESTRICT_LIMIT_ORDER_BY` are Rust `FeatureFlags` constants (`crates/ditto-dql/src/engine/mod.rs`) that the subscription code path sets for you. `SHOW` and `ALTER SYSTEM SET` reject both names on **every** version with `unknown parameter` — you cannot inspect or override them from DQL. They are named here only because they appear in engine error paths.

| Restriction                       | Applies on      | Effect on subscription `SELECT`                                                                                                       |
| --------------------------------- | --------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| V1 surface only<br>(`DQL_RESTRICT_TO_ORIGINAL_SYNTAX`) | 4.14.x, 5.0.x, 5.1.x | `SELECT *` only (no expression projection), a single collection (no JOIN), no `USE IDS`, no `DISTINCT`, no `GROUP BY`/`HAVING`. |
| `ORDER BY` / `LIMIT` rejected<br>(`DQL_RESTRICT_LIMIT_ORDER_BY`) | **SDK 5.0+** | `ORDER BY` and `LIMIT` are rejected in subscription queries. `OFFSET` on its own stays legal. Use a one-shot store query for paginated or sorted reads. |

The V1-surface restriction is always on for `registerSubscription` on every SDK version — there is no unrestricted subscription path. The `ORDER BY`/`LIMIT` rejection is driven by the system parameter **`dql_restrict_subscriptions`** (default `true`), which exists on 5.0.x and 5.1.x and **not** on 4.14.x — that one *is* readable with `SHOW dql_restrict_subscriptions`. SDK 4.14.x accepts both clauses; queries using `LIMIT` maintain boundary state and should avoid mutable filter or sort fields. See the `sync-subscriptions` skill for the full version matrix and exact error strings.

### 12.2 What is — and isn't — allowed in a subscription

The table below collapses both flags. "OK" means the syntax works in a subscription across SDK 4.14.x, 5.0.x, and 5.1.x. "Restricted" means at least one of the flags above blocks it.

| Feature                              | One-shot `SELECT` | Subscription `SELECT`                                                  |
| ------------------------------------ | ----------------- | ---------------------------------------------------------------------- |
| `SELECT *`                           | OK                | OK                                                                     |
| Expression projection / `AS` aliases | OK                | Restricted under `DQL_RESTRICT_TO_ORIGINAL_SYNTAX`                     |
| `DISTINCT`                           | OK                | Restricted under `DQL_RESTRICT_TO_ORIGINAL_SYNTAX`                     |
| `USE IDS`                            | OK                | Restricted under `DQL_RESTRICT_TO_ORIGINAL_SYNTAX`                     |
| `USE INDEX` / `USE DIRECTIVES`       | OK                | OK (planner hints are honoured)                                        |
| `WHERE`                              | OK                | OK                                                                     |
| `GROUP BY` / `HAVING`                | OK                | Restricted under `DQL_RESTRICT_TO_ORIGINAL_SYNTAX`                     |
| `ORDER BY`                           | OK                | **Restricted under `DQL_RESTRICT_LIMIT_ORDER_BY`** (default on 5.0+; accepted, stateful, on 4.14.x) |
| `LIMIT`                              | OK                | **Restricted under `DQL_RESTRICT_LIMIT_ORDER_BY`** (default on 5.0+; accepted, stateful, on 4.14.x) |
| `OFFSET` alone                       | OK                | OK — the restriction fires only on `LIMIT` / `ORDER BY`                |

### 12.3 Portable subscription patterns

If you need to subscribe to a filtered set on 4.14.x, 5.0.x, and 5.1.x alike, stick to the lowest-common-denominator surface:

```sql
-- Portable subscription: SELECT * with WHERE only
SELECT * FROM movies WHERE year >= 1990 AND is_classic = true;

SELECT * FROM reviews WHERE movie_id = :movie_id;

SELECT * FROM movies WHERE array_contains(genres, 'Drama');
```

Expression projections are never available in a subscription, on any supported SDK version — model partial documents as a separate collection or an attachment instead. `ORDER BY` / `LIMIT` subscriptions work only on 4.14.x:

```sql
-- SDK 4.14.x only. LIMIT makes this stateful: boundary changes invalidate
-- and re-evaluate the query, so never filter or sort on mutable fields.
-- On SDK 5.0.x and 5.1.x, use a one-shot local query instead.
SELECT * FROM movies
WHERE year >= 1990
ORDER BY title ASC
LIMIT 50;
```

On SDK 5.x, subscribe to the unsorted set and apply presentation constraints locally.

For sorting and pagination across a subscription stream, do the sort/limit **in the host application** over the unsorted subscription result, rather than relying on the engine to maintain a sorted projection.

---

## 13. Worked examples (movies dataset)

End-to-end SELECTs covering the typical reporting patterns. Every statement runs on 4.14.x, 5.0.x, and 5.1.x unless tagged otherwise.

```sql
-- 1. Top 10 highest-rated movies
SELECT _id, title, ratings.imdb AS imdb
FROM movies
WHERE ratings.imdb IS NOT MISSING
ORDER BY imdb DESC
LIMIT 10;

-- 2. Movies released in a window, grouped by primary genre
SELECT genres[0] AS primary_genre, count(*) AS n, avg(ratings.imdb) AS avg_imdb
FROM movies
WHERE year BETWEEN 2000 AND 2010
GROUP BY genres[0]
HAVING count(*) >= 3
ORDER BY avg_imdb DESC;

-- 3. Director leaderboard
SELECT
  director.name       AS director,
  count(*)            AS films,
  avg(ratings.imdb)   AS avg_imdb,
  max(box_office_millions) AS biggest
FROM movies
GROUP BY director.name
HAVING count(*) >= 2
ORDER BY avg_imdb DESC, films DESC
LIMIT 20;

-- 4. Paginated browse, newest first
SELECT _id, title, released
FROM movies
ORDER BY released DESC
LIMIT :page_size OFFSET :page_offset;

-- 5. Lookup by id list (SELECT-only USE IDS)
SELECT _id, title, year
FROM movies
USE IDS ('tt0111161', 'tt0468569', 'tt1375666', 'tt0816692');

-- 6. Planner-hinted scan
SELECT title FROM movies
USE INDEX 'movies_year_imdb'
WHERE year >= 1990
ORDER BY ratings.imdb DESC
LIMIT 25;

-- 7. Cross-collection lookup via subquery
SELECT r.*
FROM reviews r
WHERE r.movie_id IN (
  SELECT _id FROM movies WHERE is_classic = true
);

-- 8. Latest review per movie (project + ORDER BY)
SELECT movie_id, user_id, score, created_at
FROM reviews
ORDER BY movie_id ASC, created_at DESC;

-- 9. Quantifier WHERE (v5.0+)
SELECT title FROM movies
WHERE ANY c IN `cast` SATISFIES c.role = 'Cooper' END;

-- 10. Force-no-index path for benchmarking
SELECT title FROM movies USE INDEX '' WHERE year = 2010;
```

---

## 14. `JOIN` — cross-collection reads

> **Available in:** Ditto SDK **5.1+**. On 4.14.x / 5.0.x any join syntax raises a parse error; use the two-query / denormalization patterns from the cookbook instead.

`JOIN` reads across two or more collections in one statement on a Small Peer. Both inner and outer forms exist:

```
SELECT <projection>
FROM <collection> [AS] <alias>
  [ INNER | LEFT [OUTER] | RIGHT [OUTER] ] JOIN <collection> [AS] <alias> ON <expr>
  ...more joins...
[ WHERE / GROUP BY / HAVING / ORDER BY / LIMIT / OFFSET ... ]
```

Rules and behavior (all verified against SDK 5.1.0):

- **Index the join key.** A join whose right-side match key is neither `_id` nor an indexed field fails: `Joining to "<alias>" disallowed without appropriate index support. Please run ADVISE for recommendations.` Create the index (or run `ADVISE` on the statement; see [`indexing.md`](indexing.md) §9) before relying on the join.
- **Aliases** — every joined collection should have one (`reviews r`), and qualified paths (`r.movie_id`) disambiguate columns. Unqualified projections like `SELECT *` across a join are allowed but ambiguous fields collide.
- **`ON` is a boolean expression** — equality on the FK (`r.movie_id = m._id`), compound `AND` terms, and even function predicates such as `array_contains(object_keys(m.members), u._id)` for MAP-based many-to-many relations.
- **Outer joins surface `MISSING`** on unmatched rows — filter with `<alias>.<pk> IS MISSING` for anti-joins, and wrap projected outer fields with `coalesce(...)` for defaults.
- **Supported join types** on 5.1.x: `INNER JOIN`, bare `JOIN` (an inner join), `LEFT [OUTER] JOIN`, and `RIGHT [OUTER] JOIN`. `FULL [OUTER] JOIN` and `CROSS JOIN` are **not** in the grammar and raise `Unexpected token FULL` / `Unexpected token CROSS`.
- **Self-joins** work when each side has a distinct alias (`FROM movies m1 INNER JOIN movies m2 ON …`), as do multi-join chains.

### 14.1 Inner join — projection from both sides

> **Available in:** SDK **5.1+**.

```sql
-- Every review with its movie's title and year
SELECT r._id, r.score, r.user_id, m.title, m.year
FROM reviews r
INNER JOIN movies m ON r.movie_id = m._id
ORDER BY r.score DESC
LIMIT 10;
```

Joining on `m._id` here needs no extra index (`_id` is always indexed); the left side scans `reviews`.

### 14.2 Inner join — FK on the right side needs an index

Joining the other direction — `reviews` on the right, matched on `reviews.movie_id` — requires an index on that field:

```sql
CREATE INDEX IF NOT EXISTS reviews_movie_id ON reviews (movie_id);
```

> **Available in:** SDK **5.1+** (the join below).

```sql
-- Each movie with its review scores
SELECT m._id, m.title, r.score, r.user_id
FROM movies m
INNER JOIN reviews r ON r.movie_id = m._id
ORDER BY m.title ASC, r.score DESC
LIMIT 20;
```

### 14.3 Outer join + aggregation — reviews per movie

> **Available in:** SDK **5.1+**.

```sql
-- Review count and average per movie, including movies with none
SELECT m._id, m.title,
       COUNT(r._id) AS review_count,
       coalesce(AVG(r.score), 0) AS avg_score
FROM movies m
LEFT OUTER JOIN reviews r ON r.movie_id = m._id
GROUP BY m._id, m.title
ORDER BY review_count DESC
LIMIT 10;
```

### 14.4 Join + HAVING — keep only well-reviewed movies

> **Available in:** SDK **5.1+**.

```sql
SELECT m._id, m.title, AVG(r.score) AS avg_score
FROM movies m
INNER JOIN reviews r ON r.movie_id = m._id
GROUP BY m._id, m.title
HAVING AVG(r.score) >= 8.0
ORDER BY avg_score DESC;
```

### 14.5 Anti-join — movies with no reviews

> **Available in:** SDK **5.1+**.

```sql
SELECT m._id, m.title, m.year
FROM movies m
LEFT OUTER JOIN reviews r ON r.movie_id = m._id
WHERE r._id IS MISSING
ORDER BY m.year DESC
LIMIT 10;
```

### 14.6 Compound ON and multi-join chains

Multiple `AND`-ed terms in `ON`, or several `JOIN` clauses chained (order → customer → store, page → component → element trees), are supported — each new right side still needs its match key indexed. The `dql-metrics` `retail-joins` and `forge-joins` suites are the reference catalogue of these shapes (multi-FK joins, rollups with aggregates, MAP-membership joins, and bounded self-join tree walks).

---

## 15. Cross-reference index

| Topic                                              | Go to                                       |
| -------------------------------------------------- | ------------------------------------------- |
| Operator precedence, NULL/MISSING, 4-valued logic  | [`operators.md`](operators.md)              |
| Path expressions, parameters, literals, CASE       | [`expressions.md`](expressions.md)          |
| `ANY` / `EVERY` / `SATISFIES`, comprehensions      | [`expressions.md`](expressions.md) §quantifiers |
| `array_contains`, `regexp_like`, type predicates   | [`functions.md`](functions.md)              |
| `count` / `sum` / `avg` / `min` / `max` / `median` | [`functions.md`](functions.md) §aggregates  |
| `INSERT` / `UPDATE` / `DELETE` / etc.              | [`statements.md`](statements.md)            |
| `USE IDS` mutation workaround (`WHERE _id IN …`)   | [`statements.md`](statements.md) §§3–5      |
| `MAP` / `COUNTER` / `APPLY` semantics              | [`types-mutators.md`](types-mutators.md)    |
| `CREATE INDEX`, `DROP INDEX`, full directive set   | [`indexing.md`](indexing.md)                |
| `EXPLAIN` / `PROFILE` (v5.0+ keyword)              | [`statements.md`](statements.md) §§6, 10    |
