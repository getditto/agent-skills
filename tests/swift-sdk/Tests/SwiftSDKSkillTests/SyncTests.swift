//
// CAP-06 Transports, CAP-07 Subscriptions and sync scopes, CAP-14 Sync status.
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

@Suite("Sync")
struct SyncTests {

    @Test("a subscription is registered, introspectable and cancellable")
    func subscriptionLifecycle() async throws {
        let peer = try await TestPeer.open(startSync: true)
        defer { peer.tearDown() }

        let subscription = try peer.ditto.sync.registerSubscription(
            query: "SELECT * FROM cars WHERE mileage > :minimum",
            arguments: ["minimum": 100]
        )

        #expect(subscription.queryString.contains("SELECT * FROM cars"))
        #expect(subscription.queryArguments?["minimum"] as? Int == 100)
        #expect(subscription.isCancelled == false)
        #expect(peer.ditto.sync.subscriptions.contains(subscription))

        #if !DITTO_V4
        // CBOR/JSON introspection of the bound arguments is v5 only.
        #expect(subscription.queryArgumentsJSONData != nil)
        #expect(subscription.queryArgumentsCBORData != nil)
        #endif

        subscription.cancel()
        #expect(subscription.isCancelled == true)
        #expect(peer.ditto.sync.subscriptions.contains(subscription) == false)
    }

    @Test("sync.subscriptions is computed, so a cached snapshot goes stale")
    func subscriptionsCollectionIsComputed() async throws {
        let peer = try await TestPeer.open(startSync: true)
        defer { peer.tearDown() }

        let snapshot = peer.ditto.sync.subscriptions
        #expect(snapshot.isEmpty)

        let subscription = try peer.ditto.sync.registerSubscription(query: "SELECT * FROM cars")
        defer { subscription.cancel() }

        #expect(snapshot.isEmpty)
        #expect(peer.ditto.sync.subscriptions.count == 1)
    }

    @Test("registerSubscription rejects invalid DQL")
    func subscriptionRejectsInvalidQuery() async throws {
        let peer = try await TestPeer.open(startSync: true)
        defer { peer.tearDown() }

        do {
            _ = try peer.ditto.sync.registerSubscription(query: "SELEKT * FROM cars")
            Issue.record("expected queryInvalid")
        } catch let error as DittoError {
            guard case .queryInvalid = error.storeReason else {
                Issue.record("expected queryInvalid, got \(error)")
                return
            }
        }
    }

    @Test("sync scopes are set with ALTER SYSTEM before sync starts")
    func syncScopesAreSetThroughAlterSystem() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        // sync-scopes.mdx warns this must run before `ditto.sync.start()`.
        #expect(peer.ditto.sync.isActive == false)
        try await peer.ditto.store.execute(
            query: "ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES = :syncScopes",
            arguments: ["syncScopes": ["cars": "LocalPeerOnly"]]
        )

        let result = try await peer.ditto.store.execute(query: "SHOW USER_COLLECTION_SYNC_SCOPES")
        let value = try #require(result.items.first).value
        #expect(String(describing: value).contains("LocalPeerOnly"))

        try peer.ditto.sync.start()
    }

    @Test("a live instance enables every peer-to-peer transport by default")
    func peerToPeerTransportsDefaultOn() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        let live = peer.ditto.transportConfig
        #expect(live.peerToPeer.bluetoothLE.isEnabled)
        #expect(live.peerToPeer.lan.isEnabled)
        #expect(live.peerToPeer.lan.isMDNSEnabled)
        #expect(live.peerToPeer.awdl.isEnabled)

        // A freshly constructed value type has them all OFF. Assigning one to
        // `ditto.transportConfig` therefore silently disables the mesh.
        let fresh = DittoTransportConfig()
        #expect(fresh.peerToPeer.bluetoothLE.isEnabled == false)
        #expect(fresh.peerToPeer.lan.isEnabled == false)
        #expect(fresh.peerToPeer.awdl.isEnabled == false)
    }

    @Test("a mutation carries a commitID; a SELECT and a transaction do not")
    func commitIDIsPresentOnMutationsOnly() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        let inserted = try await peer.ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:car)",
            arguments: ["car": ["_id": "commit-1", "make": "Toyota"]]
        )
        #expect(inserted.commitID != nil)

        let selected = try await peer.ditto.store.execute(query: "SELECT * FROM cars")
        #expect(selected.commitID == nil)

        _ = try await peer.ditto.store.transaction(hint: "commit-id") { transaction in
            let result = try await transaction.execute(
                query: "INSERT INTO cars DOCUMENTS (:car)",
                arguments: ["car": ["_id": "commit-2", "make": "Honda"]]
            )
            // A statement inside a transaction has no commit yet.
            #expect(result.commitID == nil)
            return DittoTransactionCompletionAction.commit
        }
    }

    @Test("transport configuration is read and updated through updateTransportConfig")
    func transportConfigRoundTrips() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        peer.ditto.updateTransportConfig { config in
            config.peerToPeer.bluetoothLE.isEnabled = false
            config.peerToPeer.lan.isEnabled = false
            config.peerToPeer.awdl.isEnabled = false
        }

        #expect(peer.ditto.transportConfig.peerToPeer.bluetoothLE.isEnabled == false)
        #expect(peer.ditto.transportConfig.peerToPeer.lan.isEnabled == false)
        #expect(peer.ditto.transportConfig.peerToPeer.awdl.isEnabled == false)
    }

    @Test("DittoHTTPListenConfig.webSocketSync flipped default from true to false in v5")
    func webSocketSyncDefault() throws {
        // Only `DittoTransportConfig` has a public initializer; the nested config
        // structs are reached through it.
        let config = DittoTransportConfig()
        #if DITTO_V4
        #expect(config.listen.http.webSocketSync == true)
        #else
        #expect(config.listen.http.webSocketSync == false)
        #endif
    }
}
