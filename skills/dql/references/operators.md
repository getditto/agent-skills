---
title: DQL operators reference
description: Complete operator catalog with precedence, NULL/MISSING semantics, and 4-valued logic. Covers Ditto SDK 4.14.x, 5.0.x, and 5.1.x; version-gated features are tagged inline.
---

# DQL operators reference

> All examples in this file query the `movies` / `reviews` schema documented in [`schema.md`](schema.md).

Authoritative catalog of every operator usable on **Ditto SDK 4.14.x, 5.0.x, and 5.1.x**. Sections are ordered so that the high-traffic answers (precedence, comparison, NULL/MISSING, logical) come first.

Unless a section carries an "Available in:" note, the operator works identically on 4.14.x, 5.0.x, and 5.1.x. Functions referenced from this file (`array_contains`, `regexp_like`, conditional helpers, type predicates, etc.) live in [`functions.md`](functions.md).

---

## 1. Operator precedence

Higher precedence binds tighter. When in doubt, parenthesize.

| Precedence | Operators                                                                  |
| ---------- | -------------------------------------------------------------------------- |
| 50         | `.` (member), `[]` (index/key) — postfix; bind tightest                   |
| 40         | `*`, `/`, `%`, `||` (string concat)                                        |
| 30         | binary `+`, binary `-`                                                     |
| 20         | `=`, `==`, `<>`, `!=`, `<`, `>`, `<=`, `>=`, `[NOT] BETWEEN`, `[NOT] IN`, unary `-` |
| 19         | `LIKE`, `NOT LIKE`, `ILIKE`, `NOT ILIKE`, `SIMILAR TO`                     |
| 17         | `IS [NOT] {NULL\|MISSING\|UNKNOWN\|TRUE\|FALSE}`, `IS [NOT] DISTINCT FROM` |
| 15         | unary `NOT`                                                                |
| 10         | `AND`                                                                      |
| 7          | `XOR` *(reserved word; rejected on every supported line — see §11)*        |
| 5          | `OR`                                                                       |

Postfix member access (`a.b`, `arr[i]`) binds tighter than arithmetic, so `ratings.imdb * 10` is `(ratings.imdb) * 10`. `NOT` is unary and prefix; `NOT a LIKE b` parses as `NOT (a LIKE b)` because `LIKE` (19) outranks `NOT` (15) only when `NOT` appears as a separate prefix — when `NOT` follows the term (`a NOT LIKE b`) it is folded into the comparison.

---

## 2. Arithmetic operators

`+`, `-`, `*`, `/`, `%`, and unary `-`. Operate on the numeric family (integers, floats).

- **Type promotion:** same-type-in → same-type-out. If either operand is a float, the result is a float. Mixed int/float promotes to float.
- **Overflow:** integer range overflow raises `Overflow`.
- **Divide-by-zero:** `x / 0` and `x % 0` raise `WrongArguments`.
- **NULL / MISSING:** any operand is `NULL` → result is `NULL`; any operand is `MISSING` → result is `MISSING`.

```sql
SELECT title, box_office_millions - 100 AS profit_over_100m
FROM movies
WHERE runtime_minutes * 60 > 10800            -- runtime in seconds > 3 hours

SELECT title, ratings.imdb / 2 AS half_rating FROM movies

-- unary minus
WHERE box_office_millions = -50               -- not a real movie, illustrative
```

---

## 3. Comparison operators

`=` (alias `==`), `<>` (alias `!=`), `<`, `>`, `<=`, `>=`. Return a boolean, `NULL`, or `MISSING`.

**Semantics:**

- Comparing across incompatible type families returns `FALSE` (e.g. `'5' = 5` → `FALSE`); within the numeric family, ints and floats compare as numbers.
- If either operand is `NULL`, the result is `NULL`.
- If either operand is `MISSING`, the result is `MISSING`.
- Arrays compare lexicographically (element-by-element; shorter array is "less" when prefix-equal).
- Objects compare by sorted field name, comparing values for shared keys; object with fewer keys is "less" when prefix-equal.
- `f64::NEG_INFINITY` is less than every other number; `f64::INFINITY` is greater. `f64::NAN` raises an error.

> **Q: What does `WHERE field = 5` return when `field` is `NULL`?**
> The expression evaluates to `NULL`, which is not `TRUE`, so the document is **excluded** from the result set. This is why `WHERE field = NULL` always returns zero rows — every comparison yields `NULL`. Use `IS NULL` instead (§4).

```sql
SELECT title FROM movies WHERE ratings.imdb > 8.0
SELECT title FROM movies WHERE genres = ['Drama']
SELECT _id FROM reviews WHERE score >= 4 AND comment <> ''
```

The two equality spellings (`=`/`==`) and the two inequality spellings (`<>`/`!=`) are exact synonyms. Prefer `=` and `<>` for portability with SQL-style readers; the others exist for ergonomic familiarity.

---

## 4. Unary `IS` predicates

These never return `NULL` — they always resolve to `TRUE` or `FALSE`. That makes them the only safe way to test for `NULL` / `MISSING` in a `WHERE` clause.

| Predicate           | True when                                                  |
| ------------------- | ---------------------------------------------------------- |
| `IS NULL`           | Field exists and its value is the JSON `null`              |
| `IS NOT NULL`       | Field exists with a non-null value                         |
| `IS MISSING`        | Field is absent from the document                          |
| `IS NOT MISSING`    | Field is present (any value, including `null`)             |
| `IS UNKNOWN`        | Field is `NULL` **or** `MISSING` (i.e. not a concrete value) |
| `IS NOT UNKNOWN`    | Field has a concrete value (not `NULL`, not `MISSING`)     |
| `IS TRUE`           | Operand evaluates to boolean `TRUE`                        |
| `IS NOT TRUE`       | Operand is `FALSE`, `NULL`, or `MISSING`                   |
| `IS FALSE`          | Operand evaluates to boolean `FALSE`                       |
| `IS NOT FALSE`      | Operand is `TRUE`, `NULL`, or `MISSING`                    |

`IS DISTINCT FROM` / `IS NOT DISTINCT FROM` compare two operands while treating `NULL` as a comparable value (so `NULL IS NOT DISTINCT FROM NULL` is `TRUE`).

```sql
SELECT title FROM movies WHERE director IS NOT MISSING
SELECT title FROM movies WHERE is_classic IS TRUE
SELECT _id FROM reviews WHERE comment IS UNKNOWN          -- comment NULL or absent

-- distinguishing NULL from MISSING
SELECT title FROM movies WHERE ratings IS NULL            -- field is explicitly null
SELECT title FROM movies WHERE ratings IS MISSING         -- field is absent entirely
```

---

## 5. Range and membership

### `BETWEEN`

```sql
SELECT title FROM movies WHERE year BETWEEN 1990 AND 1999
-- equivalent to (year >= 1990 AND year <= 1999)
```

The bounds are inclusive. The order matters: `BETWEEN 1999 AND 1990` is **not** equivalent to `BETWEEN 1990 AND 1999` and will match nothing.

`NOT BETWEEN` negates the whole predicate:

```sql
SELECT title FROM movies WHERE year NOT BETWEEN 2000 AND 2009
```

### `IN` (scalar list)

```sql
SELECT title FROM movies
WHERE _id IN ('tt0111161', 'tt0468569', 'tt1375666')
-- equivalent to _id = 'tt0111161' OR _id = 'tt0468569' OR _id = 'tt1375666'
```

**`IN` is for scalar lists, not array containment.** Writing `WHERE 'Drama' IN genres` does **not** test "is `'Drama'` an element of the `genres` array". For array containment use `array_contains()` (or `ANY ... SATISFIES` on v5.0+):

```sql
-- scalar 'Drama' is an element of the genres array
SELECT title FROM movies WHERE array_contains(genres, 'Drama')
```

See [`functions.md`](functions.md) for the full signatures of `array_contains` and friends.

`NOT IN` negates:

```sql
SELECT title FROM movies WHERE year NOT IN (2020, 2021, 2022)
```

`IN UNNEST(array_expr)` is also accepted to unwrap an array expression at parse time. **Subqueries are not supported inside `IN`** in either SDK 4.14.x or 5.0.x — the AST reserves an `InSubquery` node but the parser produces no path to it. Aggregate first and pass the values explicitly instead.

---

## 6. Pattern matching

| Operator         | Style          | Case   | Notes                                       |
| ---------------- | -------------- | ------ | ------------------------------------------- |
| `LIKE`           | SQL wildcards  | sensitive   | `%` = 0+ chars, `_` = exactly 1 char   |
| `ILIKE`          | SQL wildcards  | insensitive | as `LIKE` but case-folded              |
| `SIMILAR TO`     | regex-ish      | sensitive   | full regex alternation, classes, etc.  |
| `regexp_like()`  | full regex     | sensitive (default) | function form — see [`functions.md`](functions.md) |

```sql
-- starts with "The "
SELECT title FROM movies WHERE title LIKE 'The %'

-- case-insensitive substring match
SELECT title FROM movies WHERE title ILIKE '%lord of the%'

-- literal percent sign via ESCAPE
-- Use a non-backslash escape character: on SDK 5.1+ a backslash escapes the
-- closing quote, so the literal '\' is an unterminated string. '!' is portable.
SELECT comment FROM reviews WHERE comment LIKE '5!%%' ESCAPE '!'

-- full regex alternation
SELECT title FROM movies WHERE director.name SIMILAR TO '%(Coppola|Spielberg)%'

-- regexp_like for richer regex (anchors, character classes)
SELECT _id FROM reviews WHERE regexp_like(comment, '^[A-Z][a-z]+!')
```

Each pattern operator has a corresponding `NOT` form: `NOT LIKE`, `NOT ILIKE`, etc.

---

## 7. Logical operators — 4-valued logic

DQL has four logical truth values: `TRUE`, `FALSE`, `NULL`, and `MISSING`. The truth tables below are exhaustive — read them when a predicate seems to be "swallowing" rows you expect to match.

### `AND`

| `AND`   | True    | Null    | False   | Missing |
| ------- | ------- | ------- | ------- | ------- |
| True    | True    | Null    | False   | Missing |
| Null    | Null    | Null    | False   | Missing |
| False   | False   | False   | False   | False   |
| Missing | Missing | Missing | False   | Missing |

### `OR`

| `OR`    | True    | Null    | False   | Missing |
| ------- | ------- | ------- | ------- | ------- |
| True    | True    | True    | True    | True    |
| Null    | True    | Null    | Null    | Null    |
| False   | True    | Null    | False   | Missing |
| Missing | True    | Missing | Missing | Missing |

### `NOT`

| in      | out     |
| ------- | ------- |
| True    | False   |
| Null    | Null    |
| False   | True    |
| Missing | Missing |

**Filter semantics:** in a `WHERE` clause a row is kept only when the predicate is exactly `TRUE`. `NULL` and `MISSING` results both exclude the row.

```sql
-- 'is_classic AND has high IMDb' — rows where ratings is missing are excluded
SELECT title FROM movies WHERE is_classic AND ratings.imdb > 8.5

-- defend against missing fields with IS NOT MISSING / IS NOT UNKNOWN
SELECT title FROM movies
WHERE ratings IS NOT MISSING AND ratings.imdb > 8.5
```

---

## 8. String operator `||`

Concatenation. **No implicit type conversion** — cast non-string operands first or use `concat()` (see [`functions.md`](functions.md)).

```sql
-- need to cast year (an integer) before concatenating
SELECT title || ' (' || cast(year AS string) || ')' AS label
FROM movies
```

`||` has the same precedence as `*` / `/` / `%` (precedence 40), so it binds tighter than `+` and `-`. Parenthesize when mixing with arithmetic:

```sql
SELECT (title || ': ') || cast(year + 1 AS string) AS bumped FROM movies
```

---

## 9. Array and object access

### Array indexing — `array[i]`

Zero-based positional access. Out-of-range index, non-integer index, or applying `[i]` to a non-array → `MISSING`.

```sql
-- first cast member's name — backquoted because 'cast' is a keyword
SELECT title, `cast`[0].name AS lead_actor FROM movies

-- first listed genre
SELECT title, genres[0] AS primary_genre FROM movies WHERE genres[0] = 'Drama'
```

Array literals use `[...]`:

```sql
SELECT title FROM movies WHERE genres = ['Drama']
```

Elements inside an array literal must be literals or query parameters — you cannot reference fields inside an array literal.

For "does this array contain X" use `array_contains()` — `WHERE 'Drama' IN genres` does **not** mean that (see §5).

### Object field access — `object.field` or `object[expr]`

Missing key, applying `.field` to a non-object → `MISSING`.

```sql
-- dot form (typical)
SELECT title, director.name AS dir FROM movies

-- bracket form, useful when the key is dynamic or contains special chars
SELECT title, ratings['rotten_tomatoes'] AS rt FROM movies
```

Object literals use `{'k': v, ...}` syntax with string-literal keys:

```sql
SELECT _id, {'name': 'Anonymous', 'verified': false} AS placeholder_user
FROM reviews
```

Keys must be string literals or parameters; duplicate keys raise an error.

---

## 10. Critical warnings

These four mistakes cause more wrong queries than any other DQL pitfall.

### 10.1 Boolean operators are keywords, not symbols

```sql
-- WRONG — these are not DQL operators
WHERE is_classic && ratings.imdb > 8        -- parse error
WHERE genres == ['Drama'] || year < 1970    -- || here is string concat, not OR

-- CORRECT — use word forms
WHERE is_classic AND ratings.imdb > 8
WHERE genres = ['Drama'] OR year < 1970
```

`&&` and `!` are not DQL tokens. `||` **is** a DQL token, but it means **string concatenation**, never logical OR. Mixing it up silently changes types and your query may return strings instead of booleans.

### 10.2 String literals: single or double quotes; backticks are identifiers

```sql
-- Both work — single and double quotes are equivalent string delimiters in DQL
WHERE title = 'The Godfather'
WHERE title = "The Godfather"

-- Backticks are NOT a string delimiter — this looks for a column named "The Godfather"
WHERE title = `The Godfather`   -- WRONG
```

Single and double quotes both delimit string literals; only backticks delimit identifiers. Prefer single quotes for consistency with JSON-style examples.

### 10.3 `NULL` cannot be compared with `=`

```sql
-- WRONG — always evaluates to NULL, so the row is never kept
WHERE ratings = NULL
WHERE ratings != NULL

-- CORRECT
WHERE ratings IS NULL
WHERE ratings IS NOT NULL
```

See §3 for why and §4 for the full set of `IS` predicates.

### 10.4 `MISSING` is not `NULL`

`MISSING` is a distinct truth value for "field is absent from this document". `IS NULL` will not catch absent fields — use `IS MISSING` for absence, `IS UNKNOWN` for "either".

```sql
-- WRONG when you mean "no rating field on the document"
WHERE ratings IS NULL

-- CORRECT
WHERE ratings IS MISSING                    -- field absent
WHERE ratings IS UNKNOWN                    -- absent or explicitly null
```

---

## 11. `XOR` — version-gated

> **Available in:** Ditto SDK 4.x only (removed in 5.0, planned for return in 5.1)

On Ditto SDK 4.14.x, `XOR` is a binary logical operator with precedence 7 (between `AND` and `OR`). It returns `TRUE` when exactly one of its operands is `TRUE`. On Ditto SDK 5.0.x, the `XOR` keyword is tokenized and assigned a precedence but the parser does not produce an operator node for it — using it raises a parse error.

If you need exclusive-or semantics on v5.0.x, decompose:

```
a XOR b   ≡   (a OR b) AND NOT (a AND b)
```

```sql
-- Ditto SDK 4.x only: classics XOR'd against high-rated picks
SELECT title FROM movies
WHERE is_classic XOR ratings.imdb > 9.0

-- Portable across 4.x and 5.0.x — same result, no XOR keyword
SELECT title FROM movies
WHERE (is_classic OR ratings.imdb > 9.0)
  AND NOT (is_classic AND ratings.imdb > 9.0)
```

The 4-valued logic in §7 applies to the decomposed form: if either operand is `NULL` or `MISSING`, the expression resolves to `NULL` / `MISSING` and the row is excluded.

---

## See also

- [`functions.md`](functions.md) — scalar functions (`array_contains`, `regexp_like`, `coalesce`, `cast`, date helpers, type predicates, aggregates).
- [`expressions.md`](expressions.md) — `CASE`, subqueries, `EXISTS`, `ANY/EVERY ... SATISFIES` (v5.0+), array/object comprehensions (v5.0+).
- [`statements.md`](statements.md) — `SELECT`, `INSERT`, `UPDATE`, `DELETE`/`EVICT`/`TOMBSTONE` syntax.
- [`versions.md`](versions.md) — SDK version floors for every DQL feature.
