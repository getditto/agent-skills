# Movie mutations — Ditto

## Contents

- [Mutations](#mutations)
- [Task 11 — Increment the watch counter](#task-11--increment-the-watch-counter)
- [Task 12 — Update a nested MAP field without clobbering siblings](#task-12--update-a-nested-map-field-without-clobbering-siblings)
- [Task 13 — Flag pre-1980 films as classics with RETURNING](#task-13--flag-pre-1980-films-as-classics-with-returning)
- [Task 14 — Remove a derived field post-backfill (UNSET)](#task-14--remove-a-derived-field-post-backfill-unset)
- [Task 15 — Reset the watch counter on a re-release (RESTART)](#task-15--reset-the-watch-counter-on-a-re-release-restart)
- [Task 16 — Local cleanup of pre-1950 films (EVICT)](#task-16--local-cleanup-of-pre-1950-films-evict)
- [Task 17 — Mesh-wide retraction of a withdrawn film (TOMBSTONE)](#task-17--mesh-wide-retraction-of-a-withdrawn-film-tombstone)
- [Task 18 — Bulk delete with an id list](#task-18--bulk-delete-with-an-id-list)

Topic index: [movies-cookbook.md](movies-cookbook.md). Covers Ditto SDK 4.14.x (LTS),
5.0.x, 5.1.x and 5.2.0; version-specific notes remain inline. Read only the topic needed.

## Mutations

### Task 11 — Increment the watch counter

> **Available in:** Ditto SDK 4.14+ (COUNTER). PN_COUNTER variant requires SDK 4.11+.

**Goal:** Bump a peer-safe counter by one.

**Query (COUNTER — recommended, 4.14+):**

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

**Notes:** This is the **only** correct way to bump a counter. `SET watch_count = watch_count + 1` would silently lose concurrent increments on merge because `+ 1` resolves once on the writing peer and stores a regular `REGISTER` value. Prefer `COUNTER` (4.14+) on new code; `PN_COUNTER` exists for backwards compatibility. See [`types-mutators.md`](../references/types-mutators.md) §3.

### Task 12 — Update a nested MAP field without clobbering siblings

**Goal:** Change one rating without touching the others.

**Query:**

```sql
UPDATE movies
SET ratings.rotten_tomatoes = 95
WHERE _id = :id;
```

**Notes on `dql_strict_mode`:** No declaration on the statement — with `dql_strict_mode = false` (the assumed baseline: 5.x default, 4.14.x migration target) the engine treats `ratings` as a MAP automatically, on reads and writes. The `UPDATE COLLECTION movies (ratings MAP) ...` form is only for un-migrated 4.14.x strict peers: there, a nested-field `SET` without the declaration is rejected (or stored as a non-merging sub-`REGISTER` path), and plain reads omit the field entirely. Migrate those peers to `false` — don't write declarations for them. See [`types-mutators.md`](../references/types-mutators.md) §§2 and 7 for the strict-mode behaviors and MAP merge semantics.

### Task 13 — Flag pre-1980 films as classics with RETURNING

> **Available in:** SDK **5.1+** (`RETURNING`, see [`statements.md`](../references/statements.md) §1.8).

**Goal:** Mark every old film and capture the ids/titles that changed.

**Query:**

```sql
UPDATE movies
SET is_classic = true
WHERE year < 1980
RETURNING _id, title;
```

**Notes:** `RETURNING` is SDK 5.1+ and works there on `UPDATE`, `DELETE`, and `EVICT` (`TOMBSTONE` accepts it in the grammar, but `TOMBSTONE` itself is Big-Peer-only). The projection list mirrors the rules for `SELECT`, except `DISTINCT` and `RAW` are not allowed. See [`statements.md`](../references/statements.md) §2.5.

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

> **Available in:** Ditto SDK 4.14+ (COUNTER)

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

**Notes:** `EVICT` is **non-replicating** — Small Peer only. Other peers in the mesh still hold these documents, and if any of them syncs to this peer later, the films will return. Use `EVICT` for "this device doesn't need it in its working set anymore", and `DELETE` for "remove globally". See [`statements.md`](../references/statements.md) §3.

### Task 17 — Mesh-wide retraction of a withdrawn film (TOMBSTONE)

**Goal:** Permanently remove a document everywhere in the mesh.

**Query:**

```sql
TOMBSTONE FROM movies
WHERE _id = :withdrawn_id
RETURNING _id, title;
```

**Notes:** `TOMBSTONE` is **Big Peer only** and replicates the deletion to every connected peer. The tombstone has a TTL (7 days on Edge SDKs, 30 days on the Big Peer); offline peers that come online after that window may reintroduce the document. From an Edge SDK use `DELETE FROM ...` instead — it replicates the same way and is not gated to the Big Peer. See [`statements.md`](../references/statements.md) §4.

### Task 18 — Bulk delete with an id list

**Goal:** Remove several documents by id in one statement.

**Query:**

```sql
DELETE FROM movies
WHERE _id IN ('tt9999990', 'tt9999991', 'tt9999992');
```

**Notes:** `DELETE` writes replicating tombstones from either peer type — it is the mesh-wide delete, and the one to use from an Edge SDK (`TOMBSTONE` is a deprecated Big-Peer-only alias for it). **Do not use `USE IDS LIST` on `DELETE`, `UPDATE`, `EVICT`, or `TOMBSTONE`** — both the 4.14.x and 5.0.x parsers carry TODO comments for `USE IDS` on mutations, so `USE IDS` is `SELECT`-only today. `WHERE _id IN (...)` is the portable, supported form. See [`statements.md`](../references/statements.md) §5.

---
