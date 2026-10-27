# Compatibility expressions — Ditto

## Contents

- [4.3 Expressions](#43-expressions)
- [4.5 Operators with cross-version differences](#45-operators-with-cross-version-differences)
- [4.6 Scalar and aggregate functions](#46-scalar-and-aggregate-functions)

Topic index: [versions.md](versions.md). Covers Ditto SDK 4.14.x (LTS),
5.0.x and 5.1.x; version-specific notes remain inline. Read only the topic needed.

For movies/reviews examples, see the [schema](schema.md) only when adapting those examples; other examples define their own fields.

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
