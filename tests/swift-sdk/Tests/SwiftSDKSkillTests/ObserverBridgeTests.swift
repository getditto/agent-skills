//
// Runtime coverage for the observer bridge the skill recommends everywhere
// (`references/observers.md`, `best-practices.md`, and every UIPatterns sample).
//
// Without these, the bounded buffer, the ordering guarantee and the `onTermination`
// teardown are compile-checked prose.
//

import Foundation
import Testing
import UIPatterns

#if DITTO_V4
@preconcurrency import DittoSwift
#else
import DittoSwift
#endif

@testable import SkillSupport

@Suite("Observer bridge")
struct ObserverBridgeTests {

    @Test("the bridge yields value types extracted from the result")
    func bridgeYieldsValues() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        try await peer.ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:car)",
            arguments: ["car": ["_id": "bridge-1", "make": "Toyota", "mileage": 120]]
        )

        let bridge = try ObserverBridge(ditto: peer.ditto, query: "SELECT * FROM cars ORDER BY mileage")
        defer { bridge.cancel() }

        let cars = try await firstElement(of: bridge.stream) { !$0.isEmpty }
        #expect(cars.count == 1)
        #expect(cars[0].id == "bridge-1")
        #expect(cars[0].make == "Toyota")
        #expect(cars[0].mileage == 120)
    }

    @Test("finishing the stream cancels the observer via onTermination")
    func terminationCancelsObserver() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        let bridge = try ObserverBridge(ditto: peer.ditto, query: "SELECT * FROM cars")
        _ = try await firstElement(of: bridge.stream)
        #expect(bridge.isCancelled == false)

        // Draining the stream to completion is what a cancelled consumer does.
        // `onTermination` must then cancel the observer, or it keeps firing into a dead
        // stream for the life of the Ditto instance.
        let consumer = Task { for await _ in bridge.stream {} }
        consumer.cancel()
        _ = await consumer.value

        // Give the continuation's termination handler a turn to run.
        for _ in 0..<50 where !bridge.isCancelled {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(bridge.isCancelled == true)
        #expect(peer.ditto.store.observers.isEmpty)
    }

    /// A bounded bridge must not accumulate results the consumer never gets to.
    ///
    /// The consumer here is deliberately slower than the producer; with the default
    /// `.unbounded` policy every yield is retained and replayed, so the consumer walks
    /// the whole backlog. With `.bufferingNewest(1)` it skips straight to the current
    /// state. Verified non-vacuous: forcing `.unbounded` fails this test.
    @Test("a bounded bridge drops superseded results instead of replaying them", arguments: [true, false])
    func boundedBridgeDropsStaleResults(latestOnly: Bool) async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        let writes = 25
        let bridge = try ObserverBridge(
            ditto: peer.ditto,
            query: "SELECT * FROM cars ORDER BY mileage",
            latestOnly: latestOnly
        )
        defer { bridge.cancel() }

        // A slow consumer, started before the writes, that records how many distinct
        // results it is handed and stops once it sees the final state.
        let counter = DeliveryRecorder<Int>()
        let consumer = Task {
            for await cars in bridge.stream {
                counter.record(cars.count)
                if cars.count == writes { break }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }

        for index in 0..<writes {
            try await peer.ditto.store.execute(
                query: "INSERT INTO cars DOCUMENTS (:car)",
                arguments: ["car": ["_id": "bounded-\(index)", "make": "Toyota", "mileage": index]]
            )
        }
        _ = await consumer.value

        let deliveries = counter.deliveries
        #expect(deliveries.last == writes, "the consumer must converge on the final state")

        if latestOnly {
            // Skipping superseded results is the whole point: a bounded consumer should
            // reach the final state in far fewer steps than there were writes.
            #expect(
                deliveries.count < writes / 2,
                "a bounded stream coalesced into \(deliveries.count) deliveries for \(writes) writes"
            )
        }
        counter.finish()
    }

    @Test("Car derives identity from a non-String _id instead of falling back to position")
    func carIdentityHandlesNonStringIDs() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        // A composite (map) `_id` is a supported Ditto modelling pattern.
        try await peer.ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:a), (:b)",
            arguments: [
                "a": ["_id": ["vin": "AAA", "region": "eu"], "make": "Toyota", "mileage": 1],
                "b": ["_id": ["vin": "BBB", "region": "eu"], "make": "Honda", "mileage": 2],
            ]
        )

        let result = try await peer.ditto.store.execute(query: "SELECT * FROM cars ORDER BY mileage")
        let cars = result.items.cars()

        #expect(cars.count == 2)
        #expect(cars[0].id != cars[1].id, "distinct documents must get distinct identities")
        #expect(cars[0].id.isEmpty == false)
        #expect(cars[0].id.contains("AAA"))
        #expect(cars[0].make == "Toyota")
    }

    @Test("Car tolerates a document missing the fields it reads, preserving row count")
    func carToleratesMalformedDocuments() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        try await peer.ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:good), (:bad)",
            arguments: [
                "good": ["_id": "good", "make": "Toyota", "mileage": 1],
                "bad": ["_id": "bad"],
            ]
        )

        let result = try await peer.ditto.store.execute(query: "SELECT * FROM cars ORDER BY _id")
        let cars = result.items.cars()

        // One Car per item, always: a differ's index sets are computed over the items,
        // so dropping a row here desynchronises them from the data source.
        #expect(cars.count == result.items.count)
        #expect(cars.map(\.id).sorted() == ["bad", "good"])
        #expect(cars.first(where: { $0.id == "bad" })?.make == "Unknown")
        #expect(cars.first(where: { $0.id == "bad" })?.mileage == 0)
    }
}
