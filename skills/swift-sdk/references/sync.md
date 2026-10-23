# Sync subscriptions, scopes and status — Ditto Swift SDK

*What* a subscription is, how it propagates through the mesh, and which queries a
subscription accepts belong to the `sync-subscriptions` skill, or
<https://docs.ditto.live/sdk/latest/sync/syncing-data>. This file is the Swift call shape.

## CAP-07 Sync subscriptions and sync scopes

### Registering

```swift
let subscription = try ditto.sync.registerSubscription(
    query: "SELECT * FROM cars WHERE mileage > :minimumMileage",
    arguments: ["minimumMileage": 100]
)
```

**On v5 only**, there is a `Codable` overload for typed arguments:

```swift
struct CarFilter: Codable { let minimumMileage: Int }

let subscription = try ditto.sync.registerSubscription(
    query: "SELECT * FROM cars WHERE mileage > :minimumMileage",
    arguments: CarFilter(minimumMileage: 100)
)
```

4.14.x has only the `[String: Any?]` overload, so this does not compile there. If one source tree must build against all three lines, use the dictionary form.

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

A cancelled subscription reports `isCancelled == true` and disappears
from `ditto.sync.subscriptions`.

### `ditto.sync.subscriptions` is computed — do not cache it

In v5 it is recomputed from the SDK on every read, not a stored `Set`. A snapshot taken
once and held goes stale and never updates — read it at the point of use. The same
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
intend (<https://docs.ditto.live/sdk/latest/sync/sync-scopes>). Read the current value
back with `SHOW USER_COLLECTION_SYNC_SCOPES`. `execute` throws, so the call needs `try`.

Re-apply sync scopes on every launch, before sync starts. Why — `ALTER SYSTEM` settings
are not persisted — and the statement grammar both belong to the `write-dql` skill, or
<https://docs.ditto.live/dql/alter-system>.

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

Inside a transaction there is no commit yet, so an app that wants a commit identifier has
to run the statement outside one.

`DittoQueryResult.mutatedDocumentIDs()` returns the `DittoDocumentID`s a mutation touched
— one per document an insert wrote, and none for a `SELECT`.

To observe *when* data arrives rather than when it was written locally, register a store
observer ([observers.md](observers.md)); an observer fires on every change to its result
set regardless of which peer caused it.

### Cloud sync status

Whether this peer currently has a route to Ditto Server is
`presence.graph.localPeer.isConnectedToDittoServer` (renamed from
`isConnectedToDittoCloud` in v5). See [presence.md](presence.md).
