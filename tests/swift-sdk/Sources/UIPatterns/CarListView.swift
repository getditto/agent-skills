//
// The SwiftUI half of the ownership pattern: no DittoDiffer, no manual diffing.
// `ForEach` over `Identifiable` data already diffs and animates.
//

#if canImport(SwiftUI)
import SwiftUI

@available(iOS 15, macOS 12, macCatalyst 15, *)
public struct CarListView: View {
    @EnvironmentObject private var model: DittoAppModel

    public init() {}

    public var body: some View {
        List {
            ForEach(model.cars) { car in
                HStack {
                    Text(car.make)
                    Spacer()
                    Text("\(car.mileage) mi").foregroundStyle(.secondary)
                }
            }
        }
        .animation(.default, value: model.cars)
    }
}

/// The `App` that owns the single instance. `@StateObject` guarantees exactly one
/// model across re-renders; `.environmentObject` gives every view reach to it without
/// a global.
@available(iOS 15, macOS 12, macCatalyst 15, *)
public struct CarsApp: View {
    @StateObject private var model: DittoAppModel

    public init(ditto: Ditto) {
        _model = StateObject(wrappedValue: DittoAppModel(ditto: ditto))
    }

    public var body: some View {
        CarListView()
            .environmentObject(model)
            .task {
                do { try model.start() } catch { print("Ditto start failed: \(error)") }
            }
    }
}

#if DITTO_V4
@preconcurrency import DittoSwift
#else
import DittoSwift
#endif
#endif
