# Select access — Ditto

## Contents

- [3. USE IDS](#3-use-ids)
- [4. USE INDEX](#4-use-index)
- [5. USE DIRECTIVES](#5-use-directives)

Topic index: [select.md](select.md). Covers Ditto SDK 4.14.x (LTS),
5.0.x and 5.1.x; version-specific notes remain inline. Read only the topic needed.

For movies/reviews examples, see the [schema](schema.md) only when adapting those examples; other examples define their own fields.

## 3. USE IDS

> **SELECT-only.** `USE IDS` is supported on `SELECT` in 4.14.x, 5.0.x, and 5.1.x. On mutations it is a parse error on 4.14.x and 5.0.x, and on 5.1.x it parses on `UPDATE` (before `SET` only) but remains documented as a SELECT-only feature. `TOMBSTONE` is unavailable on every SDK version. **For mutations targeting a known id set, use `WHERE _id IN (...)` on every version** — see [`statements.md`](statements.md).

```
USE IDS ( <id_expr> [, <id_expr> ...] )
USE IDS ( <list_param> )           -- :param holding a list of ids
```

Skips the collection scan and goes directly to the indexed-by-id path.

> **Tested-SDK note:** only the single-id form of the explicit syntax is accepted by 4.14.x / 5.0.x / 5.1.0 as shipped — the multi-id list and list-parameter forms (§§3.2–3.3) currently fail with ``(...) is not supported``.
>
> You rarely need to write `USE IDS` at all on 5.0+: the planner **automatically rewrites** `_id` equality filters into an id-direct plan when it can. Harness-verified against 4.14.6 / 5.0.0 / 5.1.0 (`EXPLAIN` shows the `idScan` operator when the rewrite fires):
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
