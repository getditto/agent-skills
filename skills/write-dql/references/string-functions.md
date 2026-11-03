# String functions — Ditto

## Contents

- [4. String](#4-string)
- [4.1 SQL keyword forms](#41-sql-keyword-forms)
- [4.2 `regexp_like` flags](#42-regexp_like-flags)
- [4.3 String examples](#43-string-examples)

Topic index: [functions.md](functions.md). Covers Ditto SDK 4.14.x (LTS),
5.0.x, 5.1.x and 5.2.0; version-specific notes remain inline. Read only the topic needed.

For movies/reviews examples, see the [schema](schema.md) only when adapting those examples; other examples define their own fields.

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
-- repeat: build a star-rating indicator from the IMDb score.
-- cast(... , 'integer') truncates, which is all this display needs and keeps
-- the example runnable on every supported SDK version.
SELECT title, repeat('★', cast(ratings.imdb, 'integer')) AS stars FROM movies;
```

> `round()` would read more naturally here, but it is **SDK 5.1+ only** and is not part of the catalogue in §11 — see [`versions.md`](versions.md) §4.6. On 5.1.x you can write `cast(round(ratings.imdb), 'integer')` instead.

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
