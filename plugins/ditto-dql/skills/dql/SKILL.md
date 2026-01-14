---
name: ditto-dql
description: Use this skill when writing DQL (Ditto Query Language) queries, working with Ditto database operations, creating subscriptions, or troubleshooting Ditto query syntax. Triggers on mentions of DQL, Ditto queries, Ditto database, or Ditto sync operations.
allowed-tools: Read, Grep, Glob, Edit, Write
---

# Ditto Query Language (DQL)

DQL is a SQL-like query language for the Ditto platform. Ditto is an offline-first, peer-to-peer sync database using CRDTs for automatic conflict resolution.

## SELECT

```sql
SELECT [DISTINCT] * | field1, field2 | aggregate(field) [AS alias]
FROM collection_name
[WHERE condition]
[GROUP BY expr1, expr2, ...]
[HAVING condition]
[ORDER BY expr1 [ASC|DESC], ...]
[LIMIT value]
[OFFSET skip_count]
```

### Examples

```sql
-- All documents
SELECT * FROM tasks

-- Specific fields
SELECT title, completed FROM tasks

-- Filtering
SELECT * FROM tasks WHERE completed = false AND priority > 3

-- Sorting and limiting
SELECT * FROM tasks ORDER BY createdAt DESC LIMIT 10

-- Aggregations
SELECT status, COUNT(*) AS total FROM tasks GROUP BY status

-- Nested field access
SELECT user.name, user.email FROM profiles WHERE user.active = true
```

### Operators
- Comparison: `=`, `!=`, `<`, `>`, `<=`, `>=`
- Logical: `AND`, `OR`, `NOT`
- Null check: `IS NULL`, `IS NOT NULL`
- Pattern: `LIKE` (use `%` wildcard)
- Range: `BETWEEN`
- List: `IN`

### Aggregate Functions
`COUNT(*)`, `SUM(field)`, `AVG(field)`, `MIN(field)`, `MAX(field)`

## INSERT

```sql
INSERT INTO collection_name
DOCUMENTS ({doc1}), ({doc2}), ...
[ON ID CONFLICT DO NOTHING | DO UPDATE]
```

### Examples

```sql
-- Single document (auto-generated _id)
INSERT INTO tasks DOCUMENTS ({ 'title': 'Buy groceries', 'completed': false })

-- With explicit _id
INSERT INTO tasks DOCUMENTS ({ '_id': 'task-123', 'title': 'Review PR' })

-- Multiple documents
INSERT INTO tasks DOCUMENTS
  ({ 'title': 'Task 1' }),
  ({ 'title': 'Task 2' })

-- Upsert (update if exists)
INSERT INTO tasks
DOCUMENTS ({ '_id': 'task-123', 'title': 'Updated title' })
ON ID CONFLICT DO UPDATE
```

### Conflict Handling
- `ON ID CONFLICT FAIL` - Error if _id exists (default)
- `ON ID CONFLICT DO NOTHING` - Skip if _id exists
- `ON ID CONFLICT DO UPDATE` - Update existing document

## UPDATE

```sql
UPDATE collection_name
SET field1 = value1, field2 = value2, ...
WHERE condition
```

### Examples

```sql
-- Single field
UPDATE tasks SET completed = true WHERE _id = 'task-123'

-- Multiple fields
UPDATE tasks SET completed = true, completedAt = '2024-01-15' WHERE _id = 'task-123'

-- Nested fields (v4.11+)
UPDATE users SET profile.theme = 'dark' WHERE _id = 'user-1'

-- Bulk update
UPDATE tasks SET priority = 1 WHERE category = 'urgent'
```

### UNSET (Delete Field)
```sql
-- Remove a field (v4.11+)
UPDATE tasks UNSET dueDate WHERE _id = 'task-123'
```

## DELETE vs EVICT

```sql
-- DELETE: Permanently removes documents across all peers
DELETE FROM collection_name WHERE condition

-- EVICT: Removes locally only, other peers keep the data
EVICT FROM collection_name WHERE condition
```

### Examples

```sql
-- Permanent deletion
DELETE FROM tasks WHERE completed = true AND completedAt < '2023-01-01'

-- Local eviction (free up space)
EVICT FROM logs WHERE createdAt < '2024-01-01'
```

## Data Types

### REGISTER
Single values with last-write-wins conflict resolution:
```sql
INSERT INTO items DOCUMENTS ({ 'name': 'Widget', 'price': 29.99 })
```

### MAP
Nested key-value structures:
```sql
INSERT INTO users DOCUMENTS ({
  '_id': 'user-1',
  'profile': {
    'name': 'Alice',
    'settings': { 'theme': 'dark', 'notifications': true }
  }
})
```

### ATTACHMENT
Binary data (images, files) stored separately:
```sql
-- Attachments are typically handled via SDK, not raw DQL
-- Query attachment metadata:
SELECT _id, attachment.name, attachment.size FROM files
```

## Subscriptions

Subscriptions declare which data a device should receive from the mesh:

```sql
-- Subscribe to all incomplete tasks
SELECT * FROM tasks WHERE completed = false

-- Subscribe to user's own data
SELECT * FROM tasks WHERE ownerId = :currentUserId
```

Subscription queries use the same SELECT syntax. The Ditto SDK handles subscription lifecycle.

## Best Practices

1. **Use specific queries** - Avoid `SELECT *` in subscriptions; sync only needed data
2. **Index-friendly filters** - Filter on `_id` or indexed fields when possible
3. **Limit result sets** - Use `LIMIT` for large collections
4. **Prefer EVICT over DELETE** - Use EVICT for local cleanup without affecting peers
5. **Batch inserts** - Insert multiple documents in one statement
6. **Use explicit _id** - Provide meaningful IDs rather than auto-generated ones

## Common Patterns

### Pagination
```sql
SELECT * FROM items ORDER BY createdAt DESC LIMIT 20 OFFSET 40
```

### Soft Delete
```sql
UPDATE tasks SET deleted = true, deletedAt = '2024-01-15' WHERE _id = 'task-123'
-- Query non-deleted:
SELECT * FROM tasks WHERE deleted IS NULL OR deleted = false
```

### Optimistic Locking
```sql
UPDATE items SET value = 'new', version = 2 WHERE _id = 'item-1' AND version = 1
```
