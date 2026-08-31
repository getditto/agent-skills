---
title: Data-modeling feature matrix across SDK versions
description: Which data-modeling capabilities exist in Ditto SDK 4.14.x (LTS), 5.0.x, and 5.1.x — strict-mode defaults, CRDT types, JOINs, indexes, and mixed-version mesh rules.
---

# Version matrix for data modeling

Tagging convention used across this skill: **4.14+** (exists in the LTS line and everything newer), **5.0+**, **5.1+**. Terminology: **strict mode** = `dql_strict_mode = true` (bare objects are REGISTERs); **lenient mode** = `false` (bare objects are MAPs, the 5.x default). **This skill assumes lenient mode on every peer** — it is the 5.x default and the migration target for every 4.x mesh. If you need the DQL feature matrix (operators, functions, statements), see the `write-dql` skill's [`../../dql/references/versions.md`](../../dql/references/versions.md) — this file is the modeling-side view.

## Strict mode: `false` is the assumed baseline (most important section)

`dql_strict_mode` is a per-peer, runtime-only engine flag (exists since 4.11; not persisted across restarts) that decides how plain JSON maps onto CRDT types when a statement doesn't declare them. It changes behavior on **both writes and reads**:

| Behavior | `false` (lenient) — **baseline** | `true` (strict) — legacy 4.14.x default |
|---|---|---|
| Bare object in `INSERT`/`UPDATE` becomes | `MAP` (per-field merge) — the engine duck-types JSON into CRDT intent | `REGISTER` (whole-object LWW) |
| Scalars and arrays become | `REGISTER` (arrays are always registers) | `REGISTER` |
| `MAP`/`REGISTER` keywords on writes | **Not needed — do not write them.** The inferred default is the intended behavior | **Required** for every non-REGISTER field — an undeclared object silently stores as `REGISTER` |
| Type declarations on reads | **Not needed — do not write them.** `SELECT` returns the most recent value of every field, whatever its CRDT type | **Required** — a MAP/COUNTER field the query doesn't re-declare is **omitted from the result entirely, as if it never existed** (no error; verified on 4.14.4: plain reads return `{}`) |
| `COUNTER` / `ATTACHMENT` declarations | Still required — inference can't guess them from a JSON value | Required |

Default per SDK line: **4.14.x → `true`**, **5.0.x / 5.1.x → `false`**.

### Inspecting and changing the flag

```sql
SHOW dql_strict_mode;
ALTER SYSTEM SET dql_strict_mode = false;   -- restore the engine default with:
ALTER SYSTEM RESET dql_strict_mode;
```

Set it at every app start, before starting sync or running queries — it is not persisted.

### Migration: strict → lenient (the only direction we recommend)

If any peer in a mesh has `dql_strict_mode = true` — every default-configured 4.14.x peer does — the guidance is: **migrate to `false`, mesh-wide, and do it before upgrading to v5** so the version jump changes no merge behavior. New customers still on 4.14 should flip immediately and learn the lenient behaviors.

1. **Flip every peer**: `ALTER SYSTEM SET dql_strict_mode = false` at app start, everywhere. Never set it back to `true` on 5.x; never flip peers ad hoc mid-mesh — an uncoordinated change is how fields silently change CRDT type.
2. **Transition window** (strict peers still present): declare MAP/COUNTER explicitly on every statement a strict peer executes — writes *and* reads. Data syncs correctly regardless of each peer's setting, but a strict peer treats an undeclared MAP written by a lenient peer as a REGISTER (nested fields appear **missing**), and plain `SELECT` on a strict peer omits declared MAP/COUNTER fields unless the read repeats the declaration — `SELECT ... FROM COLLECTION orders (status_log MAP)`. No error, just absent fields.
3. **End state** (all peers lenient): stop writing `MAP`/`REGISTER` declarations entirely. Keep `COUNTER`/`ATTACHMENT` declarations and deliberate `REGISTER` overrides on atomic objects — those are per-field intent, not strict-mode boilerplate.

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
| Composite (multi-column) indexes | ✗ | ✗ | ✓ | Combined-key queries without splitting |
| `INSERT … ON ID CONFLICT DO UPDATE_LOCAL_DIFF` | ✓ (4.12+) | ✓ | ✓ | Safe denormalized duplication (skips unchanged fields) |
| `RETURNING` on INSERT/UPDATE | ✗ | ✗ | ✓ | Write-then-read in one statement |
| `JOIN` (inner/left) | ✗ | ✗ | ✓ | Normalize across collections and reassemble at read time; right-side key must be `_id` or indexed. **Small Peers only** — joins are unsupported on Big Peer and in `registerSubscription` (use `execute` / observers) |
| `EXPLAIN` / `ADVISE` | ✓ / ✗ | ✓ / ✗ | ✓ / ✓ | Verify the access path your model assumes |
| Document size limits (`document_size_soft_limit_bytes` 256 KiB / `document_size_hard_limit_bytes` 5 MiB) | ✓ | ✓ | ✓ | Same defaults everywhere; **5.1.x rejects oversized local writes**, earlier lines only log — see [`performance.md`](performance.md) |
| dot-notation nested paths + `UNSET` | ✓ (4.11+) | ✓ | ✓ | Legacy `->` arrows and `tombstone()` were removed in v5 |

## Practical rules by target version

- **Targeting 4.14.x:** migrate every peer to `dql_strict_mode = false` first (and before any v5 upgrade); while strict peers remain, declare every non-REGISTER type on the statements they execute — writes and reads; no JOINs — denormalize or fetch related collections in app code; single-column indexes only.
- **Targeting 5.1.x:** keep the strict-mode default `false` and rely on lenient inference — no `MAP`/`REGISTER` declarations on reads or writes; keywords only to override (e.g. `REGISTER` for atomic objects) or where inference can't help (`COUNTER` seeds on INSERT, `ATTACHMENT`). You may normalize more aggressively (JOIN + index the join key), but only where the split triggers in [`../best-practices.md`](../best-practices.md) actually fire — embedding is still the default.
- **Mixed 4.14/5.x mesh:** flip the 4.x peers to lenient as the first step of the upgrade; while any strict peers remain, declare MAP/COUNTER types on the statements those peers execute (including reads), and model to the 4.14 read surface (no JOIN-dependent screens).
