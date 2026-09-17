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
    /// Deterministic by construction: **nothing consumes the stream while the writes
    /// happen**, so the buffering policy alone decides how much survives. An earlier
    /// version raced a 20 ms consumer sleep against local insert latency and caught the
    /// `.unbounded` mutation only 2 runs in 4.
    @Test("a bounded bridge drops superseded results; an unbounded one keeps them",
          arguments: [true, false])
    func bufferingPolicyDecidesWhatSurvives(latestOnly: Bool) async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        let writes = 25
        let bridge = try ObserverBridge(
            ditto: peer.ditto,
            query: "SELECT * FROM cars ORDER BY mileage",
            latestOnly: latestOnly
        )
        defer { bridge.cancel() }

        for index in 0..<writes {
            try await peer.ditto.store.execute(
                query: "INSERT INTO cars DOCUMENTS (:car)",
                arguments: ["car": ["_id": "buffered-\(index)", "make": "Toyota", "mileage": index]]
            )
        }
        // Let the observer finish yielding before anything drains it.
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Drain what the buffer actually retained, stopping when it goes quiet.
        var deliveries: [Int] = []
        while let cars = try? await firstElement(of: bridge.stream, timeout: .seconds(1)) {
            deliveries.append(cars.count)
            if cars.count == writes && latestOnly { break }
            if deliveries.count > writes { break }
        }

        #expect(deliveries.isEmpty == false)
        #expect(deliveries.last == writes, "the consumer must end on the final state")

        if latestOnly {
            #expect(
                deliveries.count <= 3,
                "a bounded stream retained \(deliveries.count) results for \(writes) writes"
            )
        } else {
            #expect(
                deliveries.count >= 5,
                "an unbounded stream should retain the backlog, not coalesce it (got \(deliveries.count))"
            )
        }
    }

    /// Pins the invariant a single `for await` consumer gives: deliveries arrive in the
    /// order they were yielded, so a monotonically growing store is never observed
    /// shrinking.
    ///
    /// **What this does NOT prove.** Replacing the bridge's `continuation.yield(...)`
    /// with `Task { continuation.yield(...) }` — the unordered anti-pattern the design
    /// exists to avoid — still passes this test, measured 3 runs of 3. `AsyncStream`
    /// serialises yields, so the reordering window is too small to provoke locally. The
    /// ordering argument for `ObserverBridge` therefore rests on the structural
    /// guarantee, not on this test, and README.md lists it under "Not verified".
    @Test("a single consumer observes results in non-decreasing order")
    func singleConsumerPreservesOrder() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        let writes = 20
        let bridge = try ObserverBridge(
            ditto: peer.ditto,
            query: "SELECT * FROM cars ORDER BY mileage",
            latestOnly: false          // keep every result so ordering is observable
        )
        defer { bridge.cancel() }

        let recorder = DeliveryRecorder<Int>()
        let consumer = Task {
            for await cars in bridge.stream {
                recorder.record(cars.count)
                if cars.count == writes { break }
            }
        }

        for index in 0..<writes {
            try await peer.ditto.store.execute(
                query: "INSERT INTO cars DOCUMENTS (:car)",
                arguments: ["car": ["_id": "ordered-\(index)", "make": "Toyota", "mileage": index]]
            )
        }
        _ = await consumer.value

        let counts = recorder.deliveries
        #expect(counts.isEmpty == false)
        #expect(counts.last == writes)
        // The store only grows here, so a correctly ordered consumer never sees a count
        // smaller than one it has already seen.
        #expect(counts == counts.sorted(), "deliveries arrived out of order: \(counts)")
        recorder.finish()
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

@Suite("Deadline")
struct DeadlineTests {

    /// The regression test for the hang this helper exists to prevent. A task group
    /// around a non-cancellable continuation produces the timeout error and then blocks
    /// forever waiting for its sibling; measured at 8s+ against a 2s timeout.
    @Test("a completion that never fires throws Exceeded within the deadline")
    func neverCompletingBodyTimesOut() async throws {
        // Deliberately does NOT `await` the call directly. If `Deadline.run` regresses to
        // the task-group shape it hangs, and awaiting it here would hang the whole suite
        // instead of failing it — a stuck CI job rather than a red one. Running it
        // detached and polling a flag bounds the test itself; the leaked task is the
        // price of a regression test that guards a hang.
        let outcome = Outcome()
        let subject = Task.detached {
            do {
                try await Deadline.run(seconds: 1) { _ in
                    // Never calls `complete` — the unreachable-server case.
                }
                await outcome.record(.returned)
            } catch is Deadline.Exceeded {
                await outcome.record(.timedOut)
            } catch {
                await outcome.record(.threw)
            }
        }
        defer { subject.cancel() }

        for _ in 0..<60 where await outcome.value == nil {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(
            await outcome.value == .timedOut,
            "Deadline.run did not release its caller — see the task-group note in Deadline.swift"
        )
    }

    private actor Outcome {
        enum Value { case timedOut, returned, threw }
        private(set) var value: Value?
        func record(_ value: Value) { if self.value == nil { self.value = value } }
    }

    @Test("a completion that fires first wins and the deadline is discarded")
    func completionWins() async throws {
        let started = Date()
        try await Deadline.run(seconds: 30) { complete in complete(nil) }
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test("an error from the completion is rethrown, not swallowed by the deadline")
    func completionErrorPropagates() async throws {
        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await Deadline.run(seconds: 30) { complete in complete(Boom()) }
        }
    }

    @Test("a late completion after a timeout does not double-resume")
    func lateCompletionIsHarmless() async throws {
        await #expect(throws: Deadline.Exceeded.self) {
            try await Deadline.run(seconds: 1) { complete in
                // Fires well after the deadline; the gate must make it a no-op rather
                // than a "continuation resumed twice" crash.
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    complete(nil)
                }
            }
        }
        try await Task.sleep(nanoseconds: 2_500_000_000)
    }
}
