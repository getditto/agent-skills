---
title: DQL indexing and query optimization
description: CREATE INDEX, DROP INDEX, USE IDS/INDEX/DIRECTIVES, planner directives (full key catalog), EXPLAIN, and the #profile directive (5.0+). Covers Ditto SDK 4.14.x, 5.0.x, and 5.1.x; version-gated features are tagged inline.
---

# DQL indexing and query optimization

## Contents

- [1. CREATE INDEX](#1-create-index)
- [2. DROP INDEX](#2-drop-index)
- [3. Planner directives](#3-planner-directives)
- [4. USE IDS](#4-use-ids)
- [5. USE INDEX](#5-use-index)
- [6. EXPLAIN](#6-explain)
- [7. Profiling a query](#7-profiling-a-query)
- [8. Indexing strategy](#8-indexing-strategy)
- [9. `ADVISE` / `ADVISE AND PROVISION` (SDK 5.1+)](#9-advise--advise-and-provision-sdk-51)
- [10. Cross-reference index](#10-cross-reference-index)

> All examples in this file query the `movies` / `reviews` schema documented in [`schema.md`](schema.md).

Deep reference for index DDL, the planner-directive surface, and query-plan inspection on **Ditto SDK 4.14.x, 5.0.x, and 5.1.x**. Indexing in DQL is currently a **Small-Peer-only** feature; `CREATE INDEX` against a Big-Peer collection returns an error.

Unless a section carries an "Available in:" note, everything below works identically on 4.14.x, 5.0.x, and 5.1.x.

Cross-references:

- `SELECT` grammar including the thin `USE IDS` / `USE INDEX` / `USE DIRECTIVES` summary → [`select.md`](select.md) §§3–5
- Top-level statements including the `EXPLAIN` wrapper and the v5.0+ `PROFILE` keyword → [`statements.md`](statements.md) §§6, 10
- Path expressions and parameter syntax used inside index keys → [`expressions.md`](expressions.md)
- CRDT field types — distinguish scalar/path indexing from the verified whole-object reference case below → [`types-mutators.md`](types-mutators.md)
- SDK compatibility matrix → `versions.md` (forthcoming reference)

---

## 1. CREATE INDEX

Build a secondary index on one or more field paths of a collection. Indexes accelerate `WHERE` filtering, `ORDER BY` traversal, and (when covering) projection-only scans.

**Verified object-reference case (SDK 5.1.0, lenient mode):** an undeclared object
parent reference such as `parent_id: {store_id: 42, order_id: 'o-1'}` can be indexed
as a whole and matched by equality to the complete parent `_id` in a JOIN. Both
order and ticket examples were executed with duplicate parent numbers across scopes;
the complete-object match excluded unrelated scopes. This observation does not
establish support for every CRDT type or every MAP predicate.

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

See [planner-hints.md](planner-hints.md#3-planner-directives) for this topic.

## 4. USE IDS

See [planner-hints.md](planner-hints.md#4-use-ids) for this topic.

## 5. USE INDEX

See [planner-hints.md](planner-hints.md#5-use-index) for this topic.

## 6. EXPLAIN

See [query-diagnostics.md](query-diagnostics.md#6-explain) for this topic.

## 7. Profiling a query

See [query-diagnostics.md](query-diagnostics.md#7-profiling-a-query) for this topic.

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

See [query-diagnostics.md](query-diagnostics.md#9-advise--advise-and-provision-sdk-51) for this topic.

## 10. Cross-reference index

| Topic                                                | Go to                                           |
| ---------------------------------------------------- | ----------------------------------------------- |
| `SELECT` grammar, `USE IDS` / `USE INDEX` / `USE DIRECTIVES` summary | [`select.md`](select.md) §§3–5  |
| `EXPLAIN` as a leading-keyword wrapper               | [`statements.md`](statements.md) §6             |
| `PROFILE` keyword form (5.0+)                        | [`statements.md`](statements.md) §10            |
| Path syntax and parameter binding inside index keys  | [`expressions.md`](expressions.md)              |
| CRDT field types (object-reference caveat in §1)        | [`types-mutators.md`](types-mutators.md)        |
| Aggregate / scalar functions that may degrade plans  | [`functions.md`](functions.md)                  |
| Mutation alternatives to `USE IDS` (`WHERE _id IN`)  | [`statements.md`](statements.md) §§3–5          |
| SDK-by-feature compatibility matrix                  | [`versions.md`](versions.md)                     |
