//
// CAP-13 Presence graph and connection requests.
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

@Suite("Presence")
struct PresenceTests {

    @Test("the presence graph always has a local peer")
    func graphHasLocalPeer() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        let graph = peer.ditto.presence.graph
        #if DITTO_V4
        #expect(graph.localPeer.peerKeyString.isEmpty == false)
        #else
        #expect(graph.localPeer.peerKey.isEmpty == false)
        #endif
        #expect(graph.localPeer.deviceName.isEmpty == false)
    }

    @Test("presence.observe delivers a graph and its handle stops it")
    func observeDeliversGraph() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        let recorder = DeliveryRecorder<String>()
        let observer = peer.ditto.presence.observe { graph in
            #if DITTO_V4
            recorder.record(graph.localPeer.peerKeyString)
            #else
            recorder.record(graph.localPeer.peerKey)
            #endif
        }
        defer { observer.stop() }

        let keys = try await firstElement(of: recorder.stream) { !$0.isEmpty }
        #if DITTO_V4
        #expect(keys.first == peer.ditto.presence.graph.localPeer.peerKeyString)
        #else
        #expect(keys.first == peer.ditto.presence.graph.localPeer.peerKey)
        #endif
        recorder.finish()
    }

    @Test("peer metadata round-trips")
    func peerMetadataRoundTrips() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        try peer.ditto.presence.setPeerMetadata(["role": "fixture"])
        #expect(peer.ditto.presence.peerMetadata["role"] as? String == "fixture")
    }

    @Test("DittoPeerOS decodes the values the presence graph carries")
    func peerOSDecoding() throws {
        #expect(DittoPeerOS(from: "iOS") == .iOS)
        #expect(DittoPeerOS(from: "macOS") == .macOS)
        #expect(DittoPeerOS(from: "Android") == .android)
        // A value the SDK does not know does not crash a switch — it lands in
        // `.unknown`, which is why an exhaustive switch needs that case.
        #expect(DittoPeerOS(from: "Fuchsia") == .unknown(os: "Fuchsia"))
    }
}
