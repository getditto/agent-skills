# Query performance — Ditto

## Contents

- [Query Optimization](#query-optimization)
- [Access Paths Overview](#access-paths-overview)
- [Using EXPLAIN](#using-explain)
- [Optimization Strategies](#optimization-strategies)
- [Performance Tips](#performance-tips)
- [Performance Checklist](#performance-checklist)
- [Before Query Execution](#before-query-execution)
- [After Query Execution](#after-query-execution)
- [Data Modeling](#data-modeling)
- [Schema Changes](#schema-changes)

Topic index: [best-practices.md](../best-practices.md). Covers Ditto SDK 4.14.x (LTS),
5.0.x and 5.1.x; version-specific notes remain inline. Read only the topic needed.

For movies/reviews examples, see the [schema](schema.md) only when adapting those examples; other examples define their own fields.

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

> Operator names and JSON shape are diagnostic, not a stable contract — see [`references/indexing.md`](indexing.md) §6 for the canonical operator catalog and worked example plans. Older SDKs and some tools render lowercase variants (e.g. `index_scan`); read shape, not exact spelling.

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

For full `CREATE INDEX` grammar, covering plans, planner directives (`#profile`, `#disable_index_scan`, etc.), `EXPLAIN` output shape, and the `USE IDS` fast path, see [`references/indexing.md`](indexing.md).

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

See [`references/select.md`](select.md) for the FROM-clause grammar that accepts these datasources.

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

For full `SELECT` clause grammar — `WHERE`, `ORDER BY`, `LIMIT`/`OFFSET`, `GROUP BY`/`HAVING`, subqueries, `USE IDS`, and system datasources — see [`references/select.md`](select.md). System datasources like `system:collections`, `system:vitals`, and `system:active_requests` are documented there (§ on FROM clauses).

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
