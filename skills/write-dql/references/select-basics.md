# Select basics — Ditto

## Contents

- [1. Projection](#1-projection)
- [2. FROM clause](#2-from-clause)
- [6. WHERE clause](#6-where-clause)
- [7. GROUP BY](#7-group-by)
- [8. HAVING](#8-having)
- [9. ORDER BY](#9-order-by)
- [10. LIMIT / OFFSET](#10-limit--offset)
- [11. Cross-type sort order](#11-cross-type-sort-order)
- [13. Worked examples (movies dataset)](#13-worked-examples-movies-dataset)

Topic index: [select.md](select.md). Covers Ditto SDK 4.14.x (LTS),
5.0.x, 5.1.x and 5.2.0; version-specific notes remain inline. Read only the topic needed.

For movies/reviews examples, see the [schema](schema.md) only when adapting those examples; other examples define their own fields.

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

- `movies` — the default `default:` datasource. Undeclared field types are inferred from the value under the lenient baseline (objects → `MAP`, scalars and arrays → `REGISTER`); under strict mode everything undeclared is a `REGISTER`. See [`types-mutators.md`](types-mutators.md).
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
