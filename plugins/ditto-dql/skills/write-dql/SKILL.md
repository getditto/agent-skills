---
name: write-dql
description: Use when writing DQL queries (SELECT, INSERT, UPDATE, DELETE, EVICT) in application code, designing Ditto data models/schemas, optimizing queries with EXPLAIN, working with DQL data types (REGISTER, MAP, COUNTER), or configuring ALTER SYSTEM settings. Official docs at docs.ditto.live/dql/dql.
---

# DQL (Ditto Query Language) Quick Reference

## Context-Efficient Usage

<progressive_disclosure>
Start with this file for quick syntax and common patterns (covers 80% of tasks). Only read specialized files when you need complete operator reference or advanced data modeling guidance.
</progressive_disclosure>

<critical_dql_differences>
DQL is NOT SQL. Critical differences that cause errors:
- Single quotes ONLY for strings (no double quotes)
- Boolean operators: `AND`, `OR`, `NOT` (not `&&`, `||`, `!`)
- Use : for object properties (not =) → {_id: 'value'} not {_id = 'value'}
- No JOINs, no subqueries, no GROUP BY
- COUNTER type uses Integer in most SDKs, not Long
- ON ID CONFLICT required for INSERT statements
</critical_dql_differences>

**Token Budget:**
- SKILL.md: ~450 lines (~11k tokens) - **START HERE** (quick syntax, common patterns, critical warnings)
- dql-operators.md: ~350 lines (~9k tokens) - Read for complete operator/function reference
- best-practices.md: ~300 lines (~8k tokens) - Read for data modeling, optimization, schema versioning
- Total if all read: ~1,100 lines (~28k tokens)

## Decision Tree: When to Read Specialized Files

```
START: Writing DQL query?
│
├─ Need specific operator/function syntax? → Read dql-operators.md
│
├─ Designing data model or schema? → Read best-practices.md
│
├─ Optimizing query performance? → Read best-practices.md
│
├─ Implementing schema versioning? → Read best-practices.md
│
└─ Otherwise → Use Quick Reference below (no additional files needed)
```

---

## Overview

DQL is Ditto's SQL-like query language for document databases in distributed mesh networks.

**Key Characteristics:**
- Document-based (not relational)
- CRDT merge semantics
- Distributed by default (P2P sync)
- Offline-first (eventual consistency)
- No central authority

---

## Statement Syntax Quick Reference

### SELECT - Query Documents
```sql
SELECT [DISTINCT] projection
FROM collection_name
[WHERE condition]
[GROUP BY expression, ...]
[HAVING condition]
[ORDER BY expression [ASC|DESC], ...]
[LIMIT n]
[OFFSET n]
```

**Common Examples:**
```sql
-- All documents
SELECT * FROM tasks

-- With filter
SELECT * FROM tasks WHERE NOT deleted AND done = false

-- Specific fields
SELECT title, done, created_at FROM tasks WHERE assignee = 'alice'

-- Aggregation
SELECT COUNT(*) AS total FROM tasks WHERE NOT deleted

-- Group by
SELECT category, COUNT(*) AS count
FROM products
GROUP BY category
ORDER BY count DESC

-- Pagination
SELECT * FROM tasks ORDER BY created_at DESC LIMIT 20 OFFSET 40
```

### INSERT - Add Documents
```sql
INSERT INTO collection_name
DOCUMENTS (doc1), (doc2), ...
[ON ID CONFLICT [FAIL | DO NOTHING | DO UPDATE | DO UPDATE_LOCAL_DIFF]]
```

**Conflict Resolution:**
- `FAIL` (default) - Error if `_id` exists
- `DO NOTHING` - Skip if exists
- `DO UPDATE` - Update all fields (ensures replication)
- `DO UPDATE_LOCAL_DIFF` (SDK 4.12+) - Update only changed fields (minimizes replication)

**Common Examples:**
```sql
-- Auto-generated ID
INSERT INTO tasks DOCUMENTS ({
  'title': 'Return phone call',
  'done': false
})

-- Specific ID with upsert
INSERT INTO tasks DOCUMENTS ({
  '_id': 'task-001',
  'title': 'Update documentation',
  'done': false
}) ON ID CONFLICT DO UPDATE

-- Batch insert (recommended for efficiency)
INSERT INTO tasks DOCUMENTS
  ({'_id': 'task-010', 'title': 'Tire rotation', 'done': false}),
  ({'_id': 'task-011', 'title': 'Schedule dental cleaning', 'done': false}),
  ({'_id': 'task-012', 'title': 'Change HVAC air filter', 'done': false})
ON ID CONFLICT DO UPDATE_LOCAL_DIFF
```

### UPDATE - Modify Documents
```sql
UPDATE collection_name
SET field1 = value1, field2 = value2, ...
[WHERE condition]
```

**Common Examples:**
```sql
-- Single field
UPDATE tasks SET done = true WHERE _id = 'task-001'

-- Multiple fields
UPDATE users SET
  last_login = '2024-12-22T15:30:00Z',
  login_count = login_count + 1
WHERE _id = 'user-123'

-- Nested field (SDK 4.11+ with strict mode off)
UPDATE cars SET features.sunroof = true WHERE make = 'Tesla'

-- Remove field (SDK 4.11+)
UPDATE tasks UNSET archived_at WHERE _id = 'task-001'

-- Counter increment
UPDATE analytics SET views INCREMENT BY 1 WHERE page = 'home'

-- Counter decrement (negative value)
UPDATE analytics SET visits INCREMENT BY -5 WHERE page = 'about'

-- Set counter value
UPDATE metrics SET counter RESTART WITH 100 WHERE _id = 'metric-1'
```

### DELETE - Permanently Remove
```sql
DELETE FROM collection_name
[WHERE condition]
[ORDER BY expression]
[LIMIT n]
```

**⚠️ CRITICAL: DELETE is permanent (cannot be recovered)**

**TTL Windows:** 7 days (Edge SDK), 30 days (Cloud)

**Common Examples:**
```sql
-- Delete by ID
DELETE FROM tasks WHERE _id = 'task-001'

-- Delete by condition
DELETE FROM logs WHERE created_at < '2024-01-01T00:00:00Z'

-- Delete with limit (safe cleanup)
DELETE FROM old_data ORDER BY created_at ASC LIMIT 100
```

### EVICT - Remove from Local Storage
```sql
EVICT FROM collection_name
[WHERE condition]
[ORDER BY expression]
[LIMIT n]
```

**⚠️ EVICT is local-only: Data reappears if it exists in connected peers**

**Common Examples:**
```sql
-- Evict soft-deleted
EVICT FROM tasks WHERE deleted = true

-- Free storage
EVICT FROM attachments WHERE downloaded = true AND viewed = true
```

### EXPLAIN - Show Query Plan
```sql
EXPLAIN [DQL_STATEMENT]
```

**Look for in output:**
- `index_scan` = Good (uses index, fast)
- `scan` = Bad (full collection scan, slow)
- `intersect` = Multiple indexes (AND)
- `union` = Multiple indexes (OR)

**Example:**
```sql
EXPLAIN SELECT * FROM tasks WHERE assignee = 'alice'
-- Look for "index_scan" vs "scan" in result
```

### ALTER SYSTEM - Configure Settings
```sql
-- Show settings
SHOW ALL
SHOW <setting_name>

-- Modify
ALTER SYSTEM SET <setting> = <value>

-- Reset
ALTER SYSTEM RESET <setting>
```

**⚠️ CRITICAL: Settings are memory-only (not persisted). Apply immediately after opening instance, before sync.**

---

## Data Types Quick Reference

| Type           | Merge              | SDK   | Use Case                        |
| -------------- | ------------------ | ----- | ------------------------------- |
| **REGISTER**   | Last-write-wins    | All   | Default; scalars and objects    |
| **MAP**        | Add-wins per-field | All   | Nested objects with field merge |
| **ATTACHMENT** | Last-write-wins    | All   | Binary files (>250KB)           |
| **COUNTER**    | Inc/dec + set      | 4.13+ | Counters with explicit set      |
| **PN_COUNTER** | Inc/dec only       | 4.11+ | Legacy counters                 |

**Default:** All fields are REGISTER unless explicitly declared.

**Type Declaration:**
```sql
INSERT INTO collection (
  field1 STRING,
  field2 INTEGER,
  nested MAP(sub1 STRING, sub2 INTEGER),
  count COUNTER
) DOCUMENTS ({...})
```

---

## Strict Mode Quick Reference

Controls type inference and validation.

| Aspect                | Strict=true (4.x default) | Strict=false (5.0 default) |
| --------------------- | ------------------------- | -------------------------- |
| **Objects**           | REGISTER                  | Auto-inferred as MAP       |
| **Nested Updates**    | Replace entire            | Merge fields               |
| **Type Declarations** | Required                  | Optional                   |

**Configure (before sync):**
```sql
ALTER SYSTEM SET DQL_STRICT_MODE = false  -- Recommended
```

**⚠️ All peers should use same strict mode, or explicitly define MAP types**

---

## Common Operators

### Comparison
```sql
WHERE status = 'active'     -- Equality
WHERE count != 0            -- Inequality
WHERE price < 100           -- Less than
WHERE age >= 18             -- Greater than or equal
```

### Logical
**Use `AND`, `OR`, `NOT` keywords (not `&&`, `||`, `!`)**
```sql
WHERE active AND verified
WHERE priority = 'high' OR priority = 'urgent'
WHERE NOT deleted
```

### NULL and MISSING
```sql
WHERE field IS NULL         -- Field exists with NULL value
WHERE field IS NOT NULL
WHERE field IS MISSING      -- Field doesn't exist
WHERE field IS NOT MISSING
```

### String
```sql
WHERE contains(title, 'urgent')
WHERE starts_with(email, 'admin')
WHERE ends_with(filename, '.pdf')
WHERE name LIKE 'John%'     -- Case-sensitive
WHERE name ILIKE 'john%'    -- Case-insensitive
```

### Array
```sql
WHERE array_contains(tags, 'important')
WHERE status IN ('active', 'pending')
```

**For complete operator reference:** Read `dql-operators.md`

---

## Common Patterns

### Soft Delete
```sql
-- Mark as deleted
UPDATE tasks SET deleted = true WHERE _id = :id

-- Query active
SELECT * FROM tasks WHERE NOT deleted OR deleted IS MISSING

-- Clean up
EVICT FROM tasks WHERE deleted = true
```

### Pagination
```sql
-- Page 1
SELECT * FROM tasks ORDER BY created_at DESC LIMIT 20 OFFSET 0

-- Page 2
SELECT * FROM tasks ORDER BY created_at DESC LIMIT 20 OFFSET 20
```

### Audit Trail
```sql
UPDATE documents SET
  updated_at = clock(),
  updated_by = :user_id,
  version = version + 1
WHERE _id = :id
```

### Foreign Key
```sql
-- Parent
INSERT INTO users DOCUMENTS ({'_id': 'user-1', 'name': 'Alice'})

-- Child with reference
INSERT INTO orders DOCUMENTS ({
  '_id': 'order-1',
  'user_id': 'user-1',  -- Foreign key (immutable _id)
  'total': 99.99
})

-- Query (separate queries, no JOIN)
SELECT * FROM users WHERE _id = 'user-1'
SELECT * FROM orders WHERE user_id = 'user-1'
```

### Counter
```sql
-- Initialize
INSERT INTO analytics DOCUMENTS ({'_id': 'page-home', 'views': 0})

-- Increment (concurrent-safe)
UPDATE analytics SET views INCREMENT BY 1 WHERE _id = 'page-home'

-- Get value
SELECT views FROM analytics WHERE _id = 'page-home'
```

---

## Critical Warnings

### ⚠️ Boolean Operators
**Use `AND`, `OR`, `NOT` keywords (not `&&`, `||`, `!`)**
```sql
WHERE active AND done     -- ✅ CORRECT
WHERE active && done      -- ❌ SYNTAX ERROR
WHERE NOT deleted         -- ✅ CORRECT
WHERE !deleted            -- ❌ SYNTAX ERROR
```

### ⚠️ String Literals
**Use SINGLE quotes only (double quotes NOT supported)**
```sql
WHERE color = 'blue'   -- ✅ CORRECT
WHERE color = "blue"   -- ❌ SYNTAX ERROR
```

### ⚠️ DELETE is Permanent
**Cannot be recovered once deleted**
- TTL: 7 days (Edge SDK), 30 days (Cloud)
- Offline devices may reintroduce after TTL

### ⚠️ EVICT is Local-Only
**Data reappears if exists in connected peers**
- Use for freeing local storage
- Not for permanent deletion

### ⚠️ NULL Comparisons
**NULL compared with anything returns NULL (not false)**
```sql
WHERE field IS NULL      -- ✅ CORRECT
WHERE field = NULL       -- ❌ WRONG (returns NULL)
```

### ⚠️ ALTER SYSTEM Settings
**Memory-only (not persisted to disk)**
- Must re-apply after each restart
- Apply immediately after open, before sync

### ⚠️ Large Documents
**Documents > 5 MB don't sync**
- Documents > 250 KB trigger warnings
- Use flat models and ATTACHMENT type

### ⚠️ Schema Versioning
**NEVER change the type of an existing field**
```sql
-- ❌ BREAKS OLD VERSIONS
-- Old: 'year': 2024 (INTEGER)
-- New: 'year': '2024' (STRING)
```

### ⚠️ Strict Mode Cross-Peer
**All peers should use same strict mode**
- Mismatched settings cause display issues
- Data syncs correctly but displays differently

---

## Quick Best Practices

### Query Safety
1. **Use parameterized queries** - Prevents injection
   ```sql
   SELECT * FROM tasks WHERE title = :search  -- ✅ SAFE
   ```

2. **Always use ON ID CONFLICT** - For upserts
   ```sql
   INSERT INTO tasks DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE
   ```

3. **Handle NULL explicitly** - Use IS NULL, not = NULL

### Performance
4. **Use EXPLAIN** - Verify query uses indexes
   ```sql
   EXPLAIN SELECT * FROM tasks WHERE assignee = 'alice'
   -- Look for "index_scan" not "scan"
   ```

5. **Avoid DISTINCT** - Buffers all results in memory

6. **Use LIMIT** - Reduce data transfer
   ```sql
   SELECT * FROM tasks LIMIT 100
   ```

### Data Modeling
7. **Avoid large embedded objects** - Use flat models
8. **Use ATTACHMENT for files > 250 KB**
9. **Always include schema_version field**

### Schema Evolution
10. **Never change field types** - Add new fields instead
11. **Never remove fields** - Mark deprecated
12. **Add fields with defaults** - Ensures compatibility

**For detailed best practices:** Read `best-practices.md`

---

## System Collections

```sql
SELECT * FROM system:collections      -- All collections
SELECT * FROM system:vitals           -- Query performance
SELECT * FROM system:active_requests  -- Running queries
SELECT * FROM __presence              -- Peer connectivity
```

---

## Reserved Keywords (200+)

SELECT, INSERT, UPDATE, DELETE, WHERE, FROM, JOIN, CASE, CAST, COUNT, DISTINCT, GROUP, HAVING, LIMIT, ORDER, TRUE, FALSE, NULL, STRING, INTEGER, BOOLEAN, MAP, REGISTER, COUNTER, etc.

---

## Timestamps

**Use ISO-8601 format:**
```sql
-- Date
WHERE created_at >= '2024-01-01'

-- DateTime with timezone
WHERE updated_at >= '2024-12-22T15:30:00Z'
```

**Clock Accuracy:**
- iOS: ±100ms
- Android: Several seconds

**For critical timing:** Implement NTP (Network Time Protocol)

---

## Path Expressions

Navigate nested fields:
```sql
-- Access nested
SELECT features.seats FROM cars

-- Update nested
UPDATE cars SET features.color = 'red' WHERE _id = 'car-1'

-- Filter on nested
SELECT * FROM users WHERE profile.location = 'NYC'
```

---

## Official Documentation Links

- **DQL Overview:** https://docs.ditto.live/dql/dql
- **SELECT:** https://docs.ditto.live/dql/select
- **INSERT:** https://docs.ditto.live/dql/insert
- **UPDATE:** https://docs.ditto.live/dql/update
- **DELETE:** https://docs.ditto.live/dql/delete
- **EVICT:** https://docs.ditto.live/dql/evict
- **EXPLAIN:** https://docs.ditto.live/dql/explain
- **Data Types:** https://docs.ditto.live/dql/types-and-definitions
- **Operators:** https://docs.ditto.live/dql/operator-expressions
- **Best Practices:** https://docs.ditto.live/best-practices/
