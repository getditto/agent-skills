# Planner hints — Ditto

## Contents

- [3. Planner directives](#3-planner-directives)
- [4. USE IDS](#4-use-ids)
- [5. USE INDEX](#5-use-index)

Topic index: [indexing.md](indexing.md). Covers Ditto SDK 4.14.x (LTS),
5.0.x, 5.1.x and 5.2.0; version-specific notes remain inline. Read only the topic needed.

For movies/reviews examples, see the [schema](schema.md) only when adapting those examples; other examples define their own fields.

## 3. Planner directives

DQL exposes planner tuning via **directives**: hint-keyed JSON values that steer cost estimation and plan selection. Two surfaces deliver them — inline comments and a per-statement `USE DIRECTIVES` clause — plus the dedicated `USE INDEX` shortcut covered in §5.

### 3.1 Comment-style directives

A `/*+ … */` or `--+ …` comment immediately preceding a statement contributes a JSON object of directives that apply to that statement's plan.

```sql
-- Block comment form
/*+ {"#disable_index_scan": true} */
SELECT * FROM movies WHERE year = 2010;

-- Line comment form (closes at end-of-line)
--+ {"#prefer_order": true}
SELECT title FROM movies WHERE year >= 2000 ORDER BY ratings.imdb DESC;

-- Multiple top-level directives
/*+ {"#prefer_order": true, "#max_scans": 4} */
SELECT title FROM movies WHERE year >= 1990 ORDER BY year DESC LIMIT 100;
```

The JSON inside the directive comment is parsed strictly:

- Keys are quoted strings starting with `#` (top-level) or matching a collection alias (per-collection — see §3.3).
- Unknown keys are **silently ignored**. Typos do not raise errors.
- Malformed JSON raises a parser error.

### 3.2 `USE DIRECTIVES` clause

`USE DIRECTIVES '<json>'` is the per-`SELECT` clause-form of the comment-style directive object. The two are interchangeable on `SELECT`. See [`select.md`](select.md) §5 for the clause-level summary.

```sql
SELECT title FROM movies
USE DIRECTIVES '{"#index": ["movies_year_imdb"], "#prefer_order": true}'
WHERE year >= 2000
ORDER BY ratings.imdb DESC
LIMIT 25;
```

The clause form is supported on `SELECT` only. For non-`SELECT` statements (`UPDATE`, `DELETE`, `EVICT`, `TOMBSTONE`), use the comment-style form.

### 3.3 Top-level vs per-collection keys

Directives are scoped:

- **Top-level keys** apply to the entire statement plan. They live at the root of the JSON object.
- **Per-collection keys** apply to a single `FROM`-listed collection (matched by name or alias) and live inside a nested object keyed by that collection name.

```sql
-- Top-level: cap planner candidates to 4
-- Per-collection: pin movies to a specific index
/*+ {
  "#max_scans": 4,
  "movies": { "#index": ["movies_year_imdb"] }
} */
SELECT title FROM movies
WHERE year >= 1990
ORDER BY ratings.imdb DESC
LIMIT 10;
```

Per-collection keys are: `#prefer_order`, `#intersects`, `#index`, `#max_scans`, `#max_inlist`, `#max_serial_ranges`. Top-level-only keys are: `#disable_index_scan`, `#disable_covering`, `#disable_special`, `#disable_intersect_eo`, `#auto_use_ids`, `#reprepare`, `#profile`.

### 3.4 Recognised directive keys

| Key                     | Scope                  | Type                                              | Purpose                                                                                                                            |
| ----------------------- | ---------------------- | ------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `#disable_index_scan`   | top-level              | bool                                              | Force a full collection scan. Debugging / benchmarking.                                                                            |
| `#disable_covering`     | top-level              | bool                                              | Disable covering-index optimisation; force a document fetch even when the index has every projected column.                        |
| `#disable_special`      | top-level              | bool                                              | Disable engine-internal special-case plans (e.g. id-only fast paths).                                                              |
| `#disable_intersect_eo` | top-level              | bool                                              | Disable equality + ORDER BY intersect optimisation.                                                                                |
| `#auto_use_ids`         | top-level              | bool (default `true`)                             | Automatic rewrite of `WHERE _id = …` / `_id IN (…)` into the `USE IDS` fast path. Set `false` to keep the explicit predicate plan. |
| `#reprepare`            | top-level              | bool                                              | Force re-preparation of a cached plan. Use after schema or index changes invalidate a prior compile.                               |
| `#profile`              | top-level              | bool                                              | Request per-operator profiling info on the result. **SDK 5.0+** (see §7).                                                          |
| `#max_scans`            | top-level or per-coll. | int                                               | Hard cap on planned index scans considered.                                                                                        |
| `#intersects`           | top-level or per-coll. | int                                               | Maximum number of indexes the planner may combine in an intersect scan.                                                            |
| `#max_inlist`           | top-level or per-coll. | int                                               | Cap on the number of `IN (…)` list entries the planner will expand into per-value index probes.                                    |
| `#max_serial_ranges`    | top-level or per-coll. | int                                               | Cap on the number of serial ranges the planner emits when expanding range predicates.                                              |
| `#prefer_order`         | top-level or per-coll. | bool                                              | Bias cost estimation toward an index whose key order matches the `ORDER BY` clause.                                                |
| `#index`                | per-collection         | string \| string[] \| `null` \| `''`              | Pin / restrict / forbid indexes for that collection. `''` (or `[]`) forces a collection scan for that collection.                  |

Setting any boolean key to `false` is equivalent to omitting it (the default is recovered).

### 3.5 Per-collection example

Two collections in the same statement, each with its own pinned index:

```sql
/*+ {
  "movies":  { "#index": ["movies_year_imdb"] },
  "reviews": { "#index": ["reviews_movie_id_recent"] }
} */
SELECT r.movie_id, r.score
FROM reviews r
WHERE r.movie_id IN (
  SELECT _id FROM movies WHERE year >= 2000
);
```

Or with an alias on the `FROM` clause:

```sql
/*+ {"m": {"#index": ["movies_year_imdb"]}} */
SELECT m.title FROM movies m
WHERE m.year >= 1990
ORDER BY m.ratings.imdb DESC
LIMIT 10;
```

The directive key matches the alias `m` rather than `movies` because the alias is the canonical identifier inside the planner.

---

## 4. USE IDS

> **Cross-reference:** the canonical narrative for `USE IDS` lives in [`select.md`](select.md) §3. This section recaps the indexing-relevant facts and is the right place to look for how `USE IDS` interacts with `#auto_use_ids`, the planner, and `EXPLAIN`.

`USE IDS (id1, id2, …)` on a `SELECT` skips the collection scan and goes directly to the indexed-by-id retrieval path. It is the fastest possible query when you already know the `_id` values.

```sql
-- Multi-id: a comma-separated list. Works on 4.14.x, 5.0.x and 5.1.x.
SELECT * FROM movies USE IDS 'tt0111161', 'tt0468569';

-- Single id
SELECT * FROM movies USE IDS 'tt0111161';
```

> **Do not use the parenthesised-tuple spelling** `USE IDS ('tt0111161', 'tt0468569')` — it is rejected on **every** supported SDK version with `('tt0111161', 'tt0468569') is not supported`, because the parser reads it as one tuple expression rather than a list. The comma form above is the portable spelling. `USE IDS LIST ['a', 'b']` also works, but only on SDK 5.0+.

### 4.1 USE IDS on mutations

> **Version boundary:** `USE IDS` works on SELECT across the covered releases, on UPDATE (before `SET`) from 5.1.0, and on DELETE/EVICT from **5.2.0**. DELETE/EVICT parsed but removed nothing on 5.1.0. Use `WHERE _id IN (…)` for portable mutations. `TOMBSTONE` remains unavailable on Small Peers. Source: <https://docs.ditto.live/sdk/latest/release-notes-hub/swift>.

### 4.2 Interaction with `#auto_use_ids`

The default planner directive `#auto_use_ids` is `true`, so a `WHERE _id = …` or `WHERE _id IN (…)` clause is rewritten internally into the `USE IDS` path. Two consequences:

- You can rely on the fast path **without writing `USE IDS` explicitly**.
- The two phrasings produce the **same plan** under the default. `EXPLAIN` may report either as the `IndexScan`-by-id operator.
- Set `"#auto_use_ids": false` to suppress the rewrite — useful when you want the planner to consider a richer index that happens to lead on `_id`.

### 4.3 EXPLAIN confirms the fast path

```sql
EXPLAIN SELECT * FROM movies USE IDS ('tt0111161');
```

Expect the plan tree to root at an id-lookup operator (the exact name varies by version — both `IndexScan` and a dedicated id-fetch operator have been observed). When in doubt, compare to:

```sql
EXPLAIN SELECT * FROM movies WHERE _id = 'tt0111161';
```

Under default settings the two should produce the same plan shape.

---

## 5. USE INDEX

`USE INDEX '<name>' [ASC|DESC]` is sugar for the `#index` per-collection directive. It lives in the `SELECT` syntax — see [`select.md`](select.md) §4 for the clause-form summary.

```sql
-- Pin an index
SELECT * FROM movies USE INDEX 'movies_year_imdb' WHERE year = 2010;

-- Reverse traversal of the index
SELECT title FROM movies USE INDEX 'movies_year_imdb' DESC
WHERE year >= 1990
ORDER BY year DESC, ratings.imdb DESC
LIMIT 10;

-- Forbid any index scan (forces collection scan)
SELECT * FROM movies USE INDEX '' WHERE year = 2010;
```

Two important behaviours:

- An unknown or inapplicable index name is **silently ignored** — the planner falls back to its normal choice. There is no "fail closed" form.
- `USE INDEX ''` (empty string) is identical to `/*+ {"<collection>": {"#index": []}} */`: it forbids the planner from choosing any index for that collection.

For richer plan steering (multiple candidate indexes, combined intersect plans, etc.) reach for `USE DIRECTIVES` or the comment-style form (§3).

---
