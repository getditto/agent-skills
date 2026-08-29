---
title: DQL statements reference
description: Grammar and examples for INSERT, UPDATE, EVICT, TOMBSTONE, DELETE, EXPLAIN, ALTER SYSTEM, SHOW, SYNC CONTEXT, and PROFILE. Covers Ditto SDK 4.14.x and 5.0.x; version-gated features tagged.
---

# DQL statements reference

> All examples in this file query the `movies` / `reviews` schema documented in [`schema.md`](schema.md).

Authoritative catalog of every top-level DQL statement usable on **Ditto SDK 4.14.x and 5.0.x**, except `SELECT` (see [`select.md`](select.md)) and the indexing DDL `CREATE INDEX` / `DROP INDEX` (see [`indexing.md`](indexing.md)).

Both SDKs ship the same `Statement` enum: `Explain`, `Query` (`SELECT`), `Insert`, `Update`, `Remove` (`EVICT` / `TOMBSTONE` / `DELETE`), `AlterSystem`, `Show`, `RemoteQuery` (`SYNC CONTEXT`), `CreateIndex`, `DropIndex`. A statement may be prefixed by `EXPLAIN` and (on **5.0+ only**) by the `PROFILE` keyword.

Unless a section carries an "Available in:" note, the statement works identically on 4.14.x and 5.0.x.

For expression grammar see [`expressions.md`](expressions.md); for operators see [`operators.md`](operators.md); for functions see [`functions.md`](functions.md); for CRDT types and mutators (`COUNTER`, `MAP`, `APPLY`) see [`types-mutators.md`](types-mutators.md).

---

## 1. INSERT

Adds documents to a collection. Three optional knobs: a type definition (`INTO COLLECTION`), a conflict policy (`ON ID CONFLICT`), and a projection (`RETURNING`). The `INITIAL` flavour seeds default data on a Small Peer.

### 1.1 Grammar

```
INSERT INTO [COLLECTION] <collection> [ ( <col_def> [, <col_def> ...] ) ]
  [ INITIAL ]
  { DOCUMENTS | VALUES } ( <doc_expr> ) [, ( <doc_expr> ) ...]
  [ ON ID CONFLICT { FAIL | DO NOTHING | DO UPDATE | DO UPDATE_LOCAL_DIFF } ]
  [ RETURNING <projection> ]

<col_def> ::= <field_name> <crdt_type>     -- e.g. `director MAP`, `watch_count COUNTER`
```

- `DOCUMENTS` and `VALUES` are synonyms.
- `_id` is optional. Omit it and Ditto generates one.
- `INTO COLLECTION coll (cols…)` is **required** whenever you touch a non-register CRDT (`MAP`, `COUNTER`, `PN_COUNTER`, `ATTACHMENT`). See [`types-mutators.md`](types-mutators.md).
- `INITIAL` is **Small Peer only** (both 4.x and 5.0). Cannot be combined with `SELECT`-source or with `ON ID CONFLICT`.

### 1.2 Plain insert with auto-generated id

```sql
INSERT INTO movies DOCUMENTS
  ({ 'title': 'Inception', 'year': 2010, 'runtime_minutes': 148 });
```

### 1.3 Explicit `_id` with batched documents

```sql
INSERT INTO movies DOCUMENTS
  ({ '_id': 'tt0468569', 'title': 'The Dark Knight',   'year': 2008 }),
  ({ '_id': 'tt1375666', 'title': 'Inception',         'year': 2010 }),
  ({ '_id': 'tt1853728', 'title': 'Django Unchained',  'year': 2012 });
```

### 1.4 Full schema with CRDT type definitions

Whenever the document touches a `MAP`, `COUNTER`, `PN_COUNTER`, or `ATTACHMENT` field, declare it with `INTO COLLECTION`.

```sql
INSERT INTO COLLECTION movies (
  director    MAP,
  ratings     MAP,
  watch_count COUNTER
)
DOCUMENTS ({
  '_id': 'tt0816692',
  'title': 'Interstellar',
  'year': 2014,
  'runtime_minutes': 169,
  'genres': ['Adventure', 'Drama', 'Sci-Fi'],
  'director': { 'name': 'Christopher Nolan', 'born': 1970 },
  'cast': [
    { 'name': 'Matthew McConaughey', 'role': 'Cooper' },
    { 'name': 'Anne Hathaway',       'role': 'Brand' }
  ],
  'ratings': { 'imdb': 8.6, 'rotten_tomatoes': 73, 'metacritic': 74 },
  'box_office_millions': 677.5,
  'tags': ['space', 'time'],
  'watch_count': 0,
  'is_classic': false,
  'released': '2014-11-07'
})
ON ID CONFLICT DO UPDATE;
```

A counter initialised to `0` here will accept `APPLY watch_count INCREMENT BY n` afterwards (see [§2 UPDATE](#2-update)).

> **Available in:** `COUNTER` requires SDK 4.14+. `PN_COUNTER` requires SDK 4.11+. `MAP` and `ATTACHMENT` are available in all 4.x and 5.0.x.

### 1.5 `ON ID CONFLICT` actions

What happens when a document with the same `_id` already exists:

| Clause                                | Effect                                                            | Available on   |
| ------------------------------------- | ----------------------------------------------------------------- | -------------- |
| `ON ID CONFLICT FAIL` (default)       | Entire `INSERT` fails on the first conflict                       | Small + Big    |
| `ON ID CONFLICT DO NOTHING`           | Skip conflicting docs, insert the rest                            | Small only     |
| `ON ID CONFLICT DO UPDATE`            | Merge inserted values into the existing document                  | Small + Big    |
| `ON ID CONFLICT DO UPDATE_LOCAL_DIFF` | Like `DO UPDATE` but stores only the local diff for replication   | Small only     |

> **Available in:** `DO UPDATE_LOCAL_DIFF` requires SDK **4.12+** (AST variant `DoUpdateDifferent`).

```sql
-- Upsert: insert if new, merge fields if existing
INSERT INTO movies DOCUMENTS
  ({ '_id': 'tt1160419', 'title': 'Dune', 'year': 2021 })
ON ID CONFLICT DO UPDATE;

-- Skip conflicts silently
INSERT INTO movies DOCUMENTS
  ({ '_id': 'tt0111161', 'title': 'The Shawshank Redemption' })
ON ID CONFLICT DO NOTHING;

-- Replicate only the changed fields (smaller mesh footprint)
INSERT INTO movies DOCUMENTS
  ({ '_id': 'tt0816692', 'box_office_millions': 681.0 })
ON ID CONFLICT DO UPDATE_LOCAL_DIFF;   -- SDK 4.12+
```

### 1.6 Cross-version notes — `DO MERGE`

`DO MERGE` is **not** a portable conflict action on the 4.14.x / 5.0.x cross-section:

- **SDK 4.x:** the parser accepts `ON ID CONFLICT DO MERGE` and folds it to `DO UPDATE`. It is an undocumented alias and produces the same effect as `DO UPDATE`.
- **SDK 5.0.x:** the keyword was removed. `DO MERGE` raises a parse error.
- **SDK 5.1+ (out of scope here):** `DO MERGE` returns as a first-class action distinct from `DO UPDATE`.

**Recommendation:** write `ON ID CONFLICT DO UPDATE` for code that needs to run on both 4.14.x and 5.0.x. Avoid `DO MERGE` entirely until you can pin to 5.1+.

### 1.7 `INITIAL` — seed default data (Small Peer)

`INSERT INTO ... INITIAL DOCUMENTS (...)` inserts a document **as if it had been inserted at the beginning of time**. If a document with the same `_id` already exists, it is left untouched. If a document with that `_id` was previously deleted (tombstoned), the default does not reappear.

```sql
-- Seed a default movie record on first launch
INSERT INTO movies INITIAL DOCUMENTS
  ({ '_id': 'seed-1', 'title': 'Sample Movie', 'year': 2000 });
```

- Small Peer only on both 4.x and 5.0.x.
- Cannot be combined with `ON ID CONFLICT`.
- Cannot use `INSERT ... SELECT` source.

### 1.8 `RETURNING`

> **Available in:** Ditto SDK **5.1+** — not accepted by 4.14.x or 5.0.x (parse error / "RETURNING is not supported").

Project specific fields (or expressions) from the inserted documents.

```sql
INSERT INTO reviews DOCUMENTS
  ({ 'movie_id': 'tt0111161', 'user_id': 'u-99', 'score': 5,
     'comment': 'Perfect.', 'created_at': '2024-06-01T12:00:00Z' })
RETURNING _id, movie_id, score;
```

`DISTINCT` and `RAW` are **not** allowed inside `RETURNING`.

---

## 2. UPDATE

Modify documents in place. Three mutation clauses — `SET`, `UNSET`, `APPLY` — plus the usual `WHERE` / `ORDER BY` / `LIMIT` / `OFFSET` and an optional `RETURNING`.

### 2.1 Grammar

```
UPDATE [COLLECTION] <collection> [ ( <col_def> [, <col_def> ...] ) ]
  [ SET   <field> = <expr> [, <field> = <expr> ...] ]
  [ UNSET <field> [, <field> ...] ]
  [ APPLY <field> <counter_mutator> [, <field> <counter_mutator> ...] ]
  [ WHERE   <expr> ]
  [ ORDER BY <expr> [ASC|DESC] [, ...] ]
  [ LIMIT   <int> ]
  [ OFFSET  <int> ]
  [ RETURNING <projection> ]

<counter_mutator> ::=
    INCREMENT    BY <expr>        -- requires field declared COUNTER     (SDK 4.14+)
  | PN_INCREMENT BY <expr>        -- requires field declared PN_COUNTER  (SDK 4.11+)
  | RESTART [ WITH <expr> ]       -- counter only; resets to baseline
```

Notes:

- `SET`, `UNSET`, and `APPLY` clauses can be combined in one statement.
- `WHERE`, `ORDER BY`, `LIMIT`, and `OFFSET` behave the same as on `SELECT` — see [`select.md`](select.md).
- `UPDATE COLLECTION coll (col_defs…)` is required when any mutation touches a non-register CRDT field. The type def applies to that statement only; it does not redefine the schema globally.
- **`USE IDS` is not supported on `UPDATE`** in either 4.14.x or 5.0.x (parser TODO). To target specific docs, use `WHERE _id IN (...)`.

### 2.2 `SET` and `UNSET`

```sql
-- Set + unset, both REGISTER fields
UPDATE movies
SET is_classic = true,
    box_office_millions = 28.34
UNSET tags
WHERE _id = 'tt0111161';
```

### 2.3 Updating nested MAP fields

When a field is declared `MAP`, an object on the right-hand side of `SET` is a **bulk merge**, not a replace — fields you don't mention are left alone.

```sql
-- Only ratings.imdb is updated; rotten_tomatoes / metacritic remain
UPDATE COLLECTION movies (ratings MAP)
SET ratings = { 'imdb': 9.4 }
WHERE _id = 'tt0111161';
```

To remove a sub-field from a MAP, dotted-path `UNSET` (e.g. `UNSET ratings.imdb`) — each removal writes per-key tombstone metadata, so for mass clearing prefer `UNSET` on the parent field. See [`types-mutators.md`](types-mutators.md) for the full MAP semantics.

### 2.4 Counters — `APPLY INCREMENT BY`, `RESTART`

> **Available in:** `COUNTER` and `APPLY ... INCREMENT BY` require SDK 4.14+. `PN_COUNTER` and `APPLY ... PN_INCREMENT BY` require SDK 4.11+.

```sql
-- Increment a state-based COUNTER (4.14+)
UPDATE COLLECTION movies (watch_count COUNTER)
APPLY watch_count INCREMENT BY 1
WHERE _id = 'tt0111161';

-- Decrement (negative argument)
UPDATE COLLECTION movies (watch_count COUNTER)
APPLY watch_count INCREMENT BY -1
WHERE _id = 'tt0111161';

-- Reset the counter to a new baseline (COUNTER only)
UPDATE COLLECTION movies (watch_count COUNTER)
APPLY watch_count RESTART WITH 0
WHERE title = 'The Shawshank Redemption';

-- Legacy PN_COUNTER (4.11+); prefer COUNTER on new code
UPDATE COLLECTION movies (legacy_views PN_COUNTER)
APPLY legacy_views PN_INCREMENT BY 1
WHERE _id = 'tt0111161';
```

### 2.5 Combined clauses + `RETURNING`

> **Available in:** Ditto SDK **5.1+** (see §1.8).

```sql
-- Mark every pre-1980 film as a classic and return the result
UPDATE movies
SET is_classic = true
WHERE year < 1980
RETURNING _id, title, year, is_classic;

-- Bump watch_count for the most recent five and return them
UPDATE COLLECTION movies (watch_count COUNTER)
APPLY watch_count INCREMENT BY 1
ORDER BY released DESC
LIMIT 5
RETURNING _id, title, watch_count;
```

---

## 3. EVICT

Removes documents **from the local Small Peer's store only**. The deletion is **not** replicated — peers that still hold the document will continue to hold it, and may even re-sync it back to the evicting peer if connected.

```
EVICT FROM <collection>
  [ WHERE   <expr> ]
  [ ORDER BY <expr> [ASC|DESC] [, ...] ]
  [ LIMIT   <int> ]
  [ OFFSET  <int> ]
  [ RETURNING <projection> ]
```

- Small Peer only.
- **`USE IDS` is not supported on `EVICT`** in either 4.14.x or 5.0.x (parser TODO). Use `WHERE _id IN (...)` instead.

```sql
-- Drop all pre-1950 movies from this device's local store
EVICT FROM movies
WHERE year < 1950;

-- Sweep already-watched reviews, returning what was evicted
EVICT FROM reviews
WHERE score < 3
RETURNING _id, movie_id;
```

> EVICT is the right tool for **freeing local storage** (e.g. data the device no longer needs in its working set). It is **not** a permanent delete.

---

## 4. TOMBSTONE

Marks documents as deleted **across the mesh**. The tombstone replicates: every peer that receives it will remove the document from its store.

```
TOMBSTONE FROM <collection>
  [ WHERE   <expr> ]
  [ ORDER BY <expr> [ASC|DESC] [, ...] ]
  [ LIMIT   <int> ]
  [ OFFSET  <int> ]
  [ RETURNING <projection> ]
```

- **Big Peer only.** Running `TOMBSTONE` on a Small Peer is an error.
- **`USE IDS` is not supported on `TOMBSTONE`** in any tested version (parser TODO). Use `WHERE _id IN (...)`.
- `RETURNING` additionally requires SDK **5.1+** (§1.8), so the combinations cannot be exercised offline ahead of Big Peer support.

```sql
-- Retract a withdrawn movie mesh-wide, returning what was tombstoned
TOMBSTONE FROM movies
WHERE _id = 'tt0111161'
RETURNING _id, title, year;

-- Bulk withdraw an entire batch
TOMBSTONE FROM movies
WHERE _id IN ('tt9999990', 'tt9999991', 'tt9999992');
```

> TOMBSTONE is the right tool when you genuinely want the document gone everywhere. The replicated tombstone has a TTL (7 days on Edge SDKs, 30 days on the Big Peer / Cloud). Offline peers that come online after the TTL may re-introduce the document — design for the TTL window.

---

## 5. DELETE — alias

`DELETE FROM ...` is a **context-resolved alias**: on a Small Peer it behaves like `EVICT`; on a Big Peer it behaves like `TOMBSTONE`. Syntax is identical to both.

```
DELETE FROM <collection>
  [ WHERE   <expr> ]
  [ ORDER BY <expr> [ASC|DESC] [, ...] ]
  [ LIMIT   <int> ]
  [ OFFSET  <int> ]
  [ RETURNING <projection> ]
```

- Available on both Small and Big Peer.
- **`USE IDS` is not supported on `DELETE`** in either 4.14.x or 5.0.x (parser TODO). Use `WHERE _id IN (...)` instead.

```sql
-- Bulk delete by id list (resolves to EVICT on Small Peer, TOMBSTONE on Big Peer)
DELETE FROM movies
WHERE _id IN ('tt9999990', 'tt9999991', 'tt9999992');

-- Conditional delete with RETURNING
DELETE FROM reviews
WHERE created_at < '2020-01-01'
RETURNING _id, movie_id, user_id, score;
```

### 5.1 When to use which — EVICT vs TOMBSTONE vs DELETE

| Keyword     | Scope                                    | Replicates? | Available on  | Pick it when…                                                  |
| ----------- | ---------------------------------------- | ----------- | ------------- | -------------------------------------------------------------- |
| `EVICT`     | Local Small-Peer store only              | No          | Small Peer    | You want to free local storage / shrink working set.           |
| `TOMBSTONE` | Mesh-wide, replicates to all peers       | Yes         | Big Peer      | You want the document gone everywhere, permanently.            |
| `DELETE`    | Resolves to `EVICT` (Small) or `TOMBSTONE` (Big) | Depends     | Both          | You want one statement that "just does the right thing" per peer role. |

Mental shorthand: **EVICT = local sweep, TOMBSTONE = "tell the mesh to forget"**. If you `EVICT` a document on one peer, another peer that still has it can replicate it back. If you `TOMBSTONE` it, the tombstone propagates and the document stays gone everywhere (subject to TTL).

---

## 6. EXPLAIN

Returns the query plan as a single document and does **not** execute the statement.

```
EXPLAIN <statement>
```

`<statement>` can be `SELECT`, `INSERT`, `UPDATE`, or any of `EVICT` / `TOMBSTONE` / `DELETE` (i.e. the `Remove` family). Both 4.14.x and 5.0.x accept the same shape.

```sql
-- Plan a SELECT against an indexed collection
EXPLAIN SELECT * FROM movies WHERE year = 1994 AND ratings.imdb > 8;

-- Plan a mutating statement (no docs are modified)
EXPLAIN UPDATE movies
SET is_classic = true
WHERE year < 1980;

-- Plan a multi-collection lookup (manual join via WHERE)
EXPLAIN SELECT r.*
FROM reviews r
WHERE r.movie_id IN (SELECT _id FROM movies WHERE year = 1994);
```

Look for:

- `index_scan` — the plan uses an index (good)
- `scan` — the plan does a full collection scan (consider an index)
- `intersect` / `union` — multiple indexes combined with `AND` / `OR`

> The output **shape is not stable**. Treat it as a diagnostic tool, not an API contract.

---

## 7. ALTER SYSTEM

Change runtime configuration parameters. Equivalent to a programmatic `setParameter` call.

```
ALTER SYSTEM SET <key> { = | TO } <value>
ALTER SYSTEM RESET <key>
ALTER SYSTEM RESET ALL
```

- `=` and `TO` are interchangeable.
- **Persistence is memory-only** — settings are reset on every restart. Apply immediately after opening the Ditto instance and **before sync begins**.
- Use `SHOW` (§8) to discover available parameter names.

```sql
-- Switch off strict mode (5.0.x ships strict=false by default; 4.x ships strict=true)
ALTER SYSTEM SET DQL_STRICT_MODE = false;

-- Same thing using TO
ALTER SYSTEM SET DQL_STRICT_MODE TO false;

-- Reset one parameter to its default
ALTER SYSTEM RESET DQL_STRICT_MODE;

-- Reset everything
ALTER SYSTEM RESET ALL;
```

---

## 8. SHOW

Inspect runtime configuration parameters.

```
SHOW ALL [ { LIKE | ILIKE } '<pattern>' [ ESCAPE '<char>' ] ]
SHOW <parameter_name>
```

- `LIKE` is case-sensitive; `ILIKE` is case-insensitive.
- `%` and `_` are wildcards inside the pattern; use `ESCAPE` to introduce a literal wildcard.

```sql
SHOW ALL;                                    -- every parameter
SHOW ALL LIKE 'transport_%';                 -- all transport_… parameters
SHOW ALL ILIKE 'DQL_%';                      -- DQL_… (case-insensitive)
SHOW ALL LIKE 'transport!_%' ESCAPE '!';     -- literal underscore in pattern
SHOW DQL_STRICT_MODE;                        -- one parameter
```

---

## 9. SYNC CONTEXT (RemoteQuery)

**Big Peer only.** Sends a `SELECT` or `SHOW` to a subset of Small Peers chosen by a predicate over peer metadata. Read-only — mutations are not allowed in a remote query.

```
SYNC CONTEXT ( PEERS [ WHERE <peer_predicate> ] )
  { <select_statement> | <show_statement> }
```

The `PEERS` collection exposes three register fields:

- `peerKeyString` — the peer's identity
- `peerMetadata` — application-supplied per-peer JSON
- `identityServiceMetadata` — identity-service-supplied per-peer JSON

```sql
-- Ask all kiosk peers for their list of classic movies
SYNC CONTEXT (PEERS WHERE peerMetadata.role = 'kiosk')
  SELECT _id, title, year
  FROM movies
  WHERE is_classic = true;

-- Inspect strict-mode setting on every staging peer
SYNC CONTEXT (PEERS WHERE peerMetadata.environment = 'staging')
  SHOW DQL_STRICT_MODE;
```

---

## 10. PROFILE

> **Available in:** SDK **5.0+** only — the `PROFILE` leading keyword is **not** present in 4.x. v4 users must use `EXPLAIN` for plan inspection.

`PROFILE` executes the statement and sets the `#profile` directive on the request, asking the engine to attach per-operator profiling data to the result.

```
PROFILE <statement>
```

```sql
-- Profile a SELECT (5.0+)
PROFILE SELECT * FROM movies
WHERE year = 1994 AND ratings.imdb > 8;
```

> **Output shape:** in **5.0.x** the engine sets the `#profile` directive and any profiling output appears alongside the regular result rows in a context-dependent way. A **structured profile output object** (per-operator timing, document counts, etc.) is a **5.1+** feature and is intentionally not documented here. Treat 5.0.x profiling as a directive that requests profiling, not as a stable contract.

---

## 11. Features intentionally not documented

Three statement-level features are excluded from this reference because they are **not available in either 4.14.x or 5.0.x**:

- **`ADVISE` / `ADVISE AND PROVISION`** — index recommendation wrapper. Lands in SDK 5.1+. Not supported on either 4.14.x or 5.0.x; do not use.
- **Structured `PROFILE` output** — see §10. Lands in 5.1+.
- **`USE IDS` on `UPDATE` / `EVICT` / `TOMBSTONE` / `DELETE`** — the parser carries a TODO in both 4.14.x and 5.0.x. `USE IDS` is supported only on `SELECT`. For mutations, use `WHERE _id IN (...)` instead.

`SELECT` lives in [`select.md`](select.md). `CREATE INDEX` / `DROP INDEX` live in [`indexing.md`](indexing.md). CRDT type definitions (`MAP`, `COUNTER`, `PN_COUNTER`, `ATTACHMENT`) and their mutators are documented in [`types-mutators.md`](types-mutators.md).
