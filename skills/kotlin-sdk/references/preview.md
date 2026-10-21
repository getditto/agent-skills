# Preview and platform-specific APIs — Ditto Kotlin SDK

> **Sources for this file.** `sdk/latest/sync/data-streams`,
> `sdk/latest/release-notes-hub/kotlin`, `sdk/latest/install-guides/kotlin`,
> `sdk/latest/migration-guides/kotlin-v4`, `sdk/latest/v5-whats-new`.
>
> This is not Compose `@Preview`. It is the part of the Kotlin SDK that is
> explicitly preview, beta, experimental, or available on only one target.

## CAP-20 Preview and platform-specific APIs

### Data Streams — 5.1.0, Public Preview, Kotlin-only

Data Streams are low-latency, bidirectional, peer-to-peer channels that carry
**raw bytes** between two reachable Ditto peers over named topics. They are
ephemeral and **never write to the Ditto store** — the non-preview alternative
for data that must persist, be queried, or converge is document sync (or an
attachment) (sdk/latest/sync/data-streams).

Three facts to state wherever this API is used:

1. **Kotlin-only preview.** The Data Streams guide covers the *"Android
   (Kotlin)"* preview and its samples are Kotlin-specific; no other SDK
   documents the API. It **requires Ditto SDK 5.1.0**
   (sdk/latest/sync/data-streams).
2. **Stability warning, verbatim:** *"Data Streams are in Public Preview and
   may receive breaking changes without notice. You must acknowledge this in
   code by opting in with `@file:OptIn(com.ditto.kotlin.PreviewDataStreams::class)`."*
   (sdk/latest/sync/data-streams)
3. **Opt-in is per-file.** Every file that calls into the API needs:

   ```kotlin
   @file:OptIn(com.ditto.kotlin.PreviewDataStreams::class)
   ```

**Setup.** Data Streams run over NGN (next-generation networking), which must
be enabled *before* `DittoFactory.create(...)` — set both environment variables
in `Application.onCreate()`:

```kotlin
import android.system.Os

Os.setenv("DITTO_NETWORK_ENABLE_NGN", "true", true)   // required; streams run over NGN
Os.setenv("DITTO_REPLICATION_OVER_NGN", "false", true) // keep document sync on stable transports

// ... then DittoFactory.create(config), then:
ditto.sync.start()   // sync must run so presence can discover peers
```

A TCP listener is **not** a prerequisite for Data Streams
(sdk/latest/sync/data-streams).

**API surface** (package `com.ditto.kotlin`; entry point `ditto.dataStreams`,
a `DittoDataStreamsEndpoint`) (sdk/latest/sync/data-streams):

| Type | Purpose |
|---|---|
| `DittoDataStreamsEndpoint` | `bindTopic(topic, reliability, onNewCandidate)`; suspending `connect(peer, topic, reliability, timeoutMs) { candidate -> ... }` |
| `DittoAcceptor` | Handle returned by `bindTopic`; keep it alive to keep accepting. One acceptor per topic at a time |
| `DittoStreamCandidate` | Callback-scoped; `open()` it inside the callback or `take()` it (then close the taken candidate yourself) |
| `DittoStream` | `suspend send(payload): DittoSendStatus`; `sendAndForget(payload)`; `send(payload) { op -> }` monitor overload; `maxSendSize()`; `close()`; `suspend closeSync()`; `suspend waitUntilClosed()` |
| `DittoInbound` | A received message; `payload()` returns an owned `ByteArray` |
| `DittoSendOperation` | `currentStatus()` / `awaitStatusChange()` / `cancel()` — for backpressure |
| `DittoReliability` | `Reliable` (in order or the connection fails) / `Unreliable` (may lose, reorder, duplicate). Binder and connector **must match** or the connection is rejected |
| `DittoStreamStatus` | `Open`, `ClosedByRemote`, `ClosedByLocal` |
| `DittoSendStatus` | `Unknown`, `Pending`, `Sent`, `Failed`, `Cancelled` |

Topics must match `^[a-zA-Z0-9_ ]{1,15}$`. Lifecycle rules that bite: the
receive callback runs on the connection's **driver thread** (non-blocking work
only); closing an acceptor unbinds the topic but does **not** close streams
already open on it; streams do **not** reconnect automatically; and never call
`connect` from inside a presence-observer callback — copy the peer key out and
launch the connect on a separate coroutine (sdk/latest/sync/data-streams).

Stream failures surface as `DittoException.DataStreamsException`, a v5-new
exception type (sdk/latest/migration-guides/kotlin-v4). Catch
`CancellationException` first and rethrow it before handling a
`DataStreamsException` on retry paths (sdk/latest/sync/data-streams).

### `DittoConfig.Experimental`

```kotlin
val config = DittoConfig(
    databaseId = "your-database-id",
    connect = DittoConfig.Connect.Server(url = "REPLACE_ME_WITH_YOUR_URL"),
    experimental = DittoConfig.Experimental(coreExceptionBridgingEnabled = true),
)
```

**v4 aside:** this was the top-level `DittoConfigExperimental(coreExceptionBridgingEnabled)`;
in v5 it is nested inside `DittoConfig` (sdk/latest/migration-guides/kotlin-v4).

With `coreExceptionBridgingEnabled = true`, a native core panic surfaces as a
catchable `DittoException.DittoPanicException` (carrying `nativeCrashMessage`
and `nativeCrashStackTrace`) instead of only a hard native crash
(sdk/latest/release-notes-hub/kotlin). Treat the flag as diagnostic tooling,
not a production default.

### `DittoExperimental.triggerTestPanic()`

`DittoExperimental.triggerTestPanic()` forces a panic so you can confirm a
crash reporter is wired up and symbolicated (sdk/latest/install-guides/kotlin).
Upload the SDK's native symbols from
`$buildDir/intermediates/merged_native_libs/$variant/out/lib/$arch/libdittoffi.so`;
without them the panic is unreadable in the reporter. Never ship a call to it.

> **Source tension.** The v5.0 Kotlin changelog says *"`DittoExperimental`-annotated
> APIs are no longer publicly exposed,"* yet the current (5.1.0) install guide
> still documents `DittoExperimental.triggerTestPanic()`
> (sdk/latest/release-notes-hub/kotlin vs. sdk/latest/install-guides/kotlin).
> This skill does not resolve it — verify against the pinned artifact before
> relying on the symbol.

### Multicast transport — 5.1.0, opt-in beta

`DittoTransportConfig.PeerToPeer.MulticastBeta` (configured via
`config.peerToPeer.multicastBeta`) is the beta reliable UDP multicast
transport, and `DittoConnectionType.Multicast` is its connection-type enum —
both new in 5.1.0 (#SDKS-4471, sdk/latest/release-notes-hub/kotlin). It is
**disabled by default**, ships as an opt-in beta rather than part of the
standard build, and the docs say to **contact Ditto support before deploying
multicast in production**. On Android, a change requested while sync is active
takes effect only after sync is stopped and successfully started again.

### DittoAndroidTools — platform-adjacent diagnostics

`DittoAndroidTools` is a **separate artifact** with diagnostic UI (presence
viewer, disk usage, heartbeat, logging). For v5:

```kotlin
implementation("com.ditto:ditto-tools-android:6.0.0")
```

- Tools **6.0.0** requires `com.ditto:ditto-kotlin` **5.0.1** or a later 5.x
  release and Android API 24+ (sdk/latest/migration-guides/kotlin-v4).
- Tools imports move `live.ditto.tools.*` → `com.ditto.tools.*` — **not**
  `com.ditto.kotlin.tools.*`. Map them separately from SDK imports.
- `DittoHeartbeatInfo.peerKeyString` → `peerKey`; the heartbeat document field
  stays `peerKey`.
- **v4 aside:** the v4 coordinate was `live.ditto:ditto-tools-android:5.0.2`.

### Android-only platform APIs

These exist because they need Android runtime facilities; none of them apply to
the JVM target:

- **`DefaultDittoForegroundService`**
  (`com.ditto.kotlin.transports.DefaultDittoForegroundService`) keeps sync
  running while the app is backgrounded. It is optional — without it, syncing
  stops in the background. Declared in the manifest:

  ```xml
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE" />
  <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

  <application ...>
      <service
          android:name="com.ditto.kotlin.transports.DefaultDittoForegroundService"
          android:exported="false"
          android:foregroundServiceType="connectedDevice"
          android:stopWithTask="true">
          <meta-data android:name="notificationChannelName" android:value="Background Data Sync" />
          <meta-data android:name="notificationChannelId" android:value="BackgroundDataSyncId" />
          <meta-data android:name="smallIcon" android:resource="@drawable/small_app_icon" />
          <meta-data android:name="notificationTitle" android:value="Syncing Data" />
          <meta-data android:name="notificationText" android:value="Syncing data across connected devices" />
          <meta-data android:name="notificationId" android:value="1001" />
      </service>
  </application>
  ```

  The service is started and stopped automatically by `sync.start()` and
  `sync.stop()`. Customize the meta-data — it is user-visible — and the small
  icon must be monochrome white (sdk/latest/install-guides/kotlin). In 5.1.0,
  `sync.stop()` no longer crashes with
  `ForegroundServiceDidNotStartInTimeException` on Android 14+ when the service
  is enabled (#SPO-941, sdk/latest/release-notes-hub/kotlin).

- **`DittoInitializer`** — in v5 the Android `Context` is supplied
  automatically via AndroidX App Startup through the SDK's own manifest merger.
  Do **not** add `DittoInitializer` to your manifest; remove any manual entry
  left over from v4 (sdk/latest/migration-guides/kotlin-v4).

- **`DittoSyncPermissions`** (`com.ditto.kotlin.transports.DittoSyncPermissions`)
  — runtime-permission helper (`missingPermissions()`), Android-only
  (sdk/latest/install-guides/kotlin).

### JVM vs. Android targets

- **v4 was Android-only**: the `live.ditto:ditto` artifact and its install
  guide target *"native apps for the Android platform."*
- **v5 is a Kotlin Multiplatform rewrite** — *"native Kotlin architecture
  shared across JVM platforms"* (sdk/latest/v5-whats-new) — so the plain-JVM
  target exists only on the v5 line.
- Depend on the **KMP root artifact** `com.ditto:ditto-kotlin`; for an Android
  app Gradle's module metadata auto-resolves the `-android` variant — never
  write `com.ditto:ditto-kotlin-android` yourself
  (sdk/latest/migration-guides/kotlin-v4).
- The Android-only surfaces listed above (`DittoInitializer`,
  `DittoSyncPermissions`, `DefaultDittoForegroundService`, the manifest
  permissions) have no JVM equivalent; code targeting both must keep them
  behind Android source sets.
