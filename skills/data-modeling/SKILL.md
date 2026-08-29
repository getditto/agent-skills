---
name: data-modeling
description: Use when designing, reviewing, or migrating data models/schemas for Ditto (the CRDT-based peer-to-peer database). Covers REGISTER vs MAP vs COUNTER vs ATTACHMENT merge semantics, strict-mode defaults (SDK 4.14.x LTS vs 5.0.x/5.1.x), converting existing JSON documents into CRDT-friendly collections, embedding vs splitting collections (JOINs are 5.1+), document size limits, and sync performance across hardware and transports (BLE, LAN). Confirm the SDK version first — defaults and features vary.
allowed-tools: Read, Grep, Glob, Edit, Write
---

# Data Modeling for Ditto

Ditto stores JSON-like documents backed by CRDTs. Every field is a CRDT whose type — `REGISTER`, `MAP`, `COUNTER`, `PN_COUNTER`, `ATTACHMENT` — decides how concurrent offline edits merge. Data modeling for Ditto is therefore mostly **conflict-semantics engineering**: you are not choosing tables and columns, you are choosing how two devices that edited the same data while offline will converge when they meet.

This skill turns agents into Ditto data-modeling experts: given an existing JSON shape (or a greenfield idea) plus context, produce a CRDT-aware collection design with explicit type declarations, split points, and size/bandwidth budgets.

## When to use / when not to use

**Use this skill when:** the user shows you a JSON document and asks how to store it in Ditto; asks whether to embed or split collections; hits lost-update conflicts; hits document size warnings; plans sync over Bluetooth LE; migrates from MongoDB/SQL/another document store; or asks how to model counters, votes, inventory, presence, audit trails, or attachments.

**Do not use this skill when:** the user needs DQL statement syntax (SELECT/INSERT/UPDATE/JOIN/EXPLAIN) — use the `write-dql` skill (`../dql/SKILL.md`). This skill reuses its syntax but focuses on model design.

## Step 0: confirm SDK version(s), or assumptions will be wrong

The single biggest behavioral difference in Ditto modeling is the strict-mode default flip:

| SDK line | Status | `dql_strict_mode` default | Bare object value stores as |
|---|---|---|---|
| 4.14.x | LTS | `true` (strict) | `REGISTER` (whole-object last-write-wins) |
| 5.0.x / 5.1.x | Current | `false` (lenient) | `MAP` (per-field merge) |

If the user hasn't said which SDK they're on, ask: *"Which Ditto SDK version(s) will run this mesh — 4.14.x, 5.0.x, 5.1.x, or mixed?"* and get the rest of the intake context in one shot. The full intake checklist is [`references/workflow.md`](references/workflow.md) §1. Version matrix: [`references/versions.md`](references/versions.md).

**Portability rule that overrides everything:** declare CRDT types explicitly on every write statement (`INSERT INTO COLLECTION c (field MAP, …)`). Then the strict-mode default on any peer in the mesh can't reshape the data. Never rely on the default.

## The intake questions (ask before designing)

A recommendation made without these facts is a guess. Ask the ones the user hasn't volunteered — details and why each matters: [`references/workflow.md`](references/workflow.md) §1.

1. **SDK version(s)** — including whether 4.14.x and 5.x peers will share a mesh.
2. **Who edits what, offline** — single-writer fields can stay simple; multi-writer fields drive MAP granularity, counters, or audit-log patterns.
3. **Transports** — BLE (~20 KB/s effective) changes the acceptable document size by orders of magnitude vs LAN/Big Peer.
4. **Target hardware/OS** — low-end Android storage and CPU are far slower than modern Apple silicon; budget accordingly.
5. **Document size & growth** — and whether any sub-structure is unbounded (logs, readings, messages).
6. **Binary payloads** — anything over ~250 KB belongs in an `ATTACHMENT`, not inline.
7. **Query patterns** — which fields are filtered/sorted (indexes), and whether queries would need JOINs (5.1+ only).
8. **Permission scopes** — Big Peer sync permissions are enforced at query granularity, which can force collection boundaries.
9. **Delete/retention expectations** — tombstones expire (7 days on Small Peers); plan soft deletes.

If the user just drops raw JSON and says "make this work", still ask at minimum about SDK version and concurrency (items 1–2); derive the rest from the JSON with the review rubric.

## Reviewing raw JSON: the five flags that matter most

Walk every field with the full rubric in [`references/workflow.md`](references/workflow.md) §2. In priority order:

1. **Arrays are the sharp edge.** There is no per-element merge — an array is one last-write-wins `REGISTER` (even in v5 lenient mode). Two peers appending to the same array offline lose one append, silently. Model multi-writer or growable collections as a `MAP` keyed by ID, or as separate documents.
2. **Counter-shaped numbers.** Anything incremented/decremented by multiple peers (stock, likes, views, votes) must be `COUNTER` (4.14+) — `SET`-style arithmetic on a `REGISTER` loses updates on merge.
3. **Inline binary / large strings.** Base64 blobs, images, PDFs → `ATTACHMENT` (out-of-band, content-addressed, lazy-fetched, exempt from document size limits).
4. **Nested objects without declared types.** In v4 they silently become monolithic `REGISTER`s (whole-object overwrite on conflict). Declare `MAP` explicitly everywhere.
5. **Size & bandwidth budget.** Soft warning at 256 KiB serialized (includes CRDT metadata); hard limit at 5 MiB — **5.1+ rejects oversized local writes** (4.14.x/5.0.x only log), while replicated oversized docs are still accepted today. Over BLE, even 250 KiB is 10+ seconds of one peer's airtime. Budget math and hardware context: [`references/performance.md`](references/performance.md).

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
| Checking what a given SDK version supports / strict-mode flip | `references/versions.md` |
| Sizing documents, budgeting sync over BLE/LAN, observer/batch costs | `references/performance.md` |
| Patterns/anti-patterns: audit logs, soft delete, schema evolution, smart upserts | `best-practices.md` |
| Worked example: e-commerce/POS order | `examples/order-management.md` |
| Worked example: chat with media | `examples/chat-messaging.md` |
| Worked example: IoT time-series | `examples/iot-timeseries.md` |
| Worked example: MongoDB/SQL-style JSON → collections, JOIN vs denormalize | `examples/relational-migration.md` |

## Recommending: the output contract

When delivering a design, produce (format detail: [`references/workflow.md`](references/workflow.md) §3):

1. **Findings** — every flagged field/shape with its rubric ID (e.g. `ARRAY_LWW`, `COUNTER_CANDIDATE`, `ATTACHMENT_CANDIDATE`, `SIZE_SOFT`, `SPLIT_UNBOUNDED`, `DECLARE_TYPES`), severity, and one-line reason.
2. **Recommended model** — collections with per-field CRDT types and an `INSERT INTO COLLECTION … (…)` declaration the user can paste.
3. **Split decisions** — what moved out, the back-reference key, and how reads reassemble (`JOIN` on 5.1+, two fetches on 4.14.x).
4. **Budget notes** — estimated serialized size, BLE implication, observer scope.

## Things that bite people

- **Omitting a key from a MAP write means "no change"**, not "delete". Remove one entry with dotted-path `UNSET` (`` `UNSET items.`SKU-100``` ``) — each removal writes a per-key tombstone, so for mass clearing `UNSET` the parent field instead.
- **A MAP overwrite merges; a REGISTER overwrite replaces.** `SET profile = {...}` on a MAP keeps untouched sub-fields; on a REGISTER the whole old object is gone.
- **Inserting a plain integer without declaring `COUNTER` creates a `REGISTER`** that can never merge increments. (Lenient mode auto-creates a counter from `APPLY … INCREMENT BY` on an undeclared field — don't rely on it: strict-mode peers can't see undeclared counters. Always declare the type; same trap for PN_COUNTER + plain doubles.)
- **`_id` is immutable and never a CRDT** — you cannot declare a type for it or update it. Composite-object `_id`s are supported and useful as permission partition keys.
- **Nested arrays inside MAPs are still whole-array LWW registers** — the array rule applies at every depth.
- **Tombstone TTL** — mesh deletes propagate via tombstones that expire after 7 days on Small Peers (30 on Big Peer). A peer offline longer than that can resurrect a deleted document. Prefer soft deletes for anything with a compliance/retention story.
- **Strict-mode read trap (4.14.x)** — a MAP or COUNTER field written with a declaration is *stored* correctly but silently missing from plain `SELECT` on a strict peer unless the read repeats the declaration (`SELECT ... FROM COLLECTION c (field MAP)`). No error — just absent fields.
- **One statement per `execute()` call** — DQL rejects multi-statement strings (`;`-separated); run cookbook blocks statement by statement. `--` comments are tolerated.

## Compatibility

This skill covers **Ditto SDK 4.14.x (LTS), 5.0.x, and 5.1.x**, with 5.1.x as the headlining target. Every version-gated claim is tagged inline (`4.14+`, `5.0+`, `5.1+`); the matrix lives in [`references/versions.md`](references/versions.md). DQL syntax beyond what modeling declarations need (JOIN grammar, EXPLAIN, indexing, mutators) is in the `dql` skill — [`../dql/references/versions.md`](../dql/references/versions.md).
