---
title: Movies/reviews dataset schema
description: The pedagogical schema used by every DQL example in this skill. Every operator, function, statement, expression, and cookbook example queries one of these two collections.
---

# Movies/reviews dataset schema

Every example in the reference files and the movies cookbook queries one of two collections: **`movies`** and **`reviews`**. This file is the canonical definition of those collections — refer back here when an example uses a field you don't recognize.

The schema is "pedagogical" in the sense that it's designed to teach DQL: it intentionally mixes scalar fields, arrays of scalars, arrays of nested objects, deeply-nested object paths, and every CRDT type (REGISTER, MAP, COUNTER, ATTACHMENT). A real production schema would usually be simpler.

## `movies` collection

| Field | Type | CRDT | Notes |
|---|---|---|---|
| `_id` | string | REGISTER | Document ID. IMDb id format, e.g. `"tt0111161"`. |
| `title` | string | REGISTER | Film title. |
| `year` | integer | REGISTER | Release year. Used heavily in WHERE/ORDER BY examples. |
| `runtime_minutes` | integer | REGISTER | Duration in minutes. |
| `genres` | array<string> | REGISTER | E.g. `["Drama", "Crime"]`. Demonstrates `array_contains()` and `ANY ... SATISFIES`. |
| `director` | object | **MAP** | `{ name: string, born: integer \| null }`. Demonstrates nested-path access (`director.name`) and per-field MAP merge semantics. |
| `cast` | array<object> | REGISTER | `[{ name: string, role: string }, ...]`. Demonstrates `ANY actor IN cast SATISFIES actor.name = ...` over arrays of objects. **Note:** `cast` is also a SQL keyword; reference as `` `cast` `` when used as a bare identifier in path expressions. |
| `ratings` | object | **MAP** | `{ imdb: number, rotten_tomatoes: number, metacritic: number \| null }`. Demonstrates partial MAP updates (`SET ratings.imdb = 9.4` leaves siblings untouched). |
| `box_office_millions` | number | REGISTER | Gross in millions. Used for range filters. |
| `tags` | array<string> | REGISTER | Free-form tag list. |
| `watch_count` | integer | **COUNTER** | Distributed counter (`APPLY watch_count INCREMENT BY 1`). Available SDK 4.14+. |
| `is_classic` | boolean | REGISTER | Used in CASE / boolean-operator examples. |
| `released` | string | REGISTER | ISO-8601 date (`"1994-09-23"`). Used in date function examples. |
| `poster` | ATTACHMENT | ATTACHMENT | Binary blob with `id`/`len`/`metadata`. Optional. Not seeded in the test fixture (attachment uploads need an out-of-band ingest path). |

### Sample `movies` document

```json
{
  "_id": "tt0111161",
  "title": "The Shawshank Redemption",
  "year": 1994,
  "runtime_minutes": 142,
  "genres": ["Drama"],
  "director": { "name": "Frank Darabont", "born": 1959 },
  "cast": [
    { "name": "Tim Robbins", "role": "Andy Dufresne" },
    { "name": "Morgan Freeman", "role": "Ellis Boyd \"Red\" Redding" }
  ],
  "ratings": { "imdb": 9.3, "rotten_tomatoes": 91, "metacritic": 80 },
  "box_office_millions": 73,
  "tags": ["prison", "friendship", "redemption"],
  "watch_count": 0,
  "is_classic": true,
  "released": "1994-09-23"
}
```

## `reviews` collection

| Field | Type | CRDT | Notes |
|---|---|---|---|
| `_id` | string | REGISTER | Auto-generated review id. |
| `movie_id` | string | REGISTER | Foreign key — references `movies._id`. Used in two-step join examples (aggregate reviews → look up movies by ID list). |
| `user_id` | string | REGISTER | Reviewer id. |
| `score` | integer | REGISTER | 1–5 rating. |
| `comment` | string | REGISTER | Review text. Used in string-function examples (`contains`, `regexp_like`, etc.). |
| `created_at` | string | REGISTER | ISO-8601 timestamp (`"2024-04-02T22:31:00Z"`). Used in date arithmetic examples. |

### Sample `reviews` document

```json
{
  "_id": "rv-001",
  "movie_id": "tt0111161",
  "user_id": "u-42",
  "score": 5,
  "comment": "A masterpiece — best film I've seen all decade.",
  "created_at": "2024-04-02T22:31:00Z"
}
```

## Seeding the dataset

Assuming the lenient baseline (`dql_strict_mode = false` on every peer — the 5.x default and the 4.14.x migration target), `director` and `ratings` infer MAP with no declaration; only `watch_count` is declared, because inference can't guess a COUNTER from a plain integer. See [`statements.md`](statements.md#1-insert) for `INSERT INTO COLLECTION ... DOCUMENTS` syntax.

```sql
INSERT INTO COLLECTION movies (
  watch_count COUNTER
)
DOCUMENTS ({
  '_id': 'tt0111161',
  'title': 'The Shawshank Redemption',
  'year': 1994,
  'runtime_minutes': 142,
  'genres': ['Drama'],
  'director': { 'name': 'Frank Darabont', 'born': 1959 },
  'cast': [
    { 'name': 'Tim Robbins', 'role': 'Andy Dufresne' },
    { 'name': 'Morgan Freeman', 'role': 'Ellis Boyd "Red" Redding' }
  ],
  'ratings': { 'imdb': 9.3, 'rotten_tomatoes': 91, 'metacritic': 80 },
  'box_office_millions': 73,
  'tags': ['prison', 'friendship', 'redemption'],
  'watch_count': 0,
  'is_classic': true,
  'released': '1994-09-23'
})
ON ID CONFLICT DO UPDATE
```

For the test harness, the `movies` fixture is generated from a real movies dataset by [`tests/dql/scripts/transform-dataset.mjs`](../../../tests/dql/scripts/transform-dataset.mjs) and lives at [`tests/dql/fixtures/movies-pedagogical.ndjson`](../../../tests/dql/fixtures/movies-pedagogical.ndjson) (194 docs spanning 1893–2002). The cookbook walks through seeding interactively in [`examples/movies-cookbook.md`](../examples/movies-cookbook.md#task-1--load-movies-with-conflict-tolerant-upserts).

## Gotchas you'll meet in examples

- **`year` is an `integer`**, not a string. Compare with bare numbers: `WHERE year >= 1990`, not `WHERE year >= '1990'`.
- **`cast` is a SQL keyword** (the `CAST()` function). When used as a path expression on the `movies` schema (e.g., reading `cast[0].name`), wrap in backticks: `` SELECT `cast`[0].name FROM movies ``. The same pattern applies to `trim` if you ever name a field `trim`.
- **`director` and `ratings` are MAPs.** Updating one field leaves the others alone (`SET ratings.imdb = 9.4` keeps `rotten_tomatoes` and `metacritic` intact). REGISTER objects would replace the whole value.
- **`watch_count` is a COUNTER.** Increment with `UPDATE movies APPLY watch_count INCREMENT BY 1 WHERE ...`, **never** with `SET watch_count = watch_count + 1`. See [`types-mutators.md`](types-mutators.md#3-counter).
- **`released` is a string**, not a native date type. Use [`date_cast()`](date-time-functions.md#7-date--time) to parse it for arithmetic.
- **Cross-version MAP defaults.** Under the assumed lenient baseline (`dql_strict_mode = false` everywhere), undeclared objects become MAPs — no declarations needed on writes or reads. Only an un-migrated 4.14.x strict peer turns a bare object into a REGISTER (LWW) and omits undeclared MAP/COUNTER fields from reads; the fix is migrating that peer to `false`, not declaring types everywhere. See [`types-mutators.md`](legacy-types.md#7-strict-mode-and-the-dql_strict_mode-system-parameter).
