# Minimal app — Ditto Swift SDK

## Contents

- [What it does](#what-it-does)
- [Dependency](#dependency)
- [Program](#program)
- [Running it](#running-it)
- [Expected output](#expected-output)
- [Verified on](#verified-on)

A complete, runnable program: configure, open, authenticate, start sync, subscribe,
observe, write, and read the write back through the observer.

Longer form of [`SKILL.md` § Minimum viable app](../SKILL.md#minimum-viable-app).

**This is a copy of `Sources/MinimalApp/MinimalApp.swift` in the fixture**, which CI
compiles and runs on 4.14.6, 5.0.3, 5.1.0 and 5.2.0-rc.2.

## What it does

1. Builds a `DittoConfig` — `.server(url:)` when `DITTO_URL` and `DITTO_TOKEN` are set,
   `.smallPeersOnly()` otherwise.
2. Opens the instance with `Ditto.open(config:)`.
3. Authenticates: installs the `@Sendable async` expiration handler and awaits the first
   login (server mode), or sets the offline license token (offline mode).
4. Starts sync, then registers a subscription.
5. Registers a store observer and bridges it into a **bounded** `AsyncStream` drained by
   a single consumer — no `deliverOn:`, because it is ignored on 5.0.x.
6. Writes a document with bound arguments.
7. Waits for the observer to report the write, then tears everything down in reverse.

In **server mode** the program ends with `exit(0)` while still holding the instance, as
an app does at process termination, so it leaves its temporary directory behind. Apps
hold one instance for the process lifetime and never call `exit()`; see
[connect.md](../references/connect.md#shutdown).

## Dependency

See [minimal-app-running.md](../references/minimal-app-running.md#dependency) for this topic.

## Program

```swift
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
/// Extract into a `Sendable` struct inside the observer callback:
/// `DittoQueryResultItem.value` is `[String: Any?]`, which is not `Sendable` and must
/// not be carried across a concurrency boundary.
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
            // The handler is `@Sendable` and `async`, so the SDK can await
            // re-authentication before treating sync as authenticated.
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
        //    single consumer gives ordering, and coalesces to the newest result. That is
        //    not back-pressure: `yield` never suspends under any policy, so
        //    `.bufferingNewest(1)` drops intermediate results rather than slowing the
        //    producer. For back-pressure, use `handlerWithSignalNext`.
        let (carUpdates, continuation) = AsyncStream<[Car]>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let observer = try ditto.store.registerObserver(
            query: "SELECT * FROM cars WHERE mileage > :minimumMileage ORDER BY mileage",
            arguments: ["minimumMileage": 100]
        ) { @Sendable result in
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
            // A server-backed command-line tool ends by exiting with the instance still
            // held, as an app does at process termination. Never call `exit()` from an
            // iOS or macOS app.
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
    /// timeout and then reports `timedOut`.
    private static func login(_ ditto: Ditto, token: String, timeoutSeconds: UInt64) async throws {
        guard let auth = ditto.auth else { throw LoginError.noAuthenticator }

        let gate = Gate()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                Task { await gate.install(continuation) }

                let timer = Task {
                    do {
                        // `Task.sleep(nanoseconds:)`, not `sleep(for:)`: `Duration` is
                        // iOS 16+ and the SDK's own floor is iOS 15.
                        try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                    } catch {
                        // Do not use `try?` here. A cancelled sleep returns immediately,
                        // so swallowing its error would report a timeout after the
                        // completion has already won.
                        return
                    }
                    await gate.finish(LoginError.timedOut)
                }
                Task { await gate.adopt(timer) }

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
        private var timer: Task<Void, Never>?

        /// Lets whoever finishes first stop the deadline, including `onCancel`.
        func adopt(_ timer: Task<Void, Never>) {
            if finished {
                timer.cancel()
                return
            }
            self.timer = timer
        }

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
            timer?.cancel()
            timer = nil
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
```

## Running it

See [minimal-app-running.md](../references/minimal-app-running.md#running-it) for this topic.

## Expected output

See [minimal-app-running.md](../references/minimal-app-running.md#expected-output) for this topic.

## Verified on

See [minimal-app-running.md](../references/minimal-app-running.md#verified-on) for this topic.
