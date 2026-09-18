# Minimal app — Ditto Swift SDK

A complete, runnable program: configure, open, authenticate, start sync, subscribe,
observe, write, and read the write back through the observer.

Longer form of [`SKILL.md` § Minimum viable app](../SKILL.md#minimum-viable-app).

**This is a copy of `Sources/MinimalApp/MinimalApp.swift` in the fixture**, which is the
file CI compiles and runs. If the two ever disagree, the fixture is right.

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

In **server mode** the program terminates with `exit(0)` instead of releasing the
instance, and so leaves its temporary directory behind — deliberately, because releasing
a server-backed instance races the SDK's auth client
([connect.md](../references/connect.md#shutdown)). A long-lived tool should clean up on
its own schedule rather than copying that.

## Dependency

```swift
// Package.swift
// swift-tools-version:6.0
import PackageDescription
import Foundation

// One SPM URL serves all three supported lines; only the pin changes.
let dittoVersion = ProcessInfo.processInfo.environment["DITTO_SWIFT_VERSION"] ?? "5.1.0"

// 4.14.x needs `@preconcurrency import DittoSwift` and `disableSyncWithV3()`, both of
// which the program below selects with `#if DITTO_V4`. Without this setting, pinning
// 4.14.6 compiles the v5 branch and fails.
let versionFlags: [SwiftSetting] =
    dittoVersion.hasPrefix("4.") ? [.define("DITTO_V4")] : []

let package = Package(
    name: "MinimalApp",
    platforms: [.macOS(.v13), .iOS(.v15), .macCatalyst(.v15)],
    dependencies: [
        .package(
            url: "https://github.com/getditto/DittoSwiftPackage",
            exact: Version(stringLiteral: dittoVersion)
        )
    ],
    targets: [
        .executableTarget(
            name: "MinimalApp",
            dependencies: [.product(name: "DittoSwift", package: "DittoSwiftPackage")],
            swiftSettings: versionFlags
        )
    ]
)
```

An app targeting only 5.1.x can drop the environment variable and the flag, and pin
`from: "5.1.0"`. In Xcode, add the same package URL through **File → Add Package
Dependencies…** and add the `DittoSwift` product to the target — see
[setup.md](../references/setup.md).

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
        //    single consumer gives ordering, and coalesces to the newest result. That is
        //    NOT back-pressure: `yield` never suspends under any policy, so
        //    `.bufferingNewest(1)` DROPS intermediate results rather than slowing the
        //    producer. Real back-pressure is `handlerWithSignalNext`.
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
                    do {
                        // `Task.sleep(nanoseconds:)`, not `sleep(for:)`: `Duration` is
                        // iOS 16+ and the SDK's own floor is iOS 15.
                        try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                    } catch {
                        // `try?` here would be a BUG. A cancelled sleep returns
                        // immediately, so swallowing its error would send this task on
                        // to report a timeout — making `cancel()` below a race with the
                        // completion that just won, rather than a way to stop the timer.
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

```bash
export DITTO_OFFLINE_LICENSE="REPLACE_ME_WITH_YOUR_OFFLINE_LICENSE"
# Optional — switches the program to server mode:
# export DITTO_URL="REPLACE_ME_WITH_YOUR_CONNECT_URL"
# export DITTO_TOKEN="REPLACE_ME_WITH_YOUR_DEVELOPMENT_TOKEN"
# export DITTO_DATABASE_ID="REPLACE_ME_WITH_YOUR_DATABASE_ID"

export DITTO_SWIFT_VERSION=5.1.0
swift build --product MinimalApp
BIN="$(swift build --product MinimalApp --show-bin-path)"

# The published XCFramework ships unsigned and SwiftPM copies it without signing;
# macOS will not load an unsigned library. Xcode app targets sign automatically.
codesign --force --sign - "$BIN/DittoSwift.framework/Versions/A/DittoSwift"

# Ditto's core reads NO_COLOR as a --disable-color flag that accepts only true/false,
# so NO_COLOR=1 panics it. See ../references/testing.md.
env -u NO_COLOR DYLD_FRAMEWORK_PATH="$BIN" "$BIN/MinimalApp"
```

In the `getditto/agent-skills` repository the same thing is one command:

```bash
cd tests/swift-sdk && ./scripts/run.sh 5.1.0 --app --offline
```

## Expected output

Real runs on macOS 27.0 / arm64, Apple Swift 6.4 (swiftlang-6.4.0.34.1). Ditto's own log
lines are omitted; the build and program output is verbatim, and the only edit anywhere
below is the redacted server hostname.

Build, 5.1.0:

```
$ DITTO_SWIFT_VERSION=5.1.0 swift build --product MinimalApp
Building for debugging...
...                                     # ~40 progress lines elided
[75 / 81] SkillSupport
[78 / 81] SkillSupport
[79 / 81] MinimalApp-product
Build complete! (5.36 sec)
```

Offline mode, all three lines:

```
Ditto 5.1.0 opened at /private/var/folders/g0/.../T/ditto-minimal-app-38A3E1F1-C8E5-448A-BC58-D2B45AA87CA3
mode: smallPeersOnly
observed 1 car(s): Toyota
done
```

```
Ditto 5.0.3 opened at /private/var/folders/g0/.../T/ditto-minimal-app-6BEDB64A-AB0B-4F59-8BC2-5062FEDE18D6
mode: smallPeersOnly
observed 1 car(s): Toyota
done
```

```
Ditto 4.14.6 opened at /private/var/folders/g0/.../T/ditto-minimal-app-981D4A7D-AF62-4D77-9CC8-CB3DBEBECAFF
mode: smallPeersOnly
observed 1 car(s): Toyota
done
```

Server mode against a real Ditto Server, 5.1.0 (host redacted):

```
Ditto 5.1.0 opened at /private/var/folders/g0/.../T/ditto-minimal-app-C012E788-2615-4E39-80FF-14B52EA1BF86
mode: server (https://REDACTED.cloud.dittolive.app)
observed 1 car(s): Toyota
done
```

The 4.14.6 build additionally emits one deprecation warning, for the
`disableSyncWithV3()` call that line requires:

```
warning: 'disableSyncWithV3()' is deprecated: `disableSyncWithV3()` will be removed in
SDK 5.0. V3 sync is no longer supported.
```

## Verified on

| Ditto | Host | Toolchain | Modes run |
|---|---|---|---|
| 4.14.6 | macOS 27.0, arm64 | Apple Swift 6.4 (swiftlang-6.4.0.34.1) | offline and server |
| 5.0.3 | macOS 27.0, arm64 | Apple Swift 6.4 (swiftlang-6.4.0.34.1) | offline and server |
| 5.1.0 | macOS 27.0, arm64 | Apple Swift 6.4 (swiftlang-6.4.0.34.1) | offline and server |

The run is checked, not just started: the harness fails unless the output contains the
opened-at line for the requested version, `observed 1 car(s): Toyota`, and `done`.

The same source also compiles for the iOS Simulator, an iOS device, and Mac Catalyst at
all three versions. Nothing here was run on `x86_64`: 5.1.0 ships no Intel slice
([versions.md](../references/versions.md#shipped-xcframework-slices)).
