//
// CAP-16 Error handling.
//
// Every case here is one an application can actually catch. The v5 use-after-release
// paths are deliberately absent: they call `fatalError`, which cannot be tested without
// crashing the test host. See references/errors.md.
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

@Suite("Errors")
struct ErrorTests {

    @Test("DittoError conforms to LocalizedError and carries a message")
    func errorsAreLocalized() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        do {
            _ = try await peer.ditto.store.execute(query: "SELEKT * FROM cars")
            Issue.record("expected a DittoError")
        } catch let error as DittoError {
            #expect(error.errorDescription?.isEmpty == false)
            #expect(error.localizedDescription.isEmpty == false)
        }
    }

    @Test("the 5 MiB per-document limit is enforced from 5.1.0 and not before")
    func oversizedDocumentBehaviourIsVersionGated() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        let oversized = String(repeating: "x", count: 5 * 1024 * 1024)
        let insert = {
            try await peer.ditto.store.execute(
                query: "INSERT INTO cars DOCUMENTS (:car)",
                arguments: ["car": ["_id": "oversized", "blob": oversized]]
            )
        }

        if Ditto.version.hasPrefix("5.1.") {
            do {
                try await insert()
                Issue.record("expected the insert of an oversized document to fail on 5.1.x")
            } catch let error as DittoError {
                // The per-document limit surfaces from the query engine as
                // `unknownError` carrying the byte counts — not as
                // `validationError(.sizeLimitExceeded)`, which is what the small-peer
                // metadata setters use. Match on the message, not on the case.
                #expect(error.localizedDescription.contains("exceeds limit of 5242880 bytes"))
            }
        } else {
            // 4.14.6 and 5.0.3 accept it. An app that writes documents this large will
            // start failing on 5.1.x — see references/versions.md.
            try await insert()
            let result = try await peer.ditto.store.execute(
                query: "SELECT _id FROM cars WHERE _id = :id",
                arguments: ["id": "oversized"]
            )
            #expect(result.items.count == 1)
        }
    }

    @Test("small peer metadata over the size limit throws validationError(.sizeLimitExceeded)")
    func oversizedPeerMetadataThrows() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        let oversized = String(repeating: "x", count: 1024 * 1024)
        do {
            try peer.ditto.smallPeerInfo.setMetadata(["blob": oversized])
            Issue.record("expected a validation error for oversized metadata")
        } catch let error as DittoError {
            guard case .validationError = error else {
                Issue.record("expected validationError, got \(error)")
                return
            }
        }
    }

    @Test(
        "4.14.x throws useAfterCloseError once its Ditto is released",
        .enabled(if: isV4, "v5 calls fatalError on this path instead (#SPO-960 was not carried forward)")
    )
    func useAfterCloseThrowsOnV4() async throws {
        #if DITTO_V4
        let directory = TestPeer.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var peer: TestPeer? = try await TestPeer.open(directory: directory)
        let store = peer!.ditto.store
        peer = nil

        do {
            _ = try store.registerObserver(query: "SELECT * FROM cars") { _ in }
            Issue.record("expected useAfterCloseError")
        } catch let error as DittoError {
            guard case .useAfterCloseError(let message) = error else {
                Issue.record("expected useAfterCloseError, got \(error)")
                return
            }
            #expect(message.contains("deallocated"))
        }
        #endif
    }
}
