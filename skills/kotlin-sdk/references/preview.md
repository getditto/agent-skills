# Preview and platform-specific APIs — Ditto Kotlin SDK

> **Sources for this file.** <https://docs.ditto.live/sdk/latest/sync/data-streams>,
> <https://docs.ditto.live/sdk/latest/release-notes/kotlin>, <https://docs.ditto.live/sdk/latest/install-guides/kotlin>,
> <https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>, <https://docs.ditto.live/sdk/latest/v5-whats-new>.
>
> This is not Compose `@Preview`. It is the part of the Kotlin SDK that is
> explicitly preview, beta, experimental, or available on only one target.

## Contents

- [CAP-20 Preview and platform-specific APIs](#cap-20-preview-and-platform-specific-apis)
  - [Data Streams — 5.1.0, Public Preview, Kotlin-only](#data-streams--510-public-preview-kotlin-only)
  - [DittoConfig.Experimental](#dittoconfigexperimental)
  - [DittoExperimental.triggerTestPanic()](#dittoexperimentaltriggertestpanic)
  - [Multicast transport — 5.1.0, opt-in beta](#multicast-transport--510-opt-in-beta)
  - [DittoAndroidTools — platform-adjacent diagnostics](#dittoandroidtools--platform-adjacent-diagnostics)
  - [Android-only platform APIs](#android-only-platform-apis)
  - [JVM vs. Android targets](#jvm-vs-android-targets)

## CAP-20 Preview and platform-specific APIs

### Data Streams — 5.1.0, Public Preview, Kotlin-only

Data Streams are low-latency, bidirectional, peer-to-peer channels that carry
**raw bytes** between two reachable Ditto peers over named topics. They are
ephemeral and **never write to the Ditto store** — the non-preview alternative
for data that must persist, be queried, or converge is document sync (or an
attachment) (<https://docs.ditto.live/sdk/latest/sync/data-streams>).

Three facts to state wherever this API is used:

1. **Kotlin-only preview.** The Data Streams guide covers the *"Android
   (Kotlin)"* preview and its samples are Kotlin-specific; no other SDK
   documents the API. The docs name **Ditto SDK 5.1.0** as the requirement
   (<https://docs.ditto.live/sdk/latest/sync/data-streams>). The classes do ship in the 5.0.3 jar
   (**[source-verified]**), but their preview status there is untested and the
   KDoc still carries the closed-preview warning — treat 5.1.0 as the floor.
2. **Stability warning, verbatim:** *"Data Streams are in Public Preview and
   may receive breaking changes without notice. You must acknowledge this in
   code by opting in with `@file:OptIn(com.ditto.kotlin.PreviewDataStreams::class)`."*
   (<https://docs.ditto.live/sdk/latest/sync/data-streams>)
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
(<https://docs.ditto.live/sdk/latest/sync/data-streams>).

**API surface** (package `com.ditto.kotlin`; entry point `ditto.dataStreams`,
a `DittoDataStreamsEndpoint`) (<https://docs.ditto.live/sdk/latest/sync/data-streams>):

| Type | Purpose |
|---|---|
| `DittoDataStreamsEndpoint` | `bindTopic(topic, reliability = Reliable, onNewCandidate)`; suspending `connect(peer, topic, requestCompression = false, reliability = Reliable, timeoutMs = 0, arguments: ByteArray? = null) { candidate -> ... }` — **named args required**: `requestCompression` sits between `topic` and `reliability` positionally (**[api-dump]** 5.1.0 API reference, `com.ditto.kotlin/-ditto-data-streams-endpoint`). The API-reference KDoc writes the opt-in as `com.ditto.PreviewDataStreams`; the annotation actually lives in `com.ditto.kotlin` (package index) — use the guide's spelling |
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
launch the connect on a separate coroutine (<https://docs.ditto.live/sdk/latest/sync/data-streams>).

Stream failures surface as `DittoException.DataStreamsException`, a v5-new
exception type (<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>). Catch
`CancellationException` first and rethrow it before handling a
`DataStreamsException` on retry paths (<https://docs.ditto.live/sdk/latest/sync/data-streams>).

### `DittoConfig.Experimental`

```kotlin
val config = DittoConfig(
    databaseId = "your-database-id",
    connect = DittoConfig.Connect.Server(url = "REPLACE_ME_WITH_YOUR_URL"),
    experimental = DittoConfig.Experimental(coreExceptionBridgingEnabled = true),
)
```

**v4 aside:** this was the top-level `DittoConfigExperimental(coreExceptionBridgingEnabled)`;
in v5 it is nested inside `DittoConfig` (<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>).

With `coreExceptionBridgingEnabled = true`, a native core panic surfaces as a
catchable `DittoException.DittoPanicException` (carrying `nativeCrashMessage`
and `nativeCrashStackTrace`) instead of only a hard native crash
(<https://docs.ditto.live/sdk/latest/release-notes/kotlin>). Treat the flag as diagnostic tooling,
not a production default.

### `DittoExperimental.triggerTestPanic()`

`DittoExperimental.triggerTestPanic()` forces a panic so you can confirm a
crash reporter is wired up and symbolicated (<https://docs.ditto.live/sdk/latest/install-guides/kotlin>).
Upload the SDK's native symbols from
`$buildDir/intermediates/merged_native_libs/$variant/out/lib/$arch/libdittoffi.so`;
without them the panic is unreadable in the reporter. Never ship a call to it.

> **Why the 5.0 changelog line is not a contradiction.** The v5.0 Kotlin changelog
> says *"`DittoExperimental`-annotated APIs are no longer publicly exposed"*
> (<https://docs.ditto.live/sdk/latest/release-notes/kotlin>) — that is the *annotation-gated* APIs. The
> 5.1.0 API reference still lists `class DittoExperimental` with
> `@JvmStatic fun triggerTestPanic()` on its companion, carrying the KDoc
> *"Experimental functionality should not be used in production applications as it
> may be changed or removed at any time"* (**[api-dump]**
> `com.ditto.kotlin/-ditto-experimental`), which is what the install guide calls.

### Multicast transport — 5.1.0, opt-in beta

`DittoTransportConfig.PeerToPeer.MulticastBeta` (configured via
`config.peerToPeer.multicastBeta`) is the beta reliable UDP multicast
transport, and `DittoConnectionType.Multicast` is its connection-type enum —
both new in Kotlin 5.1.0. The 5.1.0 Kotlin changelog, verbatim
(<https://docs.ditto.live/sdk/latest/release-notes/kotlin>, #SDKS-4471): *"The transport is disabled by
default, with availability limited to supported platforms during the beta. On
Android and iOS, changes requested while sync is active take effect after sync is
stopped and successfully started again, when Ditto validates platform
prerequisites."* No multicast guide exists yet; the changelog is the only source.
5.2.0 adds `DittoSyncPermissions.requiredMulticastPermissions()` — the
permissions multicast needs beyond `requiredPermissions()` (**[api-dump]**, 5.2.0
sources; see [versions.md](versions.md#new-in-520)).

### DittoAndroidTools — platform-adjacent diagnostics

`DittoAndroidTools` is a **separate artifact** with diagnostic UI (presence
viewer, disk usage, heartbeat, logging). For v5:

```kotlin
implementation("com.ditto:ditto-tools-android:6.0.0")
```

- Tools **6.0.0** requires `com.ditto:ditto-kotlin` **5.0.1** or a later 5.x
  release and Android API 24+ (<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>).
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
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE" tools:targetApi="upside_down_cake" />
  <uses-permission android:name="android.permission.POST_NOTIFICATIONS" tools:targetApi="tiramisu" />

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
  icon must be monochrome white (<https://docs.ditto.live/sdk/latest/install-guides/kotlin>). These three
  permissions are the one case where the app declares permissions itself — the
  SDK's merged manifest covers only the transport permissions (`tools:targetApi`
  needs `xmlns:tools` on the `<manifest>`). In 5.1.0,
  `sync.stop()` no longer crashes with
  `ForegroundServiceDidNotStartInTimeException` on Android 14+ when the service
  is enabled (<https://docs.ditto.live/sdk/latest/release-notes/kotlin>).

- **`DittoInitializer`** — in v5 the Android `Context` is supplied
  automatically via AndroidX App Startup through the SDK's own manifest merger.
  Do **not** add `DittoInitializer` to your manifest; remove any manual entry
  left over from v4 (<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>).

- **`DittoSyncPermissions`** (`com.ditto.kotlin.transports.DittoSyncPermissions`)
  — runtime-permission helper (`missingPermissions()`), Android-only
  (<https://docs.ditto.live/sdk/latest/install-guides/kotlin>).

### JVM vs. Android targets

- **v4 was Android-only**: the `live.ditto:ditto` artifact and its install
  guide target *"native apps for the Android platform."*
- **v5 is a Kotlin Multiplatform rewrite** — *"native Kotlin architecture
  shared across JVM platforms"* (<https://docs.ditto.live/sdk/latest/v5-whats-new>) — so the plain-JVM
  target exists only on the v5 line.
- Depend on the **KMP root artifact** `com.ditto:ditto-kotlin`; for an Android
  app Gradle's module metadata auto-resolves the `-android` variant — never
  write `com.ditto:ditto-kotlin-android` yourself
  (<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>).
- The Android-only surfaces listed above (`DittoInitializer`,
  `DittoSyncPermissions`, `DefaultDittoForegroundService`, the manifest
  permissions) have no JVM equivalent; code targeting both must keep them
  behind Android source sets.
