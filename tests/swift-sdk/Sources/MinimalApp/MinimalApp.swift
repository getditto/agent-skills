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
        let environment = ProcessInfo.processInfo.environment

        // 1. Configure. `databaseID` is case-sensitive (uppercase ID), and
        //    `.server(url:)` takes a URL, not a String.
        let config: DittoConfig
        if let urlString = environment["DITTO_URL"], let url = URL(string: urlString),
           environment["DITTO_TOKEN"] != nil {
            config = DittoConfig(
                databaseID: environment["DITTO_DATABASE_ID"] ?? DittoConfig.defaultDatabaseID(),
                connect: .server(url: url),
                persistenceDirectory: persistenceDirectory()
            )
        } else {
            config = DittoConfig(
                databaseID: environment["DITTO_DATABASE_ID"] ?? DittoConfig.defaultDatabaseID(),
                connect: .smallPeersOnly(),
                persistenceDirectory: persistenceDirectory()
            )
        }

        // 2. Open. `Ditto.open` is async. `Ditto.openSync` is the blocking form, for a
        //    genuinely synchronous entry point such as a command-line tool — never on an
        //    iOS app's main thread, where it risks a launch-watchdog termination.
        // Held as an Optional so it can be released before the directory is removed.
        var ditto: Ditto? = try await Ditto.open(config: config)
        guard let opened = ditto else { return }
        print("Ditto \(Ditto.version) opened at \(opened.absolutePersistenceDirectory.path)")
        switch config.connect {
        case .server(let url): print("mode: server (\(url.absoluteString))")
        case .smallPeersOnly: print("mode: smallPeersOnly")
        @unknown default: print("mode: unknown")
        }

        // 3. Authenticate before starting sync.
        switch config.connect {
        case .server:
            let token = environment["DITTO_TOKEN"]!
            // The handler is `@Sendable` and `async`. Install it before `sync.start()`:
            // starting sync without one fails with
            // `DittoError.authenticationError(.expirationHandlerMissing)`.
            opened.auth?.expirationHandler = { ditto, _ in
                ditto.auth?.login(token: token, provider: .development) { _, error in
                    if let error { print("login failed: \(error)") }
                }
            }
            try await login(opened, token: token)
        case .smallPeersOnly:
            // An offline-only peer must be activated with an offline license token
            // before it will accept any work.
            try opened.setOfflineOnlyLicenseToken(
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
        try opened.disableSyncWithV3()
        #endif

        // 4. Start sync, then register a subscription. A subscription is what asks
        //    other peers for data; it is not what reads the local store.
        try opened.sync.start()
        let subscription = try opened.sync.registerSubscription(
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
        let observer = try opened.store.registerObserver(
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

        // 6. Write. `INSERT … DOCUMENTS` takes the document as a query argument, never
        //    as interpolated text.
        try await opened.store.execute(
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
        continuation.finish()
        observer.cancel()
        subscription.cancel()
        opened.sync.stop()

        // Releasing a server-backed instance shortly after it authenticates races the
        // SDK's auth client and aborts the process:
        //
        //   Panic: Attempted to submit auth request after the Ditto instance was closed
        //
        // No ordering we tried reliably avoids it — clearing the handler, logging out
        // and pausing all reduce it without closing the window. So in server mode this
        // program does what a real app does: it stops sync and lets the process exit,
        // which releases everything. See references/connect.md.
        if case .server = config.connect {
            opened.auth?.expirationHandler = nil
            print("done")
            // `exit(0)`, not `return`: returning unwinds the scope, releases `ditto`,
            // and races the auth client. `exit` terminates without running
            // deinitializers, which is what a real app's process termination does — an
            // app never deinitializes Ditto on the way out either.
            exit(0)
        }

        // Offline mode can release deterministically. The directory is only free once
        // the last strong reference to `Ditto` is gone — there is no close() — so
        // deleting it while the instance is alive would be deleting a live store's
        // files out from under it.
        let directory = opened.absolutePersistenceDirectory
        ditto = nil
        try? FileManager.default.removeItem(at: directory)
        print("done")
    }

    /// Races a stream against a deadline, so a missing delivery fails instead of
    /// suspending forever.
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
                // `Task.sleep(nanoseconds:)` and `UInt64`, not `Duration`: `Duration`
                // is iOS 16+ and this package's floor is the SDK's own iOS 15.
                try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                return nil
            }
            defer { group.cancelAll() }
            return await group.next() ?? nil
        }
    }

    /// Bridges the completion-handler `login` into async/await so the program does not
    /// race ahead of authentication.
    private static func login(_ ditto: Ditto, token: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ditto.auth?.login(token: token, provider: .development) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func persistenceDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ditto-minimal-app-\(UUID().uuidString)", isDirectory: true)
    }
}
