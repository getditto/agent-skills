# Data Modeling Best Practices

**Read this file when:** choosing embed-vs-split, designing `_id`s, modeling status/history, deletions, or evolving a live schema. For the per-field CRDT choice see [`references/crdt-types.md`](references/crdt-types.md); for running the intake + review process see [`references/workflow.md`](references/workflow.md).

---

## The default pattern

**Denormalize related data into a single document, with sub-entities stored as MAPs keyed by ID.**

```sql
INSERT INTO orders
DOCUMENTS ({
  '_id': 'order-42',
  'customer': { 'name': 'Ada Lovelace', 'tier': 'gold' },   -- infers MAP
  'items': {                                                -- infers MAP; each entry infers MAP
    'sku-100': { 'name': 'Widget',  'qty': 2, 'price_cents': 1999 },
    'sku-205': { 'name': 'Gadget',  'qty': 1, 'price_cents':  499 }
  }
});
```

No `MAP`/`REGISTER` keywords anywhere: under the assumed lenient baseline (`dql_strict_mode = false`) bare objects infer MAP at any depth, on writes **and** reads. Keywords remain only for overrides (`REGISTER` on an atomic object) and types inference can't guess (`COUNTER`, `ATTACHMENT`).

Why this is the default: one write is atomic, the doc syncs as a unit over delta sync, and add-wins maps merge concurrent edits to *different* items cleanly at any nesting depth — there is no extra CRDT cost for nesting a MAP.

## When to split into a separate collection

Split (one document per sub-entity, parent `_id` as back-reference) when **any** of these fire:

1. **Unbounded growth** — messages, readings, comments, event history. Embedded unbounded structures are the #1 modeling bug.
2. **Document size pressure** — would cross the 256 KiB soft limit ([`references/performance.md`](references/performance.md)).
3. **Independent permission scope** — Big Peer sync permissions are query-level; different access rules = collection boundary.
4. **Independent access at scale** — the sub-entity is read or written constantly without the parent ever being touched.

Reads across split collections: **5.1+** `JOIN` (right-side key must be `_id` or indexed); **4.14.x** no joins — fetch both collections in app code, or denormalize the read-time fields.

## Patterns

### Audit log (status history overwrites the old value)

```sql
-- status_log infers MAP under the lenient default; keyed by ISO-8601 timestamp, add-wins keeps every transition
INSERT INTO orders
DOCUMENTS ({ '_id': 'order-77', 'status': 'placed', 'status_log': { '2026-08-25T10:30:45.891Z': 'placed' } });

UPDATE orders
SET status = 'shipped',
    status_log.`2026-08-26T09:12:03.112Z` = 'shipped'
WHERE _id = 'order-77';
```

Derive current state at read time (latest timestamp). Timestamps from different devices can collide/skew — key with high-resolution ISO-8601 and tolerate ranges, never exact-equality lookups.

### Inventory / votes / views (accumulating numbers)

Always `COUNTER` (4.14+), declared on the statement, mutated with `APPLY … INCREMENT BY`. Model money/counts as integers (cents, units). If thousands of distinct devices write one counter, shard it (per-store, per-day buckets summed at read). See [`references/performance.md`](references/performance.md).

### Single-writer arrays are allowed

Arrays are acceptable when **exactly one device writes** and others only read: precomputed rankings, denormalized "top 3" summaries, fixed option lists. State the single-writer constraint in a comment next to the model, because nothing in the engine enforces it.

### Smart upserts from external APIs

When re-syncing server data into Ditto, `DO UPDATE` replicates every field you pass even if unchanged; `DO UPDATE_LOCAL_DIFF` (4.12+) diffs and writes only what changed:

```sql
INSERT INTO products
DOCUMENTS (:doc)
ON ID CONFLICT DO UPDATE_LOCAL_DIFF;
```

### Soft delete with TTL awareness

Tombstones from hard deletes expire: **7 days on Small Peers, 30 days on Big Peer**. A peer offline longer than that can resurrect a deleted document. When resurrection is unacceptable, soft delete and purge once safely past the window:

```sql
UPDATE tasks SET deleted = true, deleted_at = clock() WHERE _id = :id;
SELECT * FROM tasks WHERE NOT coalesce(deleted, false);
```

### `_id` design

- `_id` is **immutable** and never a CRDT field (no type declaration, no `SET _id`).
- Any JSON type except floats is allowed (floats are rejected anywhere in the value), including **composite objects**: `{ '_id': { 'region': 'us-1', 'store': 42, 'orderId': 'abc' } }` — permission rules can query `_id` subfields, making composite IDs an elegant partition key.
- Pick natural keys where they are truly stable; otherwise UUIDs.
- Serialized `_id` is limited to 256 bytes; map keys inside composite IDs must be strings.

## Anti-patterns

| Anti-pattern | Why it hurts | Do instead |
|---|---|---|
| Embedding an ever-growing array (messages, log lines) in a doc | array = whole-value LWW; concurrent appends silently lost; doc eventually hits hard limit | one doc per item in a child collection |
| `SET views = views + 1` on a REGISTER | one increment silently wins on merge | `COUNTER` + `APPLY … INCREMENT BY` |
| Flipping `dql_strict_mode` ad hoc, per peer — or leaving 4.x peers at the strict `true` default | mismatched peers store and read the same field differently — strict peers silently drop undeclared MAP/COUNTER fields from query results entirely | `false` everywhere: the 5.x default, and the 4.x migration target (mesh-wide, before upgrading to v5) |
| base64 image inline in a document | blows the size budget; every edit re-syncs the blob's register | `ATTACHMENT`, lazy fetch |
| JSON-string-encoding a sub-object into one field "to keep it simple" | unqueryable, unindexable, unmergeable | real MAP |
| Watching the whole collection with a live observer | observers re-emit the full result set per change; held state is substantially larger than the raw bytes (directionally an order of magnitude) | narrow observer + LIMIT |
| Changing a field's type in a schema migration | breaks old app versions in the mesh | add a new field; keep the old one |
| Packing scalars into fewer fields "to reduce CRDT overhead" | per-field metadata is bytes; you lose merge granularity for nothing | keep fine-grained fields; MAPs are cheap |

## Schema evolution (short version)

The golden rule in a live mesh: **never change a field's type, never remove a field** — add new fields (with defaults), bump a `schema_version` discriminator, and keep old app versions reading cleanly. The full treatment (backward/forward compatibility strategies, migration statements, version-window queries) is in the `write-dql` skill's [`../dql/best-practices.md`](../dql/best-practices.md) — same rules, this skill doesn't repeat them.

## Strict mode: the mesh discipline

**`dql_strict_mode = false` on every peer is the assumed baseline** — the 5.x default, and the state every 4.14.x mesh migrates to. In this world you write no `MAP`/`REGISTER` keywords on reads or writes: objects infer MAP (duck-typed from the JSON), and reads return the most recent value of any type. If 4.14.x and 5.x peers share a mesh:

1. **Flip the 4.x peers to `false` as the first step of the upgrade**, not after — behavior then stays identical across the version jump. The flag is runtime-only: set it at every app start, before sync and queries.
2. **Never set the flag to `true` on 5.x**, and never flip peers ad hoc — mismatched peers store and read the same field differently, and strict peers silently drop undeclared MAP/COUNTER fields from results.
3. While any strict 4.x peer remains, declare MAP/COUNTER explicitly on the statements that peer executes — writes *and* reads — and model reads to the 4.14 surface (no JOIN-dependent screens).
4. Keywords that survive the lenient world: `COUNTER` and `ATTACHMENT` declarations (inference can't infer them) and deliberate `REGISTER` overrides on atomic objects. Prefer `COUNTER` to `PN_COUNTER` for anything new. Full matrix: [`references/versions.md`](references/versions.md).
