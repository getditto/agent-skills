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

Tombstones from hard deletes expire: **7 days on Small Peers, 30 days on Big Peer — defaults, both tunable** (`TOMBSTONE_TTL_HOURS` via `ALTER SYSTEM` on a peer; Big Peer only via Ditto support, and never set the peer's above the server's). A peer offline longer than the window can resurrect a deleted document. When resurrection is unacceptable, soft delete and purge once safely past the window:

```sql
UPDATE tasks SET deleted = true, deleted_at = clock() WHERE _id = :id;
SELECT * FROM tasks WHERE NOT coalesce(deleted, false);
```

### `_id` design — default to a composite object

**Ditto's permission system can only see `_id`.** Sync permissions and Big Peer / auth-webhook rules are queries over it and nothing else in the document. Anything you will ever scope access by therefore has to live *in* the `_id` — and `_id` is immutable, so this is a design-time decision, not something to retrofit.

```sql
INSERT INTO orders
DOCUMENTS ({
  '_id':    { 'store_id': 42, 'order_id': 'order-2026-00042' },
  'status': 'placed'
});

SELECT * FROM orders WHERE _id.store_id = 42;              -- permissions can express this
CREATE INDEX IF NOT EXISTS idx_orders_store ON orders (_id.store_id);
```

- **Object `_id`s over string `_id`s** whenever a scoping value exists (store, site, tenant, region, org). Subfields are queryable (`_id.store_id`), indexable, and readable in the portal and HTTP API. Verified on 4.14.4, 5.0.3, and 5.1.0.
- **Don't copy the `_id` subfields into the body.** They are ordinary queryable, indexable paths — predicates, single and composite indexes, and JOIN keys all work against `_id.<field>` directly. A body copy adds per-field CRDT metadata to every document and gives you two values that can disagree. (A *child's back-reference* to its parent is a different thing and is fine — see the split pattern above.)
- **Composite *string* `_id`s (`'store42:order-77'`) are an anti-pattern** — a relational composite key flattened for a system that only took strings. Ditto has no such limit. Delimiter-joined keys break when a component contains the delimiter, need parsing at every read, can't be indexed per-component, and are invisible to permissions. Use the object.
- `_id` is **immutable** and never a CRDT field (no type declaration, no `SET _id`).
- Any JSON type except floats (floats are rejected anywhere inside an `_id`). Map keys inside a composite `_id` must be strings, and the serialized `_id` is capped at 256 bytes — carry the scope keys, not the document.
- Pick natural keys where they are truly stable; otherwise UUIDs for the non-scoping component.

Full rule, including when to flag it in a review: [`references/workflow.md`](references/workflow.md) §2 `COMPOSITE_ID`.

## Anti-patterns

| Anti-pattern | Why it hurts | Do instead |
|---|---|---|
| Embedding an ever-growing array (messages, log lines) in a doc | array = whole-value LWW; concurrent appends silently lost; doc eventually hits hard limit | one doc per item in a child collection |
| `SET views = views + 1` on a REGISTER | one increment silently wins on merge | `COUNTER` + `APPLY … INCREMENT BY` |
| Flipping `dql_strict_mode` ad hoc, per peer — or leaving 4.x peers at the strict `true` default | mismatched peers store and read the same field differently — strict peers silently drop undeclared MAP/COUNTER fields from query results entirely | `false` everywhere: the 5.x default, and the 4.x migration target (mesh-wide, before upgrading to v5) |
| Flipping the SDK peers to lenient but leaving backends on the Big Peer's `/api/v4/store/execute` | the v4 HTTP endpoint **is** a strict peer — it keeps writing bare objects as whole-object REGISTERs into collections your devices merge per-field, and no `ALTER SYSTEM` on a device can fix it | migrate HTTP callers to `/api/v5/store/execute` in the *same* coordinated change ([`references/versions.md`](references/versions.md)) |
| base64 image inline in a document | blows the size budget; every edit re-syncs the blob's register | `ATTACHMENT`, lazy fetch — **except behind the MongoDB Connector**, see below |
| JSON-string-encoding a sub-object into one field "to keep it simple" | unqueryable, unindexable, unmergeable | real MAP |
| Watching the whole collection with a live observer | observers re-emit the full result set per change; held state is substantially larger than the raw bytes (directionally an order of magnitude) | narrow observer + LIMIT |
| Changing a field's type in a schema migration | breaks old app versions in the mesh | add a new field; keep the old one |
| Packing scalars into fewer fields "to reduce CRDT overhead" | per-field metadata is bytes; you lose merge granularity for nothing | keep fine-grained fields; MAPs are cheap |

## Attachments — and the one place base64 is still the answer

The default is unambiguous: binaries go to `ATTACHMENT`. Blob bytes live outside the document and outside the size limits, only a small token counts against them, and the blob syncs over its own chunked protocol so a photo doesn't block the document it belongs to.

**Caveat — the MongoDB Connector does not carry attachments.** The connector maps BSON to Ditto JSON fields; the blob store is a separate mechanism it isn't aware of. If a collection is synced to MongoDB and MongoDB is the system of record for that image, an attachment token will arrive there as an opaque value with no bytes behind it. **Today, inline base64 in the document is the recommended approach for images on connector-synced collections** — the alternative (an external object store plus a URL field) usually isn't available in the offline-first deployments that pick Ditto in the first place.

That recommendation costs you the entire size budget, so treat it as a constraint to model around, not a free pass:

- **Keep the base64 field in its own document**, referenced by ID from the entity — not inline in the hot document. Every edit to a document re-serializes and re-merges *all* of it ([`references/performance.md`](references/performance.md)), and a REGISTER'd base64 string re-syncs whole on any change to it.
- **Size the image to the budget, not the camera.** Base64 adds ~33%; the 256 KiB soft limit means roughly a 190 KB source file per document, and less once metadata is counted. Downscale and re-compress before encoding.
- **Never put one over BLE without measuring.** At ~20 KB/s a 250 KiB document is 10+ seconds of airtime that everything else queues behind.
- **Split the collections if you can.** Only the collections the connector actually syncs are constrained; anything Ditto-only can still use `ATTACHMENT` normally. A connector-synced `products` collection carrying base64 thumbnails and a Ditto-only `product_media` collection using attachments for the full-resolution assets is a reasonable split.

If the images don't need to be in MongoDB at all, keep them as attachments and don't include that field in the connector's collection mapping.

## Schema evolution (short version)

The golden rule in a live mesh: **never change a field's type, never remove a field** — add new fields (with defaults), bump a `schema_version` discriminator, and keep old app versions reading cleanly. The full treatment (backward/forward compatibility strategies, migration statements, version-window queries) is in the `write-dql` skill's [`../dql/best-practices.md`](../dql/best-practices.md) — same rules, this skill doesn't repeat them.

## Strict mode: the mesh discipline

**`dql_strict_mode = false` on every peer is the assumed baseline** — the 5.x default, and the state every 4.14.x mesh migrates to. In this world you write no `MAP`/`REGISTER` keywords on reads or writes: objects infer MAP (duck-typed from the JSON), and reads return the most recent value of any type. Getting a mesh there — whether it mixes 4.14.x and 5.x SDK peers, or is all-5.x with a backend on the HTTP API:

1. **Flip the 4.x peers to `false` as the first step of the upgrade**, not after — behavior then stays identical across the version jump. The flag is runtime-only: set it at every app start, before sync and queries.
2. **Never set the flag to `true` on 5.x**, and never flip peers ad hoc — mismatched peers store and read the same field differently, and strict peers silently drop undeclared MAP/COUNTER fields from results.
3. **Migrate every Big Peer HTTP caller from `/api/v4/store/execute` to `/api/v5/store/execute` in the same change.** This is the step people miss. Strict mode is per-peer, and the HTTP Data API's *endpoint version is its strict-mode setting* — v4 behaves exactly like a strict 4.14.x peer (bare objects written as whole-object REGISTERs; undeclared MAP/COUNTER fields silently missing from responses), v5 exactly like a lenient 5.x peer. No `ALTER SYSTEM` anywhere fixes a v4 caller. Flipping every device to lenient while a backend service, webhook, or script still POSTs to v4 leaves a strict writer in the mesh — and it's usually the writer touching the most documents. Inventory the callers first; any that can't move yet must declare MAP/COUNTER on every statement they send until they do.
4. While any strict 4.x peer remains, declare MAP/COUNTER explicitly on the statements that peer executes — writes *and* reads — and model reads to the 4.14 surface (no JOIN-dependent screens).
5. Keywords that survive the lenient world: `COUNTER` and `ATTACHMENT` declarations (inference can't infer them) and deliberate `REGISTER` overrides on atomic objects. Prefer `COUNTER` to `PN_COUNTER` for anything new. Full matrix: [`references/versions.md`](references/versions.md).
