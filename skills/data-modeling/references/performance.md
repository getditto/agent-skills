---
title: Performance dimensions of Ditto data models
description: How document size, structure, hardware, and transports interact — the numbers and rules of thumb that make a Ditto data model fast or slow in production. SDK 4.14.x, 5.0.x, 5.1.x.
---

# Performance dimensions of data models

Performance in Ditto is not "fast vs slow queries" — it's the product of **document size × merge granularity × hardware × transport**. This file gives the numbers; the modeling conclusions are in [`../best-practices.md`](../best-practices.md).

## Document size limits (hard facts)

| Threshold | Default | Parameter | Behavior |
|---|---|---|---|
| Soft limit | 256 KiB | `document_size_soft_limit_bytes` | warning log; the write succeeds |
| Hard limit | 5 MiB | `document_size_hard_limit_bytes` | **5.1+: local writes exceeding it are rejected with an error.** 4.14.x/5.0.x: loud error log, write succeeds. On all versions, oversized documents arriving via replication are still stored — enforcement is writer-side only today |

Two things people miss:

1. The limits apply to the **serialized document including CRDT metadata** (per-field version state and tombstones) — not the JSON you handed to `INSERT`. A write that "shrinks" a document does not immediately shrink the serialized form: tombstones from earlier larger values remain. Remediation for a bloated document: rewrite it fresh **under a new `_id`** (tombstones don't travel to the new ID), or split the heavy sub-structure.
2. **Attachments are exempt.** Blob bytes live outside the document; only the small token counts. This is the canonical escape hatch for large payloads.

Inspect them (read-only) with:

```sql
SHOW document_size_soft_limit_bytes;
SHOW document_size_hard_limit_bytes;
```

**Do not recommend changing these.** Both are per-peer system parameters settable via `ALTER SYSTEM SET …`, but changes are **runtime-only — they silently revert on app restart** (durable overrides need the `DITTO_*` env var or SDK startup config), values must match on every peer in the mesh including Big Peer, and setting the soft limit at or above the hard limit silently disables hard-limit enforcement. The fix for an oversized model is always the model — split, attach, rewrite under a new `_id` — not the limit. If a user insists on changing them, that's a Ditto-support conversation, not a DQL snippet.

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

## Counters and actor growth

A COUNTER/PN_COUNTER stores one contribution entry per **distinct peer (actor)** that has ever incremented it. Value size grows with active writer count, not operation count — fine for a store's 20 devices, worth a thought for a public like-button with thousands of writers on one counter. There is no per-actor pruning: nothing removes a dead peer's entry short of evicting the whole document (which removes the counter's state with it). Heavily-shared single counters on very large meshes are a reason to shard counters (e.g. per-region counters summed at read).

## Tombstones and churn

- Clearing thousands of dynamic map keys with per-key `UNSET` (`UNSET map.key`) accumulates tombstone metadata inside the document — one tombstone per removed key. `UNSET` the **parent** field instead, or delete/rewrite the document.
- Tombstone TTL: 7 days on Small Peers, 30 days on Big Peer. Too-low TTLs on long-offline peers → document resurrection; too-high → storage bloat. See [`../best-practices.md`](../best-practices.md).

## Quick budget table for reviews

| Signal | Verdict |
|---|---|
| Doc < 64 KiB, fields mostly MAP | fine anywhere |
| Doc 64–256 KiB | fine on LAN/Big Peer; painful on BLE |
| Doc 256 KiB–5 MiB | never OK on BLE; warn everywhere; split or attach |
| Doc ≥ 5 MiB | blocker — 5.1+ rejects the write outright; never design a doc that can grow into this |
| Single collection-wide observer on hot collection | restructure into scoped views |
| Counter touched by thousands of distinct writers | shard by region/entity |
