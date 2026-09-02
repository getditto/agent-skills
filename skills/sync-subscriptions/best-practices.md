# Subscription Best Practices

Operational guidance for designing and running subscriptions in production.
Condensed from the Ditto docs'
[Sync Handling](https://docs.ditto.live/best-practices/sync-handling) and
validated against SDK behavior (4.14.x / 5.0.x / 5.1.x).

## Scope subscriptions narrowly

Subscribe to the smallest set of documents each device actually needs —
partition by tenant, region, role, or whatever dimensions fit your data —
instead of syncing whole collections everywhere. Every matched document costs
bandwidth, storage, and CPU on every device that holds or relays it.

## Keep subscriptions stable

Every registration, cancellation, or argument change makes the mesh
re-evaluate what it owes your device. As a guideline, don't change
subscriptions more often than roughly every fifteen minutes:

- Register at app start, after login, or when the user enters a workspace.
- Cancel when the data stops being relevant.
- To change what the *user sees*, run a local query with new filters against
  the already-synced data — do not re-register the subscription.
- Cancel dynamically created subscriptions as soon as they are obsolete; they
  stay active until explicitly cancelled and accumulate.

**C++ / Rust:** dropping the subscription handle does not cancel it — it
keeps replicating until the Ditto instance is destroyed. Always call
`cancel()` explicitly (or wrap the handle in an RAII guard that does).

## Design for flood-fill

- Within a device role, run the **same subscription shape** on every peer so
  any peer can serve any other (see
  [examples/mesh-scenarios.md](examples/mesh-scenarios.md), scenario 6).
- For relay-only devices, the subscription must cover the union of the data
  they are expected to carry — an under-subscribed relay silently starves
  everything downstream of it (see
  [references/mesh-and-flooding.md](references/mesh-and-flooding.md)).
- Prefer connectivity to the Ditto Server for paths that must never be
  partial; it typically holds all data.

## Keep subscription queries simple

- Prefer flat field comparisons (`field == value`, `field > value`) over
  deeply nested `AND`/`OR` trees and nested-object traversals — expensive to
  evaluate everywhere, and against the Ditto Server can degrade service for
  all connected peers (`503 Service Unavailable` on connect is a symptom).
- Beware programmatically generated `WHERE` clauses — inspect the final
  strings in debug logs.
- Split broad complex queries into several simple subscriptions.

## Avoid stateful subscriptions

Subscriptions using `LIMIT` maintain boundary state that invalidates on every
relevant change; combining `LIMIT` with `ORDER BY` adds sort-position
invalidations. SDK 5.x rejects both clauses in subscriptions. On 4.14.x, never
filter or sort on mutable fields when `LIMIT` is used. Details:
[references/query-limitations.md](references/query-limitations.md).

## Work with the model

- **Offline-first:** treat the local store as always available and
  connectivity as opportunistic; reads and writes never block on the mesh.
- **Conflict resolution is built in:** CRDT merge rules resolve concurrent
  edits deterministically — no locking or custom merge code.
- **Transports:** leave all relevant transports (LAN/Wi-Fi, BLE, WebSocket)
  enabled and let Ditto switch as devices move.
- **Attachments:** keep binaries out of subscribed documents; fetch them on
  demand via their tokens.
