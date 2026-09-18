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
    @StateObject private var loader: DittoLoader

    /// `configuration` is read **once**, on first render: `@StateObject`'s autoclosure
    /// does not re-run, so a parent passing a different configuration later is ignored.
    /// That is correct here — the instance is app-scoped — but it is the classic
    /// SwiftUI trap and worth knowing before this is copied somewhere it is not.
    public init(configuration: DittoLoader.Configuration) {
        _loader = StateObject(wrappedValue: DittoLoader(configuration: configuration))
    }

    public var body: some View {
        Group {
            switch loader.phase {
            case .loading:
                ProgressView("Starting Ditto…")
            case .ready(let model):
                CarListView().environmentObject(model)
            case .failed(let message):
                VStack(spacing: 12) {
                    Text("Ditto failed to start: \(message)")
                    Button("Retry") { Task { await loader.retry() } }
                }
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
    /// How to open **and activate** the instance.
    ///
    /// There is deliberately no default `DittoConfig`: `DittoConfig.default` opens an
    /// offline-only instance with the all-zero database ID and never activates it, so it
    /// accepts no work at all. Activation is not optional, and where it goes is exactly
    /// what a reader needs to see.
    public struct Configuration {
        public var config: DittoConfig
        /// Required for `.smallPeersOnly`; the instance is inert without it.
        public var offlineLicenseToken: String?
        /// Required for `.server`; `sync.start()` throws
        /// `authenticationError(.expirationHandlerMissing)` without a handler installed.
        public var authenticate: (@Sendable (Ditto) async throws -> Void)?

        public init(
            config: DittoConfig,
            offlineLicenseToken: String? = nil,
            authenticate: (@Sendable (Ditto) async throws -> Void)? = nil
        ) {
            self.config = config
            self.offlineLicenseToken = offlineLicenseToken
            self.authenticate = authenticate
        }
    }

    public enum Phase {
        case loading
        case ready(DittoAppModel)
        case failed(String)
    }

    @Published public private(set) var phase: Phase = .loading

    private let configuration: Configuration
    private var bootstrapTask: Task<Void, Never>?

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    /// Idempotent **across suspension**, which a `if case .loading` guard alone is not:
    /// `.task` can run more than once, and a second call landing while `Ditto.open` is
    /// still in flight would open a second instance on the same persistence directory
    /// and fail with `storeError(.persistenceDirectoryLocked)`.
    public func bootstrap() async {
        if let bootstrapTask {
            await bootstrapTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            // Held outside the `do` so a failure after `open` succeeded does not drop the
            // last reference HERE. This body is `@MainActor`, and in debug builds
            // `Ditto.shouldWaitForCleanupOnClose` is `true`, so that release would block
            // the main thread for up to `deinitTimeoutSeconds` — the hazard
            // `references/connect.md` documents, in the sample that documents it.
            var opened: Ditto?
            do {
                let ditto = try await Ditto.open(config: self.configuration.config)
                opened = ditto
                if let token = self.configuration.offlineLicenseToken {
                    try ditto.setOfflineOnlyLicenseToken(token)
                }
                try await self.configuration.authenticate?(ditto)
                let model = DittoAppModel(ditto: ditto)
                try model.start()
                self.phase = .ready(model)
                opened = nil        // the model owns it now
            } catch {
                uiPatternsLogger.error("Ditto bootstrap failed: \(error.localizedDescription, privacy: .public)")
                self.phase = .failed(error.localizedDescription)
                // Clear the task so `retry()` can run. Leaving it set makes a transient
                // launch failure — no network, a server blip, a login timeout — permanent
                // for the life of the process, with force-quit as the only recovery.
                self.bootstrapTask = nil
                if let failed = opened {
                    opened = nil
                    Self.release(failed)
                }
            }
        }
        bootstrapTask = task
        await task.value
    }

    /// Drops the last reference to a half-started instance **off** the main actor.
    ///
    /// Releasing `Ditto` is what frees its persistence-directory lock, so a failed
    /// bootstrap must release it or `retry()` opens onto a locked directory. Doing that
    /// on the main actor is the debug-build main-thread stall described above; a detached
    /// task owns the reference instead and lets it go on the cooperative pool.
    private nonisolated static func release(_ ditto: Ditto) {
        Task.detached { withExtendedLifetime(ditto) {} }
    }

    /// Re-attempts a failed bootstrap. Offline-first apps hit transient launch failures
    /// routinely, so the failure state needs a way out.
    public func retry() async {
        guard case .failed = phase else { return }
        phase = .loading
        await bootstrap()
    }
}

// The real entry point is one line more than this, and is deliberately not compiled
// here because a package cannot contain two `@main` types:
//
//     @main
//     struct CarsApp: App {
//         var body: some Scene {
//             WindowGroup {
//                 CarsRootView(configuration: .init(
//                     config: DittoConfig(
//                         databaseID: "REPLACE_ME_WITH_YOUR_DATABASE_ID",
//                         connect: .server(url: URL(string: "REPLACE_ME_WITH_YOUR_CONNECT_URL")!)
//                     ),
//                     authenticate: { ditto in
//                         let tokens = TokenStore(token: "REPLACE_ME_WITH_YOUR_TOKEN")
//                         try await AuthCoordinator(tokens: tokens).start(ditto)
//                     }
//                 ))
//             }
//         }
//     }
#endif
