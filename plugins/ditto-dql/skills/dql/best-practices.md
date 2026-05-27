# DQL Best Practices - Data Modeling, Optimization, and Schema Versioning

**Read this file ONLY when:** You need guidance on data modeling, query optimization, schema versioning, or understanding strict mode.

**For basic queries:** Use SKILL.md instead.

---

## Data Modeling Best Practices

### Core Principle
**"Choosing the right pattern can significantly impact the efficiency and effectiveness of your app."**

### Document Size Limits

**Hard Limits:**
- Documents > **5 MB** don't sync with connected peers
- Documents > **250 KB** trigger console warnings
- Bluetooth LE: ~20 KB/second (large docs slow to replicate)

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

-- Look for operators:
-- "index_scan" = Good (uses index, fast)
-- "scan" = Bad (full collection scan, slow)
-- "intersect" = Multiple indexes (AND logic)
-- "union" = Multiple indexes (OR logic)
```

**Example Output:**
```json
{
  "plan": {
    "#operator": "sequence",
    "children": [
      {"#operator": "index_scan", "index": "idx_assignee"},  // ✅ Using index
      {"#operator": "fetch"},
      {"#operator": "final_projection"}
    ]
  }
}
```

**vs Bad Plan:**
```json
{
  "plan": {
    "#operator": "sequence",
    "children": [
      {"#operator": "scan", "collection": "tasks"},  // ❌ Full collection scan
      {"#operator": "filter", "condition": "assignee = 'alice'"},
      {"#operator": "final_projection"}
    ]
  }
}
```

### Optimization Strategies

**1. Create Indexes for Frequently Queried Fields**

Contact Ditto team for index creation. Prioritize:
- Fields used in WHERE clauses
- Fields used in ORDER BY
- High cardinality fields (many unique values)

```sql
-- Fields that benefit from indexes:
WHERE assignee = 'alice'        -- Index on 'assignee'
WHERE status = 'active'         -- Index on 'status'
ORDER BY created_at DESC        -- Index on 'created_at'
```

**2. Use EXPLAIN to Verify Index Usage**

```sql
-- Before optimization
EXPLAIN SELECT * FROM tasks WHERE priority > 5
-- Output: {"#operator": "scan", ...}  -- ❌ Full scan

-- After adding index on 'priority'
EXPLAIN SELECT * FROM tasks WHERE priority > 5
-- Output: {"#operator": "index_scan", "index": "idx_priority"}  -- ✅ Using index
```

**3. Combine Filters for Intersect Scans**

When multiple fields are indexed:

```sql
-- Uses intersect scan (combines multiple indexes)
SELECT * FROM tasks
WHERE assignee = 'alice' AND status = 'active'

-- EXPLAIN shows:
-- {"#operator": "intersect", "children": [
--   {"#operator": "index_scan", "index": "idx_assignee"},
--   {"#operator": "index_scan", "index": "idx_status"}
-- ]}
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

-- Identify slow queries and optimize
```

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

Strict mode controls type inference and CRDT type safety in Ditto collections.

**Default State:**
- SDK 4.x: Enabled (strict mode = true)
- SDK 5.0: Disabled (strict mode = false)
- Available: SDK 4.11+

### Behavioral Differences

| Aspect | Strict=true | Strict=false |
|--------|------------|--------------|
| **Objects** | Treated as REGISTER (last-write-wins) | Auto-inferred as MAP (per-field merge) |
| **Nested Updates** | Replace entire object | Merge individual fields |
| **Collection Definitions** | Required for non-REGISTER types | Only needed for explicit REGISTER objects |
| **Counter Visibility** | Must declare COUNTER type | Auto-visible |
| **Legacy Compatibility** | Difficult | Easy |

### Configuration

**Disable Strict Mode (Recommended):**
```sql
-- Apply before starting sync
ALTER SYSTEM SET DQL_STRICT_MODE = false
```

**Enable Strict Mode:**
```sql
ALTER SYSTEM SET DQL_STRICT_MODE = true
```

**Check Current Setting:**
```sql
SHOW DQL_STRICT_MODE
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

### Cross-Peer Compatibility

**⚠️ CRITICAL: All peers should use same strict mode setting**

**Problem:**
When peers use different strict mode settings without explicit MAP definitions:
- Data syncs correctly
- But displays differently on each peer
- Appears as sync issue (but isn't)

**Solutions:**

1. **Match strict mode across all peers:**
   ```sql
   -- All peers run:
   ALTER SYSTEM SET DQL_STRICT_MODE = false
   ```

2. **Explicitly define MAP types (strict=true peers):**
   ```sql
   INSERT INTO users (
     profile MAP(bio STRING, location STRING, city STRING)
   ) DOCUMENTS ({...})
   ```

### When to Use Strict Mode

**Use Strict Mode = true when:**
- Need explicit control over CRDT types
- Want REGISTER (last-write-wins) for objects
- Have well-defined schemas
- Can ensure all peers use same setting

**Use Strict Mode = false when:**
- Want automatic MAP inference (recommended)
- Need per-field merge for nested objects
- Working with legacy data
- Mixed client versions in production

**Recommendation:** Use strict mode = false (will be default in SDK 5.0) for most applications.

---

## Query Safety

### Parameterized Queries (Prevent Injection)

**Always use parameterized queries for user input:**

```sql
-- ✅ SAFE: Parameterized
SELECT * FROM tasks WHERE title = :search
-- Pass arguments: {search: userInput}

-- ❌ UNSAFE: String concatenation (SQL injection risk)
const query = "SELECT * FROM tasks WHERE title = '" + userInput + "'";
```

**Multiple Parameters:**
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
  AND timestamp < '2025-01-01T00:00:00Z'

-- Last 7 days
WHERE created_at >= date_sub(clock(), 7, 'days')

-- Next 24 hours
WHERE expires_at <= date_add(clock(), 24, 'hours')
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

- [ ] Documents < 250 KB (avoid warnings)
- [ ] Documents < 5 MB (hard limit)
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

## Official Documentation

- **Data Modeling:** https://docs.ditto.live/best-practices/data-modeling
- **Schema Versioning:** https://docs.ditto.live/best-practices/schema-versioning
- **Access Paths:** https://docs.ditto.live/dql/access-paths
- **Strict Mode:** https://docs.ditto.live/dql/strict-mode
- **Timestamps:** https://docs.ditto.live/best-practices/timestamps
- **DQL Overview:** https://docs.ditto.live/dql/dql
