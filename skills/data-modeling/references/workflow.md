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
| 1 | Which Ditto SDK version(s)? (4.14.x / 5.0.x / 5.1.x / mixed mesh) | Strict-mode default (REGISTER vs MAP for objects); JOINs and composite indexes are 5.1+; `COUNTER` needs 4.14+ |
| 2 | Who edits which parts, and can edits be concurrent/offline? | Drives MAP granularity, COUNTER fields, audit-log patterns; single-writer data can stay simple |
| 3 | Which transports matter? (BLE, AWDL, LAN/WiFi, Big Peer only) | BLE ≈ 20 KB/s effective — a 250 KiB doc is 10+ s. Sets the acceptable document size budget |
| 4 | Target hardware/OS tier? (budget Android vs modern iOS/macOS) | Storage and CPU throughput vary by an order of magnitude; pacing, observer scope, batch sizes follow |
| 5 | Document sizes and growth — bounded? unbounded sub-lists? | Unbounded embedded structures must become keyed MAPs or child collections |
| 6 | Any binary or very large string payloads? | > ~250 KB → ATTACHMENT; inline base64 is the classic failure |
| 7 | Which fields are filtered/sorted at read time? | Index plan; array elements can't be indexed (MAP entries can); JOIN keys need `_id`/index (5.1+) |
| 8 | Different permission scopes for different parts? | Big Peer permissions are query-level; scope boundaries are collection boundaries |
| 9 | Retention/deletion expectations? | Tombstone TTL (7 days Small Peer / 30 days Big Peer) → soft delete where resurrection is unacceptable |

Version sanity check if the user doesn't know: `SHOW dql_strict_mode` returns boolean `true` on a default 4.14.x engine and `false` on a default 5.0+ engine — but the SDK package version in their build files is the authoritative signal.

## §2 The JSON review rubric

Walk the source JSON field by field (document → each nested object → each array element shape) and run this checklist. Severity: **blocker** (will lose data or fail), **warn** (conflict loss plausible / performance hazard), **info** (hygiene).
### Field-level findings

| Finding ID | Trigger in the JSON | Recommendation |
|---|---|---|
| `ARRAY_LWW` (blocker if multi-writer/unbounded, else warn) | Any array | Whole-array last-write-wins, no per-element merge, no error on lost appends → `MAP` keyed by stable ID, or child collection. OK only if strictly single-writer and bounded — say so explicitly |
| `COUNTER_CANDIDATE` (blocker if multi-writer) | Numbers that accumulate: stock, count, quantity, inventory, votes, likes, views, score totals, balance | `COUNTER` (4.14+): concurrent increments merge correctly. Integer only — model money as integer cents. Never `SET` arithmetic on a REGISTER for these |
| `ATTACHMENT_CANDIDATE` (blocker when it pushes the doc past the 256 KiB soft limit, warn otherwise) | base64 strings, image/audio/PDF payloads, any single value > ~250 KB (i.e. approaching the soft limit), URL-free blobs | Move bytes to `ATTACHMENT`; keep only the token + minimal metadata in the doc |
| `DECLARE_TYPES` (warn; blocker when multi-writer sub-fields would silently lose concurrent edits on 4.14.x strict peers) | Nested objects with no explicit CRDT declaration | On 4.14.x these store as monolithic REGISTERs (whole-object LWW), and plain `SELECT` on strict peers silently omits MAP/COUNTER fields unless the read repeats the declaration. Declare `MAP` explicitly on every INSERT/UPDATE; works identically on 5.x |
| `ATOMIC_OBJECT_REGISTER` (info) | Object whose fields must stay mutually consistent (address, geo pair, opening-hours struct) | Force `REGISTER` explicitly — on 5.x the default would be MAP, which can surface a half-merged object |
| `TIMESTAMP_SKEW` (info) | Timestamps compared for exact equality or used as ordering keys | Device clocks skew; use ISO-8601 strings, ranges not equality, and timestamp-keyed MAPs for event trails |
| `ID_DESIGN` (info/blocker if mutable) | `_id` that is null, reassigned over time, or duplicated across types | `_id` is immutable and never typed; composite-object `_id` (e.g. `{region, store, orderId}`) is allowed and useful as a permission partition key |
| `MIXED_KEYED_MAP` (warn) | Object used as a dictionary with dynamic keys AND fixed keys | Split: dynamic keys into a keyed MAP, fixed keys as fields — dynamic-key churn accumulates tombstone metadata |
| `ENUM_OR_STATE` (info) | A status/phase field string | Fine as REGISTER, but if the *history* matters, add a timestamp-keyed `status_log MAP` (audit-log pattern) |
| `FLOAT_MONEY` (info) | Money/prices/totals as floating-point (e.g. `"price": 19.99`) | Model money as integer minor units (`price_cents`) — floats invite rounding drift and are also rejected inside `_id` values |
| `ORDERED_LIST` (warn) | An array whose *order* is the data (queues, playlists, ranked lists, waitlists) | Keyed MAPs and child collections don't preserve order — use a child collection read with `ORDER BY` on a sequence/timestamp field (tolerate clock skew), or designate a single-writer authority for position |

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
| `SOFT_DELETE` (info) | User expects deletions to be permanent/mesh-wide | Tombstones expire (7d Small Peer / 30d Big Peer); long-offline peers can resurrect docs — soft delete + purge past TTL |
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
- _id: composite or string, immutable
- customer: MAP (...)
... plus a pasteable DECLARE statement:
```sql
INSERT INTO COLLECTION orders (customer MAP, items MAP (priceEach REGISTER)) …
```

## Split decisions
- items → child collection `order_items` keyed by order_id … (JOIN on 5.1+ / two fetches on 4.14.x)

## Budget
- Estimated size: ~3–6 KiB/doc … BLE implication … observer scope …
````

Every finding must cite the JSON path it refers to, the severity, and the one-line reason. Every recommendation must state its version requirements inline (e.g. "COUNTER — requires 4.14+").
