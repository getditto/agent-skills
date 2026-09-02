---
title: Data-modeling workflow — intake, JSON review rubric, output format
description: The expert process for reviewing or designing a Ditto data model. Intake questions, per-field rubric with finding IDs used by the test harness, and the recommendation output contract.
---

# Data-modeling workflow

Three phases. Phase 1 gathers context, phase 2 walks the user's JSON with the rubric, phase 3 produces the deliverable. The finding IDs in §2 (`ARRAY_LWW`, `COUNTER_CANDIDATE`, …) are stable identifiers — use them verbatim in findings so reviews are comparable (positive confirmations and free-form hygiene notes are fine alongside them; only rubric findings need IDs).

## §1 Intake — ask before designing

Ask whatever the user hasn't already provided, in one concise batch. Don't block on hallway answers to all nine — items 1–2 are mandatory; the rest can be inferred from the JSON with explicitly stated assumptions.

| # | Question | Why it changes the model |
|---|---|---|
| 1 | Which Ditto SDK version(s)? (4.14.x / 5.0.x / 5.1.x / mixed mesh) — and on 4.x, has `dql_strict_mode` been migrated to `false` yet? | Lenient mode is the assumed baseline (objects infer MAP; no type declarations on reads or writes); un-flipped 4.x strict peers get the migration playbook plus transition declarations; JOINs and composite indexes are 5.1+; `COUNTER` needs 4.14+ |
| 2 | Who edits which parts, and can edits be concurrent/offline? | Drives MAP granularity, COUNTER fields, audit-log patterns; single-writer data can stay simple |
| 3 | Which transports matter? (BLE, AWDL, LAN/WiFi, Big Peer only) | BLE ≈ 20 KB/s effective — a 250 KiB doc is 10+ s. Sets the acceptable document size budget |
| 4 | Target hardware/OS tier? (budget Android vs modern iOS/macOS) | Storage and CPU throughput vary by an order of magnitude; pacing, observer scope, batch sizes follow |
| 5 | Document sizes and growth — bounded? unbounded sub-lists? | Unbounded embedded structures must become keyed MAPs or child collections |
| 6 | Any binary or very large string payloads? | > ~250 KB → ATTACHMENT; inline base64 is the classic failure |
| 7 | Which fields are filtered/sorted at read time? | Index plan; array elements can't be indexed (MAP entries can); JOIN keys need `_id`/index (5.1+) |
| 8 | Different permission scopes for different parts — and **what are they scoped by** (store, site, tenant, region, user)? | Two decisions at once. Permissions are query-level, so scope boundaries are collection boundaries — *and* rules can only see `_id`, so the scoping value must be a subfield of a composite `_id` (`COMPOSITE_ID` below). `_id` is immutable: getting this wrong is a document-rewrite migration later |
| 9 | Retention/deletion expectations? | Tombstone TTL (defaults: 7 days Small Peer / 30 days Big Peer; tunable) → soft delete where resurrection is unacceptable |

Version sanity check if the user doesn't know: `SHOW dql_strict_mode` returns boolean `true` on a default 4.14.x engine and `false` on a default 5.0+ engine — but the SDK package version in their build files is the authoritative signal.

## §2 The JSON review rubric

Walk the source JSON field by field (document → each nested object → each array element shape) and run this checklist. Severity: **blocker** (will lose data or fail), **warn** (conflict loss plausible / performance hazard), **info** (hygiene).

### Field-level findings

| Finding ID | Trigger in the JSON | Recommendation |
|---|---|---|
| `ARRAY_LWW` (blocker if multi-writer/unbounded, else warn) | Any array | Whole-array last-write-wins, no per-element merge, no error on lost appends → `MAP` keyed by stable ID, or child collection. OK only if strictly single-writer and bounded — say so explicitly |
| `COUNTER_CANDIDATE` (blocker if multi-writer) | Numbers that accumulate: stock, count, quantity, inventory, votes, likes, views, score totals, balance | `COUNTER` (4.14+): concurrent increments merge correctly. Integer only — model money as integer cents. Never `SET` arithmetic on a REGISTER for these |
| `ATTACHMENT_CANDIDATE` (blocker when it pushes the doc past the 256 KiB soft limit, warn otherwise) | base64 strings, image/audio/PDF payloads, any single value > ~250 KB (i.e. approaching the soft limit), URL-free blobs | Move bytes to `ATTACHMENT`; keep only the token + minimal metadata in the doc. **Ask whether the collection is synced by the MongoDB Connector** — it does not carry attachments, so inline base64 is the current recommendation there; then size the image to the 256 KiB budget (base64 adds ~33%) and keep it in its own document ([`../best-practices.md`](../best-practices.md)) |
| `DECLARE_TYPES` (info on lenient meshes; warn where un-migrated 4.x/strict peers exist) | Nested objects where a deliberate override applies, or fields read/written by strict-mode peers | Lenient baseline: objects infer MAP with **no declarations on writes or reads** — flag only deliberate overrides (`REGISTER` for atomic objects, `COUNTER` seed on INSERT) or un-flipped 4.x peers: strict peers store bare objects as whole-object REGISTERs and silently omit undeclared MAP/COUNTER fields from query results entirely. Recommended 4.x fix: migrate to `dql_strict_mode = false` before the v5 upgrade; declare explicitly only on statements strict peers execute during the transition |
| `ATOMIC_OBJECT_REGISTER` (info) | Object whose fields must stay mutually consistent (address, geo pair, opening-hours struct) | Force `REGISTER` explicitly — a deliberate override of the lenient MAP default, which can otherwise surface a half-merged object |
| `TIMESTAMP_SKEW` (info) | Timestamps compared for exact equality or used as ordering keys | Device clocks skew; use ISO-8601 strings, ranges not equality, and timestamp-keyed MAPs for event trails |
| `ID_DESIGN` (info/blocker if mutable) | `_id` that is null, reassigned over time, or duplicated across types | `_id` is immutable and never typed. Any JSON type except floats; serialized `_id` capped at 256 bytes |
| `COMPOSITE_ID` (warn) | A flat `_id` in a document that carries a scoping field (store, site, tenant, region, org, device), **or** an `_id` that concatenates several values into one string (`"store42:order-77"`, `"sensor-4471:2026-08-25T…"`) | Use a composite **object** `_id` — see the dedicated rule below |
| `MIXED_KEYED_MAP` (warn) | Object used as a dictionary with dynamic keys AND fixed keys | Split: dynamic keys into a keyed MAP, fixed keys as fields — dynamic-key churn accumulates tombstone metadata that then taxes every write of the stable half. If the dynamic keys also churn in bulk, they are entities and belong in a child collection ([`performance.md`](performance.md)) |
| `ENUM_OR_STATE` (info) | A status/phase field string | Fine as REGISTER, but if the *history* matters, add a timestamp-keyed `status_log MAP` (audit-log pattern) |
| `FLOAT_MONEY` (info) | Money/prices/totals as floating-point (e.g. `"price": 19.99`) | Model money as integer minor units (`price_cents`) — floats invite rounding drift and are also rejected inside `_id` values |
| `ORDERED_LIST` (warn) | An array whose *order* is the data (queues, playlists, ranked lists, waitlists) | Keyed MAPs and child collections don't preserve order — use a child collection read with `ORDER BY` on a sequence/timestamp field (tolerate clock skew), or designate a single-writer authority for position. Note: subscriptions reject `ORDER BY` on 5.0+ — live lists subscribe unsorted and sort in app code |

### The composite `_id` rule (`COMPOSITE_ID`)

Ditto `_id`s can be **objects**, not just strings, and this is the single most Ditto-specific modeling decision in the intake. It is worth deciding deliberately on every collection rather than defaulting to a string.

```json
{
  "_id": { "store_id": 42, "order_id": "order-2026-00042" },
  "status": "placed"
}
```

**Why an object beats a string.** Ditto's permission system can only see `_id` — sync permissions and Big Peer / auth-webhook rules are expressed as queries over it, and nothing else in the document is visible to them. So **any value you will ever want to scope permissions by must be a subfield of `_id`.** With `{ "store_id": 42, "order_id": … }`, a store's device can be granted exactly the orders where `_id.store_id = 42`. With `"order-2026-00042"`, it cannot — the scope isn't there to filter on, and retrofitting it means rewriting every document under a new `_id`, which is an offline-mesh migration, not a config change.

**The `_id` subfields are real, first-class fields — don't copy them into the body.** `WHERE _id.store_id = 42`, `CREATE INDEX … ON orders (_id.store_id)`, composite indexes over `(_id.store_id, status)` (5.1+), and `JOIN … ON child.order_id = parent._id.order_id` (5.1+) all work directly against the path. A body copy buys nothing, costs a field's worth of CRDT metadata on every document, and creates two values that can disagree. Verified on 4.14.4, 5.0.0, and 5.1.0.

Three more things a composite object buys you, all verified on 4.14.4, 5.0.0, and 5.1.0:

- **Query and index the parts.** As above — whole-object equality (`WHERE _id = { … }`) works too. Subfields of a string `_id` are only reachable with string functions, and never indexable.
- **Uniqueness for free on the real key.** The tuple is the identity, so a per-store order number can't collide with another store's.
- **Readable in every tool** — portal, HTTP API, MongoDB Connector — instead of a delimiter convention every consumer has to re-parse.

**Composite *string* `_id`s are the anti-pattern.** `"store42:order-77"` is a migration smell — usually a relational composite primary key flattened for a system that only accepted string keys. Ditto doesn't have that constraint. Delimiter-joined keys break the moment a component contains the delimiter, force string parsing at every read, are unindexable per-component, and are invisible to permissions. Flag them and convert.

**When to flag:** the source JSON has a flat `_id` *and* any of — a tenant/store/site/region/org field; stated per-location or per-tenant permission requirements; a Big Peer auth webhook; an `_id` string containing a delimiter; a relational origin with a composite primary key.

**When not to flag:** none of those are present. A document with no scoping dimension — a user's own profile, a global settings doc, a lookup table — has nothing to partition by, and a single stable string or UUID `_id` is correct. Do not manufacture a scope to justify an object `_id`. If it is worth noting that the decision is irreversible, say so as a confirmation ("evaluated, not triggered"), not as a recommendation to change the model.

**Practical notes.**

- **A child's back-reference to its parent is a normal body field** and is not what this rule is about — `comments.ticket_id` pointing at a parent ticket is the documented split pattern. What to avoid is a document restating *its own* `_id` subfields in its own body.
- You may see connector-oriented examples that do duplicate `_id` subfields into the body. That is an accommodation for MongoDB Connector ID mapping, not a Ditto modeling pattern — don't generalize it to collections the connector doesn't touch.
- Map keys inside a composite `_id` must be strings, and **floats are rejected anywhere in an `_id`** — use integers or strings.
- `_id` is immutable, so a composite `_id` is a one-way decision per collection. Choose it at design time; changing it later means rewriting documents under new IDs.
- Keep it to the fields you'd scope or shard on. An `_id` carrying the whole document is just a document with extra steps, and the 256-byte serialized cap is real.
- **MongoDB Connector:** MongoDB `_id`s are usually `ObjectId`s and are rarely used this way, so the ID mapping between the two systems needs explicit configuration — it does not fall out for free.

### Document-level findings

| Finding ID | Trigger | Recommendation |
|---|---|---|
| `SIZE_SOFT` (warn) | Estimated serialized size > 256 KiB | Console warning territory — split, or move bulk to attachments. Remember the limit applies to the serialized doc *including CRDT metadata*, not the raw JSON |
| `SIZE_HARD` (blocker) | > 5 MiB | Must split/attach — 5.1+ rejects oversized local writes outright (earlier lines log but accept; replicated oversized docs are still accepted) |
| `SPLIT_UNBOUNDED` (blocker) | Embedded collection that grows without bound (messages, readings, events, comments, line history) | Child collection, one document per item, parent `_id` as back-reference + index |
| `SPLIT_INDEPENDENT` (warn) | Sub-structure read/written heavily without the parent | Child collection; keeps docs small and writes cheap |
| `SPLIT_PERMISSIONS` (warn) | Sub-structure needs different access rules | Collection boundary (Big Peer permissions are query-level) |
| `JOIN_VS_DENORMALIZE` (info) | Model would need cross-collection reads | 5.1+: `JOIN` with the right-side key as `_id` or indexed. 4.14.x: two fetches in app code, or denormalize read-time fields (`DO UPDATE_LOCAL_DIFF` keeps duplicated writes cheap) |
| `INDEX_PLAN` (info) | Fields filtered/sorted in the user's stated queries | `CREATE INDEX` (composite is 5.1+); note array elements are not indexable |
| `OBSERVER_SCOPE` (warn) | Design implies watching a whole collection or an unbounded result set | Observers re-deliver the full result set per fire and pin substantially more memory than the raw bytes — scope tightly, page with LIMIT |
| `SOFT_DELETE` (info) | User expects deletions to be permanent/mesh-wide | Tombstones expire (defaults 7d Small Peer / 30d Big Peer, both tunable); long-offline peers can resurrect docs — soft delete + purge past TTL, don't just raise the TTL |
| `SMART_UPSERT` (info) | Model implies frequent full-document rewrites (sync-from-API patterns) | `INSERT … ON ID CONFLICT DO UPDATE_LOCAL_DIFF` (4.12+) so unchanged fields don't replicate |

### Size estimation

Estimate serialized size as `JSON.stringify(doc).length` bytes, then add headroom for CRDT metadata (HLC + actor ID per field — small per field, "tens of KB" in pathologically nested docs) and state the estimate as a range. Then place it on the budget ladder from [`performance.md`](performance.md): < 64 KiB fine anywhere · < 256 KiB fine over LAN, painful over BLE · < 5 MiB never OK over BLE, warn · ≥ 5 MiB blocker.

### What NOT to flag

Fine-grained scalar fields are cheap (merge metadata per scalar is bytes, not kilobytes) — do **not** tell users to pack scalars into fewer fields or JSON-encode blobs "to save CRDT overhead". Per-field CRDT metadata is not a reason to change a model.

## §3 Output contract

Deliver the review in this shape (prose around it is fine):

````text
## Findings
- [blocker] ARRAY_LWW — orders.items: two devices appending items offline
  lose one append; whole-array LWW. …
- [warn]    SPLIT_UNBOUNDED — …

## Recommended model
### Collection: orders
- _id: composite object `{store_id, order_id}` (permission scope) — immutable
- customer: MAP (inferred — no declaration under the lenient baseline)
... plus a pasteable INSERT statement — declare only what inference
can't infer (COUNTER, ATTACHMENT, deliberate REGISTER overrides):
```sql
INSERT INTO COLLECTION orders (receipt ATTACHMENT, stock COUNTER) …
```

## Split decisions
- items → child collection `order_items` keyed by order_id … (JOIN on 5.1+ / two fetches on 4.14.x)

## Budget
- Estimated size: ~3–6 KiB/doc … BLE implication … observer scope …
````

Every finding must cite the JSON path it refers to, the severity, and the one-line reason. Every recommendation must state its version requirements inline (e.g. "COUNTER — requires 4.14+").
