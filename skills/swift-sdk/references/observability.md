# Logging, diagnostics and stats — Ditto Swift SDK

## CAP-15 Logging, diagnostics and stats

### `DittoLogger`

`DittoLogger` is static and process-wide. It is not attached to an instance, so it can be
configured before the first `Ditto.open`.

```swift
DittoLogger.isEnabled = true
DittoLogger.minimumLogLevel = .warning      // .error .warning .info .debug .verbose
```

**Executed on all three lines.** `isEnabled` exists un-deprecated on 4.14.6 too
(`sdk-release-4.14.6:cocoa/DittoSwift/DittoLogger.swift:25`); the older `enabled`
spelling is a deprecated alias there and is gone in v5.

### Routing logs into your own logger

```swift
DittoLogger.setCustomLogCallback { level, message in
    logger.log(level: level == .error ? .error : .debug, "\(message, privacy: .public)")
}
```

**Executed**: with logging enabled at `.debug`, the callback receives SDK lines while an
instance is open. Pass `nil` to remove it.

The callback is invoked from SDK threads and is **not** declared `@Sendable`. Do not touch
UI state from it, and do not call back into Ditto from inside it.

### Exporting logs

```swift
let bytesWritten = try await DittoLogger.export(to: destinationURL)
```

**Executed**: returns a non-zero byte count and creates the file. This is the current API;
the 4.14.x `setLogFile`/`setLogFileURL` forms are deprecated and gone in v5.

Logs may continue to be written into the persistence directory **after** a `Ditto`
instance has been deallocated (`DittoConfig.persistenceDirectory`'s own documentation), so
do not delete that directory immediately on teardown and expect it to stay empty.

### Crash reports

From 4.14.6 and 5.1.0 — but **not** any 5.0.x release — an uncaught exception thrown
inside an SDK callback closure is re-raised with the original call stack, so a crash
reporter attributes it to your throwing code instead of reporting a `SIGABRT` inside Ditto
(#SDKS-3483). On 5.0.x the same crash reads as a Ditto bug in the report.

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

**Executed**: after a single insert, `sizeInBytes` is greater than zero and `path` is
non-empty. The 4.14.x spelling is in
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

**Executed**: metadata round-trips, and an oversized dictionary throws
`DittoError.validationError(.sizeLimitExceeded(message:))`. `.depthLimitExceeded` and
`.notADictionary` are the other two validation failures this setter produces.

This is the channel that feeds Ditto's device-observability tooling
(<https://docs.ditto.live/sdk/latest/deployment/device-observability-and-ditto-logs>).

### System information through DQL

`SELECT * FROM system:collections`, `SELECT * FROM system:indexes` and `SHOW ALL` all run
through `ditto.store.execute` like any other statement, and each returns at least one
item on a populated store (**executed**). Statement grammar
belongs to the `dql` skill or <https://docs.ditto.live/dql/dql>.

### DittoSwiftTools

The presence viewer, disk-usage inspector, logging viewer and permissions helpers live in
a **separate** package with its own platform floor and its own version coupling — see
[preview.md](preview.md#dittoswifttools). Adding the SDK does not bring them in.
