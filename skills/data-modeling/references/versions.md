---
title: Data-modeling feature matrix across SDK versions
description: Which data-modeling capabilities exist in Ditto SDK 4.14.x (LTS), 5.0.x, and 5.1.x — strict-mode defaults, CRDT types, JOINs, indexes, and mixed-version mesh rules.
---

# Version matrix for data modeling

Tagging convention used across this skill: **4.14+** (exists in the LTS line and everything newer), **5.0+**, **5.1+**. If you need the DQL feature matrix (operators, functions, statements), see the `dql` skill's [`../../dql/references/versions.md`](../../dql/references/versions.md) — this file is the modeling-side view.

## The strict-mode default flip (most important)

| | 4.14.x (LTS) | 5.0.x | 5.1.x |
|---|---|---|---|
| `dql_strict_mode` default | `true` | `false` | `false` |
| Bare object in INSERT/UPDATE becomes | `REGISTER` (whole-object LWW) | `MAP` (per-field merge) | `MAP` |
| Scalars and arrays become | `REGISTER` | `REGISTER` | `REGISTER` (arrays are always registers) |
| Collection definitions required for MAP/COUNTER fields? | Yes, under the strict default | Inferred — but INSERT of counter/attachment values still requires a declaration; always declare for portability | Same as 5.0.x |

The knob exists since 4.11 and is runtime-only (not persisted across restarts); set it before starting sync or running queries:

```sql
SHOW dql_strict_mode;
ALTER SYSTEM SET dql_strict_mode = false;   -- or = true; restore the default with:
ALTER SYSTEM RESET dql_strict_mode;
```

**Mixed-version meshes.** Data syncs correctly regardless of each peer's strict-mode setting, but a strict peer without an explicit definition treats a MAP written by a lenient peer as a REGISTER — nested fields silently appear **missing** on that peer. The same trap exists on the read side: on a strict-mode (default 4.14.x) peer, a MAP field written *with* a declaration is invisible to plain `SELECT *` / `SELECT field` unless the read repeats the declaration — `SELECT ... FROM COLLECTION orders (status_log MAP)`. No error, just absent fields. Fixes: declare `MAP` types explicitly in statements (best), repeat declarations on reads that touch strict peers, or align `dql_strict_mode = false` on all peers. The on-disk type is decided by the writing peer's declaration, so explicit declarations make behavior version-independent.

**HTTP API note:** `dql_strict_mode = false` requires the `/api/v5/store/execute` endpoint; `/api/v4/store/execute` does not support lenient mode. Both are sync-compatible.

## CRDT type availability

| Type | 4.14.x | 5.0.x | 5.1.x |
|---|:-:|:-:|:-:|
| `REGISTER` | ✓ | ✓ | ✓ |
| `MAP` | ✓ | ✓ | ✓ |
| `ATTACHMENT` | ✓ | ✓ | ✓ |
| `COUNTER` (settable; `INCREMENT BY`, `RESTART [WITH]`) | ✓ (4.14+) | ✓ | ✓ |
| `PN_COUNTER` (legacy; `PN_INCREMENT BY`) | ✓ (4.11+) | ✓ | ✓ |

> `COUNTER` shipped with the 4.14.x LTS line. SDKs older than 4.14 are out of support; if a mesh somehow contains a pre-4.14 peer, its only counter option is `PN_COUNTER`.

## Modeling-relevant statement features

| Feature | 4.14.x | 5.0.x | 5.1.x | Modeling relevance |
|---|:-:|:-:|:-:|---|
| `CREATE INDEX` (single/nested path) | ✓ (4.12+) | ✓ | ✓ | Which fields are queryable cheaply — informs embed-vs-split |
| Composite (multi-column) indexes | ✗ | ✗ | ✓ | Combined-key queries without Splitting |
| `INSERT … ON ID CONFLICT DO UPDATE_LOCAL_DIFF` | ✓ (4.12+) | ✓ | ✓ | Safe denormalized duplication (skips unchanged fields) |
| `RETURNING` on INSERT/UPDATE | ✗ | ✗ | ✓ | Write-then-read in one statement |
| `JOIN` (inner/left) | ✗ | ✗ | ✓ | Normalize across collections and reassemble at read time; right-side key must be `_id` or indexed. **Small Peers only** — joins are unsupported on Big Peer and in `registerSubscription` (use `execute` / observers) |
| `EXPLAIN` / `ADVISE` | ✓ / ✗ | ✓ / ✗ | ✓ / ✓ | Verify the access path your model assumes |
| Document size limits (`document_size_soft_limit_bytes` 256 KiB / `document_size_hard_limit_bytes` 5 MiB) | ✓ | ✓ | ✓ | Same defaults everywhere; **5.1.x rejects oversized local writes**, earlier lines only log — see [`performance.md`](performance.md) |
| dot-notation nested paths + `UNSET` | ✓ (4.11+) | ✓ | ✓ | Legacy `->` arrows and `tombstone()` were removed in v5 |

## Practical rules by target version

- **Targeting 4.14.x:** no JOINs — denormalize or fetch related collections in app code; declare every non-REGISTER type; expect bare objects to be registers unless declared; single-column indexes only.
- **Targeting 5.1.x:** you may normalize more aggressively (JOIN + index the join key), but only where the split triggers in [`../best-practices.md`](../best-practices.md) actually fire — embedding is still the default.
- **Mixed 4.14/5.x mesh:** model to the 4.14 baseline (no JOIN-dependent reads), declare all types explicitly, and treat `COUNTER` as the only counter for new fields.
