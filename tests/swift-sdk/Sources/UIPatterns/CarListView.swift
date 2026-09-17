//
// The SwiftUI half of the ownership pattern: no DittoDiffer, no manual diffing.
// `ForEach` over `Identifiable` data already diffs and animates.
//
// Includes a real `App` entry point, because `Ditto.open` is `async` and "how do I get
// an asynchronously-opened instance into a `@main App` before the first view renders"
// is the first structural question a SwiftUI developer hits.
//

#if canImport(SwiftUI)
import SwiftUI
import Foundation

#if DITTO_V4
@preconcurrency import DittoSwift
#else
import DittoSwift
#endif

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
    }
}

/// What the app's root actually looks like.
///
/// `Ditto.open` is async, so the instance cannot be built in a stored property of an
/// `App` (which requires `init()`). Model the launch as a phase, open Ditto in `.task`,
/// and render the phase. `openSync` is the alternative and is the wrong one here — it
/// blocks the main thread under the iOS launch watchdog.
@available(iOS 15, macOS 12, macCatalyst 15, *)
public struct CarsRootView: View {
    /// `@StateObject` guarantees exactly one loader across re-renders.
    @StateObject private var loader = DittoLoader()

    public init() {}

    public var body: some View {
        Group {
            switch loader.phase {
            case .loading:
                ProgressView("Starting Ditto…")
            case .ready(let model):
                CarListView().environmentObject(model)
            case .failed(let message):
                Text("Ditto failed to start: \(message)")
            }
        }
        .task { await loader.bootstrap() }
    }
}

/// Owns the async open. Kept separate from `DittoAppModel` so the model can take a
/// non-optional `Ditto` and tests can inject one directly.
@available(iOS 15, macOS 12, macCatalyst 15, *)
@MainActor
public final class DittoLoader: ObservableObject {
    public enum Phase {
        case loading
        case ready(DittoAppModel)
        case failed(String)
    }

    @Published public private(set) var phase: Phase = .loading

    public init() {}

    /// Idempotent: `.task` can run more than once across view identity changes, and
    /// opening a second instance on the same persistence directory is an error.
    public func bootstrap(config: DittoConfig = .default) async {
        if case .loading = phase {} else { return }

        do {
            let ditto = try await Ditto.open(config: config)
            let model = DittoAppModel(ditto: ditto)
            try model.start()
            phase = .ready(model)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

// The real entry point is one line more than this and is deliberately not compiled
// here, because a package cannot contain two `@main` types:
//
//     @main
//     struct CarsApp: App {
//         var body: some Scene { WindowGroup { CarsRootView() } }
//     }
#endif
