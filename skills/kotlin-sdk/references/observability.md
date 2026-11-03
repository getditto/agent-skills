# Logging, diagnostics and stats — Ditto Kotlin SDK

## Contents

- [CAP-15 Logging, diagnostics and stats](#cap-15-logging-diagnostics-and-stats)
  - [DittoLogger](#dittologger)
  - [Emitting your own log lines](#emitting-your-own-log-lines)
  - [Routing logs into your own logger](#routing-logs-into-your-own-logger)
  - [Exporting logs](#exporting-logs)
  - [Log file rotation](#log-file-rotation)
  - [Reading logs when debugging](#reading-logs-when-debugging)
  - [Disk usage](#disk-usage)
  - [Small peer info](#small-peer-info)
  - [System information through DQL](#system-information-through-dql)
  - [Ditto Tools](#ditto-tools)

## CAP-15 Logging, diagnostics and stats

### `DittoLogger`

`DittoLogger` is static and process-wide — configure it **before** creating the `Ditto`
instance so initialization problems (filesystem access, authentication background tasks)
are captured (<https://docs.ditto.live/sdk/latest/deployment/troubleshooting>).

```kotlin
DittoLogger.isEnabled = true
DittoLogger.minimumLogLevel = DittoLogLevel.Debug
// Levels (PascalCase in v5): Error, Warning, Info, Debug, Verbose
```

The enum values are PascalCase in v5: `DittoLogLevel.Error`, `.Warning`, `.Info`,
`.Debug`, `.Verbose`. The v4 uppercase spellings (`DittoLogLevel.DEBUG`, etc.) are gone —
older docs and samples still show them (<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>;
<https://docs.ditto.live/sdk/latest/deployment/troubleshooting> shows the v4 form).

**Verified (JVM, 5.0.3 / 5.1.0):** at `DittoFactory.create` time the SDK initializes
logging and prints INFO init lines to stdout **before** any `DittoLogger.isEnabled = false`
takes effect. Setting `isEnabled = false` up front does not silence those first lines.

`DittoLogger.enabled` (v4) → `DittoLogger.isEnabled` (v5)
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>).

### Emitting your own log lines

```kotlin
DittoLog.e("sync", "failed to reconcile")   // also w / i / d / v
```

`DittoLog.e/w/i/d/v()` are unchanged in v5 (<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>).

### Routing logs into your own logger

```kotlin
scope.launch {
    DittoLogger.observeLogEvents().collect { event ->
        // event: DittoLogger.DittoLogEvent(level: DittoLogLevel, message: String)
        logger.log(mapLevel(event.level), event.message)
    }
}
```

`DittoLogger.observeLogEvents(): Flow<DittoLogger.DittoLogEvent>` replaces v4's
`setCustomLogCallback(callback)` / `unsetCustomLogCallback()`; the event type is
**nested** in `DittoLogger` and carries `level: DittoLogLevel` and `message: String`
(**[api-dump]** 5.1.0 API reference, `com.ditto.kotlin/-ditto-logger`). Cancelling the
collecting scope stops delivery — that is the v5 replacement for
`unsetCustomLogCallback()`. The `DittoLogCallback` interface is removed
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>). `DittoLogger.setLogFile(logFile: String?)`
(same API-reference page) additionally mirrors every log line to a file path; pass
`null` to stop.

### Exporting logs

```kotlin
val bytesWritten: ULong = DittoLogger.exportToFileBlocking(path)
// or, from a coroutine:
val bytesWritten: ULong = DittoLogger.exportToFile(path)   // suspend
```

Both take a destination `path: String` and return a `ULong` byte count. The v4 forms
also take a path: `exportToFileBlocking(path: String): BigInteger` and a suspend
`exportToFile(path: String): ULong` since 4.8.0 (**[source]**
`sdks/kotlin/.../DittoLogger.kt:167` in the `ditto` repo at `sdk-release-4.14.7` — the
migration guide's "now requires `path` parameter" aside is wrong about the v4
baseline; the return-type change `BigInteger` → `ULong` is the real delta).

Removed in v5: `DittoLogger.emojiLogLevelHeadingsEnabled` (no effect since 4.8.0) and the
`DittoLogCallback` interface (<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>).

### Log file rotation

Ditto writes rotating log files itself, independent of console output
(<https://docs.ditto.live/sdk/latest/deployment/logging>):

- Files rotate at **1 MB** uncompressed (configurable 1 MB–1 GB) or **24 h** age
  (configurable 1+ h), whichever comes first.
- Naming: `ditto-logs-YYYY-MM-DD-HH-MM-SS.microseconds.log`; rotated files are gzip
  compressed (`.log` → `.log.gz`).
- Retention: **15 files** maximum (configurable 3–64) — roughly ~15 MB on disk by default.
- Disk logs are always written at **DEBUG level**, independent of the console level.
- Runtime-reconfigurable system parameters: `rotating_log_file_max_size_mb`,
  `rotating_log_file_max_age_h`, `rotating_log_file_max_files_on_disk`.

### Reading logs when debugging

From the troubleshooting guide (<https://docs.ditto.live/sdk/latest/deployment/troubleshooting>):

- Set the minimum level to `Debug` **before** creating the `Ditto` instance.
- A blocked write transaction logs with escalating severity: DEBUG for t ≤ 30 s, WARN for
  31–120 s, ERROR beyond 120 s. `originator` / `blocked_by` values are `User`,
  `Internal`, or `Replication`.
- Verbose logging can slow replication considerably — turn it off before concluding sync
  has stalled.

### Disk usage

```kotlin
val item: DittoDiskUsageItem = ditto.diskUsage.item
item.sizeInBytes        // Long

scope.launch {
    ditto.diskUsage.observe().collect { item: DittoDiskUsageItem ->
        // updated usage
    }
}
```

- `diskUsage.item` returns the current `DittoDiskUsageItem`; `sizeInBytes` is a `Long`
  (widened from `Int` in v4).
- `diskUsage.observe(): Flow<DittoDiskUsageItem>` streams updates; cancel the collecting
  scope to stop.
- `DittoFileSystemType` enum values are PascalCase: `Directory`, `File`, `Symlink`.

v4 → v5 renames: `DiskUsage` → `DittoDiskUsage`, `DiskUsageItem` → `DittoDiskUsageItem`,
`FileSystemType` (`DIRECTORY`/`FILE`/`SYMLINK`) → `DittoFileSystemType`
(`Directory`/`File`/`Symlink`), `diskUsage.exec` → `diskUsage.item`,
`diskUsage.observe(handler): Closeable` → `diskUsage.observe(): Flow<…>`, and the
`DiskUsageCallback` interface is removed (<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>).

### Small peer info

The Kotlin sources consulted here document only that `ditto.smallPeerInfo` exists (added
for "configuring metadata shared with other peers during synchronization",
<https://docs.ditto.live/sdk/latest/release-notes/kotlin>) and, from the migration guide
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>):

- v5 **removed** `ditto.smallPeerInfo.syncScope` and the `DittoSmallPeerInfoSyncScope`
  enum — sync scopes are controlled via DQL `ALTER SYSTEM` instead.
- Oversized or malformed metadata raises `SmallPeerInfoException` with reasons
  `SmallPeerInfoExceptionReason.SizeLimitExceeded`, `.DepthLimitExceeded`, or
  `.NotADictionary` (all new in v5).

The documented Kotlin surface lives on the portal page, not the deployment page:
<https://docs.ditto.live/cloud/portal/capturing-small-peer-info>
(<https://docs.ditto.live/cloud/portal/capturing-small-peer-info>) shows
`ditto.smallPeerInfo.isEnabled = true` / `= false` (opt in/out of writing device data
to the portal) and `ditto.smallPeerInfo.setMetadata(metadata)` in Kotlin; the type is
`DittoSmallPeerInfo` in the 5.1.0 API reference (`com.ditto.kotlin/-ditto-small-peer-info`).
Its `syncScope` sample on that page is the removed v4 form. Verify setter signatures
against the pinned artifact before relying on them — none were executed here.

### System information through DQL

Ditto exposes a read-only system collection, `system:system_info` (SDK 4.13.0+), queryable
through `ditto.store.execute` like any other statement
(<https://docs.ditto.live/sdk/latest/deployment/getting-system-information>):

```sql
SELECT * FROM system:system_info
```

Filter by key:

```sql
SELECT * FROM system:system_info
WHERE key LIKE 'collection_num_docs%'
```

Worth knowing (namespace in parentheses): `ditto_sdk_version`, `ditto_sdk_commit`,
`ditto_sdk_language`, `ditto_sdk_platform` (core); `fs_device_available`,
`fs_device_total`, `fs_usage_store`, `fs_usage_attachment`, `fs_usage_replication`,
`fs_usage_auth`, `fs_usage_total` (core); `transport_config` and
`non_default_system_parameter[<param>]` (core); `collection_num_docs[<collection>]`
(store); `local_subscriptions[<UUID>]` (replication); `connections_bluetooth`,
`connections_lan`, `connections_p2pwifi`, `connections_websocket`,
`connections_accesspoint`, `is_connected_to_ditto_cloud`, `device_name` (presence);
`enabled`, `minimum_level` (logs); `last_reap_time`, `num_tombstones_reaped` (reaper).

**Caveat:** observers registered against `system:system_info` fire every **500 ms**
regardless of whether data changed — avoid observing it on resource-constrained devices
(<https://docs.ditto.live/sdk/latest/deployment/getting-system-information>).

### Ditto Tools

The diagnostics UI helpers (presence viewer, disk-usage inspector, logging viewer) live in
the separate **DittoAndroidTools** package, not the SDK. For v5 use:

```kotlin
implementation("com.ditto:ditto-tools-android:6.0.0")
```

(v4 coordinate: `live.ditto:ditto-tools-android:5.0.2`.) DittoAndroidTools 6 requires
`com.ditto:ditto-kotlin` 5.0.1+ and Android API 24+; imports move from `live.ditto.tools.*`
to `com.ditto.tools.*` (<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>).
