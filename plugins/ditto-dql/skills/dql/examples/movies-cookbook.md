---
title: DQL movies cookbook
description: 18 end-to-end DQL tasks against a sample movies dataset. Every statement here is verified to work on Ditto SDK 4.14.x and 5.0.x (with v4 fallbacks shown where features differ).
---

# DQL Movies Cookbook

A practical walkthrough of every major DQL capability the v5.0.0 SDK supports. Each task is self-contained — paste it into a Ditto query interface and it should run.

> **Compatibility:** Examples are tagged with the minimum Ditto SDK version they require. Most tasks work on **SDK 4.14.x and 5.0.x**. Tasks that depend on COUNTER (4.13+), PN_COUNTER (4.11+), or `DO UPDATE_LOCAL_DIFF` (4.12+) carry an explicit "Available in:" tag. Features added in v5.1.0 (`ADVISE`, structured `PROFILE` output, `INSERT ... ON ID CONFLICT DO MERGE`, `serialize_json`, `object_size`, `USE IDS` on mutations) are intentionally excluded. **Note:** the `watch_count` field uses COUNTER (SDK 4.13+); on older SDKs substitute a REGISTER and use SET instead of `APPLY ... INCREMENT BY`.

## Dataset

The cookbook uses two collections: `movies` and `reviews`.

### `movies` schema

| Field | Type | CRDT | Notes |
|---|---|---|---|
| `_id` | string | REGISTER | IMDb id, e.g. `"tt0111161"` |
| `title` | string | REGISTER | |
| `year` | integer | REGISTER | |
| `runtime_minutes` | integer | REGISTER | |
| `genres` | array<string> | REGISTER | JSON array of genre names |
| `director` | object | **MAP** | `{name, born}` |
| `cast` | array<object> | REGISTER | `[{name, role}, ...]` |
| `ratings` | object | **MAP** | `{imdb, rotten_tomatoes, metacritic}` |
| `box_office_millions` | number | REGISTER | |
| `tags` | array<string> | REGISTER | |
| `watch_count` | integer | **COUNTER** | distributed counter |
| `is_classic` | boolean | REGISTER | |
| `released` | string | REGISTER | ISO-8601 `YYYY-MM-DD` |

### `reviews` schema

| Field | Type | CRDT | Notes |
|---|---|---|---|
| `_id` | string | REGISTER | auto |
| `movie_id` | string | REGISTER | FK to `movies._id` |
| `user_id` | string | REGISTER | |
| `score` | integer | REGISTER | 1–5 |
| `comment` | string | REGISTER | |
| `created_at` | string | REGISTER | ISO-8601 timestamp |

## Seeding

### Task 1 — Load movies with conflict-tolerant upserts

> **Available in:** Ditto SDK 4.13+ (COUNTER)

**Goal:** Insert a batch of movies, treating an existing `_id` as an update rather than an error.

**Query:**

```sql
INSERT INTO COLLECTION movies (director MAP, ratings MAP, watch_count COUNTER)
DOCUMENTS
  ({ '_id': 'tt0111161', 'title': 'The Shawshank Redemption', 'year': 1994,
     'runtime_minutes': 142, 'genres': ['Drama'],
     'director': { 'name': 'Frank Darabont', 'born': 1959 },
     'cast': [
       { 'name': 'Tim Robbins',    'role': 'Andy Dufresne' },
       { 'name': 'Morgan Freeman', 'role': "Ellis Boyd 'Red' Redding" }
     ],
     'ratings': { 'imdb': 9.3, 'rotten_tomatoes': 91, 'metacritic': 80 },
     'box_office_millions': 73, 'watch_count': 0, 'is_classic': true,
     'released': '1994-09-23' }),
  ({ '_id': 'tt1375666', 'title': 'Inception', 'year': 2010,
     'runtime_minutes': 148, 'genres': ['Action', 'Sci-Fi', 'Thriller'],
     'director': { 'name': 'Christopher Nolan', 'born': 1970 },
     'ratings': { 'imdb': 8.8, 'rotten_tomatoes': 87 },
     'box_office_millions': 836, 'watch_count': 0, 'is_classic': false,
     'released': '2010-07-16' })
ON ID CONFLICT DO UPDATE;
```

**Notes:** The `INTO COLLECTION movies (director MAP, ratings MAP, watch_count COUNTER)` clause is what makes the statement portable across SDK 4.14.x (strict default) and 5.0.x (lenient default) — without it, v4 would store `director` and `ratings` as `REGISTER` and concurrent edits would clobber each other. `COUNTER` requires SDK 4.13+; on older SDKs, drop it and store `watch_count` as a plain REGISTER. See [`statements.md`](../references/statements.md) §1 for the full `INSERT` grammar and [`types-mutators.md`](../references/types-mutators.md) for the CRDT-type declarations.

### Task 2 — Seed reviews with auto-generated ids

**Goal:** Insert review documents without specifying `_id` — Ditto generates one per row.

**Query:**

```sql
INSERT INTO reviews DOCUMENTS
  ({ 'movie_id': 'tt0111161', 'user_id': 'u-42',
     'score': 5, 'comment': 'Hope is a good thing.',
     'created_at': '2024-03-15T10:00:00Z' }),
  ({ 'movie_id': 'tt0111161', 'user_id': 'u-7',
     'score': 4, 'comment': 'A slow burn that pays off.',
     'created_at': '2024-03-18T09:15:00Z' }),
  ({ 'movie_id': 'tt1375666', 'user_id': 'u-7',
     'score': 4, 'comment': "Don't think about the spinning top.",
     'created_at': '2024-04-02T22:31:00Z' });
```

**Notes:** Omitting `_id` is fine — Ditto assigns a unique string id per inserted document. No `INTO COLLECTION` clause is needed because every field on `reviews` is a `REGISTER`. See [`statements.md`](../references/statements.md) §1.2.

---

## Read patterns

### Task 3 — Top-rated movies in a decade with pagination

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
WHERE ANY actor IN cast SATISFIES actor.name = :actor_name END
ORDER BY year ASC;
```

**v4 fallback:** Quantifier expressions don't exist on 4.14.x. If you must support v4, denormalise an `actor_names` array of strings at write time and use `array_contains`:

```sql
-- v4-portable: maintain a parallel actor_names array
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
SELECT _id, title, genres
FROM movies
WHERE array_contains(genres, 'Drama')
   OR array_contains(genres, 'Crime');
```

**Notes:** The `OR`/`array_contains` form is portable across both SDK lines and is what to ship when your peer fleet is mixed. The quantifier form scales more cleanly when the candidate list is large or comes from a parameter. See [`functions.md`](../references/functions.md) §5 (array functions) and [`expressions.md`](../references/expressions.md) §7.

### Task 7 — Flat view with computed fields

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

**Notes:** Use `WHERE _id IN (...)` rather than `USE IDS LIST` — `USE IDS LIST` accepts a single list parameter on SELECT, but the `IN (...)` form is universal across SELECT/UPDATE/DELETE/EVICT/TOMBSTONE and works the same on both SDK lines. For very long id lists, see the `#max_inlist` directive in [`indexing.md`](../references/indexing.md) §3.4.

---

## Mutations

### Task 11 — Increment the watch counter

> **Available in:** Ditto SDK 4.13+ (COUNTER). PN_COUNTER variant requires SDK 4.11+.

**Goal:** Bump a peer-safe counter by one.

**Query (COUNTER — recommended, 4.13+):**

```sql
UPDATE COLLECTION movies (watch_count COUNTER)
APPLY watch_count INCREMENT BY 1
WHERE _id = :id;
```

**Query (PN_COUNTER — legacy, 4.11+):**

```sql
UPDATE COLLECTION movies (legacy_views PN_COUNTER)
APPLY legacy_views PN_INCREMENT BY 1
WHERE _id = :id;
```

**Notes:** This is the **only** correct way to bump a counter. `SET watch_count = watch_count + 1` would silently lose concurrent increments on merge because `+ 1` resolves once on the writing peer and stores a regular `REGISTER` value. Prefer state-based `COUNTER` (4.13+) on new code; `PN_COUNTER` exists for backwards compatibility. See [`types-mutators.md`](../references/types-mutators.md) §3.

### Task 12 — Update a nested MAP field without clobbering siblings

**Goal:** Change one rating without touching the others.

**Query:**

```sql
UPDATE COLLECTION movies (ratings MAP)
SET ratings.rotten_tomatoes = 95
WHERE _id = :id;
```

**Notes on `dql_strict_mode`:** On **SDK 5.0.x** the lenient default (`dql_strict_mode = false`) means the engine treats `ratings` as a MAP even without the explicit declaration — `UPDATE movies SET ratings.rotten_tomatoes = 95 WHERE _id = :id` would also work. On **SDK 4.14.x** the strict default requires the `INTO COLLECTION movies (ratings MAP)` clause; without it, the engine stores `ratings.rotten_tomatoes` as a sub-`REGISTER` path that does not merge with sibling sub-fields. For cross-version code, always declare `ratings MAP` explicitly. See [`types-mutators.md`](../references/types-mutators.md) §§2 and 7 for the strict-mode flip and MAP merge semantics.

### Task 13 — Flag pre-1980 films as classics with RETURNING

**Goal:** Mark every old film and capture the ids/titles that changed.

**Query:**

```sql
UPDATE movies
SET is_classic = true
WHERE year < 1980
RETURNING _id, title;
```

**Notes:** `RETURNING` works on `UPDATE`, `DELETE`, `EVICT`, and `TOMBSTONE` on both SDK lines. The projection list mirrors the rules for `SELECT`, except `DISTINCT` and `RAW` are not allowed. See [`statements.md`](../references/statements.md) §2.5.

### Task 14 — Remove a derived field post-backfill (UNSET)

**Goal:** Drop a transition field once a backfill has run.

**Query:**

```sql
UPDATE movies
UNSET legacy_field
WHERE legacy_field IS NOT MISSING;
```

**Notes:** `UNSET` removes the field from each matching document. The `IS NOT MISSING` predicate scopes the update to rows that still have the field — important if you re-run the cleanup over a partially-migrated dataset. See [`statements.md`](../references/statements.md) §2.2.

### Task 15 — Reset the watch counter on a re-release (RESTART)

> **Available in:** Ditto SDK 4.13+ (COUNTER)

**Goal:** Rebaseline a counter back to zero — later `INCREMENT BY` mutations start fresh from this value.

**Query:**

```sql
UPDATE COLLECTION movies (watch_count COUNTER)
APPLY watch_count RESTART WITH 0
WHERE _id = :id;
```

**Notes:** `RESTART WITH <value>` is the COUNTER-safe way to reset. `SET watch_count = 0` would be a `REGISTER` write that races concurrent increments. `RESTART` defaults to `0` if `WITH <value>` is omitted. See [`types-mutators.md`](../references/types-mutators.md) §3.

### Task 16 — Local cleanup of pre-1950 films (EVICT)

**Goal:** Free disk on a single peer without propagating the deletion.

**Query:**

```sql
EVICT FROM movies
WHERE year < 1950;
```

**Notes:** `EVICT` is **non-replicating** — Small Peer only. Other peers in the mesh still hold these documents, and if any of them syncs to this peer later, the films will return. Use `EVICT` for "this device doesn't need it in its working set anymore", and `TOMBSTONE` / `DELETE` for "remove globally". See [`statements.md`](../references/statements.md) §3.

### Task 17 — Mesh-wide retraction of a withdrawn film (TOMBSTONE)

**Goal:** Permanently remove a document everywhere in the mesh.

**Query:**

```sql
TOMBSTONE FROM movies
WHERE _id = :withdrawn_id
RETURNING _id, title;
```

**Notes:** `TOMBSTONE` is **Big Peer only** and replicates the deletion to every connected peer. The tombstone has a TTL (7 days on Edge SDKs, 30 days on the Big Peer); offline peers that come online after that window may reintroduce the document. For a peer-agnostic "delete here, propagate if on Big Peer" idiom, use `DELETE FROM ...` instead. See [`statements.md`](../references/statements.md) §4.

### Task 18 — Bulk delete with an id list

**Goal:** Remove several documents by id in one statement.

**Query:**

```sql
DELETE FROM movies
WHERE _id IN ('tt9999990', 'tt9999991', 'tt9999992');
```

**Notes:** `DELETE` is a context-resolved alias — it behaves like `EVICT` on a Small Peer and `TOMBSTONE` on a Big Peer. **Do not use `USE IDS LIST` on `DELETE`, `UPDATE`, `EVICT`, or `TOMBSTONE`** — both the 4.14.x and 5.0.x parsers carry TODO comments for `USE IDS` on mutations, so `USE IDS` is `SELECT`-only today. `WHERE _id IN (...)` is the portable, supported form. See [`statements.md`](../references/statements.md) §5.

---

## Diagnosing performance

Slow query? Walk this loop:

1. **Get the plan** with `EXPLAIN`:

   ```sql
   EXPLAIN SELECT title FROM movies
   WHERE year BETWEEN 1990 AND 2000
   ORDER BY ratings.imdb DESC;
   ```

   Look for `CollectionScan` (a full document scan — expensive) versus `IndexScan` (a hit on a named index). For the full operator catalog see [`indexing.md`](../references/indexing.md) §6.

2. **Capture timings** (SDK 5.0+ only):

   ```sql
   -- Directive form
   SELECT /*+ {"#profile": true} */ title FROM movies
   WHERE year BETWEEN 1990 AND 2000
   ORDER BY ratings.imdb DESC;

   -- Leading-keyword form (PROFILE)
   PROFILE SELECT title FROM movies
   WHERE year BETWEEN 1990 AND 2000
   ORDER BY ratings.imdb DESC;
   ```

   Both attach per-operator profiling data to the result on 5.0+. v4 has no profiling syntax — fall back to `EXPLAIN` plus wall-clock timing in your application. See [`indexing.md`](../references/indexing.md) §7.

3. **Add the missing index.** Apply the ESR rule (equality keys first, sort keys next, range last):

   ```sql
   CREATE INDEX IF NOT EXISTS movies_year_imdb
     ON movies (year ASC, ratings.imdb DESC);
   ```

   Then re-run `EXPLAIN` and confirm the plan now reports `IndexScan` against `movies_year_imdb`. See [`indexing.md`](../references/indexing.md) §8 for the ESR rule and worked examples.

4. **If the plan didn't change**, the planner may have rejected the index because the query isn't covering or the cost model preferred a scan. Force the comparison with `USE INDEX ''` to disable indexes, then re-enable and check again. See [`indexing.md`](../references/indexing.md) §6.3.
