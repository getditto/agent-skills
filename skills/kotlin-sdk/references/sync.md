# Sync subscriptions, scopes and status — Ditto Kotlin SDK

*What* a subscription is, how it propagates through the mesh, and which queries a
subscription accepts belong to the `sync-subscriptions` skill, or
<https://docs.ditto.live/sdk/latest/sync/syncing-data>. DQL grammar belongs to the
`write-dql` skill, or <https://docs.ditto.live/dql/dql>. This file is the Kotlin
(v5, `com.ditto.kotlin.*`) call shape.

## CAP-07 Sync subscriptions and sync scopes

### Registering

```kotlin
val subscription = ditto.sync.registerSubscription("SELECT * FROM cars")
```

With argument injection (`:argument` syntax in DQL):

```kotlin
val subscription = ditto.sync.registerSubscription(
    """
    SELECT *
    FROM cars
    WHERE color = :color
    """,
    mapOf("color" to "blue"),
)
```

`registerSubscription` returns a `DittoSyncSubscription`. Arguments accept a
plain `Map<String, Any?>` or a `DittoCborSerializable.Dictionary`
(sdk/latest/migration-guides/kotlin-v4).

**Retain the handle.** It is the only way to cancel the subscription later.

### Cancelling — `close()`, not `cancel()`

`DittoSyncSubscription` is `AutoCloseable` (via `DittoResource`). **Verified by
execution:** `subscription.close()` cancels it; there is **no** `cancel()`
method — calling one is `Unresolved reference: cancel`. The published docs
(sdk/latest/sync/syncing-data) agree: the Kotlin snippet uses
`subscription.close()` where other languages use `cancel()`.

```kotlin
subscription.close()
subscription.isClosed   // true once closed (the Kotlin name; other SDKs use isCancelled)
```

### Enumerating active subscriptions

```kotlin
val activeSubscriptions = ditto.sync.subscriptions
```

(sdk/latest/sync/syncing-data)

### Subscription query restrictions

A subscription describes *which* documents sync, not display order. In v5,
registering a query containing `LIMIT` or `ORDER BY` fails with
`<dql> Unsupported feature: Limit or Order by` — remove the clauses and sort or
page at query/render time in an `execute` or `registerObserver` query instead.
Joins in a subscription query likewise fail; subscribe to each collection
separately and join in the read query. Queries must be `SELECT *` — no
projections (sdk/latest/sync/syncing-data).

### Registering vs. sync state

The docs do not prescribe an ordering between `registerSubscription` and
`sync.start()`. What is documented (sdk/latest/sync/syncing-data): calling
`ditto.sync.stop()` disconnects from peers and **pauses** all active
subscriptions — the registrations survive a stop/start cycle.

### Sync scopes — DQL, not a Kotlin type

There is no `SyncScope` type in the Kotlin SDK. Scopes are set with
`ALTER SYSTEM` through `ditto.store.execute` (sdk/latest/sync/sync-scopes):

```kotlin
ditto.store.execute(
    query = "ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES = :syncScopes",
    arguments = mapOf("syncScopes" to mapOf(
        "local_mesh_orders" to "SmallPeersOnly",
    )),
)

try {
    ditto.sync.start()
} catch (e: DittoException) {
    // handle error
}
```

Scope values: `"AllPeers"` (default), `"BigPeerOnly"`, `"SmallPeersOnly"`,
`"LocalPeerOnly"`. Rules from the source page:

- **Must run before `ditto.sync.start()`** or data may sync somewhere you did
  not intend.
- Settings reset with each Ditto initialization (held in memory, not persisted)
  — re-apply after every new `Ditto` instance. Changes while sync is active are
  allowed but may take time to take effect.
- Read back with `SHOW USER_COLLECTION_SYNC_SCOPES`.
- Per-device, not shared with the mesh; enforced locally over other peers'
  subscriptions; cannot target system collections (`__` prefix).

Note: the `using-alter-system` page itself ships **no Kotlin sample** (Swift and
Java only) — **Support: no** Kotlin snippet there, but the call is the same
`ditto.store.execute(query = ...)` shape shown above from the sync-scopes page.
See that page for `SHOW ALL`, `ALTER SYSTEM SET ... = <value>` (both `=` and
`TO` forms), and `ALTER SYSTEM RESET [ALL | <setting>]` grammar.

## CAP-14 Sync status and local commit tracking

### start / stop / isActive

```kotlin
try {
    ditto.sync.start()
} catch (e: DittoException) {
    // handle error
}

ditto.sync.isActive   // true once started

ditto.sync.stop()     // declares no checked error — a try/catch here can never fire
```

Start sync in the top-most scope of the app and keep it running for the app
lifecycle. `stop()` disconnects from all peers and pauses subscriptions
(sdk/latest/sync/syncing-data).

**`isActive` answers "did I start sync", not "am I connected to anything".**
For connectivity and reachability, use presence — see
[presence.md](presence.md) (`ditto.presence.observe()` Flow;
`DittoPeer.isConnectedToDittoServer` for the cloud route).

**Android lifecycle note:** on Android, sync start/stop is typically tied to a
foreground service so the mesh stays alive off-UI — details in
[transports.md](transports.md).

### `system:data_sync_info` — per-peer sync status (SDK 4.12.0+)

A built-in, **local-only** collection reporting real-time sync status per peer
connection. It never syncs between peers; each peer has its own view
(sdk/latest/sync/monitoring-sync-status).

Document shape:

```json
{
  "_id": "peer-123",
  "is_ditto_server": true,
  "documents": {
    "sync_session_status": "Connected",
    "synced_up_to_local_commit_id": 1500,
    "last_update_received_time": 1703123456
  }
}
```

- `sync_session_status`: `"Connected"`, `"Not Connected"`, or `"Disabled"`
- `synced_up_to_local_commit_id`: highest local commit ID this peer has confirmed
- `last_update_received_time`: Unix timestamp of last data received

Querying from Kotlin (use the handler form of `execute`; read nested fields
with typed accessors on `DittoCborSerializable.Dictionary`, not casts):

```kotlin
ditto.store.execute("SELECT * FROM system:data_sync_info") { result ->
    result.items.forEach { item ->
        val peerId = item.value["_id"].stringOrNull ?: "unknown"
        val status = item.value["documents"].dictionaryOrNull
            ?.let { it["sync_session_status"].stringOrNull }
            ?: "Unknown"
        println("Peer $peerId: $status")
    }
}
```

Observing — supported, but the callback fires on a **fixed 500 ms interval**
regardless of whether the data changed:

```kotlin
// The DittoQueryResult is owned by the observer — don't wrap it in `use { }`,
// and don't return result.items out of the lambda.
val observer = ditto.store.registerObserver(
    "SELECT * FROM system:data_sync_info",
) { result ->
    result.items.forEach { item ->
        val peerId = item.value["_id"].stringOrNull ?: "unknown"
        val status = item.value["documents"].dictionaryOrNull
            ?.let { it["sync_session_status"].stringOrNull }
            ?: "Unknown"
        println("Peer $peerId: $status")
    }
}
```

API support matrix from the source page: `execute` ✅, `registerObserver` ✅,
`registerSubscription` ❌ (cannot subscribe to this collection), Big Peer HTTP
API ❌, in-memory-storage SDKs ❌.

Strict mode caveat: these queries assume `DQL_STRICT_MODE=false` (the v5
default). With strict mode on, declare the collection inline:

```sql
SELECT * FROM COLLECTION system:data_sync_info (documents MAP)
```

### Commit IDs — tracking local commits

Every `INSERT`, `UPDATE`, or `DELETE` returns a commit ID on its
`DittoQueryResult`; `SELECT` does not. In Kotlin the commit ID is a `ULong`
read via the handler form of `execute` (sdk/latest/sync/tracking-local-commits):

```kotlin
ditto.store.execute(
    "UPDATE cars SET color = 'blue' WHERE _id = '123'",
) { result ->
    println("Commit ID: ${result.commitId}")
}
```

Properties: monotonically increasing (not necessarily sequential),
device-specific, per-operation. To check whether a write reached a peer,
compare its commit ID with that peer's `synced_up_to_local_commit_id`:

```kotlin
// Step 1: Execute the write and capture its commit ID.
val commitId: ULong = ditto.store.execute(
    query = "UPDATE orders SET status = 'shipped' WHERE _id = :id",
    arguments = mapOf("id" to "order-456"),
) { result -> result.commitId!! }

// Step 2: Check if it synced to cloud.
ditto.store.execute(
    "SELECT * FROM system:data_sync_info WHERE is_ditto_server = true",
) { syncResult ->
    val item = syncResult.items.firstOrNull()
    val syncedUpTo = item?.value?.get("documents")?.dictionaryOrNull
        ?.let { it["synced_up_to_local_commit_id"].uLongOrNull }
        ?: 0u.toULong()

    if (syncedUpTo >= commitId) {
        println("Commit synced to cloud")
    } else {
        println("Syncing…")
    }
}
```

`synced_up_to_local_commit_id >= commitId` means the write reached **that
peer** — it is not a delivery receipt for the whole mesh.

To check a specific peer device instead of the cloud, filter on its `_id`:

```kotlin
ditto.store.execute(
    "SELECT * FROM system:data_sync_info WHERE _id = 'peer-device-456'",
) { syncResult ->
    val item = syncResult.items.firstOrNull() ?: return@execute
    val peerSyncedUpTo = item.value["documents"].dictionaryOrNull
        ?.let { it["synced_up_to_local_commit_id"].uLongOrNull }
    println("Peer has synced up to commit ${peerSyncedUpTo ?: "?"}")
}
```

For several in-flight writes, keep a `MutableList<ULong>` of commit IDs and
watch progress with a `registerObserver` on
`SELECT * FROM system:data_sync_info WHERE is_ditto_server = true`, removing
commits as `synced_up_to_local_commit_id` passes them (full Kotlin sample:
sdk/latest/sync/tracking-local-commits, "Monitoring Multiple Commits").

**Transaction behavior:** a commit ID is assigned only when the transaction
commits. Inside the block, `execute` reports `null`:

```kotlin
// Inside an explicit transaction, txnResult.commitId is null — nothing is
// committed yet. Result.Commit(value) carries whatever you captured, so the
// final value here is null too, NOT the assigned ID:
val captured: ULong? = (ditto.store.transaction { transaction ->
    transaction.execute(
        query = "INSERT INTO orders DOCUMENTS (:doc)",
        arguments = mapOf("doc" to mapOf("_id" to "order-123", "total" to 99.99))
    ) { txnResult ->
        DittoTransaction.Result.Commit(txnResult.commitId)   // null at this point
    }
} as? DittoTransaction.Result.Commit)?.value

println(captured ?: "null") // null — to learn the assigned commit ID, use a
                            // top-level execute (result.commitId is populated
                            // after auto-commit) or read system:data_sync_info
                            // afterwards, as shown above
```

Best practices from the source page: don't block user operations on sync
tracking (Ditto is offline-first), use it for progress UI on critical writes,
and prune old commit IDs from tracking lists.

## v4 → v5 notes

- `ditto.startSync()` / `ditto.stopSync()` → `ditto.sync.start()` /
  `ditto.sync.stop()`; `ditto.isSyncActive` → `ditto.sync.isActive`.
- Legacy `store.collection("cars").find("color == 'red'").subscribe()` is
  removed — use `ditto.sync.registerSubscription(dqlQuery, args)`. The legacy
  `DittoSubscription` type is gone.
- v4 subscriptions with `LIMIT`/`ORDER BY` do not migrate silently — v5
  rejects them at registration with `<dql> Unsupported feature: Limit or Order
  by`. Strip the clauses and sort at query time.

(sdk/latest/migration-guides/kotlin-v4)
