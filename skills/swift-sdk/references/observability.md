# Logging, diagnostics and stats — Ditto Swift SDK

For 5.2.0 additions and migration changes, read [sdk-5.2.md](sdk-5.2.md).


## CAP-15 Logging, diagnostics and stats

### `DittoLogger`

`DittoLogger` is static and process-wide. It is not attached to an instance, so it can be
configured before the first `Ditto.open`.

```swift
DittoLogger.isEnabled = true
DittoLogger.minimumLogLevel = .warning      // .error .warning .info .debug .verbose
```

`isEnabled` works on all four lines; the older `enabled` spelling is a deprecated alias on
4.14.x and is gone in v5.

### Routing logs into your own logger

```swift
// @Sendable: the callback fires on SDK threads. Registered from a @MainActor owner,
// an unannotated closure silently INHERITS main-actor isolation — touching MainActor
// state from it still compiles and then mutates that state off-thread, with no
// diagnostic. Marking the closure @Sendable turns the missing actor hop into a
// compile error instead of a data race (verified on Ditto 5.1.0 / Swift 6.4).
DittoLogger.setCustomLogCallback { @Sendable level, message in
    // Keep the raw message private — SDK diagnostics can contain authentication
    // material (login lines carry tokens and user IDs), and .public bypasses
    // unified-log redaction.
    logger.log(level: level == .error ? .error : .debug, "\(message, privacy: .private)")
}
```

Pass `nil` to remove the callback.

The callback is invoked from SDK threads and is **not** declared `@Sendable` by the SDK
(`DittoLogger.swift` — `[source-verified]`). Mark the closure `@Sendable` yourself, do
not touch actor-isolated UI state from it, and do not call back into Ditto from inside
it.

`.debug`-level `os.Logger` messages are not persisted to the unified log — use
`log stream --debug` (not `log show`) to see them, and expect `log stream` on a
simulator to show even `.private` payloads in cleartext.

### Exporting logs

```swift
let bytesWritten = try await DittoLogger.export(to: destinationURL)
```

It returns the number of bytes written. This is the current API; the 4.14.x `setLogFile`/`setLogFileURL` forms are deprecated and gone in v5.

Logs may continue to be written into the persistence directory **after** a `Ditto`
instance has been deallocated (`DittoConfig.persistenceDirectory`'s own documentation), so
do not delete that directory immediately on teardown and expect it to stay empty.

### Crash reports

From 4.14.6 and 5.1.0 — but **not** any 5.0.x release — an uncaught exception thrown
inside an SDK callback closure is re-raised with the original call stack, so a crash
reporter attributes it to your throwing code. On 5.0.x the report attributes the same
crash to a `SIGABRT` inside Ditto; look further up the stack for your own frame.

Symbolication needs `DittoSwift.framework.dSYM` (and `DittoObjC.framework.dSYM` on
4.14.x) uploaded with your own — see [setup.md](setup.md#crash-reporting).
`DittoExperimental.triggerTestPanic()` forces a panic so you can check the pipeline.

### Disk usage

```swift
let item = ditto.diskUsage.item          // DittoDiskUsageItem
item.sizeInBytes                          // Int
item.path                                 // String
item.childItems                           // [DittoDiskUsageItem]

let observer = ditto.diskUsage.observe { item in /* … */ }
observer.stop()
```

The 4.14.x spelling is in
[versions.md](versions.md#store-results-and-errors).

`DittoDiskUsage.DiskUsagePublisher` (`diskUsage.diskUsagePublisher()`) is the Combine
form. `observe` returns a **`DittoDiskUsageObserver`**, not a `DittoObserver`; both are
stopped with `stop()`.

### Small-peer info

```swift
ditto.smallPeerInfo.isEnabled = true
try ditto.smallPeerInfo.setMetadata(["deployment": "store-42"])
ditto.smallPeerInfo.metadata      // [String: Any]
```

An oversized dictionary throws
`DittoError.validationError(.sizeLimitExceeded(message:))`. `.depthLimitExceeded` and
`.notADictionary` are the other two validation failures this setter produces.

This is the channel that feeds Ditto's device-observability tooling
(<https://docs.ditto.live/sdk/latest/deployment/device-observability-and-ditto-logs>).

### System information through DQL

`SELECT * FROM system:collections`, `SELECT * FROM system:indexes` and `SHOW ALL` all run
through `ditto.store.execute` like any other statement. Note that
`system:indexes` is empty until an index exists — documents do not populate it. Statement grammar
belongs to the `write-dql` skill or <https://docs.ditto.live/dql/dql>.

### DittoSwiftTools

The presence viewer, disk-usage inspector, logging viewer and permissions helpers live in
a **separate** package with its own platform floor and its own version coupling — see
[preview.md](preview.md#dittoswifttools). Adding the SDK does not bring them in.
