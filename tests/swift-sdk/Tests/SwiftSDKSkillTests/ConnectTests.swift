//
// CAP-03 Connecting, CAP-04 Authentication, CAP-05 Lifecycle.
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

@Suite("Connect and lifecycle")
struct ConnectTests {

    @Test(
        "the build is pinned to the version it claims",
        .enabled(if: SkillTestEnvironment.expectedVersion != nil,
                 "DITTO_SWIFT_VERSION is unset — run through scripts/run.sh")
    )
    func versionMatchesPin() throws {
        // `#require`, not `guard … else { return }`: a silently-skipped guard turns the
        // suite's only stale-build check into a green no-op whenever the harness is
        // invoked outside scripts/run.sh.
        let expected = try #require(SkillTestEnvironment.expectedVersion)
        #expect(Ditto.version == expected)
    }

    @Test("an offline-only peer is not activated until a license token is set")
    func activationRequiresLicenseToken() async throws {
        let directory = TestPeer.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let config = DittoConfig(
            databaseID: SkillTestEnvironment.databaseID,
            connect: .smallPeersOnly(),
            persistenceDirectory: directory
        )
        let ditto = try await Ditto.open(config: config)

        #if DITTO_V4
        #expect(ditto.activated == false)
        #else
        #expect(ditto.isActivated == false)
        #endif

        try ditto.setOfflineOnlyLicenseToken(SkillTestEnvironment.offlineLicense)

        #if DITTO_V4
        #expect(ditto.activated == true)
        #else
        #expect(ditto.isActivated == true)
        #endif
    }

    @Test("an invalid license token throws activationError(.licenseTokenVerificationFailed)")
    func invalidLicenseTokenThrows() async throws {
        let directory = TestPeer.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let config = DittoConfig(
            databaseID: SkillTestEnvironment.databaseID,
            connect: .smallPeersOnly(),
            persistenceDirectory: directory
        )
        let ditto = try await Ditto.open(config: config)

        do {
            try ditto.setOfflineOnlyLicenseToken("not-a-license-token")
            Issue.record("expected setOfflineOnlyLicenseToken to throw")
        } catch let error as DittoError {
            guard case .activationError(let reason) = error else {
                Issue.record("expected activationError, got \(error)")
                return
            }
            if case .licenseTokenVerificationFailed = reason {
                // Expected.
            } else {
                Issue.record("expected licenseTokenVerificationFailed, got \(reason)")
            }
        }
    }

    @Test("opening a second instance on a live persistence directory fails")
    func persistenceDirectoryIsExclusive() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        let config = DittoConfig(
            databaseID: SkillTestEnvironment.databaseID,
            connect: .smallPeersOnly(),
            persistenceDirectory: peer.directory
        )

        // Assert the specific reason, not merely "something threw" — otherwise an
        // unopenable path or a bad license would satisfy this test just as well.
        do {
            _ = try await Ditto.open(config: config)
            Issue.record("expected persistenceDirectoryLocked")
        } catch let error as DittoError {
            guard case .persistenceDirectoryLocked = error.storeReason else {
                Issue.record("expected persistenceDirectoryLocked, got \(error)")
                return
            }
        }
    }

    @Test("the same directory can be reopened once the first instance is released")
    func persistenceDirectoryIsReusableAfterRelease() async throws {
        let directory = TestPeer.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var first: TestPeer? = try await TestPeer.open(directory: directory)
        try await first?.ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:car)",
            arguments: ["car": ["_id": "reopen-1", "make": "Volvo"]]
        )
        first = nil

        let second = try await TestPeer.open(directory: directory)
        defer { second.tearDown() }

        let result = try await second.ditto.store.execute(
            query: "SELECT * FROM cars WHERE _id = :id",
            arguments: ["id": "reopen-1"]
        )
        #expect(result.items.count == 1)
    }

    @Test("sync.start and sync.stop drive sync.isActive")
    func syncLifecycle() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        #expect(peer.ditto.sync.isActive == false)
        try peer.ditto.sync.start()
        #expect(peer.ditto.sync.isActive == true)
        peer.ditto.sync.stop()
        #expect(peer.ditto.sync.isActive == false)
    }

    @Test("the local store stays readable after sync is stopped")
    func storeSurvivesSyncStop() async throws {
        let peer = try await TestPeer.open(startSync: true)
        defer { peer.tearDown() }

        try await peer.ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:car)",
            arguments: ["car": ["_id": "offline-1", "make": "Saab"]]
        )
        peer.ditto.sync.stop()

        let result = try await peer.ditto.store.execute(query: "SELECT * FROM cars")
        #expect(result.items.count == 1)
    }

    @Test("auth is nil on an offline-only instance")
    func authIsNilOffline() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }
        #expect(peer.ditto.auth == nil)
    }

    @Test(
        "a server-backed instance refuses to start sync without an expiration handler",
        .enabled(if: SkillTestEnvironment.serverURL != nil, "needs DITTO_URL")
    )
    func serverSyncRequiresExpirationHandler() async throws {
        let directory = TestPeer.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let config = DittoConfig(
            databaseID: SkillTestEnvironment.databaseID,
            connect: .server(url: SkillTestEnvironment.serverURL!),
            persistenceDirectory: directory
        )
        let ditto = try await Ditto.open(config: config)
        #expect(ditto.auth != nil)

        do {
            try ditto.sync.start()
            ditto.sync.stop()
            Issue.record("expected sync.start() to fail without an expiration handler")
        } catch let error as DittoError {
            guard case .authenticationError(let reason) = error,
                  case .expirationHandlerMissing = reason
            else {
                Issue.record("expected expirationHandlerMissing, got \(error)")
                return
            }
        }
    }

    // NOTE: there is deliberately no test for the documented server-teardown sequence.
    //
    // Two reasons. It cannot catch the regression it would exist for — the panic needs a
    // login in flight during shutdown, which a short test almost never has, so removing
    // a step from the sequence does not make such a test fail. And worse, running it
    // *triggers* the race often enough to abort the whole test process, taking every
    // other case with it. The race is described in references/connect.md and listed
    // under "Not verified" in README.md, which is the honest place for it.

    @Test("an explicit persistence directory is the resolved absolute directory")
    func explicitPersistenceDirectoryIsHonoured() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        #expect(
            peer.ditto.absolutePersistenceDirectory.standardizedFileURL.path
                == peer.directory.standardizedFileURL.path
        )
    }
}
