# DQL Best Practices - Data Modeling, Optimization, and Schema Versioning

**Read this file ONLY when:** You need guidance on data modeling, query optimization, schema versioning, timestamps, soft delete, or understanding strict mode.

**For basic queries:** Use `SKILL.md` instead.

**For canonical syntax and per-version (4.14.x vs 5.0.x) behavior:** Use the files under `references/` — see the [Related Reference Files](#related-reference-files) list at the bottom of this file.

---

## Data Modeling Best Practices

### Core Principle
**"Choosing the right pattern can significantly impact the efficiency and effectiveness of your app."**

### Document Size Limits

**Engine thresholds** (both readable and settable via `ALTER SYSTEM`; the defaults are identical on 4.14.6, 5.0.3 and 5.1.0 — the *behaviour* of the hard limit is not):

| Parameter | Default | Behaviour when exceeded |
| --- | --- | --- |
| `document_size_soft_limit_bytes` | `262144` (**256 KiB**) | Warn-level log entry. The write succeeds. Same on every version. |
| `document_size_hard_limit_bytes` | `5242880` (**5 MiB**) | **5.1+: the local write is rejected** with a `DocumentSizeLimitError`. 4.14.x / 5.0.x: error-level log entry only — the write succeeds and the document still syncs. |

```sql
SHOW document_size_soft_limit_bytes;   -- 262144
SHOW document_size_hard_limit_bytes;   -- 5242880
```

> **Enforcement is version-dependent, and writer-side only.** On **5.1+** a local write over the hard limit fails outright (verified on 5.1.0: a 6 MiB `INSERT` and `UPDATE` both error; 5.0.3 and 4.14.6 accept the same write and log). On **every** version the check applies only to user-originated writes — an oversized document arriving over replication is still stored, so a 5.1 peer can hold a document it would refuse to write itself. Note that docs.ditto.live still describes the pre-5.1 "logs but succeeds" behaviour for the hard limit; the engine changed in 5.1 and the page has not caught up. Both values must be set to the **same** number on every peer in the mesh — mismatched limits disable replication sessions where enforcement is live.

Large documents are also slow on constrained transports — Bluetooth LE in particular (~20 KB/second effective) — so the practical ceiling is usually well below the soft limit.

**Recommendation:** Keep documents small and focused.

### Embedded vs Flat Models

#### When to Use Embedded Objects

**Advantages:**
- Retrieve/update related data together (single query)
- Atomic updates (all or nothing)
- Simpler queries (no joins)

**Best For:**
- Data always queried together
- Stable, unlikely to grow significantly
- Simple, shallow structure (1-2 levels)
- Users edit same items offline (less conflict)

**Example:**
```sql
INSERT INTO users DOCUMENTS ({
  '_id': 'user-1',
  'name': 'Alice',
  'profile': {
    'bio': 'Software Engineer',
    'location': 'NYC',
    'avatar_url': 'https://...'
  }
})
```

#### When to Use Flat Models

**Advantages:**
- Access/modify parts separately (efficiency)
- Handles growth and complexity
- Reduced conflicts (users edit different documents)
- Smaller documents (faster sync)

**Best For:**
- Access/update only parts frequently
- Expected to grow complex over time
- Deep nesting (3+ hierarchy levels)
- Users unlikely to edit simultaneously offline

**Example:**
```sql
-- ✅ GOOD: Separate collections with foreign keys
INSERT INTO people DOCUMENTS ({
  '_id': 'person-1',
  'name': 'Susan',
  'age': 31
})

INSERT INTO cars DOCUMENTS
  ({'_id': 'car-1', 'owner_id': 'person-1', 'make': 'Hyundai', 'year': 2020}),
  ({'_id': 'car-2', 'owner_id': 'person-1', 'make': 'Tesla', 'year': 2023})

-- Query separately
SELECT * FROM people WHERE _id = 'person-1'
SELECT * FROM cars WHERE owner_id = 'person-1'
```

### Decision Matrix

| Factor | Choose Embedded | Choose Flat |
|--------|----------------|-------------|
| **Query** | Retrieve/update pairs together | Access parts separately |
| **Size** | Stable, unlikely to grow | May become complex |
| **Concurrency** | Users edit same items offline | Users edit different items |
| **Structure** | Simple (1-2 levels) | Deep nesting (3+ levels) |
| **Data Growth** | Predictable, limited | Unbounded or unpredictable |
| **Access Pattern** | All-or-nothing | Selective field access |

### Additional Guidelines

**Use ATTACHMENT for Large Binary Data:**
```sql
-- For files > 250 KB
INSERT INTO files DOCUMENTS ({
  '_id': 'file-1',
  'filename': 'photo.jpg',
  'file_data': :attachment_object  -- ATTACHMENT type
})
```

**Use Immutable _id for Foreign Keys:**
```sql
-- _id never changes (stable reference)
INSERT INTO orders DOCUMENTS ({
  '_id': 'order-1',
  'user_id': 'user-123',  -- Immutable foreign key
  'product_id': 'prod-456',
  'quantity': 2
})
```

**Collections are Cheap:**
- Use them liberally to organize data
- Better to have many small collections than few large ones
- No performance penalty for multiple collections

---

## Schema Versioning Best Practices

### Golden Rule
**⚠️ NEVER change the type of an existing field**

This is the most critical rule for distributed systems. Changing field types breaks forward-compatibility and crashes old app versions.

### Why Schema Versioning Matters

In distributed systems:
- **Cannot control all production versions** simultaneously
- **Devices may be offline** for days/weeks/months
- **Old versions must read new data** (forward-compatibility)
- **New versions must read old data** (backward-compatibility)

### Core Principle

**Add schema_version to every document:**

```sql
INSERT INTO collection DOCUMENTS ({
  '_id': :id,
  'schema_version': 1,  -- Increment on schema changes
  'field1': :value1,
  'field2': :value2
}) ON ID CONFLICT DO UPDATE
```

### Four Primary Strategies

#### 1. Backward-Compatibility

**Purpose:** Older data coexists with new schemas

**Implementation:**
```sql
-- Bump version on schema changes
INSERT INTO cars DOCUMENTS ({
  '_id': :id,
  'schema_version': 2,  -- Incremented from 1
  'make': :make,
  'model': :model,
  'year': :year,
  'color': :color  -- New field added in v2
}) ON ID CONFLICT DO UPDATE

-- Old v1 documents still readable:
-- {_id: 'car-1', schema_version: 1, make: 'Honda', model: 'Civic', year: 2020}
-- New v2 documents include color:
-- {_id: 'car-2', schema_version: 2, make: 'Tesla', model: 'Model 3', year: 2024, color: 'blue'}
```

**Key Points:**
- Ditto replication protocol is backward-compatible
- Devices offline eventually resync with updated peers
- Older app versions can read newer data (if forward-compatible)

#### 2. Same-Version Compatibility

**Purpose:** Simplify business logic by processing only known schemas

**Implementation:**
```sql
-- Query specific version only
SELECT * FROM cars WHERE schema_version = 1

-- Or current version
SELECT * FROM cars WHERE schema_version = :currentVersion

-- Ignore unknown versions
SELECT * FROM cars WHERE schema_version <= :currentVersion
```

**Benefits:**
- Application code processes only understood structures
- Reduces validation complexity
- Clear separation between schema versions
- Safer (no surprises from unknown fields)

#### 3. Force Upgrade

**Purpose:** Detect incompatible newer versions, prompt user to update app

**Implementation:**
```sql
-- Detect documents with newer schema
SELECT * FROM cars WHERE schema_version > :currentVersion

-- If found, show user:
-- "Please update to the latest version to view this content"
```

**User Experience:**
- Similar to Apple Notes approach
- App halts sync when encountering incompatible data
- Prompts user to upgrade application
- Prevents data corruption from misinterpretation

**Example:**
```javascript
// App running schema v2
const incompatible = await query("SELECT COUNT(*) FROM cars WHERE schema_version > 2");
if (incompatible.count > 0) {
  showUpgradePrompt("New data available. Please update your app.");
  stopSync();
}
```

#### 4. Forward-Compatibility (Most Critical)

**Purpose:** Allow older app versions to read data created by newer versions

**Golden Rule:** **NEVER change the type of an existing field**

**Safe Changes:**
```sql
-- ✅ SAFE: Add new optional fields
UPDATE cars SET color = 'blue' WHERE _id = :id

-- ✅ SAFE: Add nested fields (with strict mode off or MAP type)
UPDATE cars SET features.sunroof = true WHERE _id = :id

-- ✅ SAFE: Add new collections
INSERT INTO car_maintenance DOCUMENTS ({
  '_id': 'maint-1',
  'car_id': 'car-1',
  'service_date': '2024-12-01'
})
```

**Unsafe Changes:**
```sql
-- ❌ UNSAFE: Change field type
-- v1: 'year': 2024 (INTEGER)
-- v2: 'year': '2024' (STRING)
-- Result: Old versions crash trying to read string as integer

-- ❌ UNSAFE: Remove existing field
UPDATE cars UNSET make WHERE _id = :id
-- Result: Old versions expect 'make' field, may crash

-- ❌ UNSAFE: Rename field
-- v1: 'color'
-- v2: 'paint_color'
-- Result: Old versions can't find 'color', may crash or show blank
```

**Safe Migration Pattern:**
```sql
-- Instead of changing type, add new field
-- Keep old field for compatibility

-- v1: year (INTEGER)
INSERT INTO cars DOCUMENTS ({
  'schema_version': 1,
  'year': 2024  -- INTEGER
})

-- v2: Add year_string, keep year
UPDATE cars SET
  schema_version = 2,
  year_string = CAST(year AS STRING)
WHERE schema_version = 1

-- Old versions still read 'year' (INTEGER)
-- New versions prefer 'year_string' (STRING) but fall back to 'year'
```

### Implementation Pattern

**1. Define Version Constants:**
```javascript
const SCHEMA_VERSION_V1 = 1;
const SCHEMA_VERSION_V2 = 2;
const SCHEMA_VERSION_V3 = 3;
const CURRENT_SCHEMA_VERSION = SCHEMA_VERSION_V3;
const MINIMUM_SUPPORTED_VERSION = SCHEMA_VERSION_V2;  // Drop v1 support
```

**2. Create Validation Model:**
```javascript
class CarDocument {
  static CURRENT_VERSION = 2;

  validate(doc) {
    // Check version
    if (!doc.schema_version) {
      throw new Error('Missing schema_version');
    }

    if (doc.schema_version > this.CURRENT_VERSION) {
      throw new Error('Incompatible schema version (upgrade app)');
    }

    // Validate required fields
    if (!doc.make || typeof doc.make !== 'string') {
      throw new Error('Invalid make field');
    }

    if (typeof doc.year !== 'number') {
      throw new Error('Invalid year field type');
    }

    return doc;
  }

  migrate(doc) {
    // Migrate v1 to v2
    if (doc.schema_version === 1) {
      return {
        ...doc,
        schema_version: 2,
        color: doc.color || 'unknown'  // Add missing field with default
      };
    }

    return doc;
  }
}
```

**3. Handle Version Migration:**
```sql
-- Migrate v1 documents to v2
UPDATE cars
SET
  schema_version = 2,
  color = 'unknown'  -- Add missing field with default
WHERE schema_version = 1 AND color IS MISSING

-- Verify migration
SELECT schema_version, COUNT(*) AS count
FROM cars
GROUP BY schema_version
ORDER BY schema_version
```

**4. Query with Version Awareness:**
```sql
-- Read only current version
SELECT * FROM cars WHERE schema_version = 2

-- Read compatible versions (current and previous)
SELECT * FROM cars WHERE schema_version IN (1, 2)

-- Read current or older (backward-compatible)
SELECT * FROM cars WHERE schema_version <= 2

-- Detect incompatible future versions
SELECT COUNT(*) AS incompatible_count
FROM cars
WHERE schema_version > 2
```

### Multi-Version Support Example

```sql
-- Application supports v1 and v2
-- v1: Basic car info (make, model, year)
-- v2: Adds 'features' nested object and 'color'

-- Read query handles both versions
SELECT
  _id,
  make,
  model,
  year,
  coalesce(color, 'unknown') AS color,  -- v2 field with fallback
  CASE
    WHEN schema_version >= 2 THEN features
    ELSE NULL
  END AS features
FROM cars
WHERE schema_version IN (1, 2)

-- Write always uses latest version
INSERT INTO cars DOCUMENTS ({
  '_id': :id,
  'schema_version': 2,
  'make': :make,
  'model': :model,
  'year': :year,
  'color': :color,
  'features': {
    'sunroof': false,
    'leather': true,
    'seats': 5
  }
}) ON ID CONFLICT DO UPDATE
```

### Schema Versioning Best Practices Summary

1. **Always include schema_version** - Every document should have it
2. **Never change field types** - Add new fields instead
3. **Never remove fields** - Mark as deprecated, remove only after full migration
4. **Add fields with defaults** - Ensures backward-compatibility
5. **Validate before insert** - Type-check at application level
6. **Support N and N-1 versions** - Graceful degradation
7. **Test with old versions** - Verify forward-compatibility
8. **Document schema changes** - Maintain migration guide
9. **Plan deprecation timeline** - Communicate version lifecycle
10. **Monitor version distribution** - Track active versions in production

---

## Query Optimization

### Access Paths Overview

Access paths determine how Ditto retrieves documents. The query planner automatically selects the most efficient path based on filters, indexes, and sort requirements.

**Access Path Types (fastest to slowest):**

| Access Path | Performance | Use Case | How to Verify |
|-------------|-------------|----------|---------------|
| **Index Scan** | Fast | Single indexed field filter/sort | `"index_scan"` in EXPLAIN |
| **Intersect Scan** | Fast | Multiple indexed fields (AND) | `"intersect"` in EXPLAIN |
| **Union Scan** | Fast | Multiple values (OR) | `"union"` in EXPLAIN |
| **Collection Scan** | Slow | No indexes, small collections | `"scan"` in EXPLAIN |

### Using EXPLAIN

**Always use EXPLAIN to verify query plans:**

```sql
-- Check access path
EXPLAIN SELECT * FROM tasks WHERE assignee = 'alice'

-- Look for operators (canonical names):
-- IndexScan       = Good (uses index, fast)
-- CollectionScan  = Bad (full collection scan, slow)
-- Intersect       = Multiple indexes combined under AND
-- Union           = Multiple indexes combined under OR
-- Fetch           = Document materialization after an IndexScan (absent on covering plans)
-- Filter          = Residual WHERE predicate the index could not satisfy
```

> Operator names and JSON shape are diagnostic, not a stable contract — see [`references/indexing.md`](references/indexing.md) §6 for the canonical operator catalog and worked example plans. Older SDKs and some tools render lowercase variants (e.g. `index_scan`); read shape, not exact spelling.

### Optimization Strategies

**1. Create Indexes for Frequently Queried Fields**

`CREATE INDEX` is user-facing DQL on all three supported SDK versions. Prioritize:
- Fields used in WHERE clauses
- Fields used in ORDER BY
- High cardinality fields (many unique values)

```sql
-- Fields that benefit from indexes:
CREATE INDEX IF NOT EXISTS idx_assignee   ON tasks (assignee);
CREATE INDEX IF NOT EXISTS idx_status     ON tasks (status);
CREATE INDEX IF NOT EXISTS idx_created_at ON tasks (created_at DESC);

WHERE assignee = 'alice'        -- Uses idx_assignee
WHERE status = 'active'         -- Uses idx_status
ORDER BY created_at DESC        -- Uses idx_created_at
```

For full `CREATE INDEX` grammar, covering plans, planner directives (`#profile`, `#disable_index_scan`, etc.), `EXPLAIN` output shape, and the `USE IDS` fast path, see [`references/indexing.md`](references/indexing.md).

**2. Use EXPLAIN to Verify Index Usage**

```sql
-- Before optimization
EXPLAIN SELECT * FROM tasks WHERE priority > 5
-- Plan rooted at CollectionScan  -- ❌ Full scan

-- After CREATE INDEX ON tasks (priority)
EXPLAIN SELECT * FROM tasks WHERE priority > 5
-- Plan rooted at IndexScan referencing idx_priority  -- ✅ Using index
```

**3. Combine Filters for Intersect Scans**

When multiple fields are indexed:

```sql
-- Uses intersect scan (combines multiple indexes)
SELECT * FROM tasks
WHERE assignee = 'alice' AND status = 'active'

-- EXPLAIN shows an Intersect node with two IndexScan children
-- (one per index). See references/indexing.md §6 for full plan shapes.
```

**4. Avoid Collection Scans on Large Collections**

```sql
-- ❌ BAD: Full collection scan
SELECT * FROM large_collection

-- ✅ BETTER: Use WHERE to filter
SELECT * FROM large_collection WHERE category = 'active'

-- ✅ BETTER: Use LIMIT to reduce results
SELECT * FROM large_collection LIMIT 100

-- ✅ BEST: Use indexed field with LIMIT
SELECT * FROM large_collection
WHERE status = 'active'
ORDER BY created_at DESC
LIMIT 100
```

**5. Monitor with System Collections**

DQL exposes a `system` datasource that holds virtual collections describing peer state. The ones most useful for diagnostics:

| Collection                | What it returns                                                                  |
| ------------------------- | -------------------------------------------------------------------------------- |
| `system:collections`      | List of every collection the peer knows about, with declared types per field.    |
| `system:vitals`           | Per-query performance counters (parse/plan/execution time, request counts).      |
| `system:active_requests`  | Currently-running queries and subscriptions on this peer.                        |
| `__presence`              | Peer-to-peer presence — which peers are visible on the mesh, with metadata.      |

```sql
-- Query performance statistics
SELECT * FROM system:vitals

-- Fields include:
-- - execution_time (total time)
-- - parse_time (parsing time)
-- - plan_time (planning time)
-- - request_count (number of executions)

-- Active query execution
SELECT * FROM system:active_requests

-- Collection catalog
SELECT * FROM system:collections

-- Mesh presence
SELECT * FROM __presence
```

See [`references/select.md`](references/select.md) for the FROM-clause grammar that accepts these datasources.

### Performance Tips

**Aggregate "Dam" Behavior:**
```sql
-- ⚠️ Processes ALL documents before returning
SELECT COUNT(*) FROM large_collection
SELECT SUM(price) FROM orders
SELECT AVG(rating) FROM reviews

-- ✅ Non-aggregate queries stream results incrementally
SELECT * FROM large_collection
```

**DISTINCT Memory Usage:**
```sql
-- ⚠️ Buffers ALL results in memory
SELECT DISTINCT category FROM products

-- ✅ Better: Use GROUP BY (more efficient)
SELECT category FROM products GROUP BY category
```

**LIMIT for Pagination:**
```sql
-- ✅ Return results incrementally
SELECT * FROM tasks ORDER BY created_at DESC LIMIT 20

-- ❌ Returns ALL, then discards most
SELECT * FROM tasks ORDER BY created_at DESC  -- No LIMIT
```

For full `SELECT` clause grammar — `WHERE`, `ORDER BY`, `LIMIT`/`OFFSET`, `GROUP BY`/`HAVING`, subqueries, `USE IDS`, and system datasources — see [`references/select.md`](references/select.md). System datasources like `system:collections`, `system:vitals`, and `system:active_requests` are documented there (§ on FROM clauses).

**Push Filters to WHERE (not HAVING):**
```sql
-- ✅ GOOD: Filter before aggregation
SELECT category, COUNT(*) FROM products
WHERE NOT deleted
GROUP BY category

-- ❌ BAD: Aggregate all, then filter
SELECT category, COUNT(*) FROM products
GROUP BY category
HAVING category != 'deleted'
```

---

## Strict Mode

### Overview

Strict mode controls CRDT type inference when `INSERT`/`UPDATE` encounters an object literal with no type definition — and controls whether `SELECT` needs type declarations to *see* non-REGISTER fields.

**This guidance assumes `dql_strict_mode = false` (lenient) on every peer** — the 5.x factory default and the migration target for 4.14.x meshes. With strict mode false you do **not** use `MAP`/`REGISTER` keywords on reads or writes: objects infer MAP, and reads return the most recent value of every field whatever its CRDT type.

**Default State:**
- SDK 4.14.x: `dql_strict_mode = true` (legacy default — migrate to `false`) → object → `REGISTER` (last-write-wins on the whole object)
- SDK 5.0.x: `dql_strict_mode = false` → object → `MAP` (per-field merge)
- Available: SDK 4.11+; runtime-only, re-apply at every app start

For the full per-version behavior matrix, the internal `DQL_MUTATOR_OBJECTS_AS_MAPS` flag, and worked merge examples, see [`references/types-mutators.md`](references/types-mutators.md) §7.

### Behavioral Differences

| Aspect | Strict=true (legacy 4.14.x default) | Strict=false (baseline) |
|--------|------------|--------------|
| **Objects on writes** | Stored as REGISTER (last-write-wins whole object) | Auto-inferred as MAP (per-field merge) — duck-typed from the JSON |
| **Nested Updates** | Replace entire object | Merge individual fields |
| **`MAP`/`REGISTER` keywords on writes** | Required for every non-REGISTER field | **Not needed — do not write them** |
| **Type declarations on reads** | Required — an undeclared MAP/COUNTER field is **omitted from results entirely**, as if it never existed (no error) | **Not needed** — reads return the most recent value of any type |
| **Counter Visibility** | Must declare COUNTER type on writes and reads | Declare COUNTER on writes; reads just work |
| **Legacy Compatibility** | Difficult | Easy |

### Configuration

The canonical user-facing parameter is `dql_strict_mode`. Parameter names in `ALTER SYSTEM SET` / `RESET` / `SHOW` are **case-insensitive** — the resolver lowercases the identifier, so `SHOW DQL_STRICT_MODE` works — but prefer lowercase: it is the name `SHOW` echoes back and the only spelling that matches a case-sensitive `SHOW ALL LIKE` pattern (use `ILIKE` if you want to match uppercase). See [`references/types-mutators.md`](references/types-mutators.md) §7 for the full feature-flag model (including the internal `DQL_MUTATOR_OBJECTS_AS_MAPS` flag that strict mode derives).

**Opting into lenient mode (the 5.0+ default; the migration target on 4.x):**
```sql
-- Apply before starting sync
ALTER SYSTEM SET dql_strict_mode = false
```

**Enable Strict Mode (legacy 4.14.x default — not recommended on any version):**
```sql
ALTER SYSTEM SET dql_strict_mode = true
```

**Check Current Setting:**
```sql
SHOW dql_strict_mode
```

### Example: Object Merge Behavior

**With Strict Mode = true (REGISTER):**
```sql
-- Device A writes:
UPDATE users SET profile = {'bio': 'Designer', 'location': 'NYC'} WHERE _id = 'user-1'

-- Device B writes (offline):
UPDATE users SET profile = {'bio': 'Engineer', 'city': 'SF'} WHERE _id = 'user-1'

-- Result: Last-write-wins (one completely replaces the other)
-- Either: {bio: 'Designer', location: 'NYC'}
-- Or:     {bio: 'Engineer', city: 'SF'}
-- One wins entirely, the other is lost
```

**With Strict Mode = false (MAP):**
```sql
-- Device A writes:
UPDATE users SET profile.bio = 'Designer', profile.location = 'NYC' WHERE _id = 'user-1'

-- Device B writes (offline):
UPDATE users SET profile.bio = 'Engineer', profile.city = 'SF' WHERE _id = 'user-1'

-- Result: Per-field merge (both updates preserved)
-- {bio: 'Engineer', location: 'NYC', city: 'SF'}
-- Last write wins per field, not per object
```

> Dotted path syntax (`profile.bio`, `features.seats`, etc.) is a **path expression** — supported in `SET`, `WHERE`, projections, and `ORDER BY` on all three supported SDK versions. See [`references/expressions.md`](references/expressions.md) §4 for the full path-expression grammar including array indexing (`tags[0]`) and parameter-driven keys.

### Cross-Peer Compatibility

**⚠️ CRITICAL: every peer should run `dql_strict_mode = false`**

**Problem:**
When peers use different strict mode settings without explicit MAP definitions:
- Data syncs correctly
- But displays differently on each peer — strict peers silently omit undeclared MAP/COUNTER fields from query results, as if the fields never existed
- Appears as sync issue (but isn't)

**Solutions:**

1. **Set lenient mode on every peer (the fix — do this first):**
   ```sql
   -- All peers run, at every app start:
   ALTER SYSTEM SET dql_strict_mode = false
   ```

2. **Transition window only — declare MAP types on statements still-strict peers execute (writes and reads):**
   ```sql
   INSERT INTO users (
     profile MAP(bio STRING, location STRING, city STRING)
   ) DOCUMENTS ({...})
   ```

### When to Use Strict Mode

**Strict mode = true is the legacy 4.14.x factory default, not a configuration choice.** No new mesh should adopt it, and existing 4.14.x meshes should migrate off it. If you find it set to `true` anywhere, plan the migration to `false` — mesh-wide, and before upgrading to v5 so the version jump changes no merge behavior.

**Strict Mode = false (the assumed baseline):**
- Automatic MAP inference — objects duck-type to per-field merge
- No `MAP`/`REGISTER` keywords on writes or reads
- Reads return the most recent value of every field, whatever its CRDT type
- Keywords remain only for `COUNTER`/`ATTACHMENT` and deliberate `REGISTER` overrides on atomic objects

**Recommendation:** never change the flag on 5.0+ (the lenient default is correct); on 4.x migrate to `dql_strict_mode = false` mesh-wide before upgrading to 5.0.

---

## Query Safety

### Parameterized Queries (Prevent Injection)

**Always use parameterized queries for user input:**

```sql
-- ✅ SAFE: Parameterized
SELECT * FROM tasks WHERE title = :search
-- Pass arguments: {search: userInput}
```

```js
// ❌ UNSAFE: String concatenation (SQL injection risk)
const query = "SELECT * FROM tasks WHERE title = '" + userInput + "'";
```

**Multiple parameters** bind the same way — one statement, several named placeholders:

```sql
SELECT * FROM tasks
WHERE assignee = :user AND status = :status AND priority >= :min_priority
-- Pass: {user: 'alice', status: 'active', min_priority: 3}
```

### Always Use ON ID CONFLICT

**For upserts (insert or update):**

```sql
-- ✅ CORRECT: Handles duplicate IDs gracefully
INSERT INTO tasks DOCUMENTS ({
  '_id': :id,
  'title': :title
}) ON ID CONFLICT DO UPDATE

-- ❌ WRONG: Fails if ID exists
INSERT INTO tasks DOCUMENTS ({
  '_id': :id,
  'title': :title
})
-- Error: "Identifier conflict on document {\"_id\":\"...\": using FAIL conflict policy"
```

**Common Mistake:** Forgetting `ON ID CONFLICT` when doing upsert-style operations (e.g., updating an order by re-inserting with same ID). This causes the DQL default FAIL policy to reject the operation.

**Conflict Resolution Options:**
- `DO UPDATE` - Update all fields (ensures replication)
- `DO UPDATE_LOCAL_DIFF` (SDK 4.12+) - Update only changed fields (optimal)
- `DO NOTHING` - Skip if ID exists
- `FAIL` - Error if ID exists (default, rarely used)

### Deleting Documents — TTL Awareness

When deleting documents you need mesh-wide (`DELETE`, or the deprecated `TOMBSTONE` on a Big Peer), the replicated tombstone is **not** kept forever:

An offline peer that comes back online after the retention window has expired can re-introduce the document, because no peer still holds a tombstone to suppress it.

> **Confirm the retention period for your deployment with Ditto support.** It differs between Small Peer / Edge and Big Peer / Cloud and is not stated in the public documentation, so it should not be hard-coded from memory. Design for the existence of a window rather than a specific number of days.

Note also that `TOMBSTONE` as a DQL statement is rejected on 4.14.6, 5.0.3 and 5.1.0 when run from a Small Peer (`Tombstone is not supported`) — it is Big-Peer-only. From an Edge SDK, use `DELETE` — it writes a replicating tombstone, exactly like `TOMBSTONE` does on a Big Peer, and is not a local-only eviction. See [`references/statements.md`](references/statements.md) §4–§5 for the full `EVICT`/`TOMBSTONE`/`DELETE` semantics and when each applies.

### Soft Delete Pattern

For data you want to "hide" without losing mesh-wide:

```sql
-- Soft delete: mark as deleted, retain document
UPDATE tasks SET deleted = true, deleted_at = clock() WHERE _id = :id

-- Reads filter out deleted documents
SELECT * FROM tasks WHERE NOT coalesce(deleted, false)

-- Periodic cleanup: hard-delete once safely past your retention window
DELETE FROM tasks WHERE deleted = true AND deleted_at < date_sub(clock(), 30, 'days')
```

This keeps writers in control of the deletion timeline rather than relying on the replicated tombstone TTL.

---

## Timestamp Best Practices

### ISO-8601 Format

**Always use ISO-8601 for timestamps:**

```sql
-- Date format: YYYY-MM-DD
WHERE created_at >= '2024-01-01'
WHERE expires_at <= '2024-12-31'

-- DateTime format: YYYY-MM-DDTHH:mm:ssZ
WHERE updated_at >= '2024-12-22T15:30:00Z'
WHERE event_time = '2024-12-22T15:30:00.000Z'

-- Insert with timestamp
INSERT INTO events DOCUMENTS ({
  '_id': :id,
  'timestamp': '2024-12-22T15:30:00.000Z',
  'event': 'login',
  'user_id': :user_id
})
```

### Clock Accuracy in Distributed Systems

**Device Clock Accuracy:**
- **iOS devices:** Typically within ±100ms of accuracy
- **Android devices:** Can deviate by several seconds
- **Each device:** Operates on its own system clock
- **Clock skew:** Creates time discrepancies across mesh

**Implications:**
```sql
-- ⚠️ Two devices may assign different timestamps to same event
-- Device A (10:00:00.000): INSERT ... timestamp = '2024-12-22T10:00:00.000Z'
-- Device B (09:59:58.500): INSERT ... timestamp = '2024-12-22T09:59:58.500Z'
-- Both created simultaneously, but timestamps differ by 1.5 seconds
```

### Network Time Protocol (NTP)

**For applications requiring high timing accuracy:**

1. **Implement NTP synchronization**
   - Sync device clocks with authoritative time server
   - Reduces clock skew across mesh
   - Critical for time-sensitive applications

2. **Use logical timestamps**
   - Lamport timestamps
   - Vector clocks
   - Hybrid logical clocks (HLC)

3. **Server-side timestamps**
   - If using Ditto Cloud, request server timestamp
   - More consistent than device clocks

**Example: Compensating for Clock Skew**
```sql
-- Instead of exact timestamp comparisons:
-- ❌ Fragile
WHERE created_at = '2024-12-22T10:00:00.000Z'

-- ✅ Use time ranges (tolerates skew)
WHERE created_at >= '2024-12-22T09:59:00.000Z'
  AND created_at <= '2024-12-22T10:01:00.000Z'
```

### Common Timestamp Patterns

**Track Elapsed Time:**
```sql
SELECT
  _id,
  title,
  clock() - created_at AS age_ms,
  date_diff(clock(), created_at, 'hours') AS age_hours
FROM documents
```

**Event Timestamps:**
```sql
INSERT INTO messages DOCUMENTS ({
  '_id': :id,
  'message': :text,
  'sent_at': clock(),  -- Current time
  'sender_id': :sender_id
})
```

**Time-Range Queries:**
```sql
-- Documents in specific month
SELECT * FROM logs
WHERE timestamp >= '2024-12-01T00:00:00Z'
  AND timestamp < '2025-01-01T00:00:00Z';
```

```sql
-- Last 7 days
SELECT * FROM logs
WHERE created_at >= date_sub(clock(), 7, 'days');
```

```sql
-- Next 24 hours
SELECT * FROM logs
WHERE expires_at <= date_add(clock(), 24, 'hours');
```

**Recent Documents:**
```sql
SELECT * FROM tasks
WHERE updated_at >= '2024-12-01T00:00:00Z'
ORDER BY updated_at DESC
LIMIT 50
```

**Expired Documents:**
```sql
SELECT * FROM sessions
WHERE expires_at < clock()
```

### Key Takeaway

**Anticipate time discrepancies in distributed environments:**
- iOS ±100ms accuracy
- Android several seconds deviation
- Implement NTP for critical timing
- Use time ranges instead of exact matches
- Consider logical timestamps for ordering

---

## Performance Checklist

### Before Query Execution

- [ ] Use EXPLAIN to verify access path
- [ ] Check for "index_scan" (not "scan")
- [ ] Add LIMIT if returning many results
- [ ] Avoid DISTINCT on large result sets
- [ ] Push filters to WHERE (not HAVING)

### After Query Execution

- [ ] Monitor system:vitals for performance stats
- [ ] Check execution_time for slow queries
- [ ] Verify indexes being used
- [ ] Optimize queries with full scans

### Data Modeling

- [ ] Documents < 256 KiB (avoid warnings)
- [ ] Documents < 5 MiB (hard limit — 5.1+ rejects the local write)
- [ ] Use flat models for complex data
- [ ] Use ATTACHMENT for large files
- [ ] Include schema_version field

### Schema Changes

- [ ] Never change field types
- [ ] Never remove fields
- [ ] Add fields with defaults
- [ ] Bump schema_version
- [ ] Test with old versions
- [ ] Document migration path

---

## Related Reference Files

This best-practices file covers the cross-cutting "how should I think about this?" advice. For canonical syntax, grammar, and per-version behavior:

- [`references/statements.md`](references/statements.md) — `INSERT`/`UPDATE`/`EVICT`/`TOMBSTONE`/`DELETE`/`ALTER SYSTEM`/`SHOW`/`SYNC CONTEXT`/`PROFILE` grammar, including TOMBSTONE TTL specifics.
- [`references/select.md`](references/select.md) — full `SELECT` grammar, `USE IDS`, system datasources.
- [`references/expressions.md`](references/expressions.md) — literals, path expressions (`a.b.c`, `arr[i]`), `CASE`, quantifiers, comprehensions.
- [`references/operators.md`](references/operators.md) — comparison, logical, arithmetic, string, set operators.
- [`references/functions.md`](references/functions.md) — scalar and aggregate function catalog.
- [`references/types-mutators.md`](references/types-mutators.md) — `REGISTER`/`MAP`/`COUNTER`/`PN_COUNTER`/`ATTACHMENT` types, `SET`/`UNSET`/`APPLY` mutators, the `dql_strict_mode` parameter.
- [`references/indexing.md`](references/indexing.md) — `CREATE INDEX`/`DROP INDEX`, `EXPLAIN`, `#profile`, planner directives, covering plans, `USE IDS`.
- [`references/versions.md`](references/versions.md) — SDK 4.14.x vs 5.0.x compatibility matrix.

## Official Documentation

- **Data Modeling:** https://docs.ditto.live/best-practices/data-modeling
- **Schema Versioning:** https://docs.ditto.live/best-practices/schema-versioning
- **Access Paths:** https://docs.ditto.live/dql/access-paths
- **Strict Mode:** https://docs.ditto.live/dql/strict-mode
- **Timestamps:** https://docs.ditto.live/best-practices/timestamps
- **DQL Overview:** https://docs.ditto.live/dql/dql
