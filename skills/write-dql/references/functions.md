---
title: DQL functions reference
description: Complete built-in function catalog for Ditto DQL (math, string, array, object, date, duration, aggregates). Covers Ditto SDK 4.14.x, 5.0.x, 5.1.x and 5.2.0; version-gated features are tagged inline.
---

# DQL functions reference

## Contents

- [1. Mathematical](#1-mathematical)
- [2. Conditional / null-handling](#2-conditional--null-handling)
- [3. Type / conversion](#3-type--conversion)
- [4. String](#4-string)
- [5. Array](#5-array)
- [6. Object](#6-object)
- [7. Date / time](#7-date--time)
- [8. Duration](#8-duration)
- [9. Miscellaneous](#9-miscellaneous)
- [10. Aggregates](#10-aggregates)
- [11. Alphabetical function index](#11-alphabetical-function-index)
- [See also](#see-also)

> All examples in this file query the `movies` / `reviews` schema documented in [`schema.md`](schema.md).

Authoritative catalog of every predefined function in DQL on **Ditto SDK 4.14.x, 5.0.x, 5.1.x and 5.2.0**. Function names are **case-insensitive**. Examples use the `movies` and `reviews` collections from the [`movies-cookbook.md`](../examples/movies-cookbook.md).

Every function in this catalog exists on **all four** covered SDK versions — 4.14.x, 5.0.x, 5.1.x and 5.2.0. The function harness checks a representative semantic case for each of the **73 names** in §11 on 4.14.6, 5.0.3, 5.1.0 and 5.2.0, including aggregates; it does not exhaust every overload or input edge case. Functions that are **not** in this catalog because they require 5.1+: `round()`, `array_sort()`, `serialize_json()`, `object_size()`. See [`versions.md`](versions.md) §4.6. For operator syntax (`+`, `||`, `LIKE`, `IS NULL`, etc.) see [`operators.md`](operators.md).

Notation:

- `v`, `expr` — any expression
- `str` — string expression
- `num` — numeric expression
- `[arg]` — optional argument
- `→ T` — return type (best-effort; most functions return `MISSING` when an input is `MISSING`)

---

## 1. Mathematical

| Signature       | Returns   | Notes                                |
| --------------- | --------- | ------------------------------------ |
| `abs(num)`      | `num`     | Absolute value                       |
| `ceil(num)`     | `num`     | Next integer at or above             |
| `floor(num)`    | `num`     | Previous integer at or below         |

```sql
SELECT title, ceil(runtime_minutes / 60.0) AS approx_hours FROM movies;
```

```sql
SELECT title, abs(box_office_millions - 100) AS distance_from_100m FROM movies;
```

---

## 2. Conditional / null-handling

| Signature                                          | Behaviour                                                                                          |
| -------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `coalesce(v1, v2, ...)`                            | First non-`NULL`, non-`MISSING` argument; `NULL` if all are nullish                                |
| `decode(in, c1, r1, [c2, r2, ...], [default])`     | Compare `in` against each `ci` (type + value); return matching `ri`. `MISSING` input → `MISSING`. |
| `nvl(v, r1[, r2])`                                 | 2-arg: `v` if non-null else `r1`. 3-arg: `r1` if `v` non-null else `r2`.                          |
| `isnull(v)` → `bool`                               | `TRUE` if `v` is `NULL`                                                                            |
| `ismissing(v)` → `bool`                            | `TRUE` if `v` is `MISSING`                                                                         |
| `ismissingornull(v)` → `bool`                      | `TRUE` if `v` is `NULL` or `MISSING`                                                               |
| `ifnull(v, ...)`                                   | First non-`NULL` argument; `NULL` if all are `NULL`                                                |
| `ifmissing(v, ...)`                                | First non-`MISSING` argument; `NULL` if all are `MISSING`                                          |
| `ifmissingornull(v, ...)`                          | Synonym for `coalesce`                                                                             |
| `nullif(v1, v2)`                                   | `NULL` if `v1 = v2`; otherwise `v1`. `NULL`/`MISSING` operand → `NULL`/`MISSING`.                  |
| `missingif(v1, v2)`                                | `MISSING` if `v1 = v2`; otherwise `v1`. `NULL`/`MISSING` operand → `NULL`/`MISSING`.               |

```sql
-- Display "N/A" when a movie has no IMDb rating
SELECT title, coalesce(cast(ratings.imdb, 'string'), 'N/A') AS imdb FROM movies;
```

```sql
-- Map a numeric score (1..5) to a label
SELECT _id, decode(score,
    5, 'love',
    4, 'like',
    3, 'meh',
    2, 'dislike',
    1, 'hate',
    'unrated'
) AS label
FROM reviews;
```

```sql
-- Suppress a sentinel value: convert score 0 to NULL
SELECT _id, nullif(score, 0) AS score FROM reviews;
```

The `IS NULL` / `IS MISSING` / `IS UNKNOWN` predicates (operator form) are documented in [`operators.md`](operators.md#4-unary-is-predicates). The function forms (`isnull`, `ismissing`, `ismissingornull`) return the same booleans but compose inside other expressions.

---

## 3. Type / conversion

| Signature                            | Returns                                                                | Notes                                                |
| ------------------------------------ | ---------------------------------------------------------------------- | ---------------------------------------------------- |
| `cast(v, 'type-name')`               | Value of target type, or `MISSING` if impossible                       | Function form. Targets below.                        |
| `CAST(v AS type)`                    | Same as above                                                          | SQL keyword form                                     |
| `deserialize_json(string)`           | Value                                                                  | JSON string → DQL value                              |
| `is_boolean(v)` → `bool`             | `TRUE` if `v` is a boolean                                             | Type predicate                                       |
| `is_number(v)` → `bool`              | `TRUE` if `v` is integer or float                                       | Type predicate                                       |
| `is_string(v)` → `bool`              | `TRUE` if `v` is a string                                              | Type predicate                                       |
| `type(v)` → `string`                 | One of `boolean`, `string`, `integer`, `float`, `object`, `array`, `binary`, `null` | DQL-flavoured type names                 |
| `json_type(v)` → `string`            | JSON-style names: `boolean`, `string`, `number`, `object`, `array`, `binary`, `null` | Integer/float collapsed to `number`        |

**`cast` target types:** `boolean`, `string`, `integer`, `float`, `object`, `array`, `binary`, `null`.

```sql
-- Function form
SELECT title, cast(year, 'string') AS year_str FROM movies;

-- SQL keyword form (same result)
SELECT title, CAST(year AS string) AS year_str FROM movies;
```

```sql
-- Type-introspect a polymorphic field
SELECT _id, type(ratings.imdb) AS imdb_type FROM movies;
```

```sql
-- Parse a JSON string back into a DQL value
SELECT deserialize_json('{"label":"hit","year":1994}') AS parsed;
```

`type()` distinguishes integer and float; `json_type()` collapses them to `number`. `serialize_json()` is **SDK 5.1+** — on 4.14.x and 5.0.x, render JSON in the application layer.

---

## 4. String

See [string-functions.md](string-functions.md#4-string) for this topic.

## 5. Array

| Signature                          | Returns    | Notes                                                              |
| ---------------------------------- | ---------- | ------------------------------------------------------------------ |
| `array_contains(array, value)`     | `bool`     | `NULL` if either operand is `NULL`                                  |
| `array_contains_null(array)`       | `bool`     | `TRUE` if any element is `NULL`                                     |
| `array_length(array)`              | `integer`  | Element count                                                       |

```sql
-- Movies tagged with the Drama genre
SELECT title FROM movies WHERE array_contains(genres, 'Drama');
```

```sql
-- Movies whose cast list is the largest
-- `cast` is a SQL keyword (and a function name) — backtick the field identifier
SELECT title, array_length(`cast`) AS cast_size FROM movies
ORDER BY cast_size DESC LIMIT 5;
```

```sql
-- Movies whose tags array has at least one explicit NULL slot
SELECT _id FROM movies WHERE array_contains_null(tags);
```

For "is this element in this array" use `array_contains` — `WHERE 'Drama' IN genres` does **not** mean array containment in DQL. See [`operators.md`](operators.md#5-range-and-membership) §5.

---

## 6. Object

| Signature                                              | Returns   | Notes                                                                                      |
| ------------------------------------------------------ | --------- | ------------------------------------------------------------------------------------------ |
| `object_length(obj)`                                   | `integer` | Top-level key count                                                                         |
| `object_keys(obj)`                                     | `array`   | Top-level keys                                                                              |
| `object_values(obj)`                                   | `array`   | Top-level values                                                                            |
| `object_set(obj, field, value[, replace_existing])`    | `object`  | Sets `field`; errors when overwriting unless `replace_existing` is `TRUE`                   |
| `object_unset(obj, field[, ignore_missing])`           | `object`  | Removes `field`; errors when missing unless `ignore_missing` is `TRUE`                      |
| `object_concat(o1, o2, ...)`                           | `object`  | Shallow merge; later argument wins on key conflicts                                          |
| `object_rename(obj, old, new)`                         | `object`  | Errors if `old` missing; silently overwrites `new`                                          |
| `object_content(obj[, config...])`                     | `array`   | Flatten / inspect — see config grammar below                                                |

### 6.1 `object_content` configuration

`config` arguments can be a single object or multiple strings; conflicting options error.

| Option        | Values                                | Effect                                                                                  |
| ------------- | ------------------------------------- | --------------------------------------------------------------------------------------- |
| `output`      | `'fields'` (default), `'keys'`, `'values'` | Each entry: a single `{field: value}` object, just the key, or just the value      |
| `nested`      | `'no'` (default), `'yes'`, `'only'`   | `yes`: recurse and report parent + children. `only`: skip parents unless children empty |
| `subscripts`  | `false` (default), `true`             | Array processing: `true` reports each element; `false` reports unique values with `*`   |

Shortcuts: pass `'fields'`, `'keys'`, `'values'`, `'nested'`, `'nested-only'`, or `'subscripts'` as bare strings.

### 6.2 Object examples

```sql
-- Top-level keys of a movie's ratings object
SELECT object_keys(ratings) AS metrics FROM movies WHERE _id = 'tt0111161';
-- → ["imdb", "metacritic", "rotten_tomatoes"]
```

```sql
-- Overwrite a rating without errors
SELECT object_set(ratings, 'imdb', 9.4, true) AS new_ratings
FROM movies WHERE _id = 'tt0111161';
```

```sql
-- Backfill missing rating sources with defaults
SELECT object_concat({'imdb': 0, 'rotten_tomatoes': 0, 'metacritic': 0}, ratings) AS filled
FROM movies;
```

```sql
-- Remove a key
SELECT object_unset(director, 'born') AS dir_no_dob FROM movies;
```

```sql
-- Rename a key
SELECT object_rename(ratings, 'imdb', 'imdb_rating') AS renamed FROM movies;
```

```sql
-- Flatten a nested object for inspection
SELECT object_content(ratings, 'nested') AS flat FROM movies WHERE _id = 'tt0111161';
```

There is no `object_size` in v5.0.x.

---

## 7. Date / time

See [date-time-functions.md](date-time-functions.md#7-date--time) for this topic.

## 8. Duration

See [date-time-functions.md](date-time-functions.md#8-duration) for this topic.

## 9. Miscellaneous

| Signature           | Returns                                                            |
| ------------------- | ------------------------------------------------------------------ |
| `request_info()`    | `{ app_id: string, request_id: string, start_time: string }`       |

`start_time` is an ISO 8601 timestamp with a timezone offset, not epoch milliseconds
(executed on 4.14.6, 5.0.3, 5.1.0 and 5.2.0).

```sql
SELECT request_info() AS req;
```

---

## 10. Aggregates

Aggregates take a single expression evaluated per document in a group; they return one value per group. With no explicit `GROUP BY`, there is one implicit group (the entire result set). All aggregates accept a leading `DISTINCT` modifier.

| Signature                  | Returns          | Behaviour                                                                                                              |
| -------------------------- | ---------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `count([DISTINCT] expr)`   | `integer`        | Counts items where `expr` is not `NULL`/`MISSING`/`FALSE`. `count(*)` is shorthand for `count(true)`.                  |
| `sum([DISTINCT] expr)`     | `num`            | Non-numeric values silently ignored                                                                                    |
| `min(expr)` / `max(expr)`  | (input type)     | `MISSING` silently ignored; cross-type ordering rules in [`operators.md`](operators.md#3-comparison-operators) §3      |
| `avg([DISTINCT] expr)`     | `num`            | Non-numeric values silently ignored                                                                                    |
| `mid([DISTINCT] expr)`     | `num`            | `(min(expr) + max(expr)) / 2` — arithmetic midpoint of the extremes, **NOT** the statistical median. Use `median` for the middle value of a sorted set. |
| `median([DISTINCT] expr)`  | `num`            | Statistical median                                                                                                      |

### 10.1 `count` — three useful forms

```sql
-- Every document
SELECT count(*) AS total FROM movies;

-- Documents where the field is present and non-NULL
SELECT count(ratings.imdb) AS rated FROM movies;

-- Distinct values
SELECT count(DISTINCT director.name) AS directors FROM movies;
```

### 10.2 Aggregate examples

```sql
-- Headline catalogue stats
SELECT
    count(*)                       AS total_movies,
    count(ratings.imdb)            AS rated_movies,
    count(DISTINCT director.name)  AS directors,
    avg(ratings.imdb)              AS avg_imdb,
    median(ratings.imdb)           AS median_imdb,
    max(box_office_millions)       AS top_grossing,
    min(year)                      AS earliest_year
FROM movies;
```

```sql
-- Aggregates with GROUP BY — see select.md for the full clause
SELECT year, count(*) AS n, avg(ratings.imdb) AS avg_rating
FROM movies
GROUP BY year
HAVING count(*) > 1
ORDER BY year DESC;
```

### 10.3 Aggregate caveats

- **Aggregates dam the pipeline** — results stream only after every input row is consumed.
- Memory grows with the number of distinct groups and with each `DISTINCT` aggregate (every distinct value seen is retained).
- To explicitly count `NULL` / `MISSING` rows, wrap the expression: `count(ifmissingornull(field, 'sentinel'))`.
- For `GROUP BY` / `HAVING` syntax see [`select.md`](select.md) (Task 8 will create this).

---

## 11. Alphabetical function index

`abs`, `array_contains`, `array_contains_null`, `array_length`, `avg`, `byte_length`, `cast`, `ceil`, `char_length`, `character_length`, `clock`, `coalesce`, `concat`, `contains`, `count`, `date_add`, `date_cast`, `date_diff`, `date_format`, `date_part`, `date_range`, `date_sub`, `date_trunc`, `decode`, `deserialize_json`, `duration_cast`, `duration_format`, `ends_with`, `floor`, `ifmissing`, `ifmissingornull`, `ifnull`, `is_boolean`, `is_number`, `is_string`, `ismissing`, `ismissingornull`, `isnull`, `joinstr`, `json_type`, `length`, `lower`, `lpad`, `ltrim`, `max`, `median`, `mid`, `min`, `missingif`, `nullif`, `nvl`, `object_concat`, `object_content`, `object_keys`, `object_length`, `object_rename`, `object_set`, `object_unset`, `object_values`, `pos`, `regexp_like`, `repeat`, `request_info`, `rpad`, `rtrim`, `split`, `starts_with`, `substr`, `sum`, `trim`, `type`, `tz_offset`, `upper`.

---

## See also

- [`operators.md`](operators.md) — operators, precedence, 4-valued logic, `IS NULL`/`IS MISSING` predicates.
- [`expressions.md`](expressions.md) — `CASE`, subqueries, `EXISTS`, `ANY/EVERY ... SATISFIES` (v5.0+), comprehensions.
- [`select.md`](select.md) — `SELECT`, `GROUP BY`, `HAVING`, `ORDER BY`, `LIMIT`.
- [`versions.md`](versions.md) — SDK version floors for every DQL feature.
