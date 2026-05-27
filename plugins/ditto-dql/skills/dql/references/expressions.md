---
title: DQL expressions reference
description: Literals, identifiers, parameters, path expressions, CASE, quantifiers (ANY/EVERY SATISFIES), and comprehensions (ARRAY/OBJECT FOR). Covers Ditto SDK 4.14.x and 5.0.x; some features are 5.0+ only and tagged accordingly.
---

# DQL expressions reference

> All examples in this file query the `movies` / `reviews` schema documented in [`schema.md`](schema.md).

An **expression** evaluates to a value (or `NULL` / `MISSING`). This file catalogs the expression grammar usable on **Ditto SDK 4.14.x and 5.0.x** — literals, identifiers, parameters, path expressions, conditional `CASE`, the array/object quantifiers (`ANY`/`EVERY ... SATISFIES`), and the comprehension forms (`ARRAY ... FOR ...`, `OBJECT k:v FOR ...`).

Operators (arithmetic, comparison, logical, `IN`, `LIKE`, `IS NULL`, etc.) live in [`operators.md`](operators.md). Functions (`array_contains`, `cast`, `coalesce`, `regexp_like`, type predicates, aggregates, date helpers) live in [`functions.md`](functions.md). Statement-level clauses (`SELECT`, `WHERE`, `ORDER BY`, `INSERT … DOCUMENTS`, mutators) live in `statements.md` / `select.md`.

Sections that exist only on Ditto SDK 5.0+ carry an "Available in" callout. Everything else works identically on 4.14.x and 5.0.x.

---

## 1. Literals

DQL literals match JSON for arrays and objects; identifiers and quoting follow SQL conventions.

| Form         | Examples                                       |
| ------------ | ---------------------------------------------- |
| Integer      | `1`, `-42`, `1000000`                          |
| Float        | `1.5`, `-0.001`, `1.0e9`                       |
| Hex integer  | `0xff`, `0xCAFE` (uncommon; prefer decimal)    |
| Boolean      | `TRUE`, `FALSE` (case-insensitive)             |
| Null marker  | `NULL` — value known to be absent              |
| Absence      | `MISSING` — field is not present (see below)   |
| String       | `'hello'`, `'O''Reilly'` (escape `'` with `''`) |
| Array        | `[]`, `[1, 'a', { 'k': 1 }]`                   |
| Object       | `{}`, `{ 'name': 'Alice', 'age': 30 }`         |

Array and object literals accept a trailing comma. Both forms can mix any expression types — including nested literals and (for parameters and path expressions) computed values. Object keys must be string literals or parameters; duplicate keys raise an error.

```sql
SELECT * FROM movies WHERE year = 1994
SELECT * FROM movies WHERE genres = ['Drama', 'Crime']
SELECT * FROM movies WHERE director = { 'name': 'Christopher Nolan', 'born': 1970 }
```

### `NULL` vs `MISSING` (forward link)

Literal `NULL` and `MISSING` are allowed in expressions, but you almost never want to compare to them with `=`. Use the `IS [NOT] NULL` / `IS [NOT] MISSING` / `IS [NOT] UNKNOWN` predicates instead — see [`operators.md`](operators.md) §4 for the full table and §10.3 / §10.4 for the gotchas. Writing `MISSING` as an object value (`{'a': missing, 'b': null}`) is identical to omitting the key.

---

## 2. Identifiers

Case-sensitive. Two forms:

- **Regular identifier** — `[A-Za-z_][A-Za-z0-9_]*`. Examples: `title`, `_id`, `release_year`. `1abc` is not a regular identifier.
- **Delimited identifier** — backtick-wrapped. Any characters allowed; escape an inner backtick with two backticks. Examples: `` `1abc` ``, `` `release year` ``, `` `ratings.imdb` `` (a field literally named `ratings.imdb`, not a path), `` `some ``person`` foo` ``.

Single quotes and double quotes both delimit **string literals** in DQL — `'foo'` and `"foo"` are equivalent. Only backticks delimit identifiers. If you want an identifier with special characters, use backticks.

You must delimit an identifier when it:

1. Starts with a digit (`` `1abc` ``).
2. Contains `.`, spaces, or other non-`[A-Za-z0-9_]` characters.
3. Collides with a contextual SQL keyword. The most common offenders in this codebase:
   - `` `cast` `` — when used as a field name. The `cast` field on `movies` (the array of actors) shadows the `cast()` function and the `CAST(... AS ...)` keyword. See the `array_length(`cast`)` example in [`functions.md`](functions.md).
   - `` `trim` `` — when calling the function as a regular call. `TRIM(...)` is a reserved keyword form, so `trim('  hello  ')` parses but `` `trim`('  hello  ') `` is the unambiguous form. See [`functions.md`](functions.md) §4.
   - `` `year` ``, `` `month` ``, `` `day` `` — clash with `EXTRACT(YEAR FROM ...)` only inside the `EXTRACT` clause; safe as plain field names elsewhere, but backtick if a query gets parser-confused.

The parser only treats a word as a keyword when grammar position allows it: `SELECT * FROM where` works because `WHERE` cannot appear right after `FROM`; `SELECT * FROM collection` fails because `COLLECTION` is allowed there.

```sql
-- Collision: cast is the actor-array field; backtick to read it
SELECT title, array_length(`cast`) AS cast_size FROM movies
ORDER BY cast_size DESC LIMIT 5
```

---

## 3. Parameters

Syntax: `:identifier`. The name follows the identifier rules, so you can delimit it: `` :`1bc` ``, `` :`my param` ``. SDKs bind parameter values by name.

Parameters are accepted in:

- `WHERE` clauses
- `ORDER BY` expressions
- `LIMIT` and `OFFSET`
- The `DOCUMENTS` / `VALUES` clause of `INSERT`
- Mutator values (`UPDATE movies SET title = :new_title`)
- Function arguments and anywhere a value expression is grammatically allowed

```sql
-- Bind { year: 1994 } from the SDK call
SELECT title, ratings.imdb FROM movies
WHERE year = :year
ORDER BY ratings.imdb DESC
LIMIT :limit
```

Parameters never appear bare on the **left** of a path operator (no `:p.field`), and they cannot stand in for an identifier — they're values, not names. To parameterize an identifier (a field name), build the query string in your application.

---

## 4. Path expressions

Used to read top-level and nested fields. **Collection names cannot appear inside a path** — `movies.title` is illegal; you select `title` from `FROM movies`.

```text
PathExpr ::= Identifier ( '.' Identifier | '[' Expression ']' )*
```

Resolution rules:

- The first identifier `_id` resolves to the document id; otherwise it resolves to a top-level field.
- `.field` returns `MISSING` when the LHS isn't an object / attachment / Map CRDT, or when the field doesn't exist.
- `[expr]` is zero-based positional access on arrays; returns `MISSING` when the LHS isn't an array, the index isn't a non-negative integer, or the index is out of range.
- For a Map CRDT, both the field name **and** the expected CRDT subtype must match — otherwise `MISSING`.

### Examples against `movies`

Given a movie with `director` as a Map CRDT (`{name, born}`) and `cast` as a REGISTER array of objects (`[{name, role}, …]`):

| Expression                  | Meaning                                                         |
| --------------------------- | --------------------------------------------------------------- |
| `_id`                       | Document id (string in our dataset). Never `MISSING`.           |
| `title`                     | Top-level register. `MISSING` if absent.                        |
| `director.name`             | `name` inside the `director` Map CRDT.                          |
| `cast[0].name`              | Name of the first cast entry.                                   |
| `cast[10].name`             | `MISSING` if `cast` has fewer than 11 entries.                  |
| `ratings.imdb`              | `imdb` register inside the `ratings` Map CRDT.                  |
| `` `ratings.imdb` ``        | A top-level register *literally* named `ratings.imdb` (rare).   |
| `` `cast` ``                | The `cast` array — backticked because `cast` is a SQL keyword.  |

```sql
-- nested path
SELECT title, director.name AS director FROM movies

-- array index + nested field
SELECT title, cast[0].name AS lead_actor FROM movies

-- backticked path part — field literally named "ratings.imdb"
-- (only useful if your data has such a field; unusual)
SELECT _id, `ratings.imdb` FROM movies
```

For dynamic key access (`ratings['rotten_tomatoes']`) and array literal containment (`['Drama']`), see [`operators.md`](operators.md) §9.

---

## 5. `CASE` — simple form

Matches `expression` against each `value-expr` in order; first match wins. No match and no `ELSE` returns `NULL`.

```text
CASE expression
  WHEN value-expr THEN result-expr
  [ WHEN value-expr THEN result-expr ] ...
  [ ELSE default-expr ]
END
```

```sql
-- Genre score keyed off the first listed genre
SELECT
  title,
  CASE genres[0]
    WHEN 'Drama'  THEN 1
    WHEN 'Comedy' THEN 2
    WHEN 'Action' THEN 3
    ELSE 0
  END AS genre_score
FROM movies
ORDER BY genre_score DESC, title
```

`CASE` is shorthand for chained ternaries. For two-branch decisions, `IF(cond, t, f)` (see [`functions.md`](functions.md)) is more compact; for null-coalescing chains, prefer `coalesce(...)`.

---

## 6. `CASE` — searched form

Each `WHEN` is an independent boolean predicate. The first one that evaluates to `TRUE` wins. `NULL` / `MISSING` predicates skip to the next branch; no match and no `ELSE` returns `NULL`.

```text
CASE
  WHEN cond-expr THEN result-expr
  [ WHEN cond-expr THEN result-expr ] ...
  [ ELSE default-expr ]
END
```

```sql
-- IMDb verdict — defends against missing ratings via IS MISSING
SELECT
  title,
  CASE
    WHEN ratings.imdb >= 9 THEN 'masterpiece'
    WHEN ratings.imdb >= 7 THEN 'good'
    WHEN ratings.imdb IS MISSING THEN 'unrated'
    ELSE 'meh'
  END AS verdict
FROM movies
ORDER BY title
```

Two practical notes:

- Branch conditions are evaluated top-to-bottom; **order them most-specific-first**. The two examples above both put the high-rating bucket before the catch-all `ELSE`.
- A `WHEN ratings.imdb IS MISSING` arm has to come **before** any branch that reads `ratings.imdb`, because `ratings.imdb >= 9` on a missing field evaluates to `MISSING` (which is not `TRUE`, so the branch is skipped — but no error). Putting the `IS MISSING` arm first keeps the intent explicit.

For two-way conditionals and null-coalescing, see `IF` / `IFNULL` / `coalesce` in [`functions.md`](functions.md).

---

## 7. `ANY ... IN ... SATISFIES ... END`

> **Available in:** Ditto SDK 5.0+ (not supported in 4.14.x).

Existential quantifier over an array or object. Returns `TRUE` as soon as one element satisfies the condition; `FALSE` if no element matches; `NULL` if the source isn't an array/object; `MISSING` if the source is missing.

```text
ANY  (NameVar:)? ValueVar  IN  Expression  SATISFIES Condition END
```

- `ValueVar` binds each element value.
- `NameVar` (optional) binds the array index (number) or object key (string).
- `IN` iterates the **direct** children only.

```sql
-- Movies featuring Morgan Freeman
SELECT title FROM movies
WHERE ANY actor IN `cast` SATISFIES actor.name = 'Morgan Freeman' END

-- Movies whose ratings object contains at least one score above 9.0
SELECT title FROM movies
WHERE ANY k:v IN ratings SATISFIES v > 9.0 END
```

For simple "does this array literally contain X" tests, `array_contains(genres, 'Drama')` is more compact than `ANY g IN genres SATISFIES g = 'Drama' END` and works on 4.14.x too. See [`functions.md`](functions.md) §5.

---

## 8. `EVERY ... IN ... SATISFIES ... END`

> **Available in:** Ditto SDK 5.0+ (not supported in 4.14.x).

Universal quantifier — every element must satisfy the condition. **An empty source satisfies `EVERY`** (vacuously true).

```sql
-- Movies where every cast entry has a non-empty role string
SELECT title FROM movies
WHERE EVERY actor IN `cast` SATISFIES actor.role IS NOT MISSING AND actor.role <> '' END

-- Movies whose every rating in the ratings object is at least 7.0
SELECT title FROM movies
WHERE EVERY k:v IN ratings SATISFIES v >= 7.0 END
```

A common pitfall: `EVERY ... SATISFIES` over an empty / missing array returns `TRUE`. If you mean "has at least one entry **and** every entry passes", use the next form.

---

## 9. `ANY AND EVERY ... IN ... SATISFIES ... END`

> **Available in:** Ditto SDK 5.0+ (not supported in 4.14.x).

Like `EVERY`, but an empty (or missing) source returns `FALSE`. Use this when you want "non-empty **and** all pass".

```sql
-- Movies that have a cast and every entry has a recorded role
SELECT title FROM movies
WHERE ANY AND EVERY actor IN `cast`
  SATISFIES actor.role IS NOT MISSING AND actor.role <> '' END
```

---

## 10. `IN` vs `WITHIN` inside quantifiers and comprehensions

> **Available in:** the `IN` form works on Ditto SDK 5.0+ (the whole quantifier syntax is 5.0+). The `WITHIN` keyword is also 5.0+ and additionally introduces a recursive iteration mode.

Both `IN` and `WITHIN` appear inside the same quantifier/comprehension grammar:

- `IN` — iterates the **direct** children of the source.
- `WITHIN` — recurses into nested arrays/objects, binding **every** value seen at any depth.

```sql
-- IN: any score directly in the ratings object is null
SELECT title FROM movies
WHERE ANY v IN ratings SATISFIES v IS NULL END

-- WITHIN: any value anywhere in ratings (incl. inside nested objects) is null
SELECT title FROM movies
WHERE ANY v WITHIN ratings SATISFIES v IS NULL END
```

### `WITHIN` + `IS MISSING` — the gotcha

Because `WITHIN` recurses *into* values, an `IS MISSING` predicate can become true on a recursively-bound scalar that has no fields at all:

```sql
-- Looks like "any nested object lacks key a", but it's also TRUE because
-- WITHIN binds the scalar 1 next, and 1.a IS MISSING is TRUE (scalars
-- have no fields).
ANY x WITHIN [{'a': 1}] SATISFIES x.a IS MISSING END
-- => TRUE (probably not what was intended)
```

Rule of thumb: when you want to check immediate children, use `IN`. Reserve `WITHIN` for "anywhere in this tree". And when combining `WITHIN` with `IS MISSING` / `IS NULL`, qualify with a type predicate (`object_length(x) > 0`, `array_length(x) > 0`, or `x IS NOT MISSING`) to filter the unexpected scalar bindings.

---

## 11. `ARRAY expr FOR ... IN ... [WHEN ...] END`

> **Available in:** Ditto SDK 5.0+ (not supported in 4.14.x).

Array comprehension — build a new array from a source array or object. Elements where the projection evaluates to `MISSING` are omitted from the result.

```text
ARRAY ValueExpr FOR (NameVar:)? ValueVar (IN | WITHIN) Source [WHEN Condition] END
```

```sql
-- Pull just the cast names out of the cast array of objects
SELECT
  _id,
  title,
  ARRAY actor.name FOR actor IN `cast` END AS cast_names
FROM movies

-- Pull names of cast members whose role string starts with "Lead"
SELECT
  _id,
  ARRAY actor.name FOR actor IN `cast` WHEN actor.role LIKE 'Lead%' END AS leads
FROM movies

-- Build an array of rating-keys whose score is at least 8
SELECT
  _id,
  title,
  ARRAY k FOR k:v IN ratings WHEN v >= 8 END AS strong_ratings
FROM movies
```

Comprehensions are the cleanest way to project nested data into a flat shape directly in DQL — without them you'd have to denormalize at write time or post-process on the client.

---

## 12. `OBJECT NameExpr : ValueExpr FOR ... IN ... [WHEN ...] END`

> **Available in:** Ditto SDK 5.0+ (not supported in 4.14.x).

Object comprehension — build a new object. `NameExpr` must evaluate to a string. `ValueExpr` must not be `MISSING` (entries with missing values are dropped). Duplicate names silently overwrite.

```text
OBJECT NameExpr : ValueExpr FOR (NameVar:)? ValueVar (IN | WITHIN) Source [WHEN Condition] END
```

```sql
-- Build an actor->role map from the cast array
SELECT
  _id,
  title,
  OBJECT actor.name : actor.role FOR actor IN `cast` END AS cast_by_name
FROM movies

-- Normalize ratings: uppercase the keys, keep the values
SELECT
  _id,
  title,
  OBJECT upper(k) : v FOR k:v IN ratings END AS RATINGS
FROM movies

-- Build "field_0", "field_1", … from a positional array
SELECT
  _id,
  OBJECT 'genre_' || cast(i, 'string') : g FOR i:g IN genres END AS genre_slots
FROM movies
```

---

## See also

- [`operators.md`](operators.md) — arithmetic, comparison, `IN`, `LIKE`, `IS NULL` / `IS MISSING`, 4-valued logic, `XOR` (v4 only).
- [`functions.md`](functions.md) — `array_contains`, `cast`, `coalesce`, `IF` / `IFNULL`, `regexp_like`, date helpers, aggregates.
- [`statements.md`](statements.md) — where these expressions are legal (`WHERE`, `ORDER BY`, projections, mutator values).
- [`versions.md`](versions.md) — SDK version floors for every DQL feature.
