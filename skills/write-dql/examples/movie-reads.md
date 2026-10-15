# Movie reads — Ditto

## Contents

- [Read patterns](#read-patterns)
- [Task 3 — Top-rated movies in a decade with pagination](#task-3--top-rated-movies-in-a-decade-with-pagination)
- [Task 4 — Single-document lookup (fastest path)](#task-4--single-document-lookup-fastest-path)
- [Task 5 — Films featuring a specific actor](#task-5--films-featuring-a-specific-actor)
- [Task 6 — Films in any of N genres](#task-6--films-in-any-of-n-genres)
- [Task 7 — Flat view with computed fields](#task-7--flat-view-with-computed-fields)
- [Task 8 — Director leaderboard](#task-8--director-leaderboard)
- [Task 9 — Per-movie review statistics](#task-9--per-movie-review-statistics)
- [Task 10 — Two-step "join" (top movies by review average)](#task-10--two-step-join-top-movies-by-review-average)

Topic index: [movies-cookbook.md](movies-cookbook.md). Covers Ditto SDK 4.14.x (LTS),
5.0.x and 5.1.x; version-specific notes remain inline. Read only the topic needed.

## Read patterns

### Task 3 — Top-rated movies in a decade with pagination

> **Available in:** Ditto SDK 5.0+ (`BETWEEN`). On 4.14.x rewrite as `year >= :decade_start AND year <= :decade_end`.

**Goal:** Page through highly-rated films released between two years, ordered by IMDb score.

**Query:**

```sql
SELECT _id, title, year, ratings.imdb AS imdb
FROM movies
WHERE year BETWEEN :decade_start AND :decade_end
  AND ratings.imdb >= :min_imdb
ORDER BY imdb DESC, title ASC
LIMIT :page_size OFFSET :offset;
```

**Notes:** `BETWEEN` is inclusive on both ends. Adding `title ASC` after the primary sort gives a stable tie-break, which matters as soon as `LIMIT` / `OFFSET` are in play. To make this query covering, add an index on `(year ASC, ratings.imdb DESC)` — see [`indexing.md`](../references/indexing.md) §8 (ESR rule). Operator reference: [`operators.md`](../references/operators.md).

### Task 4 — Single-document lookup (fastest path)

**Goal:** Fetch one movie by id with the cheapest possible plan.

**Query:**

```sql
SELECT * FROM movies USE IDS (:id);
```

**Notes:** `USE IDS` is supported only on `SELECT` in both 4.14.x and 5.0.x. It bypasses any collection scan and hits the primary id index directly. With the default `#auto_use_ids` directive (`true`), the planner will rewrite `WHERE _id = :id` into the same plan — but writing `USE IDS` explicitly makes the intent visible and stable across SDK versions. See [`select.md`](../references/select.md) §3.

### Task 5 — Films featuring a specific actor

> **Available in:** Ditto SDK 5.0+ for the `ANY ... SATISFIES` form. v4 requires the fallback below.

**Goal:** Find every movie whose `cast` array contains an actor with the given name.

**Query (5.0+):**

```sql
SELECT _id, title, year
FROM movies
WHERE ANY actor IN `cast` SATISFIES actor.name = :actor_name END
ORDER BY year ASC;
```

**v4 fallback:** Quantifier expressions don't exist on 4.14.x. If you must support v4, denormalise an `actor_names` array of strings at write time and use `array_contains`:

```sql
-- Available in: SDK 4.14+ (all three lines) — array_contains is portable
SELECT _id, title, year
FROM movies
WHERE array_contains(actor_names, :actor_name)
ORDER BY year ASC;
```

**Notes:** `ANY ... IN ... SATISFIES ... END` iterates the array and tests the condition per element, returning `TRUE` on the first match. See [`expressions.md`](../references/expressions.md) §7.

### Task 6 — Films in any of N genres

> **Available in:** Ditto SDK 5.0+ for the `ANY ... SATISFIES` form. Both forms below produce the same result.

**Goal:** Match films whose `genres` array overlaps with a candidate set.

**Query (5.0+):**

```sql
SELECT _id, title, genres
FROM movies
WHERE ANY g IN genres SATISFIES g IN ('Drama', 'Crime') END;
```

**v4-portable form (also works on 5.0+):**

```sql
-- Available in: SDK 4.14+ (all three lines)
SELECT _id, title, genres
FROM movies
WHERE array_contains(genres, 'Drama')
   OR array_contains(genres, 'Crime');
```

**Notes:** The `OR`/`array_contains` form is portable across all three SDK versions and is what to ship when your peer fleet is mixed. The quantifier form scales more cleanly when the candidate list is large or comes from a parameter. See [`functions.md`](../references/functions.md) §5 (array functions) and [`expressions.md`](../references/expressions.md) §7.

### Task 7 — Flat view with computed fields

> **Available in:** Ditto SDK 5.0+ (`CASE`). On 4.14.x there is no in-query conditional at all (no `CASE`, and no `IF()` function on any version) — use `coalesce`/`ifnull` for null-coalescing only, and derive branch columns in app code.

**Goal:** Project a row per movie with one or two derived columns.

**Query:**

```sql
SELECT
  _id,
  title,
  year,
  ratings.imdb AS imdb,
  CASE
    WHEN ratings.imdb >= 9 THEN 'masterpiece'
    WHEN ratings.imdb >= 7 THEN 'good'
    WHEN ratings.imdb IS MISSING THEN 'unrated'
    ELSE 'meh'
  END AS verdict,
  year < 1980 AS is_pre_1980
FROM movies
ORDER BY year DESC;
```

**Notes:** Searched `CASE` (no operand between `CASE` and the first `WHEN`) works identically on 4.14.x and 5.0.x. `IS MISSING` is the right way to test "field absent" — `IS NULL` matches only an explicit null. See [`expressions.md`](../references/expressions.md) §6.

### Task 8 — Director leaderboard

**Goal:** Aggregate films by director, showing count, average IMDb, and top-grossing film. Filter to directors with three or more films.

**Query:**

```sql
SELECT
  director.name            AS director,
  count(*)                 AS films,
  avg(ratings.imdb)        AS avg_imdb,
  max(box_office_millions) AS top_grossing
FROM movies
WHERE director IS NOT MISSING
GROUP BY director.name
HAVING count(*) >= 3
ORDER BY avg_imdb DESC
LIMIT 25;
```

**Notes:** `HAVING` filters groups after aggregation; `WHERE` filters rows before. The `WHERE director IS NOT MISSING` guard prevents unattributed films from collapsing into a single null-named group. See [`select.md`](../references/select.md) for `GROUP BY` / `HAVING` and [`functions.md`](../references/functions.md) for aggregate signatures.

### Task 9 — Per-movie review statistics

**Goal:** For each movie, surface review count plus min/avg/max score.

**Query:**

```sql
SELECT
  movie_id,
  count(*)   AS review_count,
  avg(score) AS avg_score,
  min(score) AS min_score,
  max(score) AS max_score
FROM reviews
GROUP BY movie_id
HAVING count(*) >= 10
ORDER BY avg_score DESC;
```

**Notes:** This is the right shape for "show me the best-reviewed films" — Step 1 of the two-step pattern in Task 10. To make this query fast, add a single-key index on `reviews(movie_id)` so the planner can build groups directly from index order. See [`indexing.md`](../references/indexing.md) §8.

### Task 10 — Two-step "join" (top movies by review average)

**Goal:** DQL has no JOIN. To get titles for the best-reviewed films, aggregate on `reviews` first, then look the movies up by id.

**Query (Step 1 — collect top movie ids from `reviews`):**

```sql
SELECT movie_id, avg(score) AS avg_score
FROM reviews
GROUP BY movie_id
HAVING count(*) >= 50 AND avg(score) >= 4.5
ORDER BY avg_score DESC
LIMIT 10;
```

**Query (Step 2 — fetch the matching movies):**

```sql
SELECT _id, title, year
FROM movies
WHERE _id IN (:top_ids);
```

**JS glue (conceptual):**

```js
const topReviews = await store.execute(step1Query);
const topIds = topReviews.items.map(r => r.value.movie_id);
const movies = await store.execute(step2Query, { top_ids: topIds });
```

**Notes:** Use `WHERE _id IN (...)` rather than `USE IDS LIST` — `USE IDS LIST` accepts a single list parameter on SELECT, but the `IN (...)` form is universal across SELECT/UPDATE/DELETE/EVICT/TOMBSTONE and works the same on all three SDK versions. For very long id lists, see the `#max_inlist` directive in [`indexing.md`](../references/indexing.md) §3.4.

---
