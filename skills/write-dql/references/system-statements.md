# System statements — Ditto

## Contents

- [6. EXPLAIN](#6-explain)
- [7. ALTER SYSTEM](#7-alter-system)
- [8. SHOW](#8-show)
- [9. SYNC CONTEXT (RemoteQuery)](#9-sync-context-remotequery)
- [10. PROFILE](#10-profile)

Topic index: [statements.md](statements.md). Covers Ditto SDK 4.14.x (LTS),
5.0.x and 5.1.x; version-specific notes remain inline. Read only the topic needed.

For movies/reviews examples, see the [schema](schema.md) only when adapting those examples; other examples define their own fields.

## 6. EXPLAIN

Returns the query plan as a single document and does **not** execute the statement.

```
EXPLAIN <statement>
```

> **Version-gated by statement kind.** `EXPLAIN SELECT` works on 4.14.x, 5.0.x and 5.1.x. `EXPLAIN` of any **mutation** (`INSERT`, `UPDATE`, `DELETE`, `EVICT`) is **SDK 5.1+** — on 4.14.x and 5.0.x it raises `Explain DML is not supported`.

```sql
-- Plan a SELECT against an indexed collection — works on every SDK version
EXPLAIN SELECT * FROM movies WHERE year = 1994 AND ratings.imdb > 8;

-- Plan a mutating statement (no docs are modified) -- SDK 5.1+ only
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
-- Lenient mode: the 5.0.x default, and the recommended setting on 4.x (which ships strict=true)
ALTER SYSTEM SET dql_strict_mode = false;

-- Same thing using TO
ALTER SYSTEM SET dql_strict_mode TO false;

-- Reset one parameter to its default
ALTER SYSTEM RESET dql_strict_mode;

-- Reset everything
ALTER SYSTEM RESET ALL;
```

---

## 8. SHOW

Inspect runtime configuration parameters.

```
SHOW ALL [ { LIKE | ILIKE } '<pattern>' [ ESCAPE '<char>' ] ]   -- filter clause: SDK 5.1+
SHOW <parameter_name>
```

> **`SHOW ALL` and `SHOW <parameter_name>` work on every SDK version. The `LIKE` / `ILIKE` / `ESCAPE` filter clause is SDK 5.1+** — on 4.14.x and 5.0.x it is a parse error (`Unexpected token LIKE`). On those versions, run bare `SHOW ALL` and filter in the application.

- `LIKE` is case-sensitive; `ILIKE` is case-insensitive. Parameter names are lowercase, so `LIKE 'DQL_%'` matches nothing — use `'dql_%'` or `ILIKE`.
- `%` and `_` are wildcards inside the pattern; use `ESCAPE` to introduce a literal wildcard.

```sql
SHOW ALL;                                    -- every parameter (all SDK versions)
SHOW dql_strict_mode;                        -- one parameter (all SDK versions)
```

```sql
-- Available in: SDK 5.1+
SHOW ALL LIKE 'transport_%';                 -- all transport_… parameters
SHOW ALL ILIKE 'DQL_%';                      -- dql_… (case-insensitive)
SHOW ALL LIKE 'transport!_%' ESCAPE '!';     -- literal underscore in pattern
SHOW dql_strict_mode;                        -- one parameter
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
  SHOW dql_strict_mode;
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
