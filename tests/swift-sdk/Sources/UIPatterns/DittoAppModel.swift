//
// The composition root the skill recommends for SwiftUI.
//
// One app-lived `Ditto`, owned by a `@MainActor` model, injected into the view tree.
// Compiled for iOS, Mac Catalyst and macOS against 4.14.6, 5.0.3 and 5.1.0 by
// tests/swift-sdk/scripts/build-platforms.sh.
//

import Foundation
import Combine

#if DITTO_V4
@preconcurrency import DittoSwift
#else
import DittoSwift
#endif

/// A value type extracted from a query result item.
///
/// `DittoQueryResultItem.value` is `[String: Any?]`, which is not `Sendable`. Extract
/// into a value type inside the observer callback and hand *that* to the UI.
///
/// The initializer is deliberately **non-failable**. A `DittoDiffer`'s index sets are
/// computed over the raw `[DittoQueryResultItem]`, so any row dropped between the diff
/// and the data source desynchronises the two and makes `performBatchUpdates` raise
/// *"invalid number of rows in section 0"*. Tolerating a malformed document — which can
/// arrive from any peer at any schema version — is what keeps the counts equal.
public struct Car: Identifiable, Sendable, Equatable {
    public let id: String
    public let make: String
    public let mileage: Int

    public init(_ value: [String: Any?], fallbackID: String) {
        self.id = value["_id"] as? String ?? fallbackID
        self.make = value["make"] as? String ?? "Unknown"
        // Numbers narrow to the smallest CBOR width that holds them, so read through
        // NSNumber rather than casting to a single Swift type.
        self.mileage = (value["mileage"] as? NSNumber)?.intValue ?? 0
    }
}

extension Array where Element == DittoQueryResultItem {
    /// Extracts one `Car` per item, preserving count and order, and releases each item's
    /// materialized value afterwards.
    ///
    /// Call this **after** `DittoDiffer.diff(_:)` — the differ needs the items
    /// materialized, and dematerializing first throws away what it reads.
    func cars() -> [Car] {
        enumerated().map { index, item in
            defer { item.dematerialize() }
            return Car(item.value, fallbackID: "row-\(index)")
        }
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
    private var observer: DittoStoreObserver?
    private var consumer: Task<Void, Never>?

    public init(ditto: Ditto) {
        self.ditto = ditto
    }

    /// Starts sync and begins observing. Safe to call once per app launch.
    public func start(minimumMileage: Int = 0) throws {
        guard observer == nil else { return }

        try ditto.sync.start()
        isSyncStarted = ditto.sync.isActive

        subscription = try ditto.sync.registerSubscription(
            query: "SELECT * FROM cars WHERE mileage >= :minimumMileage",
            arguments: ["minimumMileage": minimumMileage]
        )

        // One bounded stream with ONE consumer task. This is the part that matters:
        // creating an unstructured `Task { @MainActor in … }` per delivery gives no
        // ordering guarantee between deliveries, so an older result can land last and
        // pin the UI to stale data. A single `for await` loop is ordered by
        // construction, and `.bufferingNewest(1)` bounds memory and drops results the
        // UI would never have displayed anyway.
        let (updates, continuation) = AsyncStream<[Car]>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )

        let observer = try ditto.store.registerObserver(
            query: "SELECT * FROM cars WHERE mileage >= :minimumMileage ORDER BY mileage",
            arguments: ["minimumMileage": minimumMileage]
        ) { result in
            // Decode here, off the main actor. `deliverOn:` is ignored on 5.0.x, so
            // never assume this closure is already on the main queue — the hop below is
            // what makes the same code correct on every supported line.
            continuation.yield(result.items.cars())
        }
        self.observer = observer

        // Tie the observer's lifetime to the stream's: if the consumer is cancelled the
        // observer stops, instead of firing into a dead stream for the life of `Ditto`.
        continuation.onTermination = { _ in observer.cancel() }

        consumer = Task { @MainActor [weak self] in
            for await cars in updates {
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
        observer?.cancel()
        observer = nil
        subscription?.cancel()
        subscription = nil
        ditto.sync.stop()
        isSyncStarted = false
    }

    public func report(_ error: any Error) {
        failure = error.localizedDescription
    }

    deinit {
        // `deinit` is nonisolated; cancel through the captured handles only.
        consumer?.cancel()
        observer?.cancel()
        subscription?.cancel()
    }
}
