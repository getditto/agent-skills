# Date time functions — Ditto

## Contents

- [7. Date / time](#7-date--time)
- [8. Duration](#8-duration)

Topic index: [functions.md](functions.md). Covers Ditto SDK 4.14.x (LTS),
5.0.x, 5.1.x and 5.2.0; version-specific notes remain inline. Read only the topic needed.

For movies/reviews examples, see the [schema](schema.md) only when adapting those examples; other examples define their own fields.

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
| `date_diff(d1, d2, part)`                                 | `integer`                                                        | Number of `part`s between, with sign `d1 - d2` (positive when `d1` is later than `d2`; executed on all four covered SDK versions) |
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
    date_diff(clock(), date_cast(released), 'day') AS days_since_release
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
