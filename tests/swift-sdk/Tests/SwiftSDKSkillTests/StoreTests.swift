//
// CAP-08 Querying, CAP-09 Transactions, CAP-10 Indexing, CAP-17 Eviction.
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

@Suite("Store")
struct StoreTests {

    @Test("query arguments are bound, not interpolated")
    func argumentsAreBound() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        try await peer.ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:a), (:b)",
            arguments: [
                "a": ["_id": "bind-1", "make": "Toyota", "mileage": 120],
                "b": ["_id": "bind-2", "make": "Honda", "mileage": 80],
            ]
        )

        let result = try await peer.ditto.store.execute(
            query: "SELECT * FROM cars WHERE mileage > :minimum ORDER BY mileage",
            arguments: ["minimum": 100]
        )
        #expect(result.items.count == 1)
        #expect(result.items[0].value["make"] as? String == "Toyota")
    }

    @Test("integers round-trip as Int, including values beyond 2^53")
    func integersRoundTripAsInt() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        try await peer.ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:car)",
            arguments: ["car": [
                "_id": "types-1",
                "mileage": 120,
                "serial": 9_007_199_254_740_993 as Int,
                "sold": false,
            ]]
        )
        let value = try #require(
            try await peer.ditto.store.execute(query: "SELECT * FROM cars").items.first
        ).value

        #expect(value["mileage"] as? Int == 120)
        #expect(value["serial"] as? Int == 9_007_199_254_740_993)
        #expect(value["sold"] as? Bool == false)
    }

    @Test("a floating-point field is Float or Double depending on its value, so `as? Double` is unsafe")
    func floatingPointWidthIsValueDependent() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        try await peer.ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:car)",
            arguments: ["car": [
                "_id": "floats-1",
                // Exactly representable in binary32.
                "price": 19_999.5 as Double,
                // Not exactly representable in binary32.
                "rate": 0.1 as Double,
            ]]
        )
        let item = try #require(
            try await peer.ditto.store.execute(query: "SELECT * FROM cars").items.first
        )
        let value = item.value

        // The SDK narrows a value that fits binary32, so the obvious cast silently
        // fails on one field and succeeds on the other.
        #expect(value["price"] is Float)
        #expect(value["price"] as? Double == nil)
        #expect(value["rate"] is Double)

        // NSNumber accepts both.
        #expect((value["price"] as? NSNumber)?.doubleValue == 19_999.5)
        #expect((value["rate"] as? NSNumber)?.doubleValue == 0.1)

        // Decoding the item's JSON with Codable is the pattern the skill recommends:
        // both fields arrive as Double.
        struct Car: Codable { let price: Double; let rate: Double }
        let decoded = try JSONDecoder().decode(Car.self, from: item.jsonData())
        #expect(decoded.price == 19_999.5)
        #expect(decoded.rate == 0.1)
    }

    @Test("dematerialize() drops the cached value and .value re-materializes it")
    func dematerializeIsRepeatable() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        try await peer.ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:car)",
            arguments: ["car": ["_id": "demat-1", "make": "Toyota"]]
        )
        let item = try #require(
            try await peer.ditto.store.execute(query: "SELECT * FROM cars").items.first
        )

        #expect(item.isMaterialized == false)
        _ = item.value
        #expect(item.isMaterialized == true)
        item.dematerialize()
        #expect(item.isMaterialized == false)
        #expect(item.value["make"] as? String == "Toyota")
    }

    @Test("an invalid query throws storeError(.queryInvalid)")
    func invalidQueryThrows() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        do {
            _ = try await peer.ditto.store.execute(query: "SELEKT * FROM cars")
            Issue.record("expected a queryInvalid error")
        } catch let error as DittoError {
            guard case .queryInvalid = error.storeReason else {
                Issue.record("expected queryInvalid, got \(error)")
                return
            }
        }
    }

    @Test("an unsupported argument type throws storeError(.queryArgumentsInvalid)")
    func invalidArgumentsThrow() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        final class Unsupported: NSObject {}

        do {
            _ = try await peer.ditto.store.execute(
                query: "SELECT * FROM cars WHERE mileage > :minimum",
                arguments: ["minimum": Unsupported()]
            )
            Issue.record("expected a queryArgumentsInvalid error")
        } catch let error as DittoError {
            guard case .queryArgumentsInvalid = error.storeReason else {
                Issue.record("expected queryArgumentsInvalid, got \(error)")
                return
            }
        }
    }

    @Test("a Date argument is accepted and stored as a tagged object, not rejected")
    func dateArgumentsAreNotRejected() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        // `Date` is not a DQL type. It does not throw — it is encoded as
        // `{"__type": "date_epoch_timestamp", "__value": <seconds>}`, which will not
        // compare against anything an app expects. Store an ISO-8601 string instead.
        try await peer.ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:car)",
            arguments: ["car": ["_id": "date-1", "servicedAt": Date(timeIntervalSince1970: 1_700_000_000)]]
        )
        let value = try #require(
            try await peer.ditto.store.execute(query: "SELECT * FROM cars").items.first
        ).value
        let stored = try #require(value["servicedAt"] as? [String: Any?])
        #expect(stored["__type"] as? String == "date_epoch_timestamp")
    }

    @Test("a mutation reports its mutated document IDs")
    func mutationReportsDocumentIDs() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        let result = try await peer.ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:car)",
            arguments: ["car": ["_id": "mutate-1", "make": "Toyota"]]
        )
        #expect(result.mutatedDocumentIDs().count == 1)

        // A read reports none.
        let selected = try await peer.ditto.store.execute(query: "SELECT * FROM cars")
        #expect(selected.mutatedDocumentIDs().isEmpty)
    }

    @Test("a transaction returning .commit persists its writes")
    func transactionCommits() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        _ = try await peer.ditto.store.transaction(hint: "commit") { transaction in
            try await transaction.execute(
                query: "INSERT INTO cars DOCUMENTS (:car)",
                arguments: ["car": ["_id": "txn-commit", "make": "Toyota"]]
            )
            return DittoTransactionCompletionAction.commit
        }

        let result = try await peer.ditto.store.execute(
            query: "SELECT * FROM cars WHERE _id = :id",
            arguments: ["id": "txn-commit"]
        )
        #expect(result.items.count == 1)
    }

    @Test("a transaction returning .rollback discards its writes")
    func transactionRollsBack() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        _ = try await peer.ditto.store.transaction(hint: "rollback") { transaction in
            try await transaction.execute(
                query: "INSERT INTO cars DOCUMENTS (:car)",
                arguments: ["car": ["_id": "txn-rollback", "make": "Toyota"]]
            )
            return DittoTransactionCompletionAction.rollback
        }

        let result = try await peer.ditto.store.execute(
            query: "SELECT * FROM cars WHERE _id = :id",
            arguments: ["id": "txn-rollback"]
        )
        #expect(result.items.isEmpty)
    }

    @Test("a throwing transaction scope rolls back and rethrows")
    func throwingTransactionRollsBack() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        struct Boom: Error {}

        await #expect(throws: Boom.self) {
            _ = try await peer.ditto.store.transaction(hint: "throwing") { transaction in
                try await transaction.execute(
                    query: "INSERT INTO cars DOCUMENTS (:car)",
                    arguments: ["car": ["_id": "txn-throw", "make": "Toyota"]]
                )
                throw Boom()
            } as Void
        }

        let result = try await peer.ditto.store.execute(
            query: "SELECT * FROM cars WHERE _id = :id",
            arguments: ["id": "txn-throw"]
        )
        #expect(result.items.isEmpty)
    }

    @Test("a read-only transaction rejects a mutation with storeError(.transactionReadOnly)")
    func readOnlyTransactionRejectsMutation() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        do {
            _ = try await peer.ditto.store.transaction(hint: "read-only", isReadOnly: true) { transaction in
                try await transaction.execute(
                    query: "INSERT INTO cars DOCUMENTS (:car)",
                    arguments: ["car": ["_id": "txn-readonly", "make": "Toyota"]]
                )
                return DittoTransactionCompletionAction.commit
            }
            Issue.record("expected transactionReadOnly")
        } catch let error as DittoError {
            guard case .transactionReadOnly = error.storeReason else {
                Issue.record("expected transactionReadOnly, got \(error)")
                return
            }
        }
    }

    @Test("CREATE INDEX and DROP INDEX execute through the same call as any DQL")
    func indexingExecutes() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        try await peer.ditto.store.execute(query: "CREATE INDEX cars_mileage ON cars (mileage)")
        try await peer.ditto.store.execute(query: "DROP INDEX cars_mileage ON cars")
    }

    @Test("EVICT removes documents locally without deleting them for other peers")
    func evictRemovesLocally() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        try await peer.ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:car)",
            arguments: ["car": ["_id": "evict-1", "make": "Toyota", "mileage": 120]]
        )
        try await peer.ditto.store.execute(
            query: "EVICT FROM cars WHERE mileage > :minimum",
            arguments: ["minimum": 100]
        )

        let result = try await peer.ditto.store.execute(query: "SELECT * FROM cars")
        #expect(result.items.isEmpty)
    }
}
