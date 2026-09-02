---
name: data-modeling
description: Use when designing, reviewing, or migrating data models/schemas for Ditto (the CRDT-based peer-to-peer database). Covers REGISTER vs MAP vs COUNTER vs ATTACHMENT merge semantics, strict mode (`dql_strict_mode = false` is the assumed baseline; how to migrate 4.14.x peers off `true`), converting existing JSON documents into CRDT-friendly collections, embedding vs splitting collections (JOINs are 5.1+), document size limits, and sync performance across hardware and transports (BLE, LAN). Confirm the SDK version first — defaults and features vary.
allowed-tools: Read, Grep, Glob, Edit, Write
---

# Data Modeling for Ditto

Ditto stores JSON-like documents backed by CRDTs. Every field is a CRDT whose type — `REGISTER`, `MAP`, `COUNTER`, `PN_COUNTER`, `ATTACHMENT` — decides how concurrent offline edits merge. Data modeling for Ditto is therefore mostly **conflict-semantics engineering**: you are not choosing tables and columns, you are choosing how two devices that edited the same data while offline will converge when they meet.

This skill turns agents into Ditto data-modeling experts: given an existing JSON shape (or a greenfield idea) plus context, produce a CRDT-aware collection design with per-field merge semantics, split points, and size/bandwidth budgets.

## When to use / when not to use

**Use this skill when:** the user shows you a JSON document and asks how to store it in Ditto; asks whether to embed or split collections; hits lost-update conflicts; hits document size warnings; plans sync over Bluetooth LE; migrates from MongoDB/SQL/another document store; or asks how to model counters, votes, inventory, presence, audit trails, or attachments.

**Do not use this skill when:** the user needs DQL statement syntax (SELECT/INSERT/UPDATE/JOIN/EXPLAIN) — use the `write-dql` skill (`../dql/SKILL.md`). This skill reuses its syntax but focuses on model design.

## Step 0: strict mode — assumed `false` on every peer

**This skill assumes `dql_strict_mode = false` (lenient mode) on every peer, and all guidance and code examples here are written for that world.** It is the factory default on SDK 5.0.x/5.1.x and the required end-state on 4.14.x. The flag is per-peer, runtime-only (re-apply at every app start), and exists since 4.11.

What the flag actually controls — on **both writes and reads**:

| | `false` (lenient) — **the baseline** | `true` (strict) — legacy 4.14.x default |
|---|---|---|
| **Writes:** bare JSON object stores as | `MAP` (per-field merge) — the engine duck-types JSON into CRDT intent; scalars and arrays stay `REGISTER` | `REGISTER` (whole-object last-write-wins) |
| **Writes:** `MAP`/`REGISTER` keywords | **Not needed — do not write them.** The inferred default *is* the correct behavior | **Required** on every non-REGISTER field, or it silently stores as `REGISTER` |
| **Reads:** type declarations in `SELECT` | **Not needed — do not write them.** Reads return the most recent value of every field, whatever its CRDT type | **Required** — a MAP/COUNTER field the query doesn't re-declare is **left out of the result entirely, as if it never existed**. No error, no warning |

Only three declaration keywords survive in the lenient world, and none of them are strict-mode boilerplate: `COUNTER` and `ATTACHMENT` (inference can't guess them from a JSON value) and a deliberate `REGISTER` *override* on an object that must stay atomic. Everything else is keyword-free — on reads **and** writes.

**If any peer has `dql_strict_mode = true` (the 4.14.x factory default), migrate it to `false`** — mesh-wide, and *before* upgrading to v5, so the version jump changes no merge behavior: `ALTER SYSTEM SET dql_strict_mode = false` at every app start. While un-flipped strict peers remain in the mesh, declare MAP/COUNTER explicitly on the statements *those peers* execute — writes and reads. Migration playbook and mixed-mesh rules: [`references/versions.md`](references/versions.md).

With strict mode settled, confirm SDK version(s) — features vary independently: JOINs and composite indexes are 5.1+, `COUNTER` needs 4.14+. If the user hasn't said, ask: *"Which Ditto SDK version(s) will run this mesh — 4.14.x, 5.0.x, 5.1.x, or mixed? On 4.x, has `dql_strict_mode` been set to `false` yet?"* and get the rest of the intake context in one shot. The full intake checklist is [`references/workflow.md`](references/workflow.md) §1. Version matrix: [`references/versions.md`](references/versions.md).

## The intake questions (ask before designing)

A recommendation made without these facts is a guess. Ask the ones the user hasn't volunteered — details and why each matters: [`references/workflow.md`](references/workflow.md) §1.

1. **SDK version(s)** — including whether 4.14.x and 5.x peers will share a mesh, and whether every 4.x peer is migrated to `dql_strict_mode = false`.
2. **Who edits what, offline** — single-writer fields can stay simple; multi-writer fields drive MAP granularity, counters, or audit-log patterns.
3. **Transports** — BLE (~20 KB/s effective) changes the acceptable document size by orders of magnitude vs LAN/Big Peer.
4. **Target hardware/OS** — low-end Android storage and CPU are far slower than modern Apple silicon; budget accordingly.
5. **Document size & growth** — and whether any sub-structure is unbounded (logs, readings, messages).
6. **Binary payloads** — anything over ~250 KB belongs in an `ATTACHMENT`, not inline.
7. **Query patterns** — which fields are filtered/sorted (indexes), and whether queries would need JOINs (5.1+ only).
8. **Permission scopes — and what they're scoped *by*** (store, site, tenant, region, user). Permissions are enforced at query granularity, so scopes force collection boundaries; and rules can only see `_id`, so the scoping value has to be a subfield of a composite `_id`. `_id` is immutable, so this is decided at design time.
9. **Delete/retention expectations** — tombstones expire (7 days on Small Peers by default, tunable); plan soft deletes.

If the user just drops raw JSON and says "make this work", still ask at minimum about SDK version and concurrency (items 1–2); derive the rest from the JSON with the review rubric.

## Reviewing raw JSON: the flags that matter most

Walk every field with the full rubric in [`references/workflow.md`](references/workflow.md) §2. In priority order:

1. **Arrays are the sharp edge.** There is no per-element merge — an array is one last-write-wins `REGISTER` (even in v5 lenient mode). Two peers appending to the same array offline lose one append, silently. Model multi-writer or growable collections as a `MAP` keyed by ID, or as separate documents.
2. **Counter-shaped numbers.** Anything incremented/decremented by multiple peers (stock, likes, views, votes) must be `COUNTER` (4.14+) — `SET`-style arithmetic on a `REGISTER` loses updates on merge.
3. **Inline binary / large strings.** Base64 blobs, images, PDFs → `ATTACHMENT` (out-of-band, content-addressed, lazy-fetched, exempt from document size limits). **Exception:** the MongoDB Connector does not carry attachments, so on connector-synced collections inline base64 is currently the recommended approach — with the size budget then doing all the work. See [`best-practices.md`](best-practices.md).
4. **Nested objects need no type declarations.** Under the lenient baseline they infer as MAPs (per-field merge) at any depth — that's the correct behavior, keyword-free. Declare only to *override* (force `REGISTER` on an object that must stay atomic). The one exception: un-migrated 4.14.x strict peers silently store bare objects as whole-object `REGISTER`s and drop undeclared MAP/COUNTER fields from reads — migrate them to `false`; declare only on statements strict peers still execute.
5. **`_id` shape.** Ditto `_id`s can be objects, and permission rules can see *only* `_id`. If the document is scoped by anything (store, site, tenant, region, org), that value belongs inside a composite object `_id` — `{ 'store_id': 42, 'order_id': 'o-1' }`. The subfields are ordinary queryable, indexable paths (`WHERE _id.store_id = 42`, `CREATE INDEX … ON orders (_id.store_id)`), so don't copy them into the document body. Delimiter-joined string `_id`s (`'store42:order-77'`) are a migration smell, not a composite key. `_id` is immutable, so this is expensive to fix later. Full rule: `COMPOSITE_ID` in [`references/workflow.md`](references/workflow.md) §2.
6. **Size & bandwidth budget.** Soft warning at 256 KiB serialized (includes CRDT metadata); hard limit at 5 MiB — **5.1+ rejects oversized local writes** (4.14.x/5.0.x only log), while replicated oversized docs are still accepted today. Over BLE, even 250 KiB is 10+ seconds of one peer's airtime. Budget math and hardware context: [`references/performance.md`](references/performance.md).

## Embedded vs split collections

Default pattern (from Ditto's own guidance): **denormalize related data into one document, with sub-entities as `MAP`s keyed by ID.** A single write is atomic, maps merge concurrent edits cleanly, and nested maps cost nothing extra — until one of the split triggers fires:

- The sub-entity is unbounded (logs, readings, messages, comments) → separate collection, one doc per item, keyed back by parent `_id`.
- The document would breach the size budget → split the heavy part (or move binaries to `ATTACHMENT`).
- Different permission scopes → separate collections (Big Peer permissions are query-level).
- The sub-entity is read/written independently at scale → separate collection with an index.

On 5.1+, reassemble with `JOIN` (requires the right-side key to be `_id` or indexed; Small Peers only — no joins on Big Peer or in `registerSubscription`). On 4.14.x there are **no joins** — either fetch both collections in app code or duplicate read-time fields with `ON ID CONFLICT DO UPDATE_LOCAL_DIFF`-friendly denormalization. Full guidance: [`best-practices.md`](best-practices.md) and [`examples/relational-migration.md`](examples/relational-migration.md).

## Where to look

| If you're doing this... | Read |
|---|---|
| Running the intake interview + JSON review rubric + output format | `references/workflow.md` |
| Choosing REGISTER vs MAP vs COUNTER vs PN_COUNTER vs ATTACHMENT | `references/crdt-types.md` |
| Checking what a given SDK version supports / strict mode + migration | `references/versions.md` |
| Sizing documents, budgeting sync over BLE/LAN, observer/batch costs | `references/performance.md` |
| Patterns/anti-patterns: audit logs, soft delete, schema evolution, smart upserts | `best-practices.md` |
| Worked example: e-commerce/POS order | `examples/order-management.md` |
| Worked example: chat with media | `examples/chat-messaging.md` |
| Worked example: IoT time-series | `examples/iot-timeseries.md` |
| Worked example: MongoDB/SQL-style JSON → collections, JOIN vs denormalize | `examples/relational-migration.md` |

## Recommending: the output contract

When delivering a design, produce (format detail: [`references/workflow.md`](references/workflow.md) §3):

1. **Findings** — every flagged field/shape with its rubric ID (e.g. `ARRAY_LWW`, `COUNTER_CANDIDATE`, `ATTACHMENT_CANDIDATE`, `COMPOSITE_ID`, `SIZE_SOFT`, `SPLIT_UNBOUNDED`, `DECLARE_TYPES`), severity, and one-line reason.
2. **Recommended model** — collections with per-field CRDT types and a pasteable `INSERT` statement (type declarations only where inference can't help: `COUNTER`, `ATTACHMENT`, deliberate `REGISTER` overrides).
3. **Split decisions** — what moved out, the back-reference key, and how reads reassemble (`JOIN` on 5.1+, two fetches on 4.14.x).
4. **Budget notes** — estimated serialized size, BLE implication, observer scope.

## Things that bite people

- **Omitting a key from a MAP write means "no change"**, not "delete". Remove one entry with dotted-path `UNSET` (`` UNSET items.`SKU-100` ``) — each removal writes a per-key tombstone. Needing to clear *thousands* of keys is a modeling smell, not a tuning problem: the entries should have been documents in a child collection. `UNSET` the parent field to buy time, then re-model ([`references/performance.md`](references/performance.md)).
- **A MAP overwrite merges; a REGISTER overwrite replaces.** `SET profile = {...}` on a MAP keeps untouched sub-fields; on a REGISTER the whole old object is gone.
- **Inserting a plain integer without declaring `COUNTER` creates a `REGISTER`** that can never merge increments. (Lenient mode auto-creates a counter from `APPLY … INCREMENT BY` on an undeclared field — don't rely on it: seeding an initial value on INSERT still needs the declaration, and un-migrated strict peers can't see undeclared counters. Always declare `COUNTER`; same trap for PN_COUNTER + plain doubles.)
- **`_id` is immutable and never a CRDT** — you cannot declare a type for it or update it. Prefer a composite **object** `_id` wherever a permission scope exists: rules see nothing but `_id`, and subfields stay queryable and indexable. Composite *string* `_id`s (`'store42:order-77'`) are the anti-pattern.
- **Nested arrays inside MAPs are still whole-array LWW registers** — the array rule applies at every depth.
- **Tombstone TTL** — mesh deletes propagate via tombstones that expire after 7 days on Small Peers, 30 on Big Peer. Those are defaults and are tunable (`TOMBSTONE_TTL_HOURS` on a peer; Big Peer via Ditto support). A peer offline longer than that can resurrect a deleted document. Prefer soft deletes for anything with a compliance/retention story.
- **Strict mode (`true`) silently drops fields from reads** — on a strict peer, a MAP or COUNTER field written *with* a declaration is stored correctly but omitted from plain `SELECT` results unless the query repeats the declaration (`SELECT ... FROM COLLECTION c (field MAP)`). No error — the field is gone as if it never existed. Lenient peers never need read declarations; this trap is why every 4.14.x mesh migrates to `dql_strict_mode = false`.
- **One statement per `execute()` call** — DQL rejects multi-statement strings (`;`-separated); run cookbook blocks statement by statement. `--` comments are tolerated.

## Compatibility

This skill covers **Ditto SDK 4.14.x (LTS), 5.0.x, and 5.1.x**, with 5.1.x as the headlining target. Every version-gated claim is tagged inline (`4.14+`, `5.0+`, `5.1+`); the matrix lives in [`references/versions.md`](references/versions.md). DQL syntax beyond what modeling declarations need (JOIN grammar, EXPLAIN, indexing, mutators) is in the `write-dql` skill — [`../dql/references/versions.md`](../dql/references/versions.md).
