---
title: Performance dimensions of Ditto data models
description: How document size, structure, hardware, and transports interact — the numbers and rules of thumb that make a Ditto data model fast or slow in production. SDK 4.14.x, 5.0.x, 5.1.x and 5.2.0.
---

# Performance dimensions of data models

## Contents

- [Document size limits (hard facts)](#document-size-limits-hard-facts)
- [What actually costs when a document changes](#what-actually-costs-when-a-document-changes)
- [Transports: the bandwidth budget](#transports-the-bandwidth-budget)
- [Hardware tiers](#hardware-tiers)
- [Observers (live queries)](#observers-live-queries)
- [Counters and actor growth](#counters-and-actor-growth)
- [Tombstones and churn](#tombstones-and-churn)
- [Quick budget table for reviews](#quick-budget-table-for-reviews)

Performance in Ditto is not "fast vs slow queries" — it's the product of **document size × merge granularity × hardware × transport**. This file gives the numbers; the modeling conclusions are in [`../best-practices.md`](../best-practices.md).

## Document size limits (hard facts)

| Threshold | Default | Parameter | Behavior |
|---|---|---|---|
| Soft limit | 256 KiB | `document_size_soft_limit_bytes` | warning log; the write succeeds |
| Hard limit | 5 MiB | `document_size_hard_limit_bytes` | **5.1+: local writes exceeding it are rejected with an error.** 4.14.x/5.0.x: loud error log, write succeeds. Before 5.2.0, oversized replicated documents are still stored. In 5.2.0, a replication diff that would push the resulting document over its hard limit is dropped; that document stops receiving updates until evicted and re-synced |

Two things people miss:

1. The limits apply to the **serialized document including CRDT metadata** (per-field version state and tombstones) — not the JSON you handed to `INSERT`. A write that "shrinks" a document does not immediately shrink the serialized form: tombstones from earlier larger values remain. Remediation for a bloated document: rewrite it fresh **under a new `_id`** (tombstones don't travel to the new ID), or split the heavy sub-structure.
2. **Attachments are exempt.** Blob bytes live outside the document; only the small token counts. This is the canonical escape hatch for large payloads.

Inspect them (read-only) with:

```sql
SHOW document_size_soft_limit_bytes;
SHOW document_size_hard_limit_bytes;
```

**Do not recommend changing these.** Both are per-peer system parameters settable via `ALTER SYSTEM SET …`, but changes are **runtime-only — they silently revert on app restart** (durable overrides need the `DITTO_*` env var or SDK startup config), values must match on every peer in the mesh including Big Peer, and the two are not independent: the hard check is nested inside the soft check, so the effective reject threshold is `max(soft, hard)`. Raising the soft limit above the hard one therefore *lifts* enforcement for everything between them — with `soft = 10 MiB`, a 6 MiB write is accepted on 5.1.0 with no warning and no error, where the defaults reject it. (Verified 5.1.0; the skewed configuration is untested in the engine's own suite.) The fix for an oversized model is always the model — split, attach, rewrite under a new `_id` — not the limit. If a user insists on changing them, that's a Ditto-support conversation, not a DQL snippet.

## What actually costs when a document changes

- **On the wire:** for MAP fields only the changed entries' CRDT state travels (field-level diff sync). But a REGISTER's value is atomic — touching one byte of a REGISTER'd object or array transmits the whole value. *Modeling consequence: put hot, independently-edited sub-fields in MAPs; never in registers or arrays.*
- **On disk/CPU:** the whole document is re-serialized per write, and CRDT merge cost scales with **document size, not change size**. A one-field edit to a 2 MB document pays a 2 MB document's merge. This is the real reason for the 256 KiB soft limit.
- **Deserialization** of large nested documents costs orders of magnitude more per document than tiny ones (directional rule of thumb). At high ingest rates large documents need pacing and modest write batches — hundreds, not thousands, per batch for ~15 KB-class documents.

## Transports: the bandwidth budget

| Transport | Effective throughput | Time to first-replicate a 250 KiB doc |
|---|---|---|
| Bluetooth LE | ~20 KB/s | 10+ seconds (a 5 MiB doc: minutes — forbid by design) |
| AWDL / LAN / WiFi | orders of magnitude higher | sub-second to seconds |

**Modeling consequences when BLE is in the mesh:** keep documents in the single-digit-KB range; split anything larger; move binaries to ATTACHMENT (blobs use a separate chunked protocol, but they still eat the same airtime — fetch them lazily and on demand); avoid large update bursts that queue behind each other on the same link.

## Hardware tiers

Ditto's engine speed tracks the hardware it runs on:

- **Low-end Android devices** with slower flash storage and CPUs handle sustained write/merge throughput measurably worse than **modern iPhones, iPads, and Macs** with fast NVMe-class storage. Don't extrapolate performance measured on one tier to the other.
- The engine also carries a fixed native footprint before any data is stored; on resource-constrained devices, per-document overhead matters more, so model smaller.
- Always validate a model on the *slowest target device*, not on a dev machine or flagship phone.

Use the intake question "what's the slowest device class and OS in your fleet?" ([`workflow.md`](workflow.md) §1 #4) to set the size/batch/observer budget, and phase guidance as budgets (e.g. "keep docs < 32 KiB on this fleet over BLE") rather than absolute claims — speeds depend on hardware and SDK version and improve release over release.

## Observers (live queries)

- Every observer fire **re-runs the query and re-delivers the full current result set**, not just the delta. Held observer state is substantially larger than the raw document bytes it surfaces (directionally: an order of magnitude, per internal measurement).
- Wide observers (whole-collection, big unbounded result sets) over large collections are the most common "my app is slow / grows in memory" cause.
- **Model so that the screens that observe are narrow:** small hot collections ("today's open orders") rather than one mega-collection filtered in-app.

### Getting the delta: use the Differ, don't diff by hand

The observer hands you a whole result set, but the SDK will tell you *what changed* in it. `DittoDiffer` (`Differ` in JavaScript) compares one emission's `items` against the previous one and returns a `DittoDiff` with four index sets — `insertions`, `deletions`, `updates`, `moves` — into the new array (`deletions`/`moves` index the previous one). That is the supported way to drive incremental UI updates and to avoid re-processing every row on every fire.

```js
const differ = new Differ();
let previousIds = [];                       // keep your own copy: only extracted data, never live items

const observer = ditto.store.registerObserver(
  "SELECT * FROM orders WHERE status = 'open'",
  (queryResult) => {
    const diff = differ.diff(queryResult.items);
    const currentIds = queryResult.items.map((item) => {
      const id = item.value._id;
      item.dematerialize();                 // release the materialized value
      return id;
    });
    diff.insertions.forEach((i) => addRow(currentIds[i]));
    diff.updates.forEach((i) => refreshRow(currentIds[i]));
    diff.deletions.forEach((i) => removeRow(previousIds[i]));   // indexes the PREVIOUS array
    previousIds = currentIds;
  },
);
```

Three things that bite people:

- **Kotlin v5 owns the differ for you** — `DittoDiffer`'s constructor is internal there; use the `registerObserver` overload whose lambda takes `(result, diff)`. Every other SDK still constructs one explicitly and reuses it across callbacks.
- **`deletions` and `moves` index the previous emission**, which the differ does not keep for you. Store your own array of extracted values (IDs, not `QueryResultItem`s — those are cursors, and holding one across emissions is a use-after-free).
- **The first fire reports everything as an insertion**, because the differ starts empty. There is no separate "initial event" flag. Metadata-only changes are ignored, so `updates` means the value actually changed.

The Differ reduces the *work you do per fire*. It does not shrink the result set the engine materializes — a whole-collection observer still costs a whole collection every fire. Narrow the query first, then diff it.

## Counters and actor growth

A COUNTER/PN_COUNTER stores one contribution entry per **distinct peer (actor)** that has ever incremented it. Value size grows with active writer count, not operation count — fine for a store's 20 devices, worth a thought for a public like-button with thousands of writers on one counter. Ordinary increments never prune: a dead peer's entry survives until something clears it. `APPLY … RESTART [WITH v]` does clear it — a winning set resets the base register and **discards the whole per-actor map** — so the period-reset pattern doubles as the only in-place compaction, and it is COUNTER-only (a `PN_COUNTER`'s actor map can never shrink; only evicting the document removes it). Heavily-shared single counters on very large meshes are a reason to shard counters (e.g. per-region counters summed at read).

## Tombstones and churn

### Mass per-key `UNSET` is a modeling failure, not a tuning problem

If you find yourself clearing thousands of dynamic map keys with per-key `UNSET map.key`, **stop and re-model — do not reach for a workaround.** Each removed key leaves a tombstone inside the document forever-ish, so the document grows as you delete from it, and the merge cost of every subsequent write grows with it. Getting here means the model is wrong in one of three specific ways:

| What you have | Why it fails | The actual fix |
|---|---|---|
| A map used as an unbounded, churning collection (per-message, per-reading, per-event keys) | Keys are entities with their own lifecycle; the document is a container that can only grow | One document per entity in a child collection. Deleting an entity then deletes a document, not a key — see `SPLIT_UNBOUNDED` in [`workflow.md`](workflow.md) |
| A map used as a work queue / scratch buffer that is filled and drained | Drain-to-empty means every key you ever wrote is now a tombstone | Child collection + `EVICT`, or rewrite the document under a fresh `_id` each cycle |
| A map mixing dynamic keys with fixed schema fields | The dynamic half's churn taxes reads and writes of the stable half | Split the dynamic keys into their own field or collection — `MIXED_KEYED_MAP` in [`workflow.md`](workflow.md) |

The mechanical mitigations exist and are worth knowing — `UNSET` the **parent** field to clear a whole subtree in one tombstone rather than N, or rewrite the document under a new `_id` (tombstones don't travel to a new ID) — but treat reaching for either as the signal that triggered this section. They buy time to re-model; they are not the model. Removing a handful of keys from a bounded, slow-changing map is fine and always was.

### Tombstone TTL (deletes, not map keys)

Document tombstones from hard deletes expire. **These are the defaults, and they are tunable:**

| | Default | How to change it |
|---|---|---|
| Small Peer / Edge SDK | 7 days (`TOMBSTONE_TTL_HOURS = 168`) | `ALTER SYSTEM SET` on the peer, alongside `TOMBSTONE_TTL_ENABLED` (default `true`) and the reaper schedule (`DAYS_BETWEEN_REAPING`, default 1 day) |
| Big Peer / Ditto Cloud | 30 days, reaped hourly | Not a client setting — contact Ditto support |

Too short, and a peer offline past the window resurrects the document it never learned was deleted; too long, and tombstone storage accumulates. **Never set the Small Peer TTL higher than the Big Peer's** — the peer will re-send tombstones the server has already reaped. Where resurrection is unacceptable, don't tune the TTL: soft delete and purge past the window ([`../best-practices.md`](../best-practices.md)).

## Quick budget table for reviews

| Signal | Verdict |
|---|---|
| Doc < 64 KiB, fields mostly MAP | fine anywhere |
| Doc 64–256 KiB | fine on LAN/Big Peer; painful on BLE |
| Doc 256 KiB–5 MiB | never OK on BLE; warn everywhere; split or attach |
| Doc ≥ 5 MiB | blocker — 5.1+ rejects the write outright; never design a doc that can grow into this |
| Single collection-wide observer on hot collection | restructure into scoped views |
| Counter touched by thousands of distinct writers | shard by region/entity |
