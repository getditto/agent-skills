#if DITTO_DATA_STREAMS
@_spi(PreviewDataStreams) import DittoSwift
import Foundation
import Testing
import SkillSupport
@testable import UIPatterns

@Suite("Data Streams — 5.2.0 preview", .serialized)
struct DataStreamsSampleTests {
    private func open(databaseID: String) async throws -> Ditto {
        let ditto = try await Ditto.open(config: DittoConfig(
            databaseID: databaseID, connect: .smallPeersOnly(),
            persistenceDirectory: TestPeer.makeTemporaryDirectory(),
            systemParameters: ["network_enable_ngn": .bool(true), "replication_over_ngn": .bool(false)]
        ))
        try ditto.setOfflineOnlyLicenseToken(SkillTestEnvironment.offlineLicense)
        return ditto
    }

    private func cleanUp(_ ditto: Ditto) {
        ditto.dataStreams.close()
        ditto.sync.stop()
        try? FileManager.default.removeItem(at: ditto.absolutePersistenceDirectory)
    }

    private func connect(from ditto: Ditto, to peerKey: String, topic: String,
                         reliability: DittoReliability = .reliable) async throws -> DittoStreamCandidate<MaySendArguments.Disallowed> {
        let deadline = Date().addingTimeInterval(20)
        while true {
            do {
                return try await ditto.dataStreams.connect(
                    peerKey: peerKey, topic: topic, reliability: reliability, timeoutMs: 1_000,
                    arguments: Data("request".utf8)
                ) { candidate in
                    let taken = candidate.take()
                    #expect(throws: DittoError.self) { try candidate.topic }
                    return taken
                }
            } catch {
                guard Date() < deadline else { throw error }
                try await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    @Test("Invalid topics and duplicate binds fail; close unbinds and invalidates handles")
    func validationAndClose() async throws {
        let ditto = try await open(databaseID: UUID().uuidString.lowercased())
        defer { cleanUp(ditto) }
        #expect(throws: DittoError.self) { try ditto.dataStreams.bindTopic("invalid!") { _ in } }
        let acceptor = try ditto.dataStreams.bindTopic("sensor_data", reliability: .unreliable) { _ in }
        #expect(try acceptor.topic == "sensor_data")
        #expect(try acceptor.reliability == .unreliable)
        #expect(throws: DittoError.self) { try ditto.dataStreams.bindTopic("sensor_data") { _ in } }
        acceptor.close()
        #expect(throws: DittoError.self) { try acceptor.topic }
        let rebound = try ditto.dataStreams.bindTopic("sensor_data") { _ in }
        ditto.dataStreams.close()
        #expect(throws: DittoError.self) { try rebound.topic }
        #expect(throws: DittoError.self) { try ditto.dataStreams.bindTopic("late") { _ in } }
    }

    @Test("Documented inbox receives ordered bytes and shuts down", .timeLimit(.minutes(1)))
    func twoPeerExchange() async throws {
        let databaseID = UUID().uuidString.lowercased()
        let receiver = try await open(databaseID: databaseID)
        defer { cleanUp(receiver) }
        let sender = try await open(databaseID: databaseID)
        defer { cleanUp(sender) }
        // Loopback TCP makes peer discovery deterministic; NGN carries the stream.
        let port = UInt16.random(in: 20_000..<40_000)
        receiver.updateTransportConfig { config in
            config.peerToPeer.lan.isEnabled = false
            config.listen.tcp.isEnabled = true
            config.listen.tcp.interfaceIP = "127.0.0.1"
            config.listen.tcp.port = port
        }
        sender.updateTransportConfig { $0.peerToPeer.lan.isEnabled = false; $0.connect.tcpServers = ["127.0.0.1:\(port)"] }
        try receiver.sync.start()
        try sender.sync.start()

        let (payloads, received) = AsyncStream<Data>.makeStream()
        let (errors, failed) = AsyncStream<String>.makeStream()
        let inbox = try StreamInbox(ditto: receiver, onPayload: { received.yield($0) }, onError: { failed.yield(String(describing: $0)) })
        defer { inbox.close(); received.finish(); failed.finish() }
        let peerKey = receiver.presence.graph.localPeer.peerKey
        // Presence/discovery can lag sync.start(). Retry only the connection setup.
        let candidate = try await connect(from: sender, to: peerKey, topic: "sensor_data")
        defer { candidate.close() }
        #expect(try candidate.topic == "sensor_data")
        let stream = try candidate.open()
        defer { stream.close() }
        #expect(try stream.peerKey == peerKey)
        for text in ["one", "two", "three"] {
            #expect(try await stream.send(Data(text.utf8)) == .sent)
        }
        for text in ["one", "two", "three"] {
            #expect(try await firstElement(of: payloads) == Data(text.utf8))
        }
        // Closing the acceptor via the sample closes its retained streams too.
        inbox.close()
        #expect(try await stream.waitUntilClosed() == .closedByRemote)

        // Exercise the exact sender function documented alongside the inbox.
        let nextInbox = try StreamInbox(ditto: receiver, onPayload: { received.yield($0) }, onError: { failed.yield(String(describing: $0)) })
        defer { nextInbox.close() }
        try await sendReading(from: sender, to: peerKey, payload: Data("reading".utf8))
        #expect(try await firstElement(of: payloads) == Data("reading".utf8))
        // Finishing makes a queued callback error fail without waiting for another.
        failed.finish()
        var errorIterator = errors.makeAsyncIterator()
        #expect(await errorIterator.next() == nil)
    }

    @Test("Bidirectional bytes and handshake arguments; unbinding leaves open streams alive",
          .timeLimit(.minutes(1)), arguments: [DittoReliability.reliable, .unreliable])
    func bidirectional(reliability: DittoReliability) async throws {
        let databaseID = UUID().uuidString.lowercased()
        let server = try await open(databaseID: databaseID)
        defer { cleanUp(server) }
        let client = try await open(databaseID: databaseID)
        defer { cleanUp(client) }
        let port = UInt16.random(in: 20_000..<40_000)
        server.updateTransportConfig {
            $0.peerToPeer.lan.isEnabled = false
            $0.listen.tcp.isEnabled = true
            $0.listen.tcp.interfaceIP = "127.0.0.1"
            $0.listen.tcp.port = port
        }
        client.updateTransportConfig { $0.peerToPeer.lan.isEnabled = false; $0.connect.tcpServers = ["127.0.0.1:\(port)"] }
        try server.sync.start()
        try client.sync.start()

        let (opened, accepted) = AsyncStream<DittoStream>.makeStream()
        let (serverBytes, serverReceived) = AsyncStream<Data>.makeStream()
        let (clientBytes, clientReceived) = AsyncStream<Data>.makeStream()
        let acceptor = try server.dataStreams.bindTopic("roundtrip", reliability: reliability) { candidate in
            do {
                #expect(try candidate.arguments == Data("request".utf8))
                let stream = try candidate.open(arguments: Data("accepted".utf8)) { inbound in
                    do { serverReceived.yield(try inbound.payload) } catch { Issue.record(error) }
                }
                accepted.yield(stream)
            } catch { Issue.record(error) }
        }
        defer { acceptor.close(); accepted.finish(); serverReceived.finish(); clientReceived.finish() }
        let candidate = try await connect(from: client, to: server.presence.graph.localPeer.peerKey,
                                          topic: "roundtrip", reliability: reliability)
        defer { candidate.close() }
        #expect(try candidate.arguments == Data("accepted".utf8))
        let clientStream = try candidate.open { inbound in
            do { clientReceived.yield(try inbound.payload) } catch { Issue.record(error) }
        }
        defer { clientStream.close() }
        let serverStream = try await firstElement(of: opened)
        defer { serverStream.close() }
        do {
            try await client.dataStreams.connect(
                peerKey: server.presence.graph.localPeer.peerKey, topic: "roundtrip",
                reliability: reliability == .reliable ? .unreliable : .reliable, timeoutMs: 1_000
            ) { _ in Issue.record("Mismatched reliability was accepted") }
            Issue.record("Expected a reliability mismatch to fail")
        } catch let error as DittoError {
            guard case .dataStreamsError = error else { throw error }
        }
        acceptor.close()
        #expect(try clientStream.maxSendSize > 0)
        #expect(try await clientStream.send(Data("ping".utf8)) == .sent)
        #expect(try await firstElement(of: serverBytes) == Data("ping".utf8))
        #expect(try await serverStream.send(Data("pong".utf8)) == .sent)
        #expect(try await firstElement(of: clientBytes) == Data("pong".utf8))
        server.dataStreams.close()
        #expect(throws: DittoError.self) { try serverStream.topic }
        #expect(try await clientStream.waitUntilClosed() == .closedByRemote)
    }
}
#endif
