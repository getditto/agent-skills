# Query diagnostics — Ditto

## Contents

- [6. EXPLAIN](#6-explain)
- [7. Profiling a query](#7-profiling-a-query)
- [9. `ADVISE` / `ADVISE AND PROVISION` (SDK 5.1+)](#9-advise--advise-and-provision-sdk-51)

Topic index: [indexing.md](indexing.md). Covers Ditto SDK 4.14.x (LTS),
5.0.x, 5.1.x and 5.2.0; version-specific notes remain inline. Read only the topic needed.

For movies/reviews examples, see the [schema](schema.md) only when adapting those examples; other examples define their own fields.

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
