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
- [Sources and verification](#sources-and-verification)

## Availability and import

- **Introduced in 5.2.0.** The 5.1.0 module interface has no Data Streams symbols at all; 5.2.0
  exposes them as a system programming interface. Every file that uses them imports:

  ```swift
  @_spi(PreviewDataStreams) import DittoSwift
  ```

  A plain `import DittoSwift` compiles nothing in this file. `@_spi` is an underscored
  attribute: it is the SDK's way of shipping a preview, not a stable public API.
- Resolve the latest stable SwiftPM release for a new app and verify its preview
  interface before using these symbols. 5.2.0 is the latest release known to this
  skill; fixed fixture pins reproduce that evidence. See [setup.md](setup.md).
- Swift names: lowercase enum cases (`.reliable`, `.sent`, `.closedByRemote`), accessors are
  **throwing properties** (`try stream.maxSendSize`, `try candidate.peerKey`,
  `try inbound.payload`), and the Kotlin `closeSync()` is **`closeAndWait()`**.

## Enable NGN at open

Supply your portal database UUID, persistence directory and offline license token.

```swift
let config = DittoConfig(
    databaseID: "REPLACE_ME_WITH_YOUR_DATABASE_ID",
    connect: .smallPeersOnly(),
    persistenceDirectory: directory,
    systemParameters: [
        "ngn_data_streams_enabled": .bool(true),     // required: streams run over NGN
        "ngn_sync_enabled": .bool(false),  // keep document sync on the stable transports
    ]
)
let ditto = try await Ditto.open(config: config)
try ditto.setOfflineOnlyLicenseToken(token)
ditto.updateTransportConfig { config in /* modify the live copy; never a fresh config */ }
try ditto.sync.start()                          // presence needs sync running
```

`systemParameters` is a 5.2.0 initializer (**executed**). `ngn_sync_enabled` must be
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

The following complete sample is compiled as `StreamInbox.swift` and executed by
`DataStreamsSampleTests`. Retain the inbox and parent Ditto, provide short thread-safe
callbacks, and call `inbox.close()` at shutdown. The inbox keeps one stream per peer,
closes replaced streams, and handles callbacks racing with shutdown. Copy inbound bytes
before returning; hand off expensive work to an actor or queue.

```swift
@_spi(PreviewDataStreams) import DittoSwift
import Foundation

/// Owns the bound topic and one stream per remote peer until close().
final class StreamInbox: @unchecked Sendable {
    private let ditto: Ditto
    private let lock = NSLock()
    // Mutable state is protected by lock, including callbacks racing with close().
    private var acceptor: DittoAcceptor?
    private var streams: [String: DittoStream] = [:]
    private var closed = false

    init(
        ditto: Ditto,
        onPayload: @escaping @Sendable (Data) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) throws {
        self.ditto = ditto
        acceptor = try ditto.dataStreams.bindTopic("sensor_data", reliability: .reliable) { [weak self] candidate in
            guard let self else { return }
            do {
                let key = try candidate.peerKey
                let stream = try candidate.open { inbound in
                    do {
                        let bytes = try inbound.payload // Copy before the callback returns.
                        onPayload(bytes) // Must return quickly; hand off expensive work.
                    } catch { onError(error) }
                }
                let previous: DittoStream? = lock.withLock {
                    guard !closed else { return stream }
                    return streams.updateValue(stream, forKey: key)
                }
                previous?.close()
            } catch { onError(error) }
        }
    }

    func close() {
        let handles: (DittoAcceptor?, [DittoStream]) = lock.withLock {
            closed = true
            let result = (acceptor, Array(streams.values))
            acceptor = nil
            streams.removeAll()
            return result
        }
        handles.0?.close()
        for stream in handles.1 { stream.close() }
    }

    deinit { close() }
}

enum StreamSendError: Error { case payloadTooLarge, unsuccessful(DittoSendStatus) }

func sendReading(from ditto: Ditto, to peerKey: String, payload: Data) async throws {
    try await ditto.dataStreams.connect(
        peerKey: peerKey, topic: "sensor_data", reliability: .reliable, timeoutMs: 2_000
    ) { candidate in
        let stream = try candidate.open()
        defer { stream.close() }
        guard payload.count <= (try stream.maxSendSize) else { throw StreamSendError.payloadTooLarge }
        let status = try await stream.send(payload)
        guard status == .sent else { throw StreamSendError.unsuccessful(status) }
        // .sent is transport progress, not an application-level acknowledgement.
        _ = try await stream.closeAndWait()
    }
}
```

`sendReading` opens one connection for one reading. For a long-lived session, reuse an
opened stream as shown below. To open a candidate outside its callback, retain the
returned `candidate.take()` value and close it when done. Bind-side deferred opens must
run concurrently with the connecting task, which waits for acceptance.

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

## Sources and verification

Inspected the shipped 5.2.0 macOS public and private `.swiftinterface` files (SPI
symbols appear only in the private interface) and compared the older packages:
4.14.6, 5.0.3 and 5.1.0 contain no Data Streams symbols. The same sample compiles for
macOS, iOS Simulator, iOS device and Mac Catalyst. Physical devices and multi-hop
routing are not verified here.

Source: `getditto/ditto`, tag `sdk-release-5.2.0`, commit
`72d4443018494cd3e6dd37923df8a184f7784c26`, paths under `sdks/swift/`:
`DittoSwift/DittoDataStreams.swift:130` (bind/connect/acceptor),
`DittoSwift/DittoStreamCandidate.swift:101` (take/open/inbound),
`DittoSwift/DittoStream.swift:66` (send/close),
`DittoSwift/DittoSendOperation.swift:80` (status/cancellation), and
`DittoSwiftTests/DittoDataStreamsTests.swift:85` (NGN setup and two-peer tests).
Executed behavior and the shipped interface take precedence over source inference.
