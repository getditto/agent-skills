//
// CAP-19 version-gated behaviour that the skill states as fact.
//
// These are the claims in references/versions.md that can be asserted from a running
// SDK rather than read out of a changelog.
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

@Suite("Version-gated behaviour")
struct VersionTests {

    @Test(
        "4.14.x rejects mutating DQL until disableSyncWithV3() is called",
        .enabled(if: isV4, "v5 has no v3 sync to disable")
    )
    func mutatingDQLRequiresDisableSyncWithV3() async throws {
        #if DITTO_V4
        let directory = TestPeer.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let config = DittoConfig(
            databaseID: SkillTestEnvironment.databaseID,
            connect: .smallPeersOnly(),
            persistenceDirectory: directory
        )
        let ditto = try await Ditto.open(config: config)
        try ditto.setOfflineOnlyLicenseToken(SkillTestEnvironment.offlineLicense)

        do {
            try await ditto.store.execute(
                query: "INSERT INTO cars DOCUMENTS (:car)",
                arguments: ["car": ["_id": "v3-gate", "make": "Toyota"]]
            )
            Issue.record("expected mutating DQL to be rejected before disableSyncWithV3()")
        } catch let error as DittoError {
            guard case .queryNotSupported(let message) = error.storeReason else {
                Issue.record("expected queryNotSupported, got \(error)")
                return
            }
            #expect(message.contains("disable sync with V3"))
        }

        // A SELECT is accepted either way — only mutations are gated.
        _ = try await ditto.store.execute(query: "SELECT * FROM cars")

        try ditto.disableSyncWithV3()
        try await ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:car)",
            arguments: ["car": ["_id": "v3-gate", "make": "Toyota"]]
        )
        #endif
    }

    @Test(
        "isActivated is the v5 spelling; 4.14.x has only the deprecated activated",
        .enabled(if: !isV4, "the v4 spelling is asserted in ConnectTests")
    )
    func isActivatedIsV5Spelling() async throws {
        #if !DITTO_V4
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }
        #expect(peer.ditto.isActivated == true)
        #endif
    }

    // NOTE: there is deliberately no test for "the observation handler type aliases are
    // @Sendable from 5.1.0". It is a compile-time property, and this fixture compiles
    // one source tree for all three lines, so any assertion that passed on 5.0.3 would
    // be vacuous and any assertion that failed would break the 5.0.3 build. The claim is
    // carried as `source` evidence in references/versions.md and listed under "Not
    // verified" in README.md.

    /// Named for what it asserts. The `ditto-{databaseID}` LEAF is not observable from
    /// `defaultRootDirectory`, which is the container above it — that claim is covered by
    /// `scripts/persistence-matrix.sh`'s default-directory leg, which opens with no
    /// `persistenceDirectory` and asserts the resulting path with `--expect-directory`.
    @Test("Ditto.defaultRootDirectory is under Application Support on every line")
    func defaultRootDirectoryIsUnderApplicationSupport() async throws {
        #expect(Ditto.defaultRootDirectory.path.contains("Application Support"))
    }

    @Test("DittoConnectionType.multicast exists from 5.1.0 only")
    func multicastConnectionTypeIsNewIn51() throws {
        let hasMulticast = DittoConnectionType.allCases.contains { $0.rawValue == "Multicast" }
        if Ditto.version.hasPrefix("5.1.") {
            #expect(hasMulticast)
        } else {
            #expect(hasMulticast == false)
        }
    }
}
