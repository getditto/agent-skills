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

    /// `references/observers.md` tells readers which paths run `onTermination` and which
    /// do not. The Ditto-backed test below covers the cancellation path; this covers
    /// `finish()` and the walked-away consumer, without needing an instance.
    @Test("onTermination runs on finish() but not when a consumer merely stops reading")
    func onTerminationFiresOnFinishOnly() async throws {
        let terminated = Flag()
        var (stream, continuation) = AsyncStream<Int>.makeStream()
        continuation.onTermination = { _ in terminated.set() }

        continuation.yield(1)
        for await _ in stream { break }          // walk away, stream still alive
        #expect(terminated.value == false, "breaking out of the loop must not terminate the stream")

        continuation.finish()
        for _ in 0..<50 where !terminated.value {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(terminated.value == true, "finish() must run onTermination")

        // Silences "never mutated"; `stream` is a `var` only because the pair is
        // destructured together.
        stream = AsyncStream { $0.finish() }
        _ = stream
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var flag = false
        func set() { lock.lock(); flag = true; lock.unlock() }
        var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    }

    /// `cancel()` is the teardown every sample calls. If it only cancelled the observer,
    /// a consumer suspended in `for await` would never be released — it would hold its
    /// captures for the life of the process, which is the leak this type exists to avoid.
    @Test("cancel() releases a consumer suspended in for-await")
    func cancelReleasesASuspendedConsumer() async throws {
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }

        let bridge = try ObserverBridge(ditto: peer.ditto, query: "SELECT * FROM cars")
        let finished = Flag()
        // The ONLY consumer — `AsyncStream` traps on a second one, so this test cannot
        // also await a first element to synchronise.
        let consumer = Task {
            for await _ in bridge.stream {}
            finished.set()                 // only reachable once the stream ENDS
        }

        // Let the consumer reach its suspension point.
        try await Task.sleep(nanoseconds: 300_000_000)
        bridge.cancel()

        // Polled, NOT `withTaskGroup` racing `await consumer.value`: awaiting a
        // non-throwing `Task.value` is not cancellation-aware, so the group would not
        // return until the consumer did — a test that hangs instead of failing, which is
        // the trap Deadline.swift's header documents. (Measured: it hung.)
        var waited = 0
        while !finished.value && waited < 50 {
            try await Task.sleep(nanoseconds: 100_000_000)
            waited += 1
        }
        #expect(finished.value, "cancel() left the consumer suspended in for-await")
        _ = consumer
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
    /// Asserts a **relation** — how many yields survived, against how many there were —
    /// not an absolute count. An earlier version required the unbounded arm to retain at
    /// least 5 results for 25 writes, which measured how often *Ditto* chose to fire
    /// rather than what the buffering policy did: it failed 30 of 30 runs in isolation
    /// and about 1 in 7 in the full suite.
    ///
    /// Nothing consumes the stream while the writes happen, so the policy alone decides
    /// what survives.
    @Test("the buffering policy decides how many yields survive", arguments: [true, false])
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

        let yielded = bridge.yieldCount
        // `>= 2`, not `>= 1`: with a single yield every assertion below is trivially true
        // on both arms, so the test would pass green-and-empty rather than fail if the
        // SDK ever coalesced this hard. Observed: 10-12 yields for 25 writes.
        #expect(yielded >= 2, "only \(yielded) yield(s) — nothing for the policy to decide")

        // Drain with a single iteration — `AsyncStream` supports one consumer.
        var retained: [Int] = []
        for await cars in bridge.stream {
            retained.append(cars.count)
            if cars.count == writes { break }
            if retained.count >= yielded { break }
        }

        #expect(retained.contains(writes), "the final state must survive under either policy")

        if latestOnly {
            // `.bufferingNewest(1)` keeps one pending result, so a consumer that starts
            // late sees far fewer than were yielded.
            #expect(
                retained.count < yielded || yielded == 1,
                "bounded retained \(retained.count) of \(yielded) yields"
            )
            #expect(retained.count <= 2, "bounded retained \(retained.count) results")
        } else {
            // `.unbounded` retains every yield, so the consumer walks the whole backlog.
            #expect(
                retained.count == yielded,
                "unbounded retained \(retained.count) of \(yielded) yields"
            )
        }
    }

    /// Pins the invariant a single `for await` consumer gives: deliveries arrive in the
    /// order they were yielded, so a monotonically growing store is never observed
    /// shrinking.
    ///
    /// **What this does NOT prove.** Replacing the bridge's `continuation.yield(...)`
    /// with `Task { continuation.yield(...) }` — the unordered anti-pattern the design
    /// exists to avoid — still passes this test, measured 3 of 3 and then 10 of 10.
    /// `AsyncStream` serialises yields, so a single-process fixture does not provoke the
    /// reordering. That the anti-pattern passes says nothing about its safety: a `Task`
    /// per delivery has no ordering guarantee at all. The argument for `ObserverBridge`
    /// is structural, and README.md lists this under "Not verified".
    @Test("a single consumer never observes a growing store shrink")
    func growingStoreIsNeverObservedShrinking() async throws {
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

        var waited = 0
        while await outcome.value == nil && waited < 60 {
            try await Task.sleep(nanoseconds: 100_000_000)
            waited += 1
        }
        let observed = await outcome.value
        #expect(
            observed == .timedOut,
            "Deadline.run did not release its caller — see the task-group note in Deadline.swift"
        )
    }

    private actor Outcome {
        enum Value { case timedOut, returned, threw, cancelled }
        private(set) var value: Value?
        func record(_ value: Value) { if self.value == nil { self.value = value } }
    }

    /// Only that the completion path wins. It cannot check that the timer was cancelled:
    /// `Gate` makes a late timer a no-op, so `timer.cancel()` is a resource optimisation
    /// rather than a guard, and deleting it leaves every test green (measured).
    /// `lateCompletionIsHarmless` covers the invariant that actually protects this.
    ///
    /// The margin is wide on purpose. A tighter one (a 2s deadline asserting under 1s)
    /// measured 1.3s and 2.1s under full-suite load — the suite runs tests in parallel
    /// against real Ditto instances, so wall-clock here bounds nothing below a second.
    @Test("a completion that fires first wins and the deadline is discarded")
    func completionWins() async throws {
        let started = Date()
        try await Deadline.run(seconds: 30) { complete in complete(nil) }
        let elapsed = Date().timeIntervalSince(started)
        #expect(elapsed < 10, "the completion should have won long before the deadline, took \(elapsed)s")
    }


    /// The other half of what `Deadline` promises. An unstructured `Task` does not
    /// inherit cancellation, so without a `withTaskCancellationHandler` the caller stays
    /// blocked for the full deadline and then reports `Exceeded` — measured at 10.4s
    /// against a 10s deadline cancelled at 0.5s. That matters in `DittoLoader`, whose
    /// bootstrap runs from SwiftUI's `.task`: a disappearing view would hold the `Ditto`
    /// instance and its directory lock, and report "unreachable server" for a teardown.
    @Test("cancelling the caller releases it promptly with CancellationError")
    func cancellationReleasesTheCaller() async throws {
        let outcome = Outcome()
        let started = Date()

        let subject = Task {
            do {
                try await Deadline.run(seconds: 30) { _ in
                    // Never completes: only cancellation can end this.
                }
                await outcome.record(.returned)
            } catch is CancellationError {
                await outcome.record(.cancelled)
            } catch is Deadline.Exceeded {
                await outcome.record(.timedOut)
            } catch {
                await outcome.record(.threw)
            }
        }

        try await Task.sleep(nanoseconds: 300_000_000)
        subject.cancel()
        _ = await subject.value

        let elapsed = Date().timeIntervalSince(started)
        // Read the actor once: `#expect`'s autoclosure is nonisolated and cannot await.
        let observed = await outcome.value
        #expect(observed == .cancelled, "expected CancellationError, got \(String(describing: observed))")
        #expect(elapsed < 5, "cancellation did not release the caller promptly (\(elapsed)s of a 30s deadline)")
    }

    @Test("an error from the completion is rethrown, not swallowed by the deadline")
    func completionErrorPropagates() async throws {
        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await Deadline.run(seconds: 30) { complete in complete(Boom()) }
        }
    }

    /// `Gate.finished` is the only thing enforcing "exactly one resumption", and deleting
    /// it aborts this run with "tried to resume its continuation more than once" — so the
    /// sleep at the end is the assertion, not padding.
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

/// `Retry` bounds the authentication expiration handler, which has no caller to rethrow
/// to: a single failed attempt there means sync stops for the rest of the session.
@Suite("Retry")
struct RetryTests {

    private actor Counter {
        private(set) var count = 0
        func increment() -> Int {
            count += 1
            return count
        }
    }

    private struct Boom: Error, Equatable {
        let attempt: Int
    }

    @Test("a body that succeeds first time is run exactly once")
    func successRunsOnce() async throws {
        let counter = Counter()
        try await Retry.run(attempts: 3, firstBackoffSeconds: 0.01) {
            _ = await counter.increment()
        }
        #expect(await counter.count == 1)
    }

    @Test("a body that fails then succeeds stops at the success")
    func stopsAtFirstSuccess() async throws {
        let counter = Counter()
        try await Retry.run(attempts: 5, firstBackoffSeconds: 0.01) {
            let attempt = await counter.increment()
            if attempt < 3 { throw Boom(attempt: attempt) }
        }
        #expect(await counter.count == 3, "should have stopped at the first success")
    }

    @Test("the attempts are spent and the last error is rethrown")
    func rethrowsAfterTheLastAttempt() async throws {
        let counter = Counter()
        let thrown = await #expect(throws: Boom.self) {
            try await Retry.run(attempts: 3, firstBackoffSeconds: 0.01) {
                throw Boom(attempt: await counter.increment())
            }
        }
        #expect(await counter.count == 3, "expected exactly 3 attempts")
        // The LAST error, not the first: a caller logging it should see the most recent
        // reason, and an unchanged first error would hide a changing failure.
        #expect(thrown == Boom(attempt: 3))
    }

    /// Asserts the DELAYS THE POLICY CHOSE, reported through `onFailure`, not the wall
    /// clock.
    ///
    /// An earlier version measured total elapsed time and asserted `>= 0.6s` for an
    /// intended 0.2 + 0.4. That could not fail: under the full parallel suite this test's
    /// own wall clock is 1.1-2.4s, so scheduling latency alone cleared the bound, and
    /// `backoff *= 1` passed it — measured, twice. An upper bound had been removed for
    /// being load-dependent, which is what left the assertion vacuous. Delays that the
    /// code computed are the thing under test and are not a clock at all.
    @Test("backoff doubles between attempts and stops at the last")
    func backoffGrows() async throws {
        let counter = Counter()
        let delays = Delays()

        _ = await #expect(throws: Boom.self) {
            try await Retry.run(
                attempts: 4,
                firstBackoffSeconds: 0.01,
                onFailure: { _, _, nextDelay in delays.record(nextDelay) }
            ) {
                throw Boom(attempt: await counter.increment())
            }
        }

        // Three failures with a retry to come, then a fourth with none.
        #expect(delays.values == [0.01, 0.02, 0.04, nil], "reported delays: \(delays.values)")
    }

    /// A rejected credential is a verdict, not a blip: retrying spends the caller's whole
    /// deadline to reach the answer it already had.
    @Test("an error classified as non-retryable stops immediately")
    func nonRetryableStopsAtOnce() async throws {
        let counter = Counter()

        _ = await #expect(throws: Boom.self) {
            try await Retry.run(
                attempts: 5,
                firstBackoffSeconds: 0.01,
                isRetryable: { _ in false }
            ) {
                throw Boom(attempt: await counter.increment())
            }
        }
        let attempts = await counter.count
        #expect(attempts == 1, "should not have retried a permanent failure")
    }

    @Test("an already-cancelled caller does not get one free attempt")
    func alreadyCancelledRunsNothing() async throws {
        let counter = Counter()
        let subject = Task {
            try await Retry.run(attempts: 3, firstBackoffSeconds: 0.01) {
                _ = await counter.increment()
            }
        }
        subject.cancel()
        _ = try? await subject.value
        let attempts = await counter.count
        #expect(attempts == 0, "ran \(attempts) attempts after cancellation")
    }

    private final class Delays: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [Double?] = []
        func record(_ delay: Double?) { lock.lock(); recorded.append(delay); lock.unlock() }
        var values: [Double?] { lock.lock(); defer { lock.unlock() }; return recorded }
    }

    /// Without this the handler runs out its remaining attempts and their backoff after a
    /// teardown has already begun — at the defaults, up to 51 seconds of a process that
    /// is trying to exit.
    @Test("cancelling during the backoff abandons the remaining attempts")
    func cancellationAbandonsRemainingAttempts() async throws {
        let counter = Counter()

        let subject = Task {
            try await Retry.run(attempts: 10, firstBackoffSeconds: 5) {
                throw Boom(attempt: await counter.increment())
            }
        }
        // Let the first attempt fail and the 5-second backoff begin.
        try await Task.sleep(nanoseconds: 300_000_000)
        subject.cancel()

        // The error type and the attempt count are what decide this, and neither depends
        // on machine load. A wall-clock bound looks like the natural assertion here and is
        // not one: swallowing the cancellation (`try?` around the sleep) makes the backoff
        // collapse to nothing, so the ten attempts run FASTER than the correct one.
        await #expect(throws: CancellationError.self) { try await subject.value }
        #expect(await counter.count == 1, "should not have started a second attempt")
    }
}
