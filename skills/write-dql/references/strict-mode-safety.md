# Strict mode safety — Ditto

## Contents

- [Strict Mode](#strict-mode)
- [Overview](#overview)
- [Behavioral Differences](#behavioral-differences)
- [Configuration](#configuration)
- [Example: Object Merge Behavior](#example-object-merge-behavior)
- [Cross-Peer Compatibility](#cross-peer-compatibility)
- [When to Use Strict Mode](#when-to-use-strict-mode)
- [Query Safety](#query-safety)
- [Parameterized Queries (Prevent Injection)](#parameterized-queries-prevent-injection)
- [Always Use ON ID CONFLICT](#always-use-on-id-conflict)
- [Deleting Documents — TTL Awareness](#deleting-documents--ttl-awareness)
- [Soft Delete Pattern](#soft-delete-pattern)

Topic index: [best-practices.md](../best-practices.md). Covers Ditto SDK 4.14.x (LTS),
5.0.x and 5.1.x; version-specific notes remain inline. Read only the topic needed.

For movies/reviews examples, see the [schema](schema.md) only when adapting those examples; other examples define their own fields.

## Strict Mode

### Overview

Strict mode controls CRDT type inference when `INSERT`/`UPDATE` encounters an object literal with no type definition — and controls whether `SELECT` needs type declarations to *see* non-REGISTER fields.

**This guidance assumes `dql_strict_mode = false` (lenient) on every peer** — the 5.x factory default and the migration target for 4.14.x meshes. With strict mode false you do **not** use `MAP`/`REGISTER` keywords on reads or writes: objects infer MAP, and reads return the most recent value of every field whatever its CRDT type.

**Default State:**
- SDK 4.14.x: `dql_strict_mode = true` (legacy default — migrate to `false`) → object → `REGISTER` (last-write-wins on the whole object)
- SDK 5.0.x: `dql_strict_mode = false` → object → `MAP` (per-field merge)
- Available: SDK 4.11+; runtime-only, re-apply at every app start

For the full per-version behavior matrix, the internal `DQL_MUTATOR_OBJECTS_AS_MAPS` flag, and worked merge examples, see [`references/types-mutators.md`](types-mutators.md) §7.

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

The canonical user-facing parameter is `dql_strict_mode`. Parameter names in `ALTER SYSTEM SET` / `RESET` / `SHOW` are **case-insensitive** — the resolver lowercases the identifier, so `SHOW DQL_STRICT_MODE` works — but prefer lowercase: it is the name `SHOW` echoes back and the only spelling that matches a case-sensitive `SHOW ALL LIKE` pattern (use `ILIKE` if you want to match uppercase). See [`references/types-mutators.md`](types-mutators.md) §7 for the full feature-flag model (including the internal `DQL_MUTATOR_OBJECTS_AS_MAPS` flag that strict mode derives).

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

> Dotted path syntax (`profile.bio`, `features.seats`, etc.) is a **path expression** — supported in `SET`, `WHERE`, projections, and `ORDER BY` on all three supported SDK versions. See [`references/expressions.md`](expressions.md) §4 for the full path-expression grammar including array indexing (`tags[0]`) and parameter-driven keys.

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

Note also that `TOMBSTONE` as a DQL statement is rejected on 4.14.6, 5.0.3 and 5.1.0 when run from a Small Peer (`Tombstone is not supported`) — it is Big-Peer-only. From an Edge SDK, use `DELETE` — it writes a replicating tombstone, exactly like `TOMBSTONE` does on a Big Peer, and is not a local-only eviction. See [`references/statements.md`](statements.md) §4–§5 for the full `EVICT`/`TOMBSTONE`/`DELETE` semantics and when each applies.

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
