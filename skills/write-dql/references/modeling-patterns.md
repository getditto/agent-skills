# Modeling patterns — Ditto

## Contents

- [Data Modeling Best Practices](#data-modeling-best-practices)
- [Core Principle](#core-principle)
- [Document Size Limits](#document-size-limits)
- [Embedded vs Flat Models](#embedded-vs-flat-models)
- [Decision Matrix](#decision-matrix)
- [Additional Guidelines](#additional-guidelines)
- [Schema Versioning Best Practices](#schema-versioning-best-practices)
- [Golden Rule](#golden-rule)
- [Why Schema Versioning Matters](#why-schema-versioning-matters)
- [Core Principle](#core-principle-1)
- [Four Primary Strategies](#four-primary-strategies)
- [Implementation Pattern](#implementation-pattern)
- [Multi-Version Support Example](#multi-version-support-example)
- [Schema Versioning Best Practices Summary](#schema-versioning-best-practices-summary)

Topic index: [best-practices.md](../best-practices.md). Covers Ditto SDK 4.14.x (LTS),
5.0.x and 5.1.x; version-specific notes remain inline. Read only the topic needed.

For movies/reviews examples, see the [schema](schema.md) only when adapting those examples; other examples define their own fields.

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
