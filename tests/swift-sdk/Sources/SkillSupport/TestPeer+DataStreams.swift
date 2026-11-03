//
// Peers for the Data Streams tests (5.2.0+, behind DITTO_DATA_STREAMS).
//
// Two instances in one process, linked only by a TCP loopback listener, with NGN enabled
// through `DittoConfig.systemParameters` — the 5.2.0 way to turn it on at open, with no
// environment variable. LAN discovery is off so the loopback link is the only one under
// test.
//

#if DITTO_DATA_STREAMS
import Foundation
import DittoSwift

extension TestPeer {

    /// System parameters that enable NGN, which Data Streams run over. `replication_over_ngn`
    /// stays false so document sync keeps using the existing transports (the docs'
    /// recommendation for the preview).
    public static let ngnSystemParameters: [String: DittoSystemParameterValue] = [
        "network_enable_ngn": .bool(true),
        "replication_over_ngn": .bool(false),
    ]

    /// Opens an offline-only peer with NGN enabled and sync started, after applying
    /// `configure` to a copy of the current transport config.
    public static func openForDataStreams(
        configure: @escaping (inout DittoTransportConfig) -> Void
    ) async throws -> TestPeer {
        let directory = makeTemporaryDirectory()
        let config = DittoConfig(
            databaseID: SkillTestEnvironment.databaseID,
            connect: .smallPeersOnly(),
            persistenceDirectory: directory,
            systemParameters: ngnSystemParameters
        )
        let ditto = try await Ditto.open(config: config)
        try ditto.setOfflineOnlyLicenseToken(SkillTestEnvironment.offlineLicense)
        // Modify the current config: a fresh DittoTransportConfig() has every transport off.
        ditto.updateTransportConfig { config in
            config.peerToPeer.lan.isEnabled = false
            configure(&config)
        }
        try await startSyncOnLargeStack(ditto)
        return TestPeer(ditto: ditto, directory: directory)
    }

    /// A loopback-connected pair: `server` listens on 127.0.0.1, `client` dials it. Returns
    /// once presence on both sides shows the other peer.
    public static func connectedPair() async throws -> (server: TestPeer, client: TestPeer) {
        let port = UInt16.random(in: 20_000..<40_000)
        let server = try await openForDataStreams { config in
            config.listen.tcp.isEnabled = true
            config.listen.tcp.interfaceIP = "127.0.0.1"
            config.listen.tcp.port = port
        }
        let client = try await openForDataStreams { config in
            config.connect.tcpServers = ["127.0.0.1:\(port)"]
        }
        let serverDitto = server.ditto, clientDitto = client.ditto   // Ditto is Sendable in v5
        let serverKey = serverDitto.presence.graph.localPeer.peerKey
        let clientKey = clientDitto.presence.graph.localPeer.peerKey
        try await waitUntil("presence shows both peers", seconds: 30) {
            serverDitto.presence.graph.remotePeers.contains { $0.peerKey == clientKey }
                && clientDitto.presence.graph.remotePeers.contains { $0.peerKey == serverKey }
        }
        return (server, client)
    }

    /// With NGN enabled, `sync.start()` synchronously spawns the UDP transport, whose
    /// future needs several hundred KB of stack in debug builds — more than a Swift
    /// cooperative thread has. The Ditto reference app and its SDK tests start sync on a
    /// dedicated large-stack thread; this does the same.
    public static func startSyncOnLargeStack(_ ditto: Ditto) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let thread = Thread {
                continuation.resume(with: Result { try ditto.sync.start() })
            }
            thread.stackSize = 64 << 20
            thread.start()
        }
    }

    public static func waitUntil(
        _ what: String,
        seconds: Double,
        _ condition: @escaping @Sendable () -> Bool
    ) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while !condition() {
            if ProcessInfo.processInfo.systemUptime >= deadline { throw SkillTestError.timedOut(what) }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
#endif
