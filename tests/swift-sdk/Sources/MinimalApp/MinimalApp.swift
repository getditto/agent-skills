//
// The normative minimal Ditto app for skills/swift-sdk.
//
// This is the program `skills/swift-sdk/examples/minimal-app.md` documents. The markdown
// carries a byte-identical copy, because a plugin user has no `tests/` tree to open;
// `scripts/validate-sdk-skills.py` fails the build if the two drift. This file is the
// one that is compiled and run, so edit it first and regenerate the markdown.
//
// It runs in one of two modes:
//   * offline  — `.smallPeersOnly` plus an offline-only license token. Used by CI.
//   * server   — `.server(url:)` plus development-provider authentication, when
//                DITTO_URL and DITTO_TOKEN are set.
//
// Everything else — subscribe, observe, write, read — is identical in both modes.
//

// MARK: - begin documented program
#if DITTO_V4
// 4.14.x predates the `Sendable` conformances v5 added: in Swift 6 language mode
// `Ditto` and `DittoStore` cannot cross an isolation boundary without this, and the
// build fails with "sending 'ditto' risks causing data races".
@preconcurrency import DittoSwift
#else
import DittoSwift
#endif
import Foundation  // v5 no longer re-exports Foundation; URL and UUID need it.

/// A value type extracted from a query result item.
///
/// Extracting into a `Sendable` struct inside the observer callback is the pattern the
/// skill teaches: `DittoQueryResultItem.value` is `[String: Any?]`, which is not
/// `Sendable` and must not be carried across a concurrency boundary.
///
/// This initializer is failable, so the extraction below uses `compactMap`. A
/// `DittoDiffer` needs the opposite — a non-failable initializer and `map`, so the row
/// count always matches its index sets. There is no differ here.
struct Car: Identifiable, Sendable, Equatable {
    let id: String
    let make: String
    let mileage: Int

    init?(_ value: [String: Any?]) {
        guard let id = value["_id"] as? String,
              let make = value["make"] as? String,
              // A stored number comes back as the narrowest CBOR type that holds it,
              // so `as? Int` / `as? Double` silently drops rows. NSNumber bridges
              // every width.
              let mileage = (value["mileage"] as? NSNumber)?.intValue
        else { return nil }
        self.id = id
        self.make = make
        self.mileage = mileage
    }
}

@main
enum MinimalApp {
    static func main() async throws {
        let config = makeConfiguration()

        // The whole workflow runs inside `runWorkflow`, which owns the only strong
        // reference to `Ditto`. That scoping is the point: there is no `close()`, so the
        // persistence directory is not free until the last reference goes away, and
        // deleting it any earlier deletes a live store's files. Binding a second name —
        // `let opened = ditto` — silently defeats this.
        let directory = try await runWorkflow(config: config)

        // By here the instance has been released, so the directory is safe to remove.
        try? FileManager.default.removeItem(at: directory)
        print("done")
    }

    /// Returns the persistence directory the (now released) instance was using.
    private static func runWorkflow(config: DittoConfig) async throws -> URL {
        let environment = ProcessInfo.processInfo.environment

        // 2. Open. `Ditto.open` is async. `Ditto.openSync` is the blocking form, for a
        //    genuinely synchronous entry point such as a command-line tool — never on an
        //    iOS app's main thread, where it risks a launch-watchdog termination.
        let ditto = try await Ditto.open(config: config)
        print("Ditto \(Ditto.version) opened at \(ditto.absolutePersistenceDirectory.path)")
        switch config.connect {
        case .server(let url): print("mode: server (\(url.absoluteString))")
        case .smallPeersOnly: print("mode: smallPeersOnly")
        @unknown default: print("mode: unknown")
        }

        // 3. Authenticate before starting sync.
        switch config.connect {
        case .server:
            let token = environment["DITTO_TOKEN"]!
            // The handler is `@Sendable` and `async`, and it is `async` precisely so the
            // SDK can AWAIT re-authentication before treating sync as authenticated.
            // Dispatching a login and returning defeats that. Install it before
            // `sync.start()`: starting without one fails with
            // `DittoError.authenticationError(.expirationHandlerMissing)`.
            ditto.auth?.expirationHandler = { ditto, _ in
                do {
                    try await login(ditto, token: token, timeoutSeconds: 15)
                } catch {
                    // Off the main actor: log, never touch UI state from here.
                    FileHandle.standardError.write(
                        Data("re-authentication failed: \(error)\n".utf8)
                    )
                }
            }
            try await login(ditto, token: token, timeoutSeconds: 15)
        case .smallPeersOnly:
            // An offline-only peer must be activated with an offline license token
            // before it will accept any work.
            try ditto.setOfflineOnlyLicenseToken(
                environment["DITTO_OFFLINE_LICENSE"] ?? ""
            )
        @unknown default:
            // `DittoConfigConnect` is a non-frozen enum in another module: an
            // exhaustive switch over it needs `@unknown default` or it will not compile.
            break
        }

        #if DITTO_V4
        // 4.14.x rejects every mutating DQL statement with
        // `storeError(.queryNotSupported)` until sync with v3 peers is disabled. This
        // applies to both connect modes, is irreversible, and spreads across the mesh.
        try ditto.disableSyncWithV3()
        #endif

        // 4. Start sync, then register a subscription. A subscription is what asks
        //    other peers for data; it is not what reads the local store.
        try ditto.sync.start()
        let subscription = try ditto.sync.registerSubscription(
            query: "SELECT * FROM cars WHERE mileage > :minimumMileage",
            arguments: ["minimumMileage": 100]
        )

        // 5. Observe the local store. The observer fires once with the current result
        //    and again on every change. Extract Sendable values inside the handler, and
        //    do not pass `deliverOn:` — it is ignored on 5.0.x, so code that depends on
        //    it is correct on two lines and wrong on the third. A bounded stream with a
        //    single consumer gives ordering and back-pressure instead.
        let (carUpdates, continuation) = AsyncStream<[Car]>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let observer = try ditto.store.registerObserver(
            query: "SELECT * FROM cars WHERE mileage > :minimumMileage ORDER BY mileage",
            arguments: ["minimumMileage": 100]
        ) { result in
            continuation.yield(
                result.items.compactMap { item in
                    defer { item.dematerialize() }   // release the native copy
                    return Car(item.value)
                }
            )
        }
        // Tie the observer's lifetime to the stream's. `[weak observer]`, or the
        // handler -> continuation storage -> onTermination -> observer chain is a cycle.
        continuation.onTermination = { [weak observer] _ in observer?.cancel() }

        // 6. Write. `INSERT … DOCUMENTS` takes the document as a query argument, never
        //    as interpolated text.
        try await ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:car)",
            arguments: ["car": ["_id": "minimal-app-1", "make": "Toyota", "mileage": 120]]
        )

        // 7. Wait for the observer to report the write — with a deadline. An unbounded
        //    `for await` hangs forever if the delivery never comes, which in CI is a
        //    stuck job rather than a failure.
        guard let cars = await firstNonEmpty(carUpdates, timeoutSeconds: 30) else {
            FileHandle.standardError.write(Data("timed out waiting for the observer\n".utf8))
            exit(1)
        }
        print("observed \(cars.count) car(s): \(cars.map(\.make).joined(separator: ", "))")

        // 8. Tear down in reverse order. Cancelling is what stops an observer —
        //    dropping the handle does not.
        let directory = ditto.absolutePersistenceDirectory
        continuation.finish()
        observer.cancel()
        subscription.cancel()
        ditto.sync.stop()

        if case .server = config.connect {
            // Releasing a server-backed instance shortly after it authenticates races
            // the SDK's auth client and aborts the process:
            //
            //   Panic: Attempted to submit auth request after the Ditto instance was closed
            //
            // No ordering reliably avoids it. Terminating without running deinitializers
            // does — which is what process termination does anyway.
            //
            // THIS IS FOR COMMAND-LINE TOOLS AND TEST HARNESSES ONLY. Never call `exit()`
            // from an iOS or macOS app: it skips `applicationWillTerminate`, reads to the
            // user as a crash, and is an App Store rejection. See references/connect.md.
            ditto.auth?.expirationHandler = nil
            print("done")
            exit(0)
        }

        return directory
    }

    private static func makeConfiguration() -> DittoConfig {
        let environment = ProcessInfo.processInfo.environment
        let databaseID = environment["DITTO_DATABASE_ID"] ?? DittoConfig.defaultDatabaseID()

        // 1. Configure. `databaseID` is case-sensitive (uppercase ID), and
        //    `.server(url:)` takes a URL, not a String.
        if let urlString = environment["DITTO_URL"], let url = URL(string: urlString),
           environment["DITTO_TOKEN"] != nil {
            return DittoConfig(
                databaseID: databaseID,
                connect: .server(url: url),
                persistenceDirectory: persistenceDirectory()
            )
        }
        return DittoConfig(
            databaseID: databaseID,
            connect: .smallPeersOnly(),
            persistenceDirectory: persistenceDirectory()
        )
    }

    /// Races a stream against a deadline, so a missing delivery fails instead of
    /// suspending forever. This shape is only safe because `AsyncStream`'s iteration is
    /// cancellation-aware — see `login` for what to do when it is not.
    private static func firstNonEmpty(
        _ stream: AsyncStream<[Car]>,
        timeoutSeconds: UInt64
    ) async -> [Car]? {
        await withTaskGroup(of: [Car]?.self) { group in
            group.addTask {
                for await cars in stream where !cars.isEmpty { return cars }
                return nil
            }
            group.addTask {
                // `Task.sleep(nanoseconds:)`, not `sleep(for:)`: `Duration` is iOS 16+
                // and this package's floor is the SDK's own iOS 15.
                try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                return nil
            }
            defer { group.cancelAll() }
            return await group.next() ?? nil
        }
    }

    /// Bridges the completion-handler `login` into async/await **with a deadline**.
    ///
    /// The deadline resumes the SAME continuation rather than racing a sibling task: a
    /// task group does not return until every child finishes, and a child suspended in
    /// `withCheckedThrowingContinuation` is not cancellable — so a "timeout" task beside
    /// it produces the error and then blocks forever waiting for its sibling. `Gate`
    /// makes exactly one of the resumptions win.
    ///
    /// `withTaskCancellationHandler` is the other half: an unstructured `Task` does not
    /// inherit cancellation, so without it a cancelled caller stays blocked for the full
    /// timeout and then reports `timedOut` — measured at 31.9s against a 30s deadline
    /// cancelled at 0.3s.
    ///
    /// `Gate` below mirrors `Deadline.Gate` in `tests/swift-sdk/Sources/UIPatterns`,
    /// which is where its test coverage lives. The duplication is deliberate — this
    /// file has to compile on its own when a reader pastes it into an empty project —
    /// and `scripts/validate-sdk-skills.py` fails the build if the two actors drift.
    private static func login(_ ditto: Ditto, token: String, timeoutSeconds: UInt64) async throws {
        guard let auth = ditto.auth else { throw LoginError.noAuthenticator }

        let gate = Gate()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                Task { await gate.install(continuation) }

                let timer = Task {
                    // `Task.sleep(nanoseconds:)`, not `sleep(for:)`: `Duration` is iOS
                    // 16+ and the SDK's own floor is iOS 15.
                    try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                    await gate.finish(LoginError.timedOut)
                }

                auth.login(token: token, provider: .development) { _, error in
                    Task {
                        timer.cancel()
                        await gate.finish(error)
                    }
                }
            }
        } onCancel: {
            Task { await gate.finish(CancellationError()) }
        }
    }

    /// Ensures a continuation is resumed exactly once when the completion, the deadline
    /// and cancellation can all resume it.
    private actor Gate {
        private var continuation: CheckedContinuation<Void, Error>?
        private var outcome: Error?
        private var finished = false

        func install(_ continuation: CheckedContinuation<Void, Error>) {
            // A resumption can arrive before `install` runs, since both are scheduled
            // onto this actor: replay it rather than dropping it.
            if finished {
                resume(continuation)
                return
            }
            self.continuation = continuation
        }

        func finish(_ error: Error?) {
            guard !finished else { return }
            finished = true
            outcome = error
            if let continuation { resume(continuation) }
        }

        private func resume(_ continuation: CheckedContinuation<Void, Error>) {
            if let outcome {
                continuation.resume(throwing: outcome)
            } else {
                continuation.resume()
            }
        }
    }

    enum LoginError: Error {
        case noAuthenticator
        case timedOut
    }

    private static func persistenceDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ditto-minimal-app-\(UUID().uuidString)", isDirectory: true)
    }
}
