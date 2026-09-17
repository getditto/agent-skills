//
// The composition root the skill recommends for SwiftUI.
//
// One app-lived `Ditto`, owned by a `@MainActor` model, injected into the view tree.
// This file is compiled for iOS, Mac Catalyst and macOS against 4.14.6, 5.0.3 and
// 5.1.0 by tests/swift-sdk/scripts/build-platforms.sh.
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
public struct Car: Identifiable, Sendable, Equatable {
    public let id: String
    public let make: String
    public let mileage: Int

    public init?(_ value: [String: Any?]) {
        guard let id = value["_id"] as? String,
              let make = value["make"] as? String,
              // Numbers narrow to the smallest CBOR width that holds them, so read
              // through NSNumber rather than casting to a single Swift type.
              let mileage = (value["mileage"] as? NSNumber)?.intValue
        else { return nil }
        self.id = id
        self.make = make
        self.mileage = mileage
    }
}

@MainActor
public final class DittoAppModel: ObservableObject {
    @Published public private(set) var cars: [Car] = []
    @Published public private(set) var isSyncing = false

    public let ditto: Ditto

    private var subscription: DittoSyncSubscription?
    private var observer: DittoStoreObserver?

    public init(ditto: Ditto) {
        self.ditto = ditto
    }

    /// Starts sync and begins observing. Safe to call once per app launch.
    public func start(minimumMileage: Int = 0) throws {
        guard observer == nil else { return }

        try ditto.sync.start()
        isSyncing = ditto.sync.isActive

        subscription = try ditto.sync.registerSubscription(
            query: "SELECT * FROM cars WHERE mileage >= :minimumMileage",
            arguments: ["minimumMileage": minimumMileage]
        )

        observer = try ditto.store.registerObserver(
            query: "SELECT * FROM cars WHERE mileage >= :minimumMileage ORDER BY mileage",
            arguments: ["minimumMileage": minimumMileage]
        ) { [weak self] result in
            // Do the decoding work here, off the main actor, then hop with plain values.
            // `deliverOn:` is ignored on 5.0.x, so never assume this closure is already
            // on the main queue — hop explicitly and the code is correct on every line.
            let cars = result.items.compactMap { item -> Car? in
                defer { item.dematerialize() }
                return Car(item.value)
            }
            Task { @MainActor [weak self] in
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
    /// either one — they live until the owning `Ditto` does.
    public func stop() {
        observer?.cancel()
        observer = nil
        subscription?.cancel()
        subscription = nil
        ditto.sync.stop()
        isSyncing = false
    }

    deinit {
        // `deinit` is nonisolated; cancel through the captured handles only.
        observer?.cancel()
        subscription?.cancel()
    }
}
