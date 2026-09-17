//
// CAP-12 Attachments.
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

@Suite("Attachments")
struct AttachmentTests {

    @Test(
        "an in-memory attachment round-trips through a document",
        .enabled(if: !isV4, "newAttachment(data:) is v5 only; 4.14.x takes a file path")
    )
    func inMemoryAttachmentRoundTrips() async throws {
        #if !DITTO_V4
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        let payload = Data("ditto swift skill fixture".utf8)
        let attachment = try await peer.ditto.store.newAttachment(
            data: payload,
            metadata: ["name": "note.txt"]
        )
        #expect(attachment.len == UInt64(payload.count))
        #expect(attachment.metadata["name"] == "note.txt")

        try await peer.ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:car)",
            arguments: ["car": ["_id": "attach-1", "photo": attachment]]
        )

        let value = try #require(
            try await peer.ditto.store.execute(
                query: "SELECT * FROM cars WHERE _id = :id",
                arguments: ["id": "attach-1"]
            ).items.first
        ).value

        // In v5 an attachment token in a query result is a plain dictionary; the
        // `DittoAttachmentToken` type is no longer public.
        let token = try #require(value["photo"] as? [String: Any])

        let recorder = DeliveryRecorder<String>()
        let fetcher = try peer.ditto.store.fetchAttachment(token: token) { event in
            switch event {
            case .completed(let fetched):
                recorder.record("completed:\(fetched.len)")
            case .progress:
                recorder.record("progress")
            case .deleted:
                recorder.record("deleted")
            @unknown default:
                recorder.record("unknown")
            }
        }
        defer { fetcher.stop() }

        let events = try await firstElement(of: recorder.stream) { events in
            events.contains { $0.hasPrefix("completed:") }
        }
        #expect(events.contains("completed:\(payload.count)"))
        recorder.finish()
        #endif
    }

    @Test("a file-backed attachment round-trips and its bytes match")
    func fileAttachmentRoundTrips() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        let payload = Data("file backed attachment".utf8)
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("skill-attachment-\(UUID().uuidString).txt")
        try payload.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let attachment = try await peer.ditto.store.newAttachment(
            path: fileURL.path,
            metadata: ["name": fileURL.lastPathComponent]
        )
        #expect(try attachment.data() == payload)
    }

    @Test(
        "an attachment token from a query result has the shape fetchAttachment requires",
        .enabled(if: !isV4, "newAttachment(data:) is v5 only")
    )
    func attachmentTokenShape() async throws {
        #if !DITTO_V4
        // `fetchAttachment(token:)` does NOT validate: a dictionary that is not a real
        // attachment token calls `fatalError` inside `DittoAttachmentToken.init`
        // (sdk-release-5.1.0:sdks/swift/DittoSwift/DittoAttachmentToken.swift:35), so an
        // app must take the token from the document rather than construct one. This
        // test pins the shape that is safe to pass.
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        let attachment = try await peer.ditto.store.newAttachment(
            data: Data("token shape".utf8),
            metadata: ["name": "note.txt"]
        )
        try await peer.ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:car)",
            arguments: ["car": ["_id": "token-shape", "photo": attachment]]
        )

        let value = try #require(
            try await peer.ditto.store.execute(
                query: "SELECT * FROM cars WHERE _id = :id",
                arguments: ["id": "token-shape"]
            ).items.first
        ).value
        let token = try #require(value["photo"] as? [String: Any])

        #expect(token["id"] is String)
        #expect(token["len"] != nil)
        #expect(token["metadata"] is [String: Any])
        #endif
    }
}
