---
title: DQL functions reference
description: Complete built-in function catalog for Ditto DQL (math, string, array, object, date, duration, aggregates). Covers Ditto SDK 4.14.x and 5.0.x.
---

# DQL functions reference

Authoritative catalog of every predefined function in DQL on **Ditto SDK 4.14.x and 5.0.x**. Function names are **case-insensitive**. Examples use the `movies` and `reviews` collections from the [`movies-cookbook.md`](../examples/movies-cookbook.md).

Every function in this catalog exists in **both** Ditto SDK 4.14.x and 5.0.x. Version-gated functions (none in this list, but watch for `serialize_json` and `object_size` arriving in v5.1) will carry an explicit `Available in:` tag. For operator syntax (`+`, `||`, `LIKE`, `IS NULL`, etc.) see [`operators.md`](operators.md).

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

`type()` distinguishes integer and float; `json_type()` collapses them to `number`. There is no `serialize_json` in v5.0.x — render JSON in the application layer.

---

## 4. String

| Signature                                  | Returns      | Notes                                                                                       |
| ------------------------------------------ | ------------ | ------------------------------------------------------------------------------------------- |
| `byte_length(str)`                         | `integer`    | UTF-8 byte count (up to 4 per char)                                                          |
| `char_length(str)` / `character_length(str)` | `integer`  | Character count                                                                              |
| `length(str)`                              | `integer`    | Deprecated alias of `byte_length`                                                            |
| `concat(s1, s2, ...)`                      | `string`     | Multi-arg concatenation; same engine as the `||` operator                                    |
| `contains(str, substr)`                    | `bool`       | Substring test                                                                               |
| `starts_with(str, substr)`                 | `bool`       | Prefix test                                                                                  |
| `ends_with(str, substr)`                   | `bool`       | Suffix test                                                                                  |
| `ltrim(str[, chars])`                      | `string`     | Trim from start                                                                              |
| `rtrim(str[, chars])`                      | `string`     | Trim from end                                                                                |
| `` `trim`(str[, chars]) ``                 | `string`     | Trim from both ends. **The bare name `trim` is a SQL keyword** — backtick the identifier when calling the function form, or use `TRIM(...)` syntax below. |
| `upper(str)` / `lower(str)`                | `string`     | Case conversion                                                                              |
| `repeat(char, count)`                      | `string`     | Repeat first character of `char` `count` times                                               |
| `split(str, delim)`                        | `array<str>` | Empty `delim` splits per character                                                            |
| `joinstr(sep, v, ...)`                     | `string`     | Joins values with `sep`; non-strings coerced; nested arrays flattened. First `NULL`/`MISSING` short-circuits to that. |
| `substr(str, start[, len])`                | `string`     | Zero-based index                                                                              |
| `pos(str, substr)`                         | `integer`    | Zero-based index of first match; `-1` if not found                                            |
| `lpad(str, len[, char])`                   | `string`     | Left-pad with first char of `char` (default space)                                            |
| `rpad(str, len[, char])`                   | `string`     | Right-pad with first char of `char` (default space)                                           |
| `regexp_like(src, pattern[, flags])`       | `bool`       | Regex match. Flag table below.                                                                |

### 4.1 SQL keyword forms

DQL accepts SQL-flavoured alternatives for three string operations. They are aliases of the function-form entries above.

```sql
-- POSITION(substr IN str) is alternative syntax for pos(str, substr)
SELECT title, POSITION('The' IN title) AS where_the FROM movies;
SELECT title, pos(title, 'The')        AS where_the FROM movies;
```

```sql
-- TRIM([LEADING | TRAILING | BOTH] [chars FROM] expr) covers ltrim/rtrim/trim
SELECT TRIM(LEADING  '0' FROM '00042')  AS no_leading;     -- '42'
SELECT TRIM(TRAILING ' ' FROM 'hi   ')   AS no_trailing;    -- 'hi'
SELECT TRIM(BOTH     '*' FROM '**core**') AS no_stars;      -- 'core'
SELECT TRIM('  hello  ')                 AS trimmed;        -- 'hello' (BOTH ' ' is default)
```

If you want the function form rather than the keyword form, quote the identifier:

```sql
-- bare `trim` clashes with the SQL keyword — backtick it
SELECT `trim`('  hello  ') AS trimmed FROM movies LIMIT 1;
```

### 4.2 `regexp_like` flags

`regexp_like(src, pattern[, flags])` — `flags` is a string of single-character switches; if a flag and its opposite both appear, the rightmost wins.

| Flag      | Meaning                                                                  |
| --------- | ------------------------------------------------------------------------ |
| `c`       | Case sensitive (default)                                                  |
| `i`       | Case insensitive                                                          |
| `m`       | Multi-line — `^` and `$` also match at `\n` boundaries                    |
| `n` / `s` | `.` matches `\n` as well                                                  |
| `x`       | Ignore whitespace in pattern (unless escaped)                             |

```sql
-- Reviews mentioning any of three positive adjectives, case-insensitively
SELECT _id, score FROM reviews
WHERE regexp_like(comment, '(amaz|fantast|brilliant)', 'i');
```

### 4.3 String examples

```sql
-- Movies whose title starts with "The "
SELECT title FROM movies WHERE starts_with(title, 'The ');
```

```sql
-- Build a display label two ways (functionally equivalent)
SELECT concat(title, ' (', cast(year, 'string'), ')') AS label FROM movies;
SELECT       title || ' (' || cast(year, 'string') || ')' AS label FROM movies;
```

```sql
-- Comment length stats — beware: byte_length counts UTF-8 bytes, char_length counts characters
SELECT _id,
    byte_length(comment) AS bytes,
    char_length(comment) AS chars
FROM reviews;
```

```sql
-- Substring & case
SELECT title, upper(substr(title, 0, 3)) AS prefix FROM movies;
```

```sql
-- Joinstr is friendlier than chained || for mixed types
SELECT _id, joinstr(' | ', title, year, ratings.imdb) AS summary FROM movies;
```

```sql
-- repeat: build a star-rating indicator from the IMDb score
SELECT title, repeat('★', cast(round(ratings.imdb), 'integer')) AS stars FROM movies;
```

```sql
-- lpad: zero-pad the year for fixed-width display
SELECT title, lpad(cast(year, 'string'), 4, '0') AS year_padded FROM movies;
```

```sql
-- rpad: right-pad the title to a fixed width with dots
SELECT rpad(title, 30, '.') AS title_padded FROM movies;
```

```sql
-- split: tokenise a comment on whitespace
SELECT split(comment, ' ') AS tokens FROM reviews LIMIT 1;
```

---

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

Dates are either **epoch milliseconds (UTC, integer)** or **ISO-style strings**. Functions that take a `format` accept either percent-style (`%F %T%.f %z`) or SQL-style (`YYYY-MM-DD hh:mm:ss.sss TZD`).

**Parts** (used by `date_add`, `date_sub`, `date_diff`, `date_trunc`):
`year` · `mon`/`month` · `day` · `hour` · `min`/`minute` · `sec`/`second` · `ms`/`millis`/`millisecond`.

`date_part` accepts everything above **plus**: `weekday` (ISO8601, Monday=1), `monthname` (English full name), `tz`/`timezone` (string `±hh:mm`).

| Signature                                                 | Returns                                                          | Notes                                                              |
| --------------------------------------------------------- | ---------------------------------------------------------------- | ------------------------------------------------------------------ |
| `date_cast(string[, format])`                             | `integer` (epoch ms, UTC)                                        | String → epoch                                                      |
| `tz_offset(string[, format])`                             | `integer` (minutes)                                              | TZ offset from a date string                                        |
| `clock([format[, tz]])`                                   | `integer` (epoch ms) or `string` (when `format` given)           | Current wall-clock time                                             |
| `date_format(date, format[, tz])`                         | `string`                                                         | Date → formatted string                                              |
| `date_add(date, part, count[, format[, tz]])`             | `integer` or `string` (matches input, or `format` if given)      | Add `count` of `part`; negative subtracts                            |
| `date_sub(date, part, count[, format[, tz]])`             | same as above                                                    | Sign-flipped `date_add`                                              |
| `date_diff(d1, d2, part)`                                 | `integer`                                                        | Number of `part`s between. Result is `d2 - d1` (positive when `d2` is later than `d1`) |
| `date_range(start, end, part, count[, format[, tz]])`     | `array<date>`                                                    | Half-open `[start, end)` stepping by `count`-`part`s                 |
| `date_part(date, part)`                                   | `integer` or `string`                                            | Extract one part                                                     |
| `date_trunc(date, part)`                                  | `integer` (epoch input) or `string` (ISO output for string input)| Zero subsequent fields                                               |

```sql
-- Movies released this year
SELECT title FROM movies
WHERE date_part(date_cast(released), 'year')
    = date_part(clock(), 'year');
```

```sql
-- date_add: warranty expires 90 days after each review
SELECT _id,
    date_format(
        date_add(date_cast(created_at), 'day', 90),
        'YYYY-MM-DD'
    ) AS warranty_end
FROM reviews;
```

```sql
-- date_format: render the release date in a human-readable form
SELECT title,
    date_format(date_cast(released), 'YYYY-MM-DD') AS d
FROM movies WHERE _id = 'tt0111161';
```

```sql
-- Days since release
SELECT title,
    date_diff(date_cast(released), clock(), 'day') AS days_since_release
FROM movies
ORDER BY days_since_release ASC LIMIT 10;
```

```sql
-- Every Monday between two dates (date_range)
SELECT date_range('2024-03-01', '2024-04-01', 'day', 1) AS march_days;
```

```sql
-- date_sub mirrors date_add with sign flipped
SELECT title,
    date_format(
        date_sub(date_cast(released), 'year', 10),
        'YYYY'
    ) AS released_minus_decade
FROM movies WHERE _id = 'tt0111161';
```

```sql
-- date_trunc to the start of the year
SELECT date_trunc(date_cast(released), 'year') AS year_start FROM movies;
```

```sql
-- TZ offset (in minutes) embedded in an ISO timestamp
SELECT _id, tz_offset('2024-06-15T14:00:00-05:00') AS minutes_off FROM reviews LIMIT 1;
```

---

## 8. Duration

| Signature                              | Returns    | Notes                                                                                                                                                |
| -------------------------------------- | ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `duration_cast(str[, unit])`           | `integer`  | Parse a duration string like `1h23m54.07s`; return count in `unit` (default ms). Units: `seconds`/`sec`, `milliseconds`/`ms`, `microseconds`/`us`/`μs`, `nanoseconds`/`ns`. |
| `duration_format(value[, unit])`       | `string`   | Format a number (treated as `unit`, default ms) as a duration string.                                                                                |

```sql
-- A runtime hint stored as "2h22m" → seconds
SELECT duration_cast('2h22m', 'seconds');                  -- 8520
```

```sql
-- Render watch_count as a fake "duration" string (illustrative)
SELECT title, duration_format(watch_count, 'ms') AS watched_for FROM movies;
```

---

## 9. Miscellaneous

| Signature           | Returns                                                            |
| ------------------- | ------------------------------------------------------------------ |
| `request_info()`    | `{ app_id: string, request_id: string, start_time: number }`       |

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
