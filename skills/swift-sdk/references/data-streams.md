# Data Streams — Swift 5.2.0 preview

## Contents

- [Availability and setup](#availability-and-setup)
- [Receive and send](#receive-and-send)
- [Lifetime and delivery rules](#lifetime-and-delivery-rules)
- [Verification and sources](#verification-and-sources)

## Availability and setup

**Verified on Ditto Swift SDK 5.2.0.** Data Streams are preview: they may change or
be removed without notice; coordinate use with Ditto. Every Swift file referencing
these symbols must opt in with `@_spi(PreviewDataStreams) import DittoSwift`.
They are absent on the verified 4.14.6, 5.0.3 and 5.1.0 Swift packages.
The public guide currently shows Kotlin; its annotations and method spellings do not
apply to Swift.

Data Streams exchange ephemeral bytes with a reachable peer over a named topic.
They do not persist documents or replace subscriptions or attachments. Use document
sync for queryable, convergent state and attachments for persisted binary payloads.

Enable NGN **before opening each Ditto** through 5.2's configuration map:

```swift
@_spi(PreviewDataStreams) import DittoSwift
import Foundation

let config = DittoConfig(
    databaseID: "REPLACE_ME_WITH_YOUR_DATABASE_ID",
    connect: .smallPeersOnly(),
    persistenceDirectory: directory,
    systemParameters: [
        "network_enable_ngn": .bool(true),
        "replication_over_ngn": .bool(false)
    ]
)
let ditto = try await Ditto.open(config: config)
try ditto.setOfflineOnlyLicenseToken(offlineLicense)
try ditto.sync.start()
```

`replication_over_ngn: false` keeps document replication on its existing networking
path. Start sync on both peers; preserve their transport settings with
`updateTransportConfig`, and meet the normal platform permissions in [setup.md](setup.md).
Select the remote **`peerKey`** from `ditto.presence.graph.remotePeers`, rather than a
numeric peer ID. Presence does not mean the remote has bound the topic; use a finite
`timeoutMs` and bounded connection retries during discovery. A zero timeout selects
the SDK's default 10 seconds.

## Receive and send

This complete sample is compiled in the fixture as `StreamInbox.swift` and exercised
between two Ditto instances. Create `StreamInbox` on the receiving peer, retain it,
and call `sendReading` on the sending peer with the receiver's key. Both peers retain
their `Ditto` instances. Supply short, thread-safe callbacks; marshal copied `Data`
to an actor or queue for processing or UI work. Call `inbox.close()` at shutdown.

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

The inbox keeps one stream per peer and closes a replaced stream. Its `close()` closes
both the acceptor and its streams without closing the shared endpoint. For a long-lived
session, connect/open once and reuse the stream with bounded sends rather than opening
one for every reading.

## Lifetime and delivery rules

- Topic names must match `^[a-zA-Z0-9_ ]{1,15}$`. Reliability must match on both peers.
  `.reliable` preserves ordering or fails the connection; `.unreliable` can lose or
  reorder messages. Request LZ4 compression with `requestCompression: true` for
  reliable streams.
- `bindTopic` callbacks run on separate SDK threads. `open(onReceive:)` callbacks run
  on the connection driver thread: return quickly and copy `try inbound.payload`
  before returning. Retaining `DittoInbound` does not extend that scope.
- Candidates expire when the bind callback or async connect continuation returns.
  Open inside that scope, or retain the **returned value** of `candidate.take()` and
  close it when done. An opened stream survives its candidate, provided it is retained.
  Only bind-side candidates accept `open(arguments:)`; the connecting side sends its
  handshake bytes in `connect(arguments:)`.
- Retain the acceptor and opened streams. Releasing or closing the acceptor unbinds
  the topic but leaves already-open streams alive. Closing the endpoint closes all its
  derived resources; keep the parent Ditto alive throughout.
- Check `try stream.maxSendSize`; chunk larger application payloads. Await sends or
  bound the in-flight queue. `sendAndForget` provides no backpressure.
  `send(payload) { operation in … }` allows progress tracking; `currentStatus`,
  `awaitStatusChange()` and `cancel()` throw. Do not overlap status waits on one
  operation. The operation closes when that async closure returns; releasing it does
  not cancel the send. Cancellation is best effort, so do not use it to undo delivery.
- Check the returned `DittoSendStatus` (`.unknown`, `.pending`, `.sent`, `.failed`,
  `.cancelled`); completion does not prove the remote application processed the bytes.
  Add application acknowledgements and duplicate handling where required.
- `close()` disallows new sends while queued traffic drains; receive callbacks can
  still run. Use `closeAndWait()` to initiate closure and await draining.
  `waitUntilClosed()` only waits; it does not initiate closure. Call it before a local
  close, or use `closeAndWait()` directly.
- Invalid/duplicate topics and failed connects throw `DittoError.dataStreamsError(message:)`.
  Accessing closed resources throws `DittoError.useAfterCloseError(message:)`.
  Cancelling connect cancels the attempt and surfaces its rejection as a Data Streams
  error. Cancelling a send/status wait requests send cancellation; cancelling a close
  wait only abandons the wait. These waits can throw `CancellationError`.

## Verification and sources

The 5.2.0 shipped `arm64-apple-macos.private.swiftinterface` confirms the SPI and every
sample signature; the ordinary interface intentionally omits SPI symbols. The fixture
executes the exact inbox/sender code, ordered payload delivery, bidirectional traffic
in both reliability modes, handshake arguments, reliability mismatch rejection,
candidate transfer, invalid/duplicate binds, rebind after close and endpoint shutdown. Platform builds
compile the same sample for macOS, iOS Simulator, iOS device and Mac Catalyst.
Physical-device and multi-hop behavior are not verified here.

Source inspection: `getditto/ditto`, tag `sdk-release-5.2.0` at commit
`72d4443018494cd3e6dd37923df8a184f7784c26`, paths under `sdks/swift/`:
`DittoSwift/DittoDataStreams.swift:130` (bind/connect/acceptor),
`DittoSwift/DittoStreamCandidate.swift:101` (take/open/inbound),
`DittoSwift/DittoStream.swift:66` (send/close),
`DittoSwift/DittoSendOperation.swift:80` (status/cancellation), and
`DittoSwiftTests/DittoDataStreamsTests.swift:85` (NGN setup and two-peer tests).
Executed behavior and the shipped interface take precedence over source inference.

Public semantics reference: <https://docs.ditto.live/sdk/latest/sync/data-streams>
(Kotlin examples; Swift syntax verified independently above).
