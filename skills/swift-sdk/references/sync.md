# Sync subscriptions, scopes and status — Ditto Swift SDK

*What* a subscription is, how it propagates through the mesh, and which queries a
subscription accepts belong to the `sync-subscriptions` skill, or
<https://docs.ditto.com/sdk/latest/sync/syncing-data>. This file is the Swift call shape.

## CAP-07 Sync subscriptions and sync scopes

### Registering

```swift
let subscription = try ditto.sync.registerSubscription(
    query: "SELECT * FROM cars WHERE mileage > :minimumMileage",
    arguments: ["minimumMileage": 100]
)
```

There is a `Codable` overload for typed arguments:

```swift
struct CarFilter: Codable { let minimumMileage: Int }

let subscription = try ditto.sync.registerSubscription(
    query: "SELECT * FROM cars WHERE mileage > :minimumMileage",
    arguments: CarFilter(minimumMileage: 100)
)
```

`registerSubscription` is `@discardableResult`, which makes it easy to drop the handle by
accident. Keep it: **the handle is the only way to cancel**, not the thing that keeps the
subscription alive.

### Introspecting and cancelling

```swift
subscription.queryString            // String
subscription.queryArguments         // [String: Any?]?
subscription.queryArgumentsJSONData // Data?   (v5 only)
subscription.queryArgumentsCBORData // Data?   (v5 only)
subscription.isCancelled            // Bool
subscription.cancel()
```

All **executed**. A cancelled subscription reports `isCancelled == true` and disappears
from `ditto.sync.subscriptions`.

### `ditto.sync.subscriptions` is computed — do not cache it

In v5 it is recomputed from the SDK on every read, not a stored `Set`
(`sdk-release-5.1.0:sdks/swift/DittoSwift/DittoSync.swift:83`). A snapshot taken once and
held goes stale and never updates — **executed**: a set captured before a registration
still reported empty afterwards, while a fresh read reported one subscription. The same
applies to `ditto.store.observers`.

This is a natural mistake when porting v4 code, where both were stored properties, and it
produces no compile error.

### Sync scopes are DQL, not a Swift type

There is no `SyncScope` type in the Swift SDK. Scopes are set with `ALTER SYSTEM`:

```swift
try await ditto.store.execute(
    query: "ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES = :syncScopes",
    arguments: ["syncScopes": ["local_mesh_orders": "SmallPeersOnly"]]
)
try ditto.sync.start()
```

**This must run before `ditto.sync.start()`** or data may sync somewhere you did not
intend (`sdk/latest/sync/sync-scopes.mdx`). Read the current value back with
`SHOW USER_COLLECTION_SYNC_SCOPES`. Both **executed**.

> The published Swift sample at `sdk/latest/sync/sync-scopes.mdx:69-76` calls
> `await ditto.store.execute(...)` with no `try` on a `throws` method, so it does not
> compile. The form above is the corrected one and is exercised by the fixture.

`ALTER SYSTEM` settings are held in memory and are not persisted to disk
(`sdk/latest/sync/using-alter-system.mdx`), so they must be re-applied on every launch,
before sync starts. Statement grammar belongs to the `dql` skill or
<https://docs.ditto.com/dql/alter-system>.

## CAP-14 Sync status and local commit tracking

### Is sync running?

```swift
try ditto.sync.start()
ditto.sync.isActive   // true
ditto.sync.stop()
ditto.sync.isActive   // false
```

`isActive` answers "did I start sync", **not** "am I connected to anything". It is `true`
on an offline-only peer with every radio off. For reachability, read the presence graph —
[presence.md](presence.md).

### Local commits

`DittoQueryResult.commitID` is the store's commit identifier for a mutation:

| Statement | `commitID` |
|---|---|
| `INSERT` / `UPDATE` / `DELETE` / `EVICT` outside a transaction | present |
| `SELECT` | `nil` |
| any statement **inside** a transaction | `nil` |

All three **executed**. Inside a transaction there is no commit yet, so an app that wants
a commit identifier has to run the statement outside one.

`DittoQueryResult.mutatedDocumentIDs()` returns the `DittoDocumentID`s a mutation touched
— **executed**: one insert reports one ID. It is empty for a `SELECT`.

To observe *when* data arrives rather than when it was written locally, register a store
observer ([observers.md](observers.md)); an observer fires on every change to its result
set regardless of which peer caused it.

### Cloud sync status

Whether this peer currently has a route to Ditto Server is
`presence.graph.localPeer.isConnectedToDittoServer` (renamed from
`isConnectedToDittoCloud` in v5). See [presence.md](presence.md).
