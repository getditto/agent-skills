---
name: sync-subscriptions
description: Use when designing, explaining, or debugging Ditto sync subscriptions (registerSubscription) — subscription query rules (SELECT * only, no projections/JOINs/GROUP BY/DISTINCT/USE IDS, LIMIT and ORDER BY rejected on SDK 5.x), how subscriptions propagate across the peer-to-peer mesh, multi-hop transitive sync and document flooding, and why a peer is missing documents. Conceptual and language-agnostic; not per-language API syntax.
---

# Ditto Sync Subscriptions

Conceptual guide to Ditto's query-based sync: what subscriptions are, what
they can express, and how they shape which documents flow through the
peer-to-peer mesh. Language-agnostic — for `registerSubscription` call syntax
in a specific SDK, see the Ditto docs
([Managing Subscriptions](https://docs.ditto.live/sdk/latest/sync/syncing-data)).

Covers Ditto SDK 4.14.x (LTS), 5.0.x, and 5.1.x. Version-specific behavior is
tagged inline.

## When to use / when not to use

Use this skill when:

- Designing what data each device or role should subscribe to.
- A peer is missing documents you expected it to have — especially in
  multi-hop topologies where peers connect through intermediate peers.
- A subscription query is rejected (e.g. `<dql> Unsupported feature: A
  projection other than wildcard (*)`).
- Deciding how to structure collections so subscriptions stay simple.

Do not use this skill for:

- Reading data already on the local device — that is a store query or
  observer, independent of subscriptions (see the `write-dql` skill).
- Per-language `registerSubscription` API syntax — that lives in the Ditto SDK
  docs and (planned) per-language skills.

## The mental model

A sync subscription is a DQL `SELECT` statement that declares **what this peer
wants other peers to send it**. It is not a query against the local database —
it runs against the *mesh*:

1. The app starts sync and registers a subscription query, e.g.
   `SELECT * FROM cars WHERE color = 'blue'`.
2. Ditto shares that query with every connected peer (and re-shares it
   whenever subscriptions change).
3. Any peer holding documents that match the query sends them — first the
   existing matches (initial sync), then every matching change as it happens
   (incremental sync), as field-level deltas.
4. The same subscription rules apply whether the other side is a nearby
   device or the Ditto Server (Big Peer).

Consequences that follow directly from the model:

- **Subscriptions are receive-side filters.** They control what flows *in*,
  not what the device keeps or can read. Local writes always land in the local
  store regardless of subscriptions, and local queries can read everything in
  the local store.
- **The subscription is in memory; the data it syncs is in the store.** The
  registration itself is not persisted and must be re-registered every time
  the app starts (typically right after `startSync`) — but the documents it
  already pulled in are in the local store and survive restarts. (Not in the
  browser: the JS SDK's store is in-memory only, so a web peer re-syncs
  everything each session.)
- **Subscriptions and reading data are separate concerns.** A subscription
  copies matching documents into the local store; an **observer** runs a
  query against that store and returns results in memory, with change
  callbacks. Neither substitutes for the other — production apps use both.
- **Attachments are the exception.** Attachment *data* is not synced by a
  subscription under the default settings — documents carry an attachment
  token and the binary is fetched explicitly. Set
  `ALTER SYSTEM SET attachments_auto_fetch = true` if you want the bytes to
  flow with matching documents automatically.

Full lifecycle detail (delta sync, dedup/refcounting, cancel semantics):
[`references/how-subscriptions-work.md`](references/how-subscriptions-work.md).

## What a subscription query can express

Subscription queries are deliberately a restricted subset of DQL. The single
most important rule: **subscriptions must be `SELECT *`** — there is no way to
sync only some fields of a document.

| Query feature | In a subscription? | Rejection message (SDK 5.1.x) |
|---|---|---|
| `SELECT *` (wildcard) | Required | — |
| Projections (`SELECT make, model ...`) | No | `Unsupported feature: A projection other than wildcard (*)` |
| `WHERE` on one collection | Yes | — |
| `USE INDEX` / directives | Yes (planner hints honoured) | — |
| JOIN / multiple collections in `FROM` | No | `Unsupported feature: Joining` (4.14.x/5.0.x: parse error) |
| `USE IDS` | No | `Unsupported feature: USE IDS` (4.14.x/5.0.x: lowercase `use ids`) |
| `DISTINCT` | No | `Unsupported feature: DISTINCT` |
| `GROUP BY` / `HAVING` | No | `Unsupported feature: Grouping` |
| Aggregate functions (`COUNT`, `SUM`, …) | No (unreachable — only legal in projections/HAVING/ORDER BY) | — |
| `LIMIT` / `ORDER BY` | **4.14.x:** allowed, stateful, discouraged. **5.x:** rejected by default | `Unsupported feature: Limit or Order by` |
| Non-`SELECT` statements | No | `Unsupported feature: non-SELECT statement in sync subscription` |

The `LIMIT`/`ORDER BY` row is the version-sensitive one: SDK 4.14.x accepts
them, while SDK 5.0+ rejects them. A subscription using `LIMIT` maintains
boundary state and can be expensive; `ORDER BY` makes that cost worse when
combined with `LIMIT`. (`OFFSET` alone is accepted on every supported SDK
version.)
Details, exact error strings, and the reasons behind the restrictions:
[`references/query-limitations.md`](references/query-limitations.md).

If you need to sync "only part of a document", the answer is data modeling,
not query syntax: split rarely-needed or bulky fields into a separate
collection (with its own subscription) or into an attachment.

## Mesh propagation and flooding

Sync sessions are **pairwise**: each pair of connected peers tracks what the
other holds and what the other wants. (SDK 5.1 adds an opt-in multicast sync
beta that replicates per group instead of per pair; this skill describes the
default pairwise transports.) Two rules explain almost every
"why doesn't this device have my data" question:

1. **A peer sends from what it *holds*, filtered by the *recipient's*
   subscriptions** — never by its own subscriptions. Anything in the local
   store that matches a connected peer's query is offered to that peer.
2. **A peer can only hold what it wrote itself or what flowed in matching
   its *own* subscriptions.** Holding is the bottleneck.

Sync is **transitive** (flood-fill): documents hop across the mesh through
intermediate peers, with no hop limit. But because of rule 2, an intermediate
peer is not a transparent pipe — it can only forward the slice of data it
actually holds.

The canonical failure case — peers A and C want the same data but only
connect through peer B, which subscribes to a subset:

```
Peer A                    Peer B                       Peer C
subscribes: all cars      subscribes: blue cars only   subscribes: all cars
holds: 100 cars  ──────▶  holds: 10 blue cars  ──────▶  receives: 10 blue cars
                  sends only                   relays only    (never the other 90 —
                  what matches                 what it holds   B cannot forward
                  B's subs                     matching C's    what it never got)
```

C stays partial until it connects (directly or transitively) to a peer that
holds the rest — e.g. a direct A↔C connection. Full walkthrough, more
scenarios, and the loop-suppression mechanism:
[`references/mesh-and-flooding.md`](references/mesh-and-flooding.md) and
[`examples/mesh-scenarios.md`](examples/mesh-scenarios.md).

## Things that bite people

1. **Trying to project fields in a subscription.** Rejected outright —
   `SELECT *` only. Split collections instead.
2. **Assuming a relay peer forwards everything.** It forwards only what it
   *holds*; its own subscriptions bound what it holds. Audit every hop, not
   just the endpoints.
3. **Re-registering a subscription with new arguments to filter a view.**
   Subscriptions should be stable; filter locally with a store query instead.
4. **Forgetting subscriptions don't survive restarts.** Register them at app
   start, every time.
5. **Expecting documents to disappear when they stop matching.** They don't —
   the peer gets one final update and keeps its copy. Removal is explicit
   (`EVICT` for local-only, `DELETE` for mesh-wide).
6. **`LIMIT`/`ORDER BY` subscriptions on mutable fields** (4.14.x, or 5.x with
   the restriction disabled): every boundary change invalidates and
   re-evaluates. See
   [best-practices.md](best-practices.md).
7. **C++ and Rust:** dropping the subscription handle does **not** cancel it —
   call `cancel()` explicitly or it keeps replicating until the Ditto instance
   is destroyed.

## Where to look

| If you're asking... | Read |
|---|---|
| How do subscriptions work end to end? Lifecycle, delta sync, cancel/dedup semantics | [`references/how-subscriptions-work.md`](references/how-subscriptions-work.md) |
| Exactly which query features are rejected, with what errors, on which SDK versions, and why | [`references/query-limitations.md`](references/query-limitations.md) |
| How subscriptions propagate through the mesh; the A→B→C subset problem; flooding mechanics | [`references/mesh-and-flooding.md`](references/mesh-and-flooding.md) |
| Worked multi-hop scenarios (subset relay, late direct connection, relay-owned documents) | [`examples/mesh-scenarios.md`](examples/mesh-scenarios.md) |
| Designing and operating subscriptions in production | [`best-practices.md`](best-practices.md) |

Canonical docs: [Syncing Data](https://docs.ditto.live/key-concepts/syncing-data)
(concepts) · [Managing Subscriptions](https://docs.ditto.live/sdk/latest/sync/syncing-data)
(SDK API) · [Sync Handling](https://docs.ditto.live/best-practices/sync-handling)
(operations) · [Stateful Subscription Performance](https://docs.ditto.live/stateful-subscriptions)
(`LIMIT`/`ORDER BY`).
