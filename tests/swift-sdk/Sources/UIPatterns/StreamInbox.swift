#if DITTO_DATA_STREAMS
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
#endif
