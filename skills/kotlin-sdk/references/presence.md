# Presence and connection requests — Ditto Kotlin SDK

> **Sources for this file.** `sdk/latest/sync/using-mesh-presence`,
> `sdk/latest/sync/handling-connection-requests`, and the verified
> `sdk/latest/migration-guides/kotlin-v4` PRESENCE / PEER & CONNECTION sections.
>
> **Do not restate mesh formation** — that is the `ditto-mesh-networking` skill.

## CAP-13 Presence graph and connection requests

Everything hangs off the `presence` namespace on the root `Ditto` object:

```kotlin
ditto.presence
```

### The graph

```kotlin
val graph = ditto.presence.graph
graph.localPeer             // DittoPeer — always present
graph.remotePeers           // List<DittoPeer> — other devices in the mesh
graph.serializeToJson()     // JSON String for diagnostics / a presence viewer
```

**v4 aside:** `DittoPresenceGraph.serializeToJson()` was `DittoPresenceGraph.json()`
(sdk/latest/migration-guides/kotlin-v4).

`DittoPeer` fields and their v4 spellings
(sdk/latest/migration-guides/kotlin-v4, PEER & CONNECTION):

| v5 | v4 | Notes |
|---|---|---|
| `peerKey: String` | `peerKeyString: String` | The v4 `peerKey: DittoPeerKey` (ByteArray) and the `DittoPeerKey` typealias, `toKeyString()`, and `decodePeerKey()` are all **removed** — the String form is the only one |
| `isConnectedToDittoServer: Boolean` | `isConnectedToDittoCloud: Boolean` | Renamed |
| `os: DittoPeerOs?` | `os: String?` | Now an enum: `Generic`, `Ios`, `Tvos`, `Android`, `Linux`, `Windows`, `MacOS` |
| `peerMetadata: DittoJsonSerializable.ObjectValue` | `Map<String, Any?>` | Type changed |
| `identityServiceMetadata: DittoJsonSerializable.ObjectValue` | `Map<String, Any?>` | Type changed |
| — | `queryOverlapGroup: Int` | **Removed** |

`DittoPeerOs.Tvos` is **deprecated in 5.1.0 but retained on purpose** so peers
running older SDK versions on tvOS can still be identified in the presence graph
(sdk/latest/release-notes-hub/kotlin). Keep handling it.

`DittoConnection` simplifies in v5: `peer1` and `peer2` are now plain `String`
peer keys (v4: deprecated `DittoPeerKey` fields plus `peerKeyString1` /
`peerKeyString2`), and `approximateDistanceInMeters` is **removed**
(sdk/latest/migration-guides/kotlin-v4).

### Observing the graph

`presence.observe()` is **Flow-based in v5** — it returns
`Flow<DittoPresenceGraph>` and takes no handler. Collect it in a
`CoroutineScope`; the upstream observer is cancelled with the scope, so no
manual `close()` is needed:

```kotlin
lifecycleScope.launch {
    ditto.presence.observe().collect { graph ->
        // graph.localPeer, graph.remotePeers
    }
}
```

**v4 aside:** `presence.observe(handler)` returned a `DittoPresenceObserver`
that had to be closed manually. On Android, a garbage-collected observer's
finalizer ran on the `FinalizerDaemon` thread and — with a custom log callback
registered — could exceed Android's 10-second finalizer timeout, crashing with
`java.util.concurrent.TimeoutException`. The v5 Flow API collected in
`lifecycleScope` eliminates that hazard. `DittoPresenceObserver`,
`DittoPresenceObserverCallback`, `DittoPeersObserver`, `ditto.observePeers()`,
and `ditto.observePeersV2()` are all **removed**; use `presence.observe()`
(sdk/latest/migration-guides/kotlin-v4, sdk/latest/sync/using-mesh-presence).

### Local peer metadata

Peer metadata travels with every connection handshake and is visible to every
peer in the mesh — keep it small and non-sensitive, especially over BLE. The SDK
enforces a **4 KB** limit (JSON-encoded): `peerMetadataMaxSizeInBytes = 4096` in
`InternalDittoPresence.kt`, the setters reject oversize payloads via FFI, and the
`DittoPresence.kt` KDoc says 4 KB (**[source-verified]** — the docs page's
"128 KB" is wrong; 128 KB is the `smallPeerInfo.metadata` limit, a different field).

In v5, `presence.peerMetadata` is typed `DittoJsonSerializable.ObjectValue`, so
wrap a plain Kotlin map with `.toDittoJson()` when assigning directly, or use
the convenience members (note `.toDittoJson()` only has `Map<String, String>` /
`Map<String, Int>` / `Map<String, DittoJsonSerializable>` overloads — nested or
mixed-value maps need `toDittoJsonOrThrow()`):

```kotlin
import com.ditto.kotlin.serialization.toDittoJson

// Set via the property (expects DittoJsonSerializable.ObjectValue)
ditto.presence.peerMetadata = mapOf("role" to "kitchen-display").toDittoJson()

// Set via the convenience method or the JSON-string property
ditto.presence.setPeerMetadata(mapOf("role" to "kitchen-display"))
ditto.presence.peerMetadataJsonString = """{"role":"kitchen-display"}"""

// Read back
ditto.presence.peerMetadata                  // DittoJsonSerializable.ObjectValue
ditto.presence.peerMetadataJsonString        // String — JSON form
ditto.presence.peerMetadataJsonBytes         // ByteArray — binary JSON form
ditto.presence.graph.localPeer.peerMetadata  // same value, via the graph
```

There is **no** `getPeerMetadataMap()` — the migration guide documents one, but the
method does not exist in 5.0.x/5.1.0 (**[source-verified]** against
`DittoPresence.kt` and the published jars). To read a plain map, read
`peerMetadata` (an `ObjectValue`) or parse `peerMetadataJsonString`.
`setPeerMetadata(Map)` and `peerMetadataJsonBytes` are **new in v5**. The v4
`Presence.peerMetadataMaxSizeInBytes` companion constant is removed from the
public API (sdk/latest/migration-guides/kotlin-v4).

Remote peers' metadata is read off the graph:

```kotlin
val firstPeer = ditto.presence.graph.remotePeers.first()
firstPeer.peerKey        // String
firstPeer.peerMetadata   // DittoJsonSerializable.ObjectValue
```

### Identity service metadata

Set during authentication (signed by the identity server, validated by reading
peers — see `sdk/latest/auth-and-authorization/data-authorization`). Read it
from the graph; the Kotlin docs show no `presence.identityServiceMetadata`
namespace property, only the graph path
(sdk/latest/sync/using-mesh-presence):

```kotlin
ditto.presence.graph.localPeer.identityServiceMetadata
```

### Connection requests

`presence.connectionRequestHandler` is a nullable
`DittoPresence.ConnectionRequestHandler` **fun interface**. The handler fires
for **both inbound and outbound** connections after the handshake completes,
and may be updated without stopping and restarting sync — the handler version
set before a handshake started is the one that validates that request
(sdk/latest/sync/handling-connection-requests):

```kotlin
ditto.presence.connectionRequestHandler =
    DittoPresence.ConnectionRequestHandler { connectionRequest ->
        println(connectionRequest.peerKey)         // String (v4: peerKeyString)
        println(connectionRequest.connectionType)
        println(connectionRequest.peerMetadata)    // DittoJsonSerializable.ObjectValue
        DittoConnectionRequestAuthorization.Allow  // or .Deny
    }
```

Rules that matter:

- **Once a handler is set, it must always return a decision.** Leaving requests
  unanswered risks request deadlocks and connection timeouts
  (sdk/latest/sync/handling-connection-requests).
- `DittoConnectionRequest.peerMetadata` and `.identityServiceMetadata` are
  `DittoJsonSerializable.ObjectValue` in v5 (were `Map<String, Any?>`).
- **v4 aside:** the v4 `presence.connectionRequestHandlerJava` /
  `DittoConnectionRequestHandlerCallback` and the
  `DittoConnectionRequestHandler` typealias are all **removed** — use the fun
  interface directly (sdk/latest/migration-guides/kotlin-v4).
- In 5.1.0 the `connectionRequestHandler` setter no longer leaks the previous
  handler and its captured closure on every reassignment
  (sdk/latest/release-notes-hub/kotlin).

### What works on one device vs. two

Works **single-device, offline**: `presence.graph` (`localPeer` is always
present), `presence.observe()` emissions, all local `peerMetadata` get/set
forms, and `serializeToJson()`.

Requires a **second reachable peer** (or the Big Peer): anything in
`remotePeers`, any `DittoConnection` rows, remote peers' metadata and identity
service metadata, and the `connectionRequestHandler` actually firing. Do not
claim to have "verified" those paths from a one-device run.
