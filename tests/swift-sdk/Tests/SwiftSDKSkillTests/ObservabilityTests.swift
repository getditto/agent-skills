//
// CAP-15 Logging, diagnostics and stats.
//

import Foundation
import Testing
#if DITTO_V4
// 4.14.x predates the `Sendable` conformances v5 added: in Swift 6 language mode
// `Ditto` and `DittoStore` cannot cross an isolation boundary without this, and the
// build fails with "sending 'ditto' risks causing data races".
@preconcurrency import DittoSwift
#else
import DittoSwift
#endif
@testable import SkillSupport

@Suite(.serialized)
struct ObservabilityTests {

    @Test("the logger level round-trips")
    func loggerLevelRoundTrips() throws {
        let originalEnabled = DittoLogger.isEnabled
        let originalLevel = DittoLogger.minimumLogLevel
        defer {
            DittoLogger.isEnabled = originalEnabled
            DittoLogger.minimumLogLevel = originalLevel
        }

        DittoLogger.isEnabled = true
        DittoLogger.minimumLogLevel = .warning
        #expect(DittoLogger.isEnabled == true)
        #expect(DittoLogger.minimumLogLevel == .warning)
    }

    @Test("a custom log callback receives SDK log lines")
    func customLogCallbackReceivesLines() async throws {
        let originalEnabled = DittoLogger.isEnabled
        let originalLevel = DittoLogger.minimumLogLevel
        defer {
            DittoLogger.setCustomLogCallback(nil)
            DittoLogger.isEnabled = originalEnabled
            DittoLogger.minimumLogLevel = originalLevel
        }

        let recorder = DeliveryRecorder<String>()
        DittoLogger.isEnabled = true
        DittoLogger.minimumLogLevel = .debug
        DittoLogger.setCustomLogCallback { level, message in
            recorder.record("\(level):\(message)")
        }

        let peer = try await TestPeer.open(startSync: true)
        defer { peer.tearDown() }
        try await peer.ditto.store.execute(query: "SELECT * FROM cars")

        let lines = try await firstElement(of: recorder.stream) { !$0.isEmpty }
        #expect(lines.isEmpty == false)
        recorder.finish()
    }

    @Test("disk usage reports the persistence directory")
    func diskUsageReportsDirectory() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        try await peer.ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:car)",
            arguments: ["car": ["_id": "disk-1", "make": "Toyota"]]
        )

        #if DITTO_V4
        // 4.14.x: `DiskUsage.exec`, renamed to `DittoDiskUsage.item` in v5.
        let item = peer.ditto.diskUsage.exec
        #else
        let item = peer.ditto.diskUsage.item
        #endif
        #expect(item.sizeInBytes > 0)
        #expect(item.path.isEmpty == false)
    }

    @Test("small peer info metadata round-trips")
    func smallPeerInfoMetadataRoundTrips() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        try peer.ditto.smallPeerInfo.setMetadata(["deployment": "fixture"])
        #expect(peer.ditto.smallPeerInfo.metadata["deployment"] as? String == "fixture")
    }

    @Test("system information is read through the same execute call as any DQL")
    func systemQueriesExecute() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        try await peer.ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:car)",
            arguments: ["car": ["_id": "system-1", "make": "Toyota", "mileage": 1]]
        )
        try await peer.ditto.store.execute(query: "CREATE INDEX cars_mileage ON cars (mileage)")

        let collections = try await peer.ditto.store.execute(query: "SELECT * FROM system:collections")
        #expect(collections.items.isEmpty == false)

        let indexes = try await peer.ditto.store.execute(query: "SELECT * FROM system:indexes")
        #expect(indexes.items.isEmpty == false)

        let all = try await peer.ditto.store.execute(query: "SHOW ALL")
        #expect(all.items.isEmpty == false)
    }

    @Test("logs export to a file")
    func logsExportToFile() async throws {
        let originalEnabled = DittoLogger.isEnabled
        defer { DittoLogger.isEnabled = originalEnabled }
        DittoLogger.isEnabled = true

        let peer = try await TestPeer.open()
        defer { peer.tearDown() }
        try await peer.ditto.store.execute(query: "SELECT * FROM cars")

        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ditto-skill-logs-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: destination) }

        let bytesWritten = try await DittoLogger.export(to: destination)
        #expect(bytesWritten > 0)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }
}
