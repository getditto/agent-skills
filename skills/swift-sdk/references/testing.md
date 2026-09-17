# Testing — Ditto Swift SDK

## CAP-18 Testing

The rules that make a Ditto test suite deterministic are the same three every time: a
**unique persistence directory per test**, an **offline-only instance** so no test
depends on a network, and **deterministic waits** instead of sleeps.

The suite this skill is verified against is `tests/swift-sdk/`; it runs against 4.14.6,
5.0.3 and 5.1.0 from one source tree.

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

**Never commit a license token.** Read it from the environment. The fixture in this repo
takes `DITTO_OFFLINE_LICENSE` from the gitignored repo-root `.env`, and CI supplies it as
a secret.

### Releasing the instance between tests

There is no `close()`. Hold the instance in an optional and nil it out, which is what the
published guidance says too (`sdk/latest/deployment/testing.mdx`):

```swift
var ditto: Ditto? = try await makeTestDitto()
// …
ditto = nil            // releases the directory lock
```

**Executed**: a directory written by a released instance was reopened by a second
instance in the same process, which read back what the first had written. Do **not** keep
using `ditto.store` after nilling the instance — on v5 that is a `fatalError`
([errors.md](errors.md#errors-you-cannot-catch)).

### Wait on events, never on time

An observer fires once immediately and again on every change, so a test can wait on the
delivery itself:

```swift
@Test func observerReportsTheWrite() async throws {
    let ditto = try await makeTestDitto()
    let (stream, continuation) = AsyncStream<Int>.makeStream()

    let observer = try ditto.store.registerObserver(query: "SELECT * FROM cars") { result in
        continuation.yield(result.items.count)
    }
    defer { observer.cancel() }

    try await ditto.store.execute(
        query: "INSERT INTO cars DOCUMENTS (:car)",
        arguments: ["car": ["_id": "test-1", "make": "Toyota"]]
    )

    for await count in stream where count == 1 { break }
}
```

Give any such wait an explicit timeout so a regression fails the suite instead of hanging
it — `tests/swift-sdk/Tests/SwiftSDKSkillTests/Helpers.swift` has a `firstElement(of:)`
helper that races the stream against `Task.sleep` and fails at the call site.

`deliverOn:` is ignored on 5.0.x, so a test that asserts *which queue* a callback ran on
must be version-gated. Asserting on the delivered **value** is portable; asserting on the
thread is not.

### Disabling cloud sync in tests

```swift
ditto.updateTransportConfig { config in
    config.connect.webSocketURLs = []
}
```

Source: `sdk/latest/deployment/testing.mdx`. Mutate through `updateTransportConfig` —
assigning a fresh `DittoTransportConfig()` disables every peer-to-peer transport as well
([transports.md](transports.md#always-mutate-through-updatetransportconfig)).

## Two things that break a command-line Swift test run

Both apply to `swift test` from the terminal and to CI. Neither appears when tests run
inside Xcode against an app target.

### 1. `swift test` sets `NO_COLOR=1`, which panics the SDK

**Executed on 4.14.6, 5.0.3 and 5.1.0.** Ditto's Rust core reads `NO_COLOR` as its
`--disable-color` option, which accepts only `true` or `false`. `swift test` exports
`NO_COLOR=1` into the test process, and the SDK panics during initialization before any
test body runs:

```
thread '<unnamed>' panicked at crates/tracing-config/src/lib.rs:
called `Result::unwrap()` on an `Err` value: … [String("--disable-color"), String("1"),
Strings(["true", "false"])]
```

There is no `swift test` flag that stops it setting the variable, so drive SwiftPM's test
helper directly with the variable cleared:

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
