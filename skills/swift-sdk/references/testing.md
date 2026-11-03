# Testing — Ditto Swift SDK

## Contents

- [CAP-18 Testing](#cap-18-testing)
- [Two things that break a command-line Swift test run](#two-things-that-break-a-command-line-swift-test-run)
- [What a unit test cannot cover](#what-a-unit-test-cannot-cover)

## CAP-18 Testing

The rules that make a Ditto test suite deterministic are the same three every time: a
**unique persistence directory per test**, an **offline-only instance** so no test
depends on a network, and **deterministic waits** instead of sleeps.

### A disposable instance per test

```swift
import Testing
import DittoSwift
import Foundation

func makeTestDitto() async throws -> Ditto {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("ditto-test-\(UUID().uuidString)", isDirectory: true)

    let config = DittoConfig(
        databaseID: DittoConfig.defaultDatabaseID(),
        connect: .smallPeersOnly(),
        persistenceDirectory: directory
    )
    let ditto = try await Ditto.open(config: config)
    try ditto.setOfflineOnlyLicenseToken(
        ProcessInfo.processInfo.environment["DITTO_OFFLINE_LICENSE"] ?? ""
    )
    return ditto
}
```

A unique directory per test is not tidiness — two instances on one directory throw
`DittoError.storeError(.persistenceDirectoryLocked(message:))`
([connect.md](connect.md#one-opened-instance-per-persistence-directory)), so sharing one
makes a suite order-dependent.

`DittoConfig.defaultDatabaseID()` is the SDK's all-zero UUID, which is what an
offline-only peer with no portal database should use.

**Never commit a license token.** Read it from the environment — locally from a
gitignored file, in CI from a secret.

### Releasing the instance between tests

The published 5.2.0 Swift `Ditto` still has no public `close()` (despite the release
notes); see [sdk-5.2.md](sdk-5.2.md). Hold the instance in an optional and nil it out, as the
[testing guide](https://docs.ditto.live/sdk/latest/deployment/testing) recommends:

```swift
var ditto: Ditto? = try await makeTestDitto()
// …
ditto = nil            // releases the directory lock
```

Once released, the directory can be reopened by a new instance in the same process, and
it sees what the first instance wrote. Do **not** keep using `ditto.store` after nilling the instance — on v5 that is a `fatalError`
([errors.md](errors.md#errors-you-cannot-catch)).

### Wait on events, never on time

An observer fires once immediately and again on every change, so a test can wait on the
delivery itself:

```swift
@Test func observerReportsTheWrite() async throws {
    let ditto = try await makeTestDitto()
    let (stream, continuation) = AsyncStream<Int>.makeStream(bufferingPolicy: .bufferingNewest(1))

    let observer = try ditto.store.registerObserver(query: "SELECT * FROM cars") { result in
        continuation.yield(result.items.count)
    }
    defer { observer.cancel(); continuation.finish() }

    try await ditto.store.execute(
        query: "INSERT INTO cars DOCUMENTS (:car)",
        arguments: ["car": ["_id": "test-1", "make": "Toyota"]]
    )

    // Never `for await … where … { break }` with no timeout: a missing delivery then
    // hangs the suite instead of failing it.
    #expect(try await firstElement(of: stream, timeout: .seconds(10)) { $0 == 1 } == 1)
}

/// Races the stream against a timeout so a missing element fails at the call site
/// instead of suspending forever.
func firstElement<Element: Sendable>(
    of stream: AsyncStream<Element>,
    timeout: Duration = .seconds(10),
    where predicate: @escaping @Sendable (Element) -> Bool = { _ in true }
) async throws -> Element {
    try await withThrowingTaskGroup(of: Element?.self) { group in
        group.addTask { for await e in stream where predicate(e) { return e }; return nil }
        group.addTask { try await Task.sleep(for: timeout); return nil }
        defer { group.cancelAll() }
        guard let result = try await group.next(), let element = result else {
            throw StreamTimeout()
        }
        return element
    }
}

struct StreamTimeout: Error {}
```

`Duration` and `Task.sleep(for:)` are iOS 16 / macOS 13 API. At the SDK's own iOS 15
floor, take the timeout as a `UInt64` of nanoseconds and use `Task.sleep(nanoseconds:)`.

**A test that asserts nothing proves nothing.** Two shapes to avoid, both of which pass
while the behaviour under test is broken:

- *"No delivery arrived after `cancel()`"* with nothing to show a delivery **would** have
  arrived. Register a second, uncancelled observer as a positive control, wait until the
  control has seen the post-cancel write, and only then assert the cancelled one's count
  is unchanged.
- *"Something threw"* — `#expect(throws: (any Error).self)` is satisfied by a bad path, a
  bad license or a typo. Match the `DittoError` case you actually mean.

`deliverOn:` is ignored on 5.0.x, so a test that asserts *which queue* a callback ran on
must be version-gated. Asserting on the delivered **value** is portable; asserting on the
thread is not.

### Disabling cloud sync in tests

```swift
ditto.updateTransportConfig { config in
    config.connect.webSocketURLs = []
}
```

See <https://docs.ditto.live/sdk/latest/deployment/testing>. Mutate through `updateTransportConfig` —
assigning a fresh `DittoTransportConfig()` disables every peer-to-peer transport as well
([transports.md](transports.md#always-mutate-through-updatetransportconfig)).

## Two things that break a command-line Swift test run

Both apply to `swift test` from the terminal and to CI. Neither appears when tests run
inside Xcode against an app target.

### 1. Clear `NO_COLOR` before the SDK initializes

The SDK accepts only `true` or `false` for the `NO_COLOR` environment variable, and
`swift test` exports `NO_COLOR=1` into the test process, so the process aborts during SDK
initialization before any test body runs. There is no `swift test` flag that stops it setting the variable, so
drive SwiftPM's test helper directly with the variable cleared:

```bash
swift build --build-tests
BIN="$(swift build --show-bin-path)"
HELPER="$(dirname "$(xcrun --find swift)")/../libexec/swift/pm/swiftpm-testing-helper"
PLATFORM="$(xcrun --sdk macosx --show-sdk-platform-path)"
BUNDLE="$BIN/MyPackageTests.xctest/Contents/MacOS/MyPackageTests"

env -u NO_COLOR \
  DYLD_FRAMEWORK_PATH="$BIN:$PLATFORM/Developer/Library/Frameworks" \
  DYLD_LIBRARY_PATH="$BIN:$PLATFORM/Developer/usr/lib" \
  "$HELPER" --test-bundle-path "$BUNDLE" "$BUNDLE" --testing-library swift-testing
```

Use the actual bundle and executable names under `$BIN`: native SwiftPM commonly
uses `<PackageName>PackageTests`, while Swift Build may use the test target's name.

Setting `NO_COLOR=false` in your own shell is enough for a plain `swift run`, but not for
`swift test`, which overwrites it.

### 2. The published XCFramework is unsigned

macOS refuses to load an unsigned library into a test host, and SwiftPM copies the
framework out of its artifact cache without signing it. Ad-hoc sign it after building and
before running:

```bash
codesign --force --sign - "$BIN/DittoSwift.framework/Versions/A/DittoSwift"
```

On 4.14.x do the same for `DittoObjC.framework`. Xcode app and test targets sign
automatically, so this only affects command-line SwiftPM runs.

The failure without it is:

```
Library not loaded: @rpath/DittoSwift.framework/Versions/A/DittoSwift
  Reason: … not valid for use in process: Trying to load an unsigned library
```

`swift build` re-copies the framework, so sign **after** the last build step.

## What a unit test cannot cover

Radio behaviour. A single-process suite exercises the store, subscriptions, observers,
attachments and the local presence entry; it cannot exercise BLE, AWDL, mDNS discovery,
multi-peer convergence or connection requests. Those need two devices, and belong to an
integration test rather than this suite.
