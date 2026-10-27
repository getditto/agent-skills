# Joins — Ditto

## Contents

- [14. `JOIN` — cross-collection reads](#14-join--cross-collection-reads)
- [14.1 Inner join — projection from both sides](#141-inner-join--projection-from-both-sides)
- [14.2 Inner join — FK on the right side needs an index](#142-inner-join--fk-on-the-right-side-needs-an-index)
- [14.3 Outer join + aggregation — reviews per movie](#143-outer-join--aggregation--reviews-per-movie)
- [14.4 Join + HAVING — keep only well-reviewed movies](#144-join--having--keep-only-well-reviewed-movies)
- [14.5 Anti-join — movies with no reviews](#145-anti-join--movies-with-no-reviews)
- [14.6 Compound ON and multi-join chains](#146-compound-on-and-multi-join-chains)

Topic index: [select.md](select.md). Covers Ditto SDK 4.14.x (LTS),
5.0.x and 5.1.x; version-specific notes remain inline. Read only the topic needed.

For movies/reviews examples, see the [schema](schema.md) only when adapting those examples; other examples define their own fields.

## 14. `JOIN` — cross-collection reads

> **Available in:** Ditto SDK **5.1+**. On 4.14.x / 5.0.x any join syntax raises a parse error; use the two-query / denormalization patterns from the cookbook instead.

`JOIN` reads across two or more collections in one statement on a Small Peer. Both inner and outer forms exist:

```
SELECT <projection>
FROM <collection> [AS] <alias>
  [ INNER | LEFT [OUTER] | RIGHT [OUTER] ] JOIN <collection> [AS] <alias> ON <expr>
  ...more joins...
[ WHERE / GROUP BY / HAVING / ORDER BY / LIMIT / OFFSET ... ]
```

Rules and behavior (all verified against SDK 5.1.0):

- **Index the join key.** A join whose right-side match key is neither `_id` nor an indexed field fails: `Joining to "<alias>" disallowed without appropriate index support. Please run ADVISE for recommendations.` Create the index (or run `ADVISE` on the statement; see [`indexing.md`](indexing.md) §9) before relying on the join.
- **Aliases** — every joined collection should have one (`reviews r`), and qualified paths (`r.movie_id`) disambiguate columns. Unqualified projections like `SELECT *` across a join are allowed but ambiguous fields collide.
- **`ON` is a boolean expression** — equality on the FK (`r.movie_id = m._id`), compound `AND` terms, and even function predicates such as `array_contains(object_keys(m.members), u._id)` for MAP-based many-to-many relations.
- **Outer joins surface `MISSING`** on unmatched rows — filter with `<alias>.<pk> IS MISSING` for anti-joins, and wrap projected outer fields with `coalesce(...)` for defaults.
- **Supported join types** on 5.1.x: `INNER JOIN`, bare `JOIN` (an inner join), `LEFT [OUTER] JOIN`, and `RIGHT [OUTER] JOIN`. `FULL [OUTER] JOIN` and `CROSS JOIN` are **not** in the grammar and raise `Unexpected token FULL` / `Unexpected token CROSS`.
- **Self-joins** work when each side has a distinct alias (`FROM movies m1 INNER JOIN movies m2 ON …`), as do multi-join chains.

### 14.1 Inner join — projection from both sides

> **Available in:** SDK **5.1+**.

```sql
-- Every review with its movie's title and year
SELECT r._id, r.score, r.user_id, m.title, m.year
FROM reviews r
INNER JOIN movies m ON r.movie_id = m._id
ORDER BY r.score DESC
LIMIT 10;
```

Joining on `m._id` here needs no extra index (`_id` is always indexed); the left side scans `reviews`.

### 14.2 Inner join — FK on the right side needs an index

Joining the other direction — `reviews` on the right, matched on `reviews.movie_id` — requires an index on that field:

```sql
CREATE INDEX IF NOT EXISTS reviews_movie_id ON reviews (movie_id);
```

> **Available in:** SDK **5.1+** (the join below).

```sql
-- Each movie with its review scores
SELECT m._id, m.title, r.score, r.user_id
FROM movies m
INNER JOIN reviews r ON r.movie_id = m._id
ORDER BY m.title ASC, r.score DESC
LIMIT 20;
```

### 14.3 Outer join + aggregation — reviews per movie

> **Available in:** SDK **5.1+**.

```sql
-- Review count and average per movie, including movies with none
SELECT m._id, m.title,
       COUNT(r._id) AS review_count,
       coalesce(AVG(r.score), 0) AS avg_score
FROM movies m
LEFT OUTER JOIN reviews r ON r.movie_id = m._id
GROUP BY m._id, m.title
ORDER BY review_count DESC
LIMIT 10;
```

### 14.4 Join + HAVING — keep only well-reviewed movies

> **Available in:** SDK **5.1+**.

```sql
SELECT m._id, m.title, AVG(r.score) AS avg_score
FROM movies m
INNER JOIN reviews r ON r.movie_id = m._id
GROUP BY m._id, m.title
HAVING AVG(r.score) >= 8.0
ORDER BY avg_score DESC;
```

### 14.5 Anti-join — movies with no reviews

> **Available in:** SDK **5.1+**.

```sql
SELECT m._id, m.title, m.year
FROM movies m
LEFT OUTER JOIN reviews r ON r.movie_id = m._id
WHERE r._id IS MISSING
ORDER BY m.year DESC
LIMIT 10;
```

### 14.6 Compound ON and multi-join chains

Multiple `AND`-ed terms in `ON`, or several `JOIN` clauses chained (order → customer → store, page → component → element trees), are supported — each new right side still needs its match key indexed. The `dql-metrics` `retail-joins` and `forge-joins` suites are the reference catalogue of these shapes (multi-FK joins, rollups with aggregates, MAP-membership joins, and bounded self-join tree walks).

---
