---
title: Ditto CRDT types for data modeling
description: REGISTER, MAP, COUNTER, PN_COUNTER, and ATTACHMENT — exact merge semantics, declaration syntax, mutation surface, and the modeling decision for each. Covers Ditto SDK 4.14.x, 5.0.x, and 5.1.x.
---

# CRDT types for data modeling

Every field in a Ditto document is a CRDT. Choosing the model means choosing, per field, which CRDT it is. This file is the modeling-side reference for the five types; for full DQL mutation grammar see the `write-dql` skill's [`../../dql/references/types-mutators.md`](../../dql/references/types-mutators.md).

| Type | Merge semantic | Payload | Min SDK | Mutators |
|---|---|---|---|---|
| `REGISTER` | Last-write-wins (whole value) | Any JSON value — scalar, object, or array | all | `SET`, `UNSET` |
| `MAP` | Add-wins recursive map — per-field merge | JSON object | all | `SET` (bulk merge), dotted-path `SET`/`UNSET`, nested `APPLY` |
| `COUNTER` | Concurrent inc/dec commute; set is LWW; set beats a concurrent inc/dec | Integer | 4.14+ | `APPLY … INCREMENT BY`, `APPLY … RESTART [WITH]` |
| `PN_COUNTER` (legacy) | Positive-negative counter only | Double | 4.11+ | `APPLY … PN_INCREMENT BY` (no set/reset) |
| `ATTACHMENT` | LWW handle in the doc; blob is content-addressed | Binary out-of-band | all | `SET` (new token), `UNSET` |

**Last-write-wins tie-break:** LWW compares a hybrid logical clock timestamp, then the writer's actor ID. On wall-clock ties the winner is deterministic but effectively arbitrary from the app's point of view — never rely on which of two simultaneous REGISTER writes wins.

## REGISTER

**Semantics.** One atomic last-writer-wins cell. The *whole value* is the unit of conflict: if the value is an object or array, concurrent writes replace it entirely — there is no field-level or element-level merge inside a register.

**Model with REGISTER when:** the value is a scalar that gets overwritten (title, status, price, timestamp); an object that is semantically atomic (an address where city and postcode must stay consistent); or a single-writer field.

**Do not model with REGISTER when:** different peers edit different sub-fields (they will overwrite each other's object); a number accumulates across peers; an array grows by appends from multiple devices.

**Default note.** Scalars and arrays are always REGISTERs by default. For *object* values the default depends on strict mode: `REGISTER` when `dql_strict_mode = true` (the 4.14.x default), `MAP` when `false` (the 5.x default). See [`versions.md`](versions.md). The intended way to work: on 5.x, rely on the lenient defaults and declare a keyword only to *override* them (e.g. force `REGISTER` on an atomic object); on 4.x, flip the mesh to `dql_strict_mode = false` (recommended before any v5 upgrade) — or declare explicitly while strict peers remain.

**Forcing REGISTER on an object:** the lenient (5.0+) default infers MAP for objects, so declare REGISTER when you actually want whole-object LWW. The declaration is also valid — though redundant — on 4.14.x strict mode:

```sql
UPDATE COLLECTION orders (address REGISTER)
SET address = { 'city': 'Portland', 'zip': '97201' }
WHERE _id = 'order-1';
```

## MAP

**Semantics.** A recursive add-wins map: each key is an independent CRDT (defaulting to REGISTER, or whatever you declare), so two peers editing different keys of the same map both win. Nesting recurses — maps inside maps merge per level. Removes write an add-wins tombstone: a remove beats edits it has *seen*, but a concurrent re-add from a peer that hadn't seen the remove survives.

**Model with MAP when:** different peers (or different features) touch different sub-fields — profiles, settings, per-item state. This is the workhorse for embedded sub-entities: a `lineItems MAP` keyed by item ID beats an array in almost every concurrent scenario.

**Behavioral traps:**

- Omitting a key is **"no change"**, not delete. Remove one entry with dotted-path `UNSET` (`` UNSET items.`SKU-100` ``); it writes a per-key add-wins tombstone — a concurrent re-add from a peer that hasn't seen the remove survives. Clearing many keys? `UNSET` the parent field — cheaper on tombstone metadata.
- **Strict-mode read trap (4.14.x):** a MAP or COUNTER field is *stored* correctly when written with a declaration, but plain `SELECT` on a strict peer omits it silently unless the read repeats the declaration (`SELECT ... FROM COLLECTION orders (status_log MAP)`). Strict peers also reject nested-field `SET`/`UNSET` without the declaration. The clean fix is migrating 4.x peers to `dql_strict_mode = false`; while strict peers remain, declare on both writes and reads that touch them.
- `SET map_field = {...}` is a **bulk merge**: keys you don't mention survive.
- Heavy add/remove churn on dynamic keys accumulates tombstone metadata; if the churn set is large, prefer `UNSET` on the parent, a fresh document, or a separate collection. See [`performance.md`](performance.md).

**Declaration:**

```sql
INSERT INTO COLLECTION orders (
  customer MAP,                                   -- sub-fields default to REGISTER
  status    MAP (history MAP)                     -- nested MAP
)
DOCUMENTS ({
  '_id': 'order-1',
  'customer': { 'name': 'Ada', 'tier': 'gold' },
  'status': { 'current': 'placed', 'history': {} }
});
```

## COUNTER (settable counter, 4.14+)

**Semantics.** A per-actor counter: each peer accumulates its own contribution, and the visible value is the sum across actors — concurrent increments always commute and none are lost. On top of that, the counter has an LWW "base value": `RESTART WITH v` sets the base, and **a set beats concurrent increments** (the set clears the accumulated residue and wins by timestamp).

**Model with COUNTER when:** a number is incremented/decremented by multiple peers — inventory, stock, seats remaining, like/view counts, vote tallies. Two devices each doing `INCREMENT BY 1` offline converge to +2.

**Do not model with COUNTER when:** the number is overwritten, not accumulated (prices, temperatures — use REGISTER); or you need arbitrary arithmetic (`max`, multiplication — counters only do inc/dec/set).

**Traps:**

- Inserting a plain integer **without declaring the type** creates a REGISTER, not a counter — increments will never merge. In lenient mode (5.x default), `APPLY … INCREMENT BY` on an undeclared field auto-creates a counter; seeding an initial value on INSERT still needs the declaration, and on strict-mode 4.x peers undeclared counters are invisible — declare `COUNTER` wherever a counter lives.
- Values are integers. Model money as integer cents, not floats.
- A counter's stored state grows with the number of **distinct peers** that have ever touched it (one entry per actor), not with the number of operations. See [`performance.md`](performance.md).

```sql
-- Declare + seed
INSERT INTO COLLECTION products (stock COUNTER)
VALUES ({ '_id': 'sku-1', 'stock': 100 });

-- Accumulate (negative = decrement)
UPDATE COLLECTION products (stock COUNTER)
APPLY stock INCREMENT BY -2
WHERE _id = 'sku-1';

-- Resets: RESTART (= 0) or RESTART WITH n (LWW set) — COUNTER only
UPDATE COLLECTION products (stock COUNTER)
APPLY stock RESTART WITH 100
WHERE _id = 'sku-1';
```

## PN_COUNTER (legacy, 4.11+)

Predecessor of `COUNTER`: same convergence for increments (`APPLY f PN_INCREMENT BY n`), but double-precision, no set/reset (`RESTART`), and negative-share bookkeeping only. New models on 4.14+ should always use `COUNTER`. Keep `PN_COUNTER` only if the field already exists in production storage — never change an existing field's CRDT type (see [`../best-practices.md`](../best-practices.md)).

## ATTACHMENT

**Semantics.** The document stores a small **token** (handle): `{ "id": <content hash>, "len": <bytes>, "metadata": {...} }`. The token field merges last-write-wins like a REGISTER; the **bytes live outside the document** in blob storage, content-addressed by hash, and sync over a separate asynchronous protocol that peers fetch lazily and explicitly.

**Model with ATTACHMENT when:** any binary payload (images, audio, PDFs, signatures), and any string payload large enough to pressure the document budget (rule of thumb: > ~250 KB, but see the transport budget in [`performance.md`](performance.md)).

**Consequences of the design:**

- Attachment bytes **do not count** against the 256 KiB / 5 MiB document limits.
- Content addressing means identical blobs are stored and transferred once; "conflicts" between identical uploads are impossible.
- Peers do **not** automatically pull blobs with a sync subscription — the app calls `fetchAttachment`. Budget for explicit fetch UI/progress over BLE.
- Metadata on the token *does* travel with the document — keep it small; don't smuggle binaries into `metadata`.
- Removal is `UNSET` on the field or `EVICT` of the document; there is no partial-update mutator.
- Merges never invent an attachment token — a field that must always be present must not be an attachment.

## Arrays — not a CRDT type, and that's the point

There is no list CRDT in Ditto. Every array, at any depth, is a whole-array LWW REGISTER: writing one element rewrites the array as a unit, and concurrent appends do not merge. There is no error and no notification when one writer's whole array silently wins.

Rules of thumb (detail in [`../best-practices.md`](../best-practices.md)):

- Model growable collections of things as a `MAP` keyed by a stable ID (natural key or UUID): `lineItems: { "item-1": {...}, "item-2": {...} }`.
- Or one document per item in a separate collection — required when the set is unbounded, large, or independently permissioned.
- **Ordered/queue-like collections** (waitlists, playlists, ranked steps): neither remedy preserves order by itself. Use a child collection plus read-time `ORDER BY` on a sequence or timestamp field (tolerating clock skew), or designate a single writer as position authority.
- Arrays are acceptable when exactly one device ever writes them, others only read (e.g. a precomputed "top 3 tags" summary). Order is by definition what the single writer wrote.
- Array elements are **not indexable**; scalar values inside MAP entries are. If you need to query or sort by the element, it cannot stay in an array.

## Decision matrix

| Field shape in the source JSON | First choice | When to deviate |
|---|---|---|
| Scalar, overwritten wholesale | `REGISTER` (no declaration needed) | — |
| Object, sub-fields edited independently | `MAP` (declared) | `REGISTER` if the object must stay atomic |
| Object, semantically atomic (address, geo pair) | `REGISTER` (declare on 5.0+) | — |
| Number accumulated across peers | `COUNTER` (4.14+) | `PN_COUNTER` only for legacy storage |
| Array, multi-writer or growable | `MAP` keyed by ID, or child collection | array only if strictly single-writer |
| Binary / large string (> ~250 KB) | `ATTACHMENT` | inline only if small and queryable |
| Unbounded stream (events, readings, messages) | separate collection, one doc each | never embed |
