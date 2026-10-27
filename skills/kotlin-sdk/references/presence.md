# Presence and connection requests — Ditto Kotlin SDK

## Contents

- [CAP-13 Presence graph and connection requests](#cap-13-presence-graph-and-connection-requests)
  - [The graph](#the-graph)
  - [Observing the graph](#observing-the-graph)
  - [Local peer metadata](#local-peer-metadata)
  - [Identity service metadata](#identity-service-metadata)
  - [Connection requests](#connection-requests)
  - [What works on one device vs. two](#what-works-on-one-device-vs-two)

> **Sources for this file.** <https://docs.ditto.live/sdk/latest/sync/using-mesh-presence>,
> <https://docs.ditto.live/sdk/latest/sync/handling-connection-requests>, and the verified
> <https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4> PRESENCE / PEER & CONNECTION sections.
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
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>).

`DittoPeer` fields and their v4 spellings
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>, PEER & CONNECTION):

| v5 | v4 | Notes |
|---|---|---|
| `peerKey: String` | `peerKeyString: String` | The v4 `peerKey: DittoPeerKey` (ByteArray) and the `DittoPeerKey` typealias, `toKeyString()`, and `decodePeerKey()` are all **removed** — the String form is the only one |
| `isConnectedToDittoServer: Boolean` | `isConnectedToDittoCloud: Boolean` | Renamed |
| `os: DittoPeerOs?` | `os: String?` | Now an enum: `Generic`, `Ios`, `Tvos`, `Android`, `Linux`, `Windows`, `MacOS` |
| `peerMetadata: DittoJsonSerializable.ObjectValue` | `Map<String, Any?>` | Type changed |
| `identityServiceMetadata: DittoJsonSerializable.ObjectValue` | `Map<String, Any?>` | Type changed |
| — | `queryOverlapGroup: Int` | **Removed** |

Unchanged fields, for completeness: `address: DittoAddress`,
`connections: List<DittoConnection>`, `deviceName: String`,
`dittoSdkVersion: String?`, `isCompatible: Boolean?` (confirmed against
`com.ditto:ditto-kotlin-android:5.1.0`).

`DittoPeerOs.Tvos` is **deprecated in 5.1.0 but retained on purpose** so peers
running older SDK versions on tvOS can still be identified in the presence graph
(<https://docs.ditto.live/sdk/latest/release-notes/kotlin>). Keep handling it — and note the Kotlin
difference from Swift: naming `DittoPeerOs.Tvos` in a `when` branch emits a
deprecation **warning**, which breaks builds with `allWarningsAsErrors`; put
`@Suppress("DEPRECATION")` on that `when` (or the enclosing function).

`DittoConnection` simplifies in v5: `peer1` and `peer2` are now plain `String`
peer keys (v4: deprecated `DittoPeerKey` fields plus `peerKeyString1` /
`peerKeyString2`), and `approximateDistanceInMeters` is **removed**
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>).

### Observing the graph

`presence.observe()` is **Flow-based in v5** — it returns
`Flow<DittoPresenceGraph>` and takes no handler. Collect it in a
`CoroutineScope`; the upstream observer is cancelled with the scope, so no
manual `close()` is needed. On Android collect inside
`repeatOnLifecycle(Lifecycle.State.STARTED)` so the collector stops while the
screen is in the background (a bare `lifecycleScope.launch { collect }` runs until
the owner is destroyed):

```kotlin
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle

lifecycleScope.launch {
    repeatOnLifecycle(Lifecycle.State.STARTED) {
        ditto.presence.observe().collect { graph ->
            // graph.localPeer, graph.remotePeers
        }
    }
}
```

**v4 aside:** `presence.observe(handler)` returned a `DittoPresenceObserver`
that had to be closed manually. On Android, a garbage-collected observer's
finalizer ran on the `FinalizerDaemon` thread and — with a custom log callback
registered — could exceed Android's 10-second finalizer timeout, crashing with
`java.util.concurrent.TimeoutException`. The v5 Flow API collected in
`lifecycleScope` eliminates that hazard. `DittoPresenceObserver`,
`DittoPresenceObserverCallback` and `DittoPeersObserver` (all present in
`live.ditto:ditto:4.14.0`) are **removed**, as are the legacy `observePeers()` /
`observePeersV2()` entry points the migration guide lists (in the 4.14.0 jar those
live on `PresenceManagerV1` / `PresenceManagerV2`; the exact v4 call path was not
re-verified here); use `presence.observe()`
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>, <https://docs.ditto.live/sdk/latest/sync/using-mesh-presence>).

### Local peer metadata

Peer metadata travels with every connection handshake and is visible to every
peer in the mesh — keep it small and non-sensitive, especially over BLE. The SDK
enforces a **4 KB** limit (JSON-encoded): `peerMetadataMaxSizeInBytes = 4096` in
`InternalDittoPresence.kt` (constant confirmed as
`InternalDittoPresence.peerMetadataMaxSizeInBytes = 4096` in
`com.ditto:ditto-internal-android:5.1.0`, and the same value in
`live.ditto:ditto:4.14.0`'s `Presence`), and the `DittoPresence.kt` KDoc says 4 KB
(**[source-verified]** — the docs page's "128 KB" is wrong; 128 KB is the
`smallPeerInfo.metadata` limit, a different field). An oversize payload is
rejected at set time; **which exception type** carries that rejection is not
verified here — `setPeerMetadata(Map)` declares `DittoException` and
`IllegalArgumentException`, and the Swift SDK reports it as a validation
size-limit error, so expect `DittoException.ValidationException` but confirm by
executing before matching on it.

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
public API (<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>).

Remote peers' metadata is read off the graph:

```kotlin
val firstPeer = ditto.presence.graph.remotePeers.first()
firstPeer.peerKey        // String
firstPeer.peerMetadata   // DittoJsonSerializable.ObjectValue
```

### Identity service metadata

Set during authentication (signed by the identity server, validated by reading
peers — see <https://docs.ditto.live/sdk/latest/auth-and-authorization/data-authorization>). Read it
from the graph; the Kotlin docs show no `presence.identityServiceMetadata`
namespace property, only the graph path
(<https://docs.ditto.live/sdk/latest/sync/using-mesh-presence>):

```kotlin
ditto.presence.graph.localPeer.identityServiceMetadata
```

### Connection requests

`presence.connectionRequestHandler` is a nullable
`DittoPresence.ConnectionRequestHandler` **fun interface** whose single method,
`handleConnectionRequest(request): DittoConnectionRequestAuthorization`, is
**`suspend`** (confirmed against `com.ditto:ditto-kotlin-android:5.1.0`) — so the
lambda may `await` an authorization service, but it gates every connection
handshake: keep it fast and never block in it. The handler fires
for **both inbound and outbound** connections after the handshake completes,
and may be updated without stopping and restarting sync — the handler version
set before a handshake started is the one that validates that request
(<https://docs.ditto.live/sdk/latest/sync/handling-connection-requests>):

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
  (<https://docs.ditto.live/sdk/latest/sync/handling-connection-requests>).
- `DittoConnectionRequest.peerMetadata` and `.identityServiceMetadata` are
  `DittoJsonSerializable.ObjectValue` in v5 (were `Map<String, Any?>`).
- **v4 aside:** the v4 `presence.connectionRequestHandlerJava` /
  `DittoConnectionRequestHandlerCallback` and the
  `DittoConnectionRequestHandler` typealias are all **removed** — use the fun
  interface directly (<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>).
- In 5.1.0 the `connectionRequestHandler` setter no longer leaks the previous
  handler and its captured closure on every reassignment
  (<https://docs.ditto.live/sdk/latest/release-notes/kotlin>).

### What works on one device vs. two

Works **single-device, offline**: `presence.graph` (`localPeer` is always
present), `presence.observe()` emissions, all local `peerMetadata` get/set
forms, and `serializeToJson()`.

Requires a **second reachable peer** (or the Big Peer): anything in
`remotePeers`, any `DittoConnection` rows, remote peers' metadata and identity
service metadata, and the `connectionRequestHandler` actually firing. Do not
claim to have "verified" those paths from a one-device run.
