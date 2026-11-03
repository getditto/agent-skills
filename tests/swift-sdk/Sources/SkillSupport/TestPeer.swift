//
// A disposable, offline-only Ditto instance in its own temporary directory.
//
// Every test gets its own directory so that one opened instance per persistence
// directory (`StoreErrorReason.persistenceDirectoryLocked`) is a property under test
// rather than an accident of ordering.
//

import Foundation
#if DITTO_V4
// 4.14.x predates the `Sendable` conformances v5 added: in Swift 6 language mode
// `Ditto` and `DittoStore` cannot cross an isolation boundary without this, and the
// build fails with "sending 'ditto' risks causing data races".
@preconcurrency import DittoSwift
#else
import DittoSwift
#endif

public final class TestPeer {
    public let ditto: Ditto
    public let directory: URL

    init(ditto: Ditto, directory: URL) {
        self.ditto = ditto
        self.directory = directory
    }

    /// Opens an activated, offline-only instance. `startSync` defaults to false: sync
    /// is not needed to exercise the local store, and leaving the radios off keeps the
    /// run deterministic and quiet.
    public static func open(
        directory: URL? = nil,
        startSync: Bool = false
    ) async throws -> TestPeer {
        let directory = directory ?? Self.makeTemporaryDirectory()
        let config = DittoConfig(
            databaseID: SkillTestEnvironment.databaseID,
            connect: .smallPeersOnly(),
            persistenceDirectory: directory
        )

        let ditto = try await Ditto.open(config: config)
        try ditto.setOfflineOnlyLicenseToken(SkillTestEnvironment.offlineLicense)

        // 4.14.x refuses mutating DQL until sync with v3 peers is disabled. The call is
        // deprecated on that line and does not exist in v5 — see
        // skills/swift-sdk/references/versions.md.
        #if DITTO_V4
        try ditto.disableSyncWithV3()
        #endif

        if startSync {
            try ditto.sync.start()
        }

        return TestPeer(ditto: ditto, directory: directory)
    }

    public static func makeTemporaryDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ditto-swift-skill-\(UUID().uuidString)", isDirectory: true)
    }

    /// Stops sync and removes the temporary directory. The `Ditto` instance itself is
    /// released when the last reference to this object goes away.
    public func tearDown() {
        if ditto.sync.isActive {
            ditto.sync.stop()
        }
        try? FileManager.default.removeItem(at: directory)
    }
}
