//
// The composition root the skill recommends for SwiftUI.
//
// One app-lived `Ditto`, owned by a `@MainActor` model, injected into the view tree.
// Compiled for iOS, Mac Catalyst and macOS against 4.14.6, 5.0.3 and 5.1.0 by
// scripts/build-platforms.sh, and its observer bridge is exercised at runtime by
// ObserverBridgeTests.
//

import Foundation
import Combine
import os

#if DITTO_V4
@preconcurrency import DittoSwift
#else
import DittoSwift
#endif

let uiPatternsLogger = Logger(subsystem: "live.ditto.skill-samples", category: "UIPatterns")

/// A value type extracted from a query result item.
///
/// `DittoQueryResultItem.value` is `[String: Any?]`, which is not `Sendable`. Extract
/// into a value type inside the observer callback and hand *that* to the UI.
///
/// The initializer is deliberately **non-failable**, for two reasons:
///
/// 1. A `DittoDiffer`'s index sets are computed over the raw `[DittoQueryResultItem]`,
///    so any row dropped between the diff and the data source desynchronises the two and
///    makes `performBatchUpdates` raise *"invalid number of rows in section 0"*.
/// 2. A malformed or unexpected document can arrive from any peer at any schema version.
public struct Car: Identifiable, Sendable, Equatable {
    public let id: String
    public let make: String
    public let mileage: Int

    public init(_ value: [String: Any?]) {
        // `_id` is not necessarily a String — a composite (map) `_id` is a supported
        // Ditto modelling pattern. Derive a stable identity from whatever it is rather
        // than falling back to a position, which is not an identity at all: a positional
        // id makes every row below an insertion look like a content change, and makes
        // cell reuse map to the wrong document.
        self.id = Car.identity(of: value["_id"] ?? nil)
        self.make = value["make"] as? String ?? "Unknown"
        // Numbers narrow to the smallest CBOR width that holds them, so read through
        // NSNumber rather than casting to a single Swift type.
        self.mileage = (value["mileage"] as? NSNumber)?.intValue ?? 0
    }

    static func identity(of rawID: Any?) -> String {
        switch rawID {
        case let string as String: return string
        case let number as NSNumber: return number.stringValue
        case .none: return ""
        case .some(let other): return String(describing: other)
        }
    }
}

extension Array where Element == DittoQueryResultItem {
    /// Extracts one `Car` per item, preserving count and order, and releases each item's
    /// materialized value afterwards.
    ///
    /// Call this **after** `DittoDiffer.diff(_:)` — the differ needs the items
    /// materialized, and dematerializing first throws away what it reads.
    public func cars() -> [Car] {
        map { item in
            defer { item.dematerialize() }
            return Car(item.value)
        }
    }
}

/// Bridges a store observer into an ordered, bounded stream of value types.
///
/// This is the shape the skill recommends everywhere, factored out so it can be tested
/// without a UI: `ObserverBridgeTests` exercises the bounded buffer under each policy,
/// the `onTermination` teardown, and `Car`'s identity rules.
///
/// Ordering is **structural, not measured**. A single `for await` consumer takes one
/// element at a time in yield order; that is what `AsyncStream` guarantees, and no test
/// here can add to it — substituting the `Task`-per-delivery anti-pattern still passes
/// the ordering test, because a single-process fixture never provokes the reordering.
/// See README.md, "Not verified".
/// **Iterate `stream` exactly once.** `AsyncStream` supports a single consumer and
/// traps on concurrent iteration; this is a value type only so it can be stored
/// alongside a `Task` without a reference dance.
public struct ObserverBridge: Sendable {
    public let stream: AsyncStream<[Car]>
    private let observer: DittoStoreObserver
    private let continuation: AsyncStream<[Car]>.Continuation

    /// How many results the observer yielded into the stream.
    ///
    /// Exposed so a test can assert what the buffering policy did — how many yields
    /// survived, relative to how many there were — rather than an absolute count, which
    /// depends on how often the SDK chose to fire and is not the property under test.
    public var yieldCount: Int { counter.value }
    private let counter: YieldCounter

    /// - Parameter latestOnly: `true` keeps only the newest pending result. The default
    ///   `AsyncStream` policy is `.unbounded`, which lets a fast observer queue a
    ///   backlog of results the UI will never display.
    public init(
        ditto: Ditto,
        query: String,
        arguments: [String: Any?]? = nil,
        latestOnly: Bool = true
    ) throws {
        let (stream, continuation) = AsyncStream<[Car]>.makeStream(
            bufferingPolicy: latestOnly ? .bufferingNewest(1) : .unbounded
        )
        self.stream = stream
        self.continuation = continuation
        let counter = YieldCounter()
        self.counter = counter
        let observer = try ditto.store.registerObserver(query: query, arguments: arguments) { result in
            counter.increment()
            continuation.yield(result.items.cars())
        }
        self.observer = observer
        // `[weak observer]`: the handler captures the continuation, whose shared storage
        // holds `onTermination` — capturing the observer strongly here closes that into
        // a reference cycle, and in a file whose thesis is "retention is about being
        // able to cancel", a leaked observer is the wrong lesson.
        continuation.onTermination = { [weak observer] _ in observer?.cancel() }
    }

    /// Stops the observer AND ends the stream.
    ///
    /// Both halves are needed. `observer.cancel()` alone leaves the stream open, so a
    /// consumer suspended in `for await` waits forever and keeps its captures alive;
    /// `continuation.finish()` alone leaves the observer firing into a dead stream.
    /// `finish()` also runs `onTermination`, which is idempotent with the cancel above.
    public func cancel() {
        observer.cancel()
        continuation.finish()
    }
    public var isCancelled: Bool { observer.isCancelled }

    /// Counts yields from the observer's callback, which runs on an SDK thread.
    final class YieldCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }
}

@MainActor
public final class DittoAppModel: ObservableObject {
    @Published public private(set) var cars: [Car] = []

    /// Whether `sync.start()` has been called. This is **not** connectivity: it is
    /// `true` on an offline-only peer with every radio disabled. Read the presence
    /// graph for reachability.
    @Published public private(set) var isSyncStarted = false

    @Published public private(set) var failure: String?

    public let ditto: Ditto

    private var subscription: DittoSyncSubscription?
    private var bridge: ObserverBridge?
    private var consumer: Task<Void, Never>?

    public init(ditto: Ditto) {
        self.ditto = ditto
    }

    /// Starts sync and begins observing. Safe to call once per app launch.
    public func start(minimumMileage: Int = 0) throws {
        guard bridge == nil else { return }

        // `bridge` is the completion flag, so a throw part-way leaves sync started and a
        // subscription registered while `bridge` is still nil — and a caller that retries
        // then registers a SECOND subscription for the same query. Roll back instead.
        defer {
            if bridge == nil {
                subscription?.cancel()
                subscription = nil
                if isSyncStarted {
                    ditto.sync.stop()
                    isSyncStarted = false
                }
            }
        }

        try ditto.sync.start()
        isSyncStarted = ditto.sync.isActive

        subscription = try ditto.sync.registerSubscription(
            query: "SELECT * FROM cars WHERE mileage >= :minimumMileage",
            arguments: ["minimumMileage": minimumMileage]
        )

        // ONE consumer task over one bounded stream. Creating an unstructured
        // `Task { @MainActor in … }` per delivery gives no ordering guarantee between
        // deliveries, so an older result can land last and pin the UI to stale data.
        let bridge = try ObserverBridge(
            ditto: ditto,
            query: "SELECT * FROM cars WHERE mileage >= :minimumMileage ORDER BY mileage",
            arguments: ["minimumMileage": minimumMileage]
        )
        self.bridge = bridge

        consumer = Task { @MainActor [weak self] in
            for await cars in bridge.stream {
                self?.cars = cars
            }
        }
    }

    public func add(make: String, mileage: Int) async throws {
        try await ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:car)",
            arguments: ["car": ["_id": UUID().uuidString, "make": make, "mileage": mileage]]
        )
    }

    /// Cancels the observer and subscription. Dropping the handles would not stop
    /// either one — they live as long as the owning `Ditto` does.
    public func stop() {
        consumer?.cancel()
        consumer = nil
        bridge?.cancel()
        bridge = nil
        subscription?.cancel()
        subscription = nil
        ditto.sync.stop()
        isSyncStarted = false
    }

    public func report(_ error: any Error) {
        uiPatternsLogger.error("Ditto failure: \(error.localizedDescription, privacy: .public)")
        failure = error.localizedDescription
    }

    deinit {
        // `deinit` is nonisolated; cancel through the captured handles only.
        consumer?.cancel()
        bridge?.cancel()
        subscription?.cancel()
    }
}
