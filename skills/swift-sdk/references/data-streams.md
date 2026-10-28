# Data Streams in Swift (5.2.0+, preview SPI)

How to express Ditto Data Streams in Swift. Concepts, lifecycle rules and design patterns
live in the `data-streams` skill (<https://docs.ditto.live/sdk/latest/sync/data-streams>, a
Kotlin-only guide); this file is the Swift spelling, read from the DittoSwift **5.2.0**
module interface and proved by the fixture
`tests/swift-sdk/Tests/SwiftSDKSkillTests/DataStreamsTests.swift` (**executed** on macOS
with 5.2.0). **Public Preview**, may change without notice, and **not documented by Ditto
for Swift**: say so when you recommend it.

## Contents

- [Availability and import](#availability-and-import)
- [Enable NGN at open](#enable-ngn-at-open)
- [Receive: bind a topic](#receive-bind-a-topic)
- [Send: connect once, reuse the stream](#send-connect-once-reuse-the-stream)
- [Send modes and `maxSendSize`](#send-modes-and-maxsendsize)
- [Closing](#closing)
- [Reconnect](#reconnect)
- [API surface](#api-surface)
- [Observed on macOS](#observed-on-macos)
- [Testing with two peers in one process](#testing-with-two-peers-in-one-process)

## Availability and import

- **5.2.0 only.** The 5.1.0 module interface has no Data Streams symbols at all; 5.2.0
  exposes them as a system programming interface. Every file that uses them imports:

  ```swift
  @_spi(PreviewDataStreams) import DittoSwift
  ```

  A plain `import DittoSwift` compiles nothing in this file. `@_spi` is an underscored
  attribute: it is the SDK's way of shipping a preview, not a stable public API.
- Pin `exact: "5.2.0"` in `Package.swift` (the skill's other content is verified through
  5.1.0; the fixture's existing tests also pass on 5.2.0).
- Swift names: lowercase enum cases (`.reliable`, `.sent`, `.closedByRemote`), accessors are
  **throwing properties** (`try stream.maxSendSize`, `try candidate.peerKey`,
  `try inbound.payload`), and the Kotlin `closeSync()` is **`closeAndWait()`**.

## Enable NGN at open

```swift
let config = DittoConfig(
    databaseID: "my-app",
    connect: .smallPeersOnly(),
    persistenceDirectory: directory,
    systemParameters: [
        "network_enable_ngn": .bool(true),     // required: streams run over NGN
        "replication_over_ngn": .bool(false),  // keep document sync on the stable transports
    ]
)
let ditto = try await Ditto.open(config: config)
try ditto.setOfflineOnlyLicenseToken(token)
ditto.updateTransportConfig { config in /* modify the live copy; never a fresh config */ }
try ditto.sync.start()                          // presence needs sync running
```

`systemParameters` is a 5.2.0 initializer (**executed**). `replication_over_ngn` must be
the same on every peer that replicates documents. No TCP listener is required.

**Stack caveat.** With NGN enabled, `sync.start()` synchronously spawns the UDP transport,
whose start-up needs several hundred KB of stack in debug builds, more than a Swift
cooperative thread has. Ditto's reference app and its SDK tests start sync on a dedicated
large-stack thread; the fixture does the same (**executed**):

```swift
func startSyncOnLargeStack(_ ditto: Ditto) async throws {
    try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
        let thread = Thread { c.resume(with: Result { try ditto.sync.start() }) }
        thread.stackSize = 64 << 20
        thread.start()
    }
}
```

Call it from `Task` code; a plain call from the main thread of an app has the main thread's
stack and is not affected.

## Receive: bind a topic

```swift
@_spi(PreviewDataStreams) import DittoSwift

final class SensorReceiverSession: @unchecked Sendable {
    private let lock = NSLock()
    private var streams: [String: DittoStream] = [:]        // bind callbacks are concurrent
    private let acceptor: DittoAcceptor

    init(ditto: Ditto, onReading: @escaping @Sendable (Data) -> Void) throws {
        acceptor = try ditto.dataStreams.bindTopic("sensor_data", reliability: .reliable) { [weak self] candidate in
            guard let self, let peer = try? candidate.peerKey else { return }
            // Nothing may throw out of here: an unopened candidate times the connector out.
            guard let stream = try? candidate.open(onReceive: { inbound in
                if let payload = try? inbound.payload { onReading(payload) }   // driver thread: hand off, return
            }) else { return }
            self.lock.withLock { self.streams.updateValue(stream, forKey: peer)?.close() }
            Task { _ = try? await stream.waitUntilClosed(); self.lock.withLock { _ = self.streams.removeValue(forKey: peer) } }
        }
    }

    func close() async {
        acceptor.close()                                     // stop accepting…
        let open = lock.withLock { let s = Array(streams.values); streams.removeAll(); return s }
        for stream in open { _ = try? await stream.closeAndWait() }   // …then close what that did not
    }
}
```

To open elsewhere, `take()` the candidate and `close()` the taken one after `open`
(**executed**); the connector is suspended in `connect` until you open, so do it
concurrently, not after `connect` returns.

## Send: connect once, reuse the stream

`connect` is `async throws`, takes an `async throws` continuation and returns its result. It
lends the candidate; the block must open it.

```swift
let stream: DittoStream = try await ditto.dataStreams.connect(
    peerKey: receiverPeerKey,                 // from ditto.presence.graph.remotePeers[i].peerKey
    topic: "sensor_data",
    reliability: .reliable,
    timeoutMs: 10_000                          // UInt32; 0 = Ditto's default 10 s
) { candidate in
    try candidate.open { inbound in            // or `try candidate.open()` for write-only
        if let payload = try? inbound.payload { handleReply(payload) }
    }
}
let maxSendSize = try stream.maxSendSize
for reading in readings {
    precondition(reading.count <= maxSendSize)
    _ = try await stream.send(reading)        // .sent = handed to the transport
}
_ = try await stream.closeAndWait()
```

Run the connect from your own `Task`, never inside a presence observer's handler.

## Send modes and `maxSendSize`

```swift
let status = try await stream.send(payload)                      // DittoSendStatus
try stream.sendAndForget(payload)                                // no status
let terminal = try await stream.send(payload) { operation in     // monitor / backpressure
    var s = try operation.currentStatus
    while s == .pending { s = try await operation.awaitStatusChange() }
    return s
}
```

All three **executed** (`.sent`; `sendAndForget` delivered). Treat `.unknown` as terminal.
Check `maxSendSize` before each send and frame large transfers yourself.

## Closing

`closeAndWait()` returns `.closedByLocal`; the other end's `waitUntilClosed()` returns
`.closedByRemote` (**executed**). `close()` returns at once; `waitUntilClosed()` only
observes. Order: cancel tasks → `closeAndWait()` streams → `acceptor.close()` → release `Ditto`.

## Reconnect

Streams never reconnect. One loop per `(peerKey, topic)`: `connect` with a timeout,
register the stream (closing an older one for the key), `waitUntilClosed`, loop; on error
`catch is CancellationError { return }`, then `if Task.isCancelled { return }` before
retrying (an in-flight cancellation can surface as `DittoError.dataStreamsError`), sleep
`min(backoff * 2, 10_000)` ms plus jitter. For two symmetric peers, let the lower peer key
connect and the higher only accept (whiteboard reference app).

## API surface

All members are `@_spi(PreviewDataStreams)`; classes are `final` and `@unchecked Sendable`
(5.2.0 module interface).

| Type | Members |
|---|---|
| `Ditto.dataStreams` | `DittoDataStreamsEndpoint` |
| `DittoDataStreamsEndpoint` | `bindTopic(_ topic: String, reliability: DittoReliability = .reliable, onNewCandidate: @escaping @Sendable (DittoStreamCandidate<MaySendArguments.Allowed>) -> Void) throws -> DittoAcceptor`; `connect<T>(peerKey: String, topic: String, requestCompression: Bool = false, reliability: DittoReliability = .reliable, timeoutMs: UInt32 = 0, arguments: Data? = nil, continuation: (DittoStreamCandidate<MaySendArguments.Disallowed>) async throws -> T) async throws -> T`; `close()` |
| `DittoAcceptor` | `topic: String { get throws }`, `reliability: DittoReliability { get throws }`, `close()` |
| `DittoStreamCandidate<Args>` | `peerKey`, `topic`, `arguments: Data?` (all `get throws`), `take()`, `close()`; `Allowed`: `open()`, `open(onReceive:)`, `open(arguments:)`, `open(arguments:onReceive:)`; `Disallowed`: `open()`, `open(onReceive:)` — all `throws -> DittoStream` |
| `DittoStream` | `send(_ payload: Data) async throws -> DittoSendStatus`; `send<T>(_:withSendOperation:) async throws -> T`; `sendAndForget(_:) throws`; `peerKey`, `topic`, `maxSendSize: Int` (`get throws`); `waitUntilClosed() async throws -> DittoStreamStatus`; `closeAndWait() async throws -> DittoStreamStatus`; `close()` |
| `DittoInbound` | `payload: Data { get throws }`, `close()` |
| `DittoSendOperation` | `currentStatus { get throws }`, `cancel() throws`, `awaitStatusChange() async throws`, `close()` |
| `DittoReliability` | `.reliable`, `.unreliable` |
| `DittoStreamStatus` | `.open`, `.closedByRemote`, `.closedByLocal` |
| `DittoSendStatus` | `.unknown`, `.pending`, `.sent`, `.failed`, `.cancelled` |
| `DittoError.dataStreamsError(message:)` | the SPI error case for bind/connect/send failures; a candidate used after its callback throws the public `DittoError.useAfterCloseError(message:)` instead |

## Observed on macOS

All **executed** with 5.2.0 (`DittoError.dataStreamsError(message:)` unless noted):

- Reliability mismatch: `Rejected(ConnectionRejected)`; connect to a topic nobody binds:
  also `Rejected(ConnectionRejected)`; connect while the remote never opens the candidate:
  `Rejected(HandshakeTimedOut)`.
- Invalid topic (`has-dash`, 16 characters, empty, non-ASCII): `Failed to bind topic:
  Err(InvalidTopic)`; a second acceptor on a bound topic: `Failed to bind topic:
  Err(TopicAlreadyBound)`.
- A borrowed candidate used after its callback throws **`DittoError.useAfterCloseError`**
  ("Attempted to use a DittoStreamCandidate after it was closed…"), not `dataStreamsError`;
  a `take()`n one opens later and is closed by you.
- Arguments: `connect(…, arguments: "hello")` reached the acceptor; the acceptor's
  `open(arguments: "welcome")` was readable from the connector's candidate; with no
  arguments sent, the acceptor-side `arguments` is `nil` (unlike the Kotlin JVM defect).
- `stream.topic` and `stream.peerKey` are correct on both ends (unlike the Kotlin JVM
  `topic()` defect). `maxSendSize` on a reliable stream was `4294967289`; a 4 GiB send
  reported `.failed` and the next send hung, so size your frames yourself.
- Closing the acceptor leaves open streams alive and makes new connects fail;
  `closeAndWait()` is `.closedByLocal` locally and `.closedByRemote` on the other end.
- The receive callback did not run on the main thread.

## Testing with two peers in one process

Two `Ditto` instances in different directories with the same database ID, LAN discovery
off, one with `config.listen.tcp.isEnabled = true; interfaceIP = "127.0.0.1"; port = p`
and the other with `config.connect.tcpServers = ["127.0.0.1:\(p)"]`, both opened with the
NGN `systemParameters` above; wait until `presence.graph.remotePeers` lists the other on
both sides, then bind, then connect with a bounded retry. `swift test` injects `NO_COLOR=1`,
which Ditto's core rejects; the fixture's `run.sh` unsets it.
