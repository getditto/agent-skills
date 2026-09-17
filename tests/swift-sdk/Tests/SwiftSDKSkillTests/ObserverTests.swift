//
// CAP-11 Observers, diffing and back-pressure.
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

/// Collects observer deliveries in a thread-safe box so a test can assert on them from
/// the test's own actor without capturing mutable state in the handler.
final class DeliveryRecorder<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Element] = []
    private let continuation: AsyncStream<[Element]>.Continuation
    let stream: AsyncStream<[Element]>

    init() {
        let (stream, continuation) = AsyncStream<[Element]>.makeStream()
        self.stream = stream
        self.continuation = continuation
    }

    func record(_ element: Element) {
        lock.lock()
        storage.append(element)
        let snapshot = storage
        lock.unlock()
        continuation.yield(snapshot)
    }

    var deliveries: [Element] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func finish() { continuation.finish() }
}

@Suite("Observers")
struct ObserverTests {

    @Test("an observer fires immediately with the current result")
    func observerFiresWithInitialResult() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        try await peer.ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:car)",
            arguments: ["car": ["_id": "obs-1", "make": "Toyota"]]
        )

        let recorder = DeliveryRecorder<Int>()
        let observer = try peer.ditto.store.registerObserver(query: "SELECT * FROM cars") { result in
            recorder.record(result.items.count)
        }
        defer { observer.cancel() }

        let counts = try await firstElement(of: recorder.stream) { !$0.isEmpty }
        #expect(counts.first == 1)
        recorder.finish()
    }

    @Test("an observer fires again when the result set changes")
    func observerFiresOnChange() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        let recorder = DeliveryRecorder<Int>()
        let observer = try peer.ditto.store.registerObserver(query: "SELECT * FROM cars") { result in
            recorder.record(result.items.count)
        }
        defer { observer.cancel() }

        _ = try await firstElement(of: recorder.stream) { !$0.isEmpty }

        try await peer.ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:car)",
            arguments: ["car": ["_id": "obs-change", "make": "Toyota"]]
        )

        let counts = try await firstElement(of: recorder.stream) { $0.contains(1) }
        #expect(counts.contains(1))
        recorder.finish()
    }

    @Test("registerObserver rejects a non-SELECT query with storeError(.queryNotSupported)")
    func observerRejectsNonSelect() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        do {
            _ = try peer.ditto.store.registerObserver(
                query: "INSERT INTO cars DOCUMENTS (:car)",
                arguments: ["car": ["_id": "nope"]]
            ) { _ in }
            Issue.record("expected queryNotSupported")
        } catch let error as DittoError {
            guard case .queryNotSupported = error.storeReason else {
                Issue.record("expected queryNotSupported, got \(error)")
                return
            }
        }
    }

    @Test("registerObserver rejects invalid DQL with storeError(.queryInvalid)")
    func observerRejectsInvalidQuery() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        do {
            _ = try peer.ditto.store.registerObserver(query: "SELEKT * FROM cars") { _ in }
            Issue.record("expected queryInvalid")
        } catch let error as DittoError {
            guard case .queryInvalid = error.storeReason else {
                Issue.record("expected queryInvalid, got \(error)")
                return
            }
        }
    }

    @Test("cancel() stops delivery and sets isCancelled")
    func cancelStopsDelivery() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        let recorder = DeliveryRecorder<Int>()
        let observer = try peer.ditto.store.registerObserver(query: "SELECT * FROM cars") { result in
            recorder.record(result.items.count)
        }
        _ = try await firstElement(of: recorder.stream) { !$0.isEmpty }

        #expect(observer.isCancelled == false)
        observer.cancel()
        #expect(observer.isCancelled == true)

        let deliveriesAtCancel = recorder.deliveries.count
        try await peer.ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:car)",
            arguments: ["car": ["_id": "after-cancel", "make": "Toyota"]]
        )
        // Give any in-flight delivery a chance to land, then assert none did.
        _ = try await peer.ditto.store.execute(query: "SELECT * FROM cars")
        #expect(recorder.deliveries.count == deliveriesAtCancel)
        recorder.finish()
    }

    @Test("store.observers is computed, so a cancelled observer disappears from it")
    func observersCollectionIsComputed() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        let observer = try peer.ditto.store.registerObserver(query: "SELECT * FROM cars") { _ in }
        let snapshot = peer.ditto.store.observers
        #expect(snapshot.contains(observer))

        observer.cancel()
        #expect(peer.ditto.store.observers.contains(observer) == false)
        // The snapshot taken before cancellation is now stale — this is why the skill
        // says to read `store.observers` at the point of use rather than caching it.
        #expect(snapshot.contains(observer))
    }

    @Test("handlerWithSignalNext delivers nothing further until signalNext() is called")
    func signalNextGatesDelivery() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        let recorder = DeliveryRecorder<Int>()
        let gate = SignalGate()

        let observer = try peer.ditto.store.registerObserver(
            query: "SELECT * FROM cars"
        ) { result, signalNext in
            recorder.record(result.items.count)
            gate.hold(signalNext)
        }
        defer { observer.cancel() }

        _ = try await firstElement(of: recorder.stream) { !$0.isEmpty }
        let deliveriesWhileHeld = recorder.deliveries.count

        // Three writes while the handler is still holding signalNext.
        for index in 0..<3 {
            try await peer.ditto.store.execute(
                query: "INSERT INTO cars DOCUMENTS (:car)",
                arguments: ["car": ["_id": "gate-\(index)", "make": "Toyota"]]
            )
        }
        #expect(recorder.deliveries.count == deliveriesWhileHeld)

        // Releasing delivers the latest state, coalesced — not one callback per write.
        gate.release()
        let counts = try await firstElement(of: recorder.stream) { $0.contains(3) }
        #expect(counts.contains(3))
        #expect(counts.contains(1) == false)
        #expect(counts.contains(2) == false)
        recorder.finish()
    }

    @Test("a DittoDiffer reports the first result as all insertions")
    func differFirstResultIsAllInsertions() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        for index in 0..<3 {
            try await peer.ditto.store.execute(
                query: "INSERT INTO cars DOCUMENTS (:car)",
                arguments: ["car": ["_id": "diff-\(index)", "make": "Toyota", "mileage": index]]
            )
        }

        let differ = DittoDiffer()
        let result = try await peer.ditto.store.execute(query: "SELECT * FROM cars ORDER BY mileage")
        let diff = differ.diff(result.items)

        #expect(diff.insertions.count == 3)
        #expect(diff.deletions.isEmpty)
        #expect(diff.updates.isEmpty)
        #expect(diff.moves.isEmpty)
    }

    @Test("a DittoDiffer is stateful across calls")
    func differIsStateful() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        for index in 0..<2 {
            try await peer.ditto.store.execute(
                query: "INSERT INTO cars DOCUMENTS (:car)",
                arguments: ["car": ["_id": "stateful-\(index)", "make": "Toyota", "mileage": index]]
            )
        }

        let differ = DittoDiffer()
        let query = "SELECT * FROM cars ORDER BY mileage"
        _ = differ.diff(try await peer.ditto.store.execute(query: query).items)

        // Second call against an unchanged result reports nothing.
        let unchanged = differ.diff(try await peer.ditto.store.execute(query: query).items)
        #expect(unchanged.insertions.isEmpty)
        #expect(unchanged.deletions.isEmpty)
        #expect(unchanged.updates.isEmpty)

        // One more document is one insertion, not a fresh full population.
        try await peer.ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:car)",
            arguments: ["car": ["_id": "stateful-2", "make": "Honda", "mileage": 2]]
        )
        let afterInsert = differ.diff(try await peer.ditto.store.execute(query: query).items)
        #expect(afterInsert.insertions.count == 1)
        #expect(afterInsert.insertions.first == 2)
    }

    @Test("a DittoDiffer reports an in-place change as an update")
    func differReportsUpdates() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        try await peer.ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:car)",
            arguments: ["car": ["_id": "update-1", "make": "Toyota", "mileage": 1]]
        )

        let differ = DittoDiffer()
        let query = "SELECT * FROM cars ORDER BY _id"
        _ = differ.diff(try await peer.ditto.store.execute(query: query).items)

        try await peer.ditto.store.execute(
            query: "UPDATE cars SET make = :make WHERE _id = :id",
            arguments: ["make": "Honda", "id": "update-1"]
        )
        let diff = differ.diff(try await peer.ditto.store.execute(query: query).items)
        #expect(diff.updates.count == 1)
        #expect(diff.insertions.isEmpty)
        #expect(diff.deletions.isEmpty)
    }

    @Test("deliverOn is honoured on 4.14.x and 5.1.x and ignored on 5.0.x")
    func deliverOnBehaviourIsVersionGated() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        let queue = DispatchQueue(label: "live.ditto.skill-tests.deliver-on")
        let key = DispatchSpecificKey<Void>()
        queue.setSpecific(key: key, value: ())

        let recorder = DeliveryRecorder<Bool>()
        let observer = try peer.ditto.store.registerObserver(
            query: "SELECT * FROM cars",
            deliverOn: queue
        ) { _ in
            recorder.record(DispatchQueue.getSpecific(key: key) != nil)
        }
        defer { observer.cancel() }

        let onRequestedQueue = try await firstElement(of: recorder.stream) { !$0.isEmpty }.first == true

        if isV50 {
            // #SDKS-3856: 5.0.x accepts `deliverOn:` and never uses it. The handler runs
            // on an SDK-internal thread, which is why a handler that touches UI state
            // must hop explicitly on this line.
            #expect(onRequestedQueue == false)
        } else {
            #expect(onRequestedQueue == true)
        }
        recorder.finish()
    }
}

/// Holds a `signalNext` closure until the test releases it.
final class SignalGate: @unchecked Sendable {
    private let lock = NSLock()
    private var held: [() -> Void] = []

    func hold(_ signalNext: @escaping () -> Void) {
        lock.lock()
        held.append(signalNext)
        lock.unlock()
    }

    func release() {
        lock.lock()
        let pending = held
        held = []
        lock.unlock()
        pending.forEach { $0() }
    }
}
