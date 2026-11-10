# Timestamps — Ditto

## Contents

- [Timestamp Best Practices](#timestamp-best-practices)
- [ISO-8601 Format](#iso-8601-format)
- [Clock Accuracy in Distributed Systems](#clock-accuracy-in-distributed-systems)
- [Network Time Protocol (NTP)](#network-time-protocol-ntp)
- [Common Timestamp Patterns](#common-timestamp-patterns)
- [Key Takeaway](#key-takeaway)

Topic index: [best-practices.md](../best-practices.md). Covers Ditto SDK 4.14.x (LTS),
5.0.x, 5.1.x and 5.2.0; version-specific notes remain inline. Read only the topic needed.

For movies/reviews examples, see the [schema](schema.md) only when adapting those examples; other examples define their own fields.

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
