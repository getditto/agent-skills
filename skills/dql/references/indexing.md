---
title: DQL indexing and query optimization
description: CREATE INDEX, DROP INDEX, USE IDS/INDEX/DIRECTIVES, planner directives (full key catalog), EXPLAIN, and the #profile directive (5.0+). Covers Ditto SDK 4.14.x, 5.0.x, and 5.1.x; version-gated features are tagged inline.
---

# DQL indexing and query optimization

> All examples in this file query the `movies` / `reviews` schema documented in [`schema.md`](schema.md).

Deep reference for index DDL, the planner-directive surface, and query-plan inspection on **Ditto SDK 4.14.x, 5.0.x, and 5.1.x**. Indexing in DQL is currently a **Small-Peer-only** feature; `CREATE INDEX` against a Big-Peer collection returns an error.

Unless a section carries an "Available in:" note, everything below works identically on 4.14.x, 5.0.x, and 5.1.x.

Cross-references:

- `SELECT` grammar including the thin `USE IDS` / `USE INDEX` / `USE DIRECTIVES` summary → [`select.md`](select.md) §§3–5
- Top-level statements including the `EXPLAIN` wrapper and the v5.0+ `PROFILE` keyword → [`statements.md`](statements.md) §§6, 10
- Path expressions and parameter syntax used inside index keys → [`expressions.md`](expressions.md)
- CRDT field types — only `REGISTER` fields are indexable; `MAP`, `COUNTER`, `PN_COUNTER`, `ATTACHMENT` are not → [`types-mutators.md`](types-mutators.md)
- SDK compatibility matrix → `versions.md` (forthcoming reference)

---

## 1. CREATE INDEX

Build a secondary index on one or more REGISTER fields of a collection. Indexes accelerate `WHERE` filtering, `ORDER BY` traversal, and (when covering) projection-only scans.

### 1.1 Grammar

```
CREATE INDEX [ IF NOT EXISTS ] <index_ref> ( <key> [, <key> ...] )

<index_ref> ::=
    <name> ON <collection>                  -- Form A
  | <collection> '.' <name>                 -- Form B
  | <name> '.' <collection>                 -- Form C (uses collection.name parse path; see below)

<key> ::= <path>
           [ ASC | DESC ]
           [ INCLUDE MISSING | EXCLUDE MISSING ]   -- parses, but NOT IMPLEMENTED on any SDK version

<path>       ::= <ident> [ '.' <ident> ... ]   -- nested paths use dot syntax
<collection> ::= [ <datasource> ':' ] <ident>
```

- `ASC` is the default sort direction.
- `INCLUDE MISSING` / `EXCLUDE MISSING` is **in the grammar but not implemented on any supported SDK version.** 4.14.6 and 5.0.3 reject it with `not implemented yet : index key not including missing`; 5.1.0 with `not implemented yet : index with include_missing=false`. Omit the modifier and take the system default — documents lacking the key get an index entry against a `MISSING` sentinel.
- Index names must be unique **per collection**. Two collections may each have an index named `by_year`.
- Without `IF NOT EXISTS`, creating an index that already exists raises an error.
- The two written forms are equivalent. Pick one and stick with it codebase-wide.

### 1.2 Form A — `name ON collection`

> **Available in:** composite (multi-column) indexes require Ditto SDK **5.1+**. Single-column and nested-path indexes work on all supported versions.

```sql
-- Composite (year asc, rating desc) — requires SDK 5.1+
CREATE INDEX IF NOT EXISTS movies_year_imdb
  ON movies (year ASC, ratings.imdb DESC);
```

> **Available in:** all supported versions (4.14.x, 5.0.x, 5.1.x) — the single-column and nested-path index examples below.

```sql
-- Single ascending key
CREATE INDEX IF NOT EXISTS movies_year ON movies (year);

-- Descending — useful for "newest first" patterns
CREATE INDEX IF NOT EXISTS movies_year_desc ON movies (year DESC);

-- Nested path
CREATE INDEX IF NOT EXISTS movies_director_name
  ON movies (director.name);

-- Composite (multi-column) — SDK 5.1+ only
CREATE INDEX reviews_score_recent
  ON reviews (score DESC, created_at DESC);
```

> `INCLUDE MISSING` / `EXCLUDE MISSING` is deliberately absent from these examples — the modifier parses but is not implemented on any supported SDK version. See §1.1.


### 1.3 Form B — `collection.name`

> **Available in:** composite (multi-column) keys require Ditto SDK **5.1+**. The `collection.name` dotted form of both statements works the same on all supported versions.

```sql
CREATE INDEX IF NOT EXISTS movies.movies_year_imdb
  (year ASC, ratings.imdb DESC);

CREATE INDEX reviews.by_movie_recent
  (movie_id ASC, created_at DESC);
```

### 1.4 Indexing nested paths

Either dot syntax or backticked path syntax works on all three SDK versions. Both forms below are valid and address the same field:

```sql
CREATE INDEX movies_imdb  ON movies (ratings.imdb DESC);
CREATE INDEX movies_imdb2 ON movies (`ratings.imdb` DESC);
```

Use backticks whenever a path segment contains characters that would otherwise tokenise oddly (spaces, hyphens, reserved words).

### 1.5 What an index covers

An index entry holds the indexed keys plus the document `_id`. A query is **covering** when every column it needs (in `SELECT`, `WHERE`, and `ORDER BY`) is present in the index, so the planner can satisfy the query from the index alone without fetching the underlying document. See §8 for the ESR rule that drives index-key ordering.

---

## 2. DROP INDEX

Tear down an index that's no longer paying for its disk and write-amplification cost.

### 2.1 Grammar

```
DROP INDEX [ IF EXISTS ] <index_ref>

<index_ref> ::= <name> ON <collection>
              | <collection> '.' <name>
```

- Without `IF EXISTS`, dropping a missing index raises an error.
- The two forms mirror `CREATE INDEX`.

### 2.2 Examples

```sql
DROP INDEX IF EXISTS movies_year_imdb ON movies;
DROP INDEX movies.movies_year_imdb;
DROP INDEX IF EXISTS reviews.by_movie_recent;
```

Inspect existing indexes via `EXPLAIN` (§6) on a representative query — there is **no** portable `SHOW INDEXES` statement on either 4.14.x or 5.0.x.

---

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

### 4.1 USE IDS is SELECT-only

On 4.14.x and 5.0.x, `USE IDS` is a parse error on `UPDATE`, `EVICT`, `TOMBSTONE` and `DELETE`. On 5.1.x it parses on `UPDATE` (pre-`SET` only); `USE IDS` remains documented as a SELECT-only feature and should not be used on mutations. **For mutations, use `WHERE _id IN (…)` on every SDK version** — see [`statements.md`](statements.md).

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

## 6. EXPLAIN

`EXPLAIN <statement>` returns the planner's chosen plan **without executing** the statement. See [`statements.md`](statements.md) §6 for the leading-keyword form; this section focuses on what you should be looking for in the output.

### 6.1 Recognising the operator family

The plan is a tree of operators. Common operators and what they mean:

| Operator                       | Meaning                                                                                                                | Read as                                  |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- |
| `IndexScan`                    | Reads entries from a named secondary index. The plan node lists `name` of the index.                                   | "Index hit — good."                      |
| `IndexScan` (id index)         | Same operator, but the index is the primary `_id` index. This is the `USE IDS` / `WHERE _id = …` fast path.            | "Best case — point lookup."              |
| `CollectionScan` / `Scan`      | Full document scan. No index used.                                                                                     | "Worst case for filterable predicates."  |
| `Intersect`                    | Combines multiple `IndexScan` children whose document-id sets are intersected. Triggered by AND-joined predicates.     | "Two indexes combined under AND."        |
| `Union`                        | Combines multiple `IndexScan` children whose document-id sets are unioned. Triggered by OR-joined predicates.          | "Two indexes combined under OR."         |
| `Fetch`                        | Materialise a full document for an id emitted by an index scan. Absent on covering plans.                              | "Index lookup → document fetch."         |
| `Filter`                       | Post-scan predicate evaluation for predicates the index could not satisfy.                                             | "Residual WHERE."                        |
| `Sort` / `OrderBy`             | In-memory sort. Appears when no index satisfies the `ORDER BY`.                                                        | "Sort cost — consider index."            |
| `Limit` / `Project`            | Top-of-plan trimming / projection nodes.                                                                               | Plumbing.                                |

> **Output shape is not a stable contract.** Field names like `#operator`, `children`, `collection`, `keys`, `name`, `statement` are typical, but specifics may evolve across SDK versions. Treat `EXPLAIN` output as diagnostic — read its shape, don't depend on it programmatically.

### 6.2 Worked examples

> **Available in:** composite (multi-column) indexes require Ditto SDK **5.1+**.

```sql
-- A covering plan: every projected and filtered field lives in the index
CREATE INDEX IF NOT EXISTS movies_year_imdb
  ON movies (year ASC, ratings.imdb DESC);

EXPLAIN SELECT year, ratings.imdb
FROM movies
WHERE year = 2010
ORDER BY ratings.imdb DESC;
```

> **Available in:** all supported versions (4.14.x, 5.0.x, 5.1.x) — the `EXPLAIN` examples below.

Expect a single `IndexScan` operator referencing `movies_year_imdb`. No `Fetch`, no `Sort`.

```sql
-- A full collection scan
EXPLAIN SELECT title FROM movies WHERE box_office_millions > 500;

-- An intersect plan: AND of two indexed predicates
CREATE INDEX IF NOT EXISTS movies_year     ON movies (year);
CREATE INDEX IF NOT EXISTS movies_director ON movies (director.name);

EXPLAIN SELECT title FROM movies
WHERE year = 2010 AND director.name = 'Christopher Nolan';
```

The second example should produce an `Intersect` with two `IndexScan` children (the planner may collapse to a single scan if one index is clearly better). Use this to confirm a multi-index plan is being chosen rather than silently rejected.

```sql
-- A union plan: OR across indexed predicates
EXPLAIN SELECT title FROM movies
WHERE year = 2010 OR director.name = 'Christopher Nolan';
```

If the plan shows `CollectionScan` instead, you have an OR where one branch isn't indexable, or the planner has decided the union cost exceeds the scan cost.

### 6.3 Forcing a comparison

To benchmark "index vs no-index" cleanly:

```sql
-- Good plan
EXPLAIN SELECT title FROM movies WHERE year = 2010;

-- Forced collection scan (same predicate)
EXPLAIN SELECT title FROM movies USE INDEX '' WHERE year = 2010;
```

Or use the comment form for `EXPLAIN`:

```sql
/*+ {"#disable_index_scan": true} */
EXPLAIN SELECT title FROM movies WHERE year = 2010;
```

---

## 7. Profiling a query

> **Available in:** Ditto SDK **5.0+** (not available in 4.14.x; use `EXPLAIN` for plan inspection)

The `#profile` planner directive — and the matching `PROFILE` leading keyword on 5.0+ — asks the engine to attach per-operator profiling data alongside the result.

### 7.1 Two forms

```sql
-- Directive form: works on any statement
/*+ {"#profile": true} */
SELECT title FROM movies
WHERE year >= 1990 AND ratings.imdb > 8
ORDER BY ratings.imdb DESC
LIMIT 10;

-- Leading-keyword form (5.0+ on SELECT, see statements.md §10)
PROFILE SELECT title FROM movies
WHERE year >= 1990 AND ratings.imdb > 8
ORDER BY ratings.imdb DESC
LIMIT 10;
```

Both forms execute the statement (unlike `EXPLAIN`, which plans without executing) and request that the engine surface profiling information.

### 7.2 What you get back

In 5.0.x, profiling surfaces as request-level state — the planner records timings and document counts per operator and returns them alongside the result rows. A **structured profile output object** (per-operator timing and doc-count fields stable enough to parse programmatically) is **5.1+** and is intentionally out of scope here. On 5.0.x, treat profiling as a request flag and inspect the engine's diagnostics surface for the resulting data.

### 7.3 Combining with EXPLAIN

```sql
-- Plan-only (no execution); cheap and safe
EXPLAIN SELECT title FROM movies WHERE year = 1994;

-- Plan + execute + profile (5.0+)
PROFILE SELECT title FROM movies WHERE year = 1994;
```

Reach for `EXPLAIN` when you want to confirm "is the right index being chosen?" — it doesn't touch the data. Reach for `PROFILE` / `#profile` when you have the plan you expect but want to know "why is it still slow?" — for that, per-operator counts and timings are what you need.

### 7.4 v4 — no profiling syntax

On 4.14.x there is no `PROFILE` keyword and the `#profile` planner directive is internal-only — there is no portable way to surface profiling data through DQL. Use `EXPLAIN` to verify the plan shape, and rely on host-SDK telemetry (request counts, durations) for runtime characterisation.

---

## 8. Indexing strategy

Adding an index is not free. Every write to the indexed collection updates the index, every replicated mutation pays the same cost on every peer, and disk pressure grows with key cardinality. Use these rules of thumb before you reach for `CREATE INDEX`.

### 8.1 The ESR rule — Equality, Sort, Range

Order composite index keys so that **equality predicates come first, sort columns next, and range predicates last**. The planner can satisfy the prefix of the index that matches this discipline; anything past a range predicate cannot be used for further filtering or ordering.

Take this query:

```sql
SELECT title, ratings.imdb
FROM movies
WHERE year = 2010              -- equality
  AND ratings.imdb > 8.0       -- range
ORDER BY ratings.imdb DESC;    -- sort
```

ESR says: equality on `year`, then sort on `ratings.imdb`, then range on `ratings.imdb` (which collapses into the sort key). So:

> **Available in:** composite (multi-column) indexes require Ditto SDK **5.1+**.

```sql
CREATE INDEX IF NOT EXISTS movies_year_imdb
  ON movies (year ASC, ratings.imdb DESC);
```

> **Available in:** all supported versions (4.14.x, 5.0.x, 5.1.x) — the remaining queries in this section.

The planner can:

1. Seek to `year = 2010` in the index.
2. Walk the sorted `ratings.imdb DESC` slice within that year.
3. Stop early when `ratings.imdb` falls below 8.0 (range bound).

A poorly ordered key — `(ratings.imdb DESC, year ASC)` — would seek the rating range first, then filter `year` post-scan, traversing far more entries.

For a multi-equality + multi-range query, the equality columns should still lead:

```sql
-- Equality on year + director.name, range on box_office_millions, sort on year
SELECT title FROM movies
WHERE year = 2010
  AND director.name = 'Christopher Nolan'
  AND box_office_millions >= 500
ORDER BY year DESC;
```

> **Available in:** composite (multi-column) indexes require Ditto SDK **5.1+**.

```sql
CREATE INDEX movies_year_director_box
  ON movies (year DESC, director.name ASC, box_office_millions ASC);
```

`year` is both an equality predicate and the sort column — it stays first, with the direction matching the `ORDER BY` so the index can be traversed forward.

### 8.2 Covering indexes

An index covers a query when every column the query reads — projection, `WHERE`, `ORDER BY` — appears as an index key. The planner can serve the result entirely from the index without fetching the underlying document.

```sql
-- Covered by movies_year_imdb (year, ratings.imdb)
SELECT year, ratings.imdb
FROM movies
WHERE year = 2010
ORDER BY ratings.imdb DESC;
```

To turn a non-covered query into a covered one, extend the index with the additional projected columns — but only when the query is hot. Adding columns inflates index size and write cost.

If you want to disable covering temporarily (e.g. to confirm the document fetch isn't the bottleneck):

```sql
/*+ {"#disable_covering": true} */
SELECT year, ratings.imdb FROM movies WHERE year = 2010;
```

### 8.3 Index direction matters for `ORDER BY`

An ascending index key supports `ORDER BY <key> ASC` natively. The reverse direction is supported by traversing the index backwards, but the planner needs an explicit signal — either matching the `ORDER BY` direction at index-creation time, or using `USE INDEX … DESC`:

```sql
CREATE INDEX movies_year_asc ON movies (year ASC);

-- Forward scan: natural fit
SELECT title FROM movies ORDER BY year ASC LIMIT 10;

-- Backward scan: needs USE INDEX … DESC or #prefer_order
SELECT title FROM movies USE INDEX 'movies_year_asc' DESC
ORDER BY year DESC LIMIT 10;
```

If you have separate "newest first" and "oldest first" hot paths, create two indexes (one ascending, one descending) rather than relying on the planner to invert traversal in the cold case.

### 8.4 When not to index

Skip the index when:

- The collection is small enough that a full scan is already fast. Indexes pay off on collections where the scan cost noticeably exceeds the index lookup cost — typically thousands of documents and up.
- The query is rare. Indexes are paid for on every write to the collection; a once-a-day report query is almost never worth the steady-state cost.
- The indexed field is missing on a large fraction of documents. Every such document still gets an index entry pointing at a MISSING sentinel — large but useless. `EXCLUDE MISSING` would be the fix, but it is not implemented on any supported SDK version (§1.1), so the practical options today are to narrow the collection or skip the index entirely.
- The predicate cannot use an index. `LIKE '%pattern%'` (leading wildcard), `regexp_like`, and most function-call predicates degrade to a scan no matter what index exists. Verify with `EXPLAIN` before paying the index cost.
- The collection is write-heavy and the query is read-rare. Index maintenance lands on the write path and is replicated to every Small Peer that holds the collection.

### 8.5 Iterating — measure, don't guess

1. Use `EXPLAIN` to confirm whether the current plan is `IndexScan` or `CollectionScan`.
2. On 5.0+, use `PROFILE` / `#profile` to confirm where the time is actually spent.
3. Adjust either the index (add keys, change direction) or the query (rewrite the predicate, add a sort-friendly clause) and re-`EXPLAIN`.
4. Drop indexes that you no longer rely on (§2) — they cost write throughput even when no read uses them.

---

## 9. `ADVISE` / `ADVISE AND PROVISION` (SDK 5.1+)

> **Available in:** Ditto SDK **5.1+** — on 4.14.x or 5.0.x `ADVISE` raises a parse error.

`ADVISE <statement>` returns the `CREATE INDEX` statements the planner believes would speed up the inner statement, without modifying the database. `ADVISE AND PROVISION <statement>` performs the same analysis and then executes the recommended `CREATE INDEX` statements. 5.1+ also uses ADVISE to report missing indexes for JOIN keys — a JOIN whose right-side key is not indexed fails with `Joining to "<alias>" disallowed without appropriate index support. Please run ADVISE for recommendations.`

`ADVISE` is **SDK 5.1+**. What to do on 4.14.x and 5.0.x when you would otherwise reach for it:

1. `EXPLAIN` the query and confirm whether the current plan uses an index (§6).
2. If it scans, identify the equality / sort / range columns the predicate touches (§8.1).
3. Build the candidate index with `CREATE INDEX` (§1), composing the keys via the ESR rule.
4. Re-run `EXPLAIN`; verify the plan is now `IndexScan`. On 5.0+, layer `PROFILE` (§7) on top to confirm the runtime is also better.
5. Drop the candidate (§2) if `EXPLAIN` shows the planner still prefers a different plan.

The cookbook walks through this loop end-to-end on the movies dataset — see [`examples/movies-cookbook.md`](../examples/movies-cookbook.md).

---

## 10. Cross-reference index

| Topic                                                | Go to                                           |
| ---------------------------------------------------- | ----------------------------------------------- |
| `SELECT` grammar, `USE IDS` / `USE INDEX` / `USE DIRECTIVES` summary | [`select.md`](select.md) §§3–5  |
| `EXPLAIN` as a leading-keyword wrapper               | [`statements.md`](statements.md) §6             |
| `PROFILE` keyword form (5.0+)                        | [`statements.md`](statements.md) §10            |
| Path syntax and parameter binding inside index keys  | [`expressions.md`](expressions.md)              |
| CRDT field types (only REGISTER is indexable)        | [`types-mutators.md`](types-mutators.md)        |
| Aggregate / scalar functions that may degrade plans  | [`functions.md`](functions.md)                  |
| Mutation alternatives to `USE IDS` (`WHERE _id IN`)  | [`statements.md`](statements.md) §§3–5          |
| SDK-by-feature compatibility matrix                  | [`versions.md`](versions.md)                     |
