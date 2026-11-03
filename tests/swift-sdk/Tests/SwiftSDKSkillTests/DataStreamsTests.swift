//
// CAP-20 Data Streams (5.2.0+, `@_spi(PreviewDataStreams)`).
//
// Executed evidence for skills/data-streams and skills/swift-sdk/references/data-streams.md.
// Two peers in this process, linked by a TCP loopback listener (see TestPeer+DataStreams).
//

#if DITTO_DATA_STREAMS
import Foundation
import Testing
@_spi(PreviewDataStreams) import DittoSwift
@testable import SkillSupport

/// A thread-safe inbox the stream callbacks post into and tests await from.
final class Mailbox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []
    private var waiter: CheckedContinuation<T, Never>?

    func post(_ value: T) {
        lock.lock()
        if let waiter {
            self.waiter = nil
            lock.unlock()
            waiter.resume(returning: value)
        } else {
            items.append(value)
            lock.unlock()
        }
    }

    func next(timeout: Duration = .seconds(15)) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    self.lock.lock()
                    if !self.items.isEmpty {
                        let value = self.items.removeFirst()
                        self.lock.unlock()
                        continuation.resume(returning: value)
                    } else {
                        self.waiter = continuation
                        self.lock.unlock()
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw StreamTimeout()
            }
            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }
}

/// The receiving side: one acceptor plus every stream a peer opened on it.
final class Receiver: @unchecked Sendable {
    let inbound = Mailbox<Data>()
    let streams = Mailbox<DittoStream>()
    let threads = Mailbox<String>()
    let arguments = Mailbox<Result<Data?, Error>>()
    let acceptor: DittoAcceptor

    init(
        _ ditto: Ditto,
        topic: String,
        reliability: DittoReliability = .reliable,
        openArguments: Data? = nil,
        readArguments: Bool = false
    ) throws {
        let inbound = self.inbound, streams = self.streams, threads = self.threads, arguments = self.arguments
        acceptor = try ditto.dataStreams.bindTopic(topic, reliability: reliability) { candidate in
            if readArguments { arguments.post(Result { try candidate.arguments }) }
            do {
                // Open inside the callback; the stream outlives the candidate.
                let stream = try candidate.open(arguments: openArguments) { message in
                    threads.post(Thread.current.description)
                    if let payload = try? message.payload { inbound.post(payload) }   // owned copy; return fast
                }
                streams.post(stream)
            } catch {
                Issue.record("open() in the bind callback threw: \(error)")
            }
        }
    }
}

/// Presence does not prove the topic is bound yet: retry a failed connect, bounded.
func connectWithRetry<T>(attempts: Int = 5, _ body: () async throws -> T) async throws -> T {
    var last: Error?
    for attempt in 0..<attempts {
        do { return try await body() } catch is CancellationError { throw CancellationError() } catch {
            last = error
            try await Task.sleep(for: .milliseconds(200 * (attempt + 1)))
        }
    }
    throw last!
}

@Suite("Data Streams", .serialized)
struct DataStreamsTests {

    @Test("bytes round-trip both ways on one reliable stream", .timeLimit(.minutes(3)))
    func roundTrip() async throws {
        let (server, client) = try await TestPeer.connectedPair()
        defer { client.tearDown(); server.tearDown() }
        let serverKey = server.ditto.presence.graph.localPeer.peerKey
        let clientKey = client.ditto.presence.graph.localPeer.peerKey

        let receiver = try Receiver(server.ditto, topic: "sensor_data")
        defer { receiver.acceptor.close() }

        let echoed = Mailbox<Data>()
        let clientStream = try await connectWithRetry {
            try await client.ditto.dataStreams.connect(
                peerKey: serverKey, topic: "sensor_data", reliability: .reliable, timeoutMs: 10_000
            ) { candidate in
                // connect() lends the candidate; this block must open it (or take() it).
                try candidate.open { message in
                    if let payload = try? message.payload { echoed.post(payload) }
                }
            }
        }
        #expect(try clientStream.maxSendSize > 0)
        #expect(try clientStream.peerKey == serverKey)
        #expect(try clientStream.topic == "sensor_data")

        // Client -> server, twice on the same stream: connect once, reuse.
        #expect(try await clientStream.send(Data("reading-1".utf8)) == .sent)
        #expect(try await clientStream.send(Data("reading-2".utf8)) == .sent)
        #expect(try await receiver.inbound.next() == Data("reading-1".utf8))
        #expect(try await receiver.inbound.next() == Data("reading-2".utf8))

        // Server -> client on the same stream: the channel is symmetric.
        let serverStream = try await receiver.streams.next()
        #expect(try serverStream.peerKey == clientKey)
        #expect(try await serverStream.send(Data("ack".utf8)) == .sent)
        #expect(try await echoed.next() == Data("ack".utf8))

        // sendAndForget delivers too; it just reports nothing.
        try clientStream.sendAndForget(Data("reading-3".utf8))
        #expect(try await receiver.inbound.next() == Data("reading-3".utf8))

        // The receive callback runs on the connection's driver thread, not the main thread.
        let thread = try await receiver.threads.next()
        #expect(!thread.contains("main"), "onReceive ran on \(thread)")

        // Monitoring overload: observe the status transitions to a terminal state.
        let terminal = try await clientStream.send(Data("reading-4".utf8)) { operation in
            var status = try operation.currentStatus
            while status == .pending { status = try await operation.awaitStatusChange() }
            return status
        }
        #expect(terminal == .sent)

        // Closing: closeAndWait() on one side is closedByRemote on the other.
        #expect(try await clientStream.closeAndWait() == .closedByLocal)
        #expect(try await serverStream.waitUntilClosed() == .closedByRemote)
    }

    @Test("arguments travel with connect() and with the acceptor's open(arguments:)", .timeLimit(.minutes(3)))
    func arguments() async throws {
        let (server, client) = try await TestPeer.connectedPair()
        defer { client.tearDown(); server.tearDown() }
        let serverKey = server.ditto.presence.graph.localPeer.peerKey

        let receiver = try Receiver(
            server.ditto, topic: "with_args", openArguments: Data("welcome".utf8), readArguments: true
        )
        defer { receiver.acceptor.close() }

        let clientSeen = Mailbox<Result<Data?, Error>>()
        let stream = try await connectWithRetry {
            try await client.ditto.dataStreams.connect(
                peerKey: serverKey, topic: "with_args", timeoutMs: 10_000, arguments: Data("hello".utf8)
            ) { candidate in
                clientSeen.post(Result { try candidate.arguments })
                return try candidate.open()   // write-only: no onReceive
            }
        }
        let atAcceptor = try await receiver.arguments.next()
        #expect(try atAcceptor.get() == Data("hello".utf8))
        let reply = try await clientSeen.next()
        print("connector-side candidate.arguments -> \(reply)")
        #expect(try reply.get() == Data("welcome".utf8))
        _ = try await stream.closeAndWait()
    }

    @Test("reading absent arguments on the acceptor side", .timeLimit(.minutes(3)))
    func absentArguments() async throws {
        let (server, client) = try await TestPeer.connectedPair()
        defer { client.tearDown(); server.tearDown() }
        let serverKey = server.ditto.presence.graph.localPeer.peerKey

        let receiver = try Receiver(server.ditto, topic: "no_args", readArguments: true)
        defer { receiver.acceptor.close() }
        let stream = try await connectWithRetry {
            try await client.ditto.dataStreams.connect(peerKey: serverKey, topic: "no_args", timeoutMs: 10_000) {
                try $0.open()
            }
        }
        let observed = try await receiver.arguments.next()
        print("acceptor-side candidate.arguments with none sent -> \(observed)")
        switch observed {
        case .success(let value): #expect(value == nil)
        case .failure(let error): Issue.record("arguments threw \(error)")
        }
        _ = try await stream.closeAndWait()
    }

    @Test("the connector's reliability must match the binding", .timeLimit(.minutes(3)))
    func reliabilityMismatch() async throws {
        let (server, client) = try await TestPeer.connectedPair()
        defer { client.tearDown(); server.tearDown() }
        let serverKey = server.ditto.presence.graph.localPeer.peerKey

        let receiver = try Receiver(server.ditto, topic: "reliable_only", reliability: .reliable)
        defer { receiver.acceptor.close() }
        do {
            _ = try await client.ditto.dataStreams.connect(
                peerKey: serverKey, topic: "reliable_only", reliability: .unreliable, timeoutMs: 5_000
            ) { try $0.open() }
            Issue.record("expected the mismatched connect to fail")
        } catch let error as DittoError {
            print("reliability mismatch -> \(error)")
            guard case .dataStreamsError = error else {
                Issue.record("expected dataStreamsError, got \(error)")
                return
            }
        }
    }

    @Test("a borrowed candidate dies with its callback unless take()n", .timeLimit(.minutes(3)))
    func candidateOwnership() async throws {
        let (server, client) = try await TestPeer.connectedPair()
        defer { client.tearDown(); server.tearDown() }
        let serverKey = server.ditto.presence.graph.localPeer.peerKey
        let clientKey = client.ditto.presence.graph.localPeer.peerKey

        let leaked = Mailbox<DittoStreamCandidate<MaySendArguments.Allowed>>()
        let taken = Mailbox<DittoStreamCandidate<MaySendArguments.Allowed>>()
        let acceptor = try server.ditto.dataStreams.bindTopic("ownership") { borrowed in
            leaked.post(borrowed)        // wrong: the wrapper closes when this returns
            taken.post(borrowed.take())  // right: ownership moves to the taken wrapper
        }
        defer { acceptor.close() }

        // connect() suspends until the acceptor opens the candidate, so the deferred open
        // must run concurrently with it — on another task, as a real app would.
        let serverStreamTask = Task { () throws -> DittoStream in
            let owned = try await taken.next()
            #expect(try owned.peerKey == clientKey)   // usable outside the callback…
            let stream = try owned.open()
            owned.close()                             // …and closed by us
            return stream
        }
        let clientStream = try await connectWithRetry {
            try await client.ditto.dataStreams.connect(peerKey: serverKey, topic: "ownership", timeoutMs: 10_000) {
                try $0.open()
            }
        }
        let serverStream = try await serverStreamTask.value
        let borrowed = try await leaked.next()
        do {
            _ = try borrowed.peerKey
            Issue.record("expected the borrowed candidate to be unusable after its callback")
        } catch let error as DittoError {
            // Swift surfaces this as the generic use-after-close case, not as dataStreamsError.
            print("use after callback -> \(error)")
            guard case .useAfterCloseError(let message) = error else {
                Issue.record("expected useAfterCloseError, got \(error)")
                return
            }
            #expect(message.contains("after it was closed"))
        }
        #expect(try await serverStream.send(Data("late open".utf8)) == .sent)
        _ = try await serverStream.closeAndWait()
        _ = try await clientStream.closeAndWait()
    }

    @Test("closing the acceptor unbinds the topic but leaves open streams alive", .timeLimit(.minutes(3)))
    func acceptorClose() async throws {
        let (server, client) = try await TestPeer.connectedPair()
        defer { client.tearDown(); server.tearDown() }
        let serverKey = server.ditto.presence.graph.localPeer.peerKey

        let receiver = try Receiver(server.ditto, topic: "unbind")
        let clientStream = try await connectWithRetry {
            try await client.ditto.dataStreams.connect(peerKey: serverKey, topic: "unbind", timeoutMs: 10_000) {
                try $0.open()
            }
        }
        let serverStream = try await receiver.streams.next()

        receiver.acceptor.close()   // the topic no longer accepts…
        // …but the stream opened under it keeps working.
        #expect(try await clientStream.send(Data("still open".utf8)) == .sent)
        #expect(try await receiver.inbound.next() == Data("still open".utf8))

        // A new connect to the unbound topic fails (bounded by its own timeout).
        do {
            _ = try await client.ditto.dataStreams.connect(peerKey: serverKey, topic: "unbind", timeoutMs: 5_000) {
                try $0.open()
            }
            Issue.record("expected connect to an unbound topic to fail")
        } catch let error as DittoError {
            print("connect to unbound topic -> \(error)")
        }
        _ = try await clientStream.closeAndWait()
        _ = try await serverStream.closeAndWait()
    }

    @Test("topics outside ^[a-zA-Z0-9_ ]{1,15}$ are rejected", .timeLimit(.minutes(3)))
    func invalidTopics() async throws {
        let peer = try await TestPeer.openForDataStreams { _ in }
        defer { peer.tearDown() }
        for bad in ["has-dash", "sixteen_chars_ab", "", "émoji"] {
            do {
                try peer.ditto.dataStreams.bindTopic(bad) { _ in }.close()
                Issue.record("expected topic '\(bad)' to be rejected")
            } catch let error as DittoError {
                print("invalid topic '\(bad)' -> \(error)")
            }
        }
        // Spaces, digits and underscores are allowed, up to fifteen characters.
        try peer.ditto.dataStreams.bindTopic("ok topic_15 abc") { _ in }.close()
    }

    @Test("payloads larger than maxSendSize do not report sent", .timeLimit(.minutes(3)))
    func oversizedPayload() async throws {
        let (server, client) = try await TestPeer.connectedPair()
        defer { client.tearDown(); server.tearDown() }
        let serverKey = server.ditto.presence.graph.localPeer.peerKey

        let receiver = try Receiver(server.ditto, topic: "too_big")
        defer { receiver.acceptor.close() }
        let stream = try await connectWithRetry {
            try await client.ditto.dataStreams.connect(peerKey: serverKey, topic: "too_big", timeoutMs: 10_000) {
                try $0.open()
            }
        }
        let max = try stream.maxSendSize
        print("maxSendSize = \(max)")
        #expect(max > 0)
        if max <= 64 * 1024 * 1024 {
            do {
                let status = try await stream.send(Data(count: max + 1))
                print("oversize send -> \(status)")
                #expect(status != .sent)
            } catch let error as DittoError {
                print("oversize send threw -> \(error)")
            }
            // The stream itself survives for correctly sized payloads.
            #expect(try await stream.send(Data(count: max)) == .sent)
        } else {
            // Observed with 5.2.0: 4294967289 for a reliable stream — too large to allocate here
            // (a 4 GiB send reported .failed and the next one hung), so only 1 MiB is exercised.
            print("maxSendSize too large to probe; sending 1 MiB instead")
            #expect(try await stream.send(Data(count: 1024 * 1024)) == .sent)
            #expect(try await receiver.inbound.next() == Data(count: 1024 * 1024))
        }
        _ = try await stream.closeAndWait()
    }

    @Test("one acceptor per topic at a time", .timeLimit(.minutes(3)))
    func oneAcceptorPerTopic() async throws {
        let peer = try await TestPeer.openForDataStreams { _ in }
        defer { peer.tearDown() }
        let first = try peer.ditto.dataStreams.bindTopic("single") { _ in }
        do {
            try peer.ditto.dataStreams.bindTopic("single") { _ in }.close()
            Issue.record("expected the second bind of the same topic to fail")
        } catch let error as DittoError {
            print("second bind of the same topic -> \(error)")
        }
        first.close()
        // After the first acceptor closes the topic can be bound again.
        try peer.ditto.dataStreams.bindTopic("single") { _ in }.close()
    }
}
#endif
