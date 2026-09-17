# Minimal app — Ditto Swift SDK

A complete, runnable program: configure, open, authenticate, start sync, subscribe,
observe, write, and read the write back through the observer.

Longer form of [`SKILL.md` § Minimum viable app](../SKILL.md#minimum-viable-app).

**This is a copy of `tests/swift-sdk/Sources/MinimalApp/MinimalApp.swift`**, which is the
file CI compiles and runs. If the two ever disagree, the fixture is right.

## What it does

1. Builds a `DittoConfig` — `.server(url:)` when `DITTO_URL` and `DITTO_TOKEN` are set,
   `.smallPeersOnly()` otherwise.
2. Opens the instance with `Ditto.open(config:)`.
3. Authenticates: installs the `@Sendable async` expiration handler and awaits the first
   login (server mode), or sets the offline license token (offline mode).
4. Starts sync, then registers a subscription.
5. Registers a store observer and bridges it into an `AsyncStream` of `Sendable` values.
6. Writes a document with bound arguments.
7. Waits for the observer to report the write, then tears everything down in reverse.

## Dependency

```swift
// Package.swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MinimalApp",
    platforms: [.macOS(.v13), .iOS(.v15), .macCatalyst(.v15)],
    dependencies: [
        .package(url: "https://github.com/getditto/DittoSwiftPackage", exact: "5.1.0")
    ],
    targets: [
        .executableTarget(
            name: "MinimalApp",
            dependencies: [.product(name: "DittoSwift", package: "DittoSwiftPackage")]
        )
    ]
)
```

In Xcode, add the same package URL through **File → Add Package Dependencies…** and add
the `DittoSwift` product to the target — see [setup.md](../references/setup.md).

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
struct Car: Identifiable, Sendable, Equatable {
    let id: String
    let make: String
    let mileage: Int

    init?(_ value: [String: Any?]) {
        guard let id = value["_id"] as? String,
              let make = value["make"] as? String,
              let mileage = value["mileage"] as? Int
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

        // 2. Open. `Ditto.open` is async; `Ditto.openSync` is the blocking form for a
        //    synchronous composition root such as `application(_:didFinishLaunching…)`.
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
            // The handler is `@Sendable` and `async`. Install it before `sync.start()`:
            // starting sync without one fails with
            // `DittoError.authenticationError(.expirationHandlerMissing)`.
            ditto.auth?.expirationHandler = { ditto, _ in
                ditto.auth?.login(token: token, provider: .development) { _, error in
                    if let error { print("login failed: \(error)") }
                }
            }
            try await login(ditto, token: token)
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
        //    and again on every change. Extract Sendable values inside the handler.
        let (carUpdates, continuation) = AsyncStream<[Car]>.makeStream()
        let observer = try ditto.store.registerObserver(
            query: "SELECT * FROM cars WHERE mileage > :minimumMileage ORDER BY mileage",
            arguments: ["minimumMileage": 100],
            deliverOn: .main
        ) { result in
            continuation.yield(result.items.compactMap { Car($0.value) })
        }

        // 6. Write. `INSERT … DOCUMENTS` takes the document as a query argument, never
        //    as interpolated text.
        try await ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:car)",
            arguments: ["car": ["_id": "minimal-app-1", "make": "Toyota", "mileage": 120]]
        )

        // 7. Wait for the observer to report the write.
        for await cars in carUpdates where !cars.isEmpty {
            print("observed \(cars.count) car(s): \(cars.map(\.make).joined(separator: ", "))")
            break
        }

        // 8. Tear down in the reverse order. Cancelling is what stops an observer —
        //    dropping the handle does not.
        continuation.finish()
        observer.cancel()
        subscription.cancel()
        ditto.sync.stop()
        try? FileManager.default.removeItem(at: ditto.absolutePersistenceDirectory)
        print("done")
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
```

## Running it

```bash
export DITTO_OFFLINE_LICENSE="REPLACE_ME_WITH_YOUR_OFFLINE_LICENSE"
# Optional — switches the program to server mode:
# export DITTO_URL="REPLACE_ME_WITH_YOUR_CONNECT_URL"
# export DITTO_TOKEN="REPLACE_ME_WITH_YOUR_DEVELOPMENT_TOKEN"
# export DITTO_DATABASE_ID="REPLACE_ME_WITH_YOUR_DATABASE_ID"

swift build --product MinimalApp
BIN="$(swift build --product MinimalApp --show-bin-path)"

# The published XCFramework ships unsigned and SwiftPM copies it without signing;
# macOS will not load an unsigned library. Xcode app targets sign automatically.
codesign --force --sign - "$BIN/DittoSwift.framework/Versions/A/DittoSwift"

# Ditto's core reads NO_COLOR as a --disable-color flag that accepts only true/false,
# so NO_COLOR=1 panics it. See ../references/testing.md.
env -u NO_COLOR DYLD_FRAMEWORK_PATH="$BIN" "$BIN/MinimalApp"
```

In this repository the same thing is one command:

```bash
cd tests/swift-sdk && ./scripts/run.sh 5.1.0 --app --offline
```

## Expected output

Real runs on macOS 27.0 / arm64, Apple Swift 6.4, offline mode. SDK log lines are
omitted; the program's own output is verbatim.

```
Ditto 5.1.0 opened at /private/var/folders/g0/.../T/ditto-minimal-app-4A2499DD-BCA6-4BBA-A776-4E1903D8C530
mode: smallPeersOnly
observed 1 car(s): Toyota
done
```

```
Ditto 5.0.3 opened at /private/var/folders/g0/.../T/ditto-minimal-app-06D4F4BD-F341-4CBC-9AFD-5850778B89E2
mode: smallPeersOnly
observed 1 car(s): Toyota
done
```

```
Ditto 4.14.6 opened at /private/var/folders/g0/.../T/ditto-minimal-app-955FFC47-39A0-4264-A4F0-ED9388209C98
mode: smallPeersOnly
observed 1 car(s): Toyota
done
```

Server mode against a real Ditto Server, 5.1.0 (host redacted — it is the only line in
these transcripts that was edited):

```
Ditto 5.1.0 opened at /private/var/folders/g0/.../T/ditto-minimal-app-2FA9D7B7-2132-491C-8FE8-C4DCDC51C211
mode: server (https://REDACTED.cloud.dittolive.app/)
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

The same source also compiles for the iOS Simulator, an iOS device, and Mac Catalyst at
all three versions — see `tests/swift-sdk/scripts/build-platforms.sh`. Nothing here was
run on `x86_64`: 5.1.0 ships no Intel slice
([versions.md](../references/versions.md#shipped-xcframework-slices)).
