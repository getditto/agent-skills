# Presence — Ditto Swift SDK

## CAP-13 Presence graph and connection requests

### The graph

```swift
let graph = ditto.presence.graph
graph.localPeer                 // DittoPeer — always present
graph.remotePeers               // [DittoPeer]
graph.allConnectionsByID()      // [String: DittoConnection]
```

**Executed**: on an offline-only instance with no peers, `localPeer.peerKey` and
`localPeer.deviceName` are both non-empty.

`DittoPeer` carries `peerKey`, `connections`, `deviceName`, `isConnectedToDittoServer`,
`os: DittoPeerOS?`, `dittoSDKVersion: String?`, `isCompatible: Bool?`, `peerMetadata` and
`identityServiceMetadata`. The v4 spellings (`peerKeyString`, `isConnectedToDittoCloud`,
`osV2`) are in [versions.md](versions.md#presence-and-peers).

`DittoConnection` has `id`, `type: DittoConnectionType`, `peer1` and `peer2`.

### Observing

```swift
let observer = ditto.presence.observe { graph in
    // graph.localPeer, graph.remotePeers
}
// …
observer.stop()
```

`presence.observe` returns a `DittoObserver`, which is stopped with **`stop()`** — not
`cancel()`, which is the store observer's method. **Executed**: the handler fires with a
graph whose `localPeer.peerKey` matches `presence.graph.localPeer.peerKey`.

`DittoPresence.GraphPublisher` (`presence.graphPublisher()`) is the Combine form;
releasing its `AnyCancellable` stops the underlying observer.

The handler is **not** declared `@Sendable` and is not guaranteed to run on the main
queue. Treat it like a store observer: extract what you need, then hop to the main actor.

### Peer metadata

```swift
try ditto.presence.setPeerMetadata(["role": "kitchen-display"])
ditto.presence.peerMetadata            // [String: Any?]
ditto.presence.peerMetadataJSONData    // Data
```

**Executed**: a value set through `setPeerMetadata` reads back from `peerMetadata`.
Metadata is capped by the SDK and an oversized dictionary throws
`DittoError.validationError(.sizeLimitExceeded(message:))`. Keep it to small identity
facts — it travels with every presence update, to every peer.

### `DittoPeerOS` and exhaustive switches

```swift
switch peer.os {
case .iOS, .macOS: …
case .android, .linux, .windows, .generic: …
case .tvOS: …              // deprecated in 5.1.0, still reachable
case .unknown(let name): … // any value this SDK version does not recognise
case .none: …              // `os` is Optional
}
```

**Executed**: `DittoPeerOS(from: "Fuchsia")` is `.unknown(os: "Fuchsia")`, so an
unrecognised peer OS never crashes a switch — but it does mean `.unknown` must be handled.

`.tvOS` is deprecated in 5.1.0 and **retained on purpose**, so peers running older tvOS
SDKs stay identifiable (#SDKS-3944). Handling it produces a deprecation warning; omitting
it produces a compile error. Suppress the warning rather than deleting the case.

### Connection requests

```swift
ditto.presence.connectionRequestHandler = { request in
    // request.peerKey, .peerMetadata, .identityServiceMetadata, .connectionType
    request.peerMetadata["role"] as? String == "kitchen-display" ? .allow : .deny
}
```

`DittoConnectionRequestHandler` is
`@Sendable (DittoConnectionRequest) async -> DittoConnectionRequestAuthorization`. It is
async, so it can await an authorization service, but it gates every inbound connection —
keep it fast and never block on the main actor.

Setting the handler while `ditto` has already been released is a silent no-op
(`sdk-release-5.1.0:sdks/swift/DittoSwift/DittoPresence.swift`), not a crash.

**Not verified here.** The fixture is a single offline peer, so remote peers, connection
types other than the local peer's, and the connection-request path are read from source
and the published documentation rather than executed. Mesh formation and which transports
produce which `DittoConnectionType` belong to `ditto-mesh-networking`, or
<https://docs.ditto.com/sdk/latest/sync/using-mesh-presence>.
