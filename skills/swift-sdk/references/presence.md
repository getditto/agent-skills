# Presence — Ditto Swift SDK

## CAP-13 Presence graph and connection requests

### The graph

```swift
let graph = ditto.presence.graph
graph.localPeer                 // DittoPeer — always present
graph.remotePeers               // [DittoPeer]
graph.allConnectionsByID()      // [String: DittoConnection]
```

`DittoPeer` carries `peerKey`, `connections`, `deviceName`, `isConnectedToDittoServer`,
`os: DittoPeerOS?`, `dittoSDKVersion: String?`, `isCompatible: Bool?`, `peerMetadata` and
`identityServiceMetadata`. The v4 spellings (`peerKeyString`, `isConnectedToDittoCloud`,
`osV2`) are in [api-compatibility.md](api-compatibility.md#presence-and-peers).

`DittoConnection` has `id`, `type: DittoConnectionType`, `peer1` and `peer2`.

### Observing

```swift
// @Sendable: presence delivers on an SDK thread. An unannotated closure registered
// from a @MainActor SwiftUI owner can inherit main-actor isolation and trap on
// callback entry under Swift 6 — before any hop inside the body could run.
let observer = ditto.presence.observe { @Sendable graph in
    // graph.localPeer, graph.remotePeers — extract here, then hop explicitly:
    Task { @MainActor in /* update UI state */ }
}
// …
observer.stop()
```

`presence.observe` returns a `DittoObserver`, which is stopped with **`stop()`** — not
`cancel()`, which is the store observer's method.

`DittoPresence.GraphPublisher` (`presence.graphPublisher()`) is the Combine form;
releasing its `AnyCancellable` stops the underlying observer.

The handler is **not** declared `@Sendable` by the SDK (`DittoPresence.swift:74` —
`[source-verified]`) and is not guaranteed to run on the main queue. Mark it
`@Sendable` yourself, extract what you need, then hop to the main actor.

### Peer metadata

```swift
try ditto.presence.setPeerMetadata(["role": "kitchen-display"])
ditto.presence.peerMetadata            // [String: Any?]
ditto.presence.peerMetadataJSONData    // Data
```

Metadata is capped by the SDK and an oversized dictionary throws
`DittoError.validationError(.sizeLimitExceeded(message:))`. Keep it to small identity
facts — it travels with every presence update, to every peer.

### `DittoPeerOS` and exhaustive switches

```swift
switch peer.os {
case .iOS, .macOS: break
case .android, .linux, .windows, .generic: break
case .tvOS: break               // deprecated in 5.1.0, still reachable
case .unknown(let name): _ = name  // a value this SDK version does not recognise
case .none: break               // `os` is Optional
@unknown default: break         // required: non-frozen enum from another module
}
```

**`@unknown default` is mandatory.** Without it the compiler rejects the switch with
*"switch covers known cases, but 'DittoPeerOS?' may have additional unknown values"*.
The same is true of `DittoConfigConnect`,
`DittoAttachmentFetchEvent` and `DittoError`.

An unrecognised peer OS arrives as `.unknown(os:)` — for example
`DittoPeerOS(from: "Fuchsia")` — so `.unknown` must be handled.

`.tvOS` is deprecated in 5.1.0 and **retained on purpose**, so peers running older tvOS
SDKs stay identifiable. Handling it in a `switch` **pattern** is
warning-free — Swift does not diagnose a deprecated case there — while omitting it is a
compile error. Keep the case. (Referring to `.tvOS` as a *value* does warn.)

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

Setting the handler while `ditto` has already been released is a silent no-op.

Mesh formation and which transports produce which `DittoConnectionType` belong to
`ditto-mesh-networking`, or <https://docs.ditto.live/sdk/latest/sync/using-mesh-presence>.
