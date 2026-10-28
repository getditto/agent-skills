# Preview and platform-specific APIs — Ditto Kotlin SDK

> **Sources for this file.** <https://docs.ditto.live/sdk/latest/sync/data-streams>,
> <https://docs.ditto.live/sdk/latest/release-notes/kotlin>, <https://docs.ditto.live/sdk/latest/install-guides/kotlin>,
> <https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>, <https://docs.ditto.live/sdk/latest/v5-whats-new>.
>
> This is not Compose `@Preview`. It is the part of the Kotlin SDK that is
> explicitly preview, beta, experimental, or available on only one target.

## Contents

- [CAP-20 Preview and platform-specific APIs](#cap-20-preview-and-platform-specific-apis)
  - [Data Streams — preview, 5.1.0 floor](#data-streams--preview-510-floor)
  - [DittoConfig.Experimental](#dittoconfigexperimental)
  - [DittoExperimental.triggerTestPanic()](#dittoexperimentaltriggertestpanic)
  - [Multicast transport — 5.1.0, opt-in beta](#multicast-transport--510-opt-in-beta)
  - [DittoAndroidTools — platform-adjacent diagnostics](#dittoandroidtools--platform-adjacent-diagnostics)
  - [Android-only platform APIs](#android-only-platform-apis)
  - [JVM vs. Android targets](#jvm-vs-android-targets)

## CAP-20 Preview and platform-specific APIs

### Data Streams — preview, 5.1.0 floor

Low-latency, bidirectional, peer-to-peer **raw-byte** channels over named topics that
**never write to the Ditto store**; the non-preview alternative for data that must
persist, be queried or converge is document sync or an attachment
(<https://docs.ditto.live/sdk/latest/sync/data-streams>).

1. **Preview.** *"Data Streams are in Public Preview and may receive breaking changes
   without notice. You must acknowledge this in code by opting in with
   `@file:OptIn(com.ditto.kotlin.PreviewDataStreams::class)`."*
   (<https://docs.ditto.live/sdk/latest/sync/data-streams>). The opt-in is per file.
2. **Versions.** The docs name **5.1.0** as the requirement and cover Android. The classes
   ship in 5.0.3 as well, and the two-peer fixture passes on 5.0.3, 5.1.0 and 5.2.0 on the
   JVM (**executed**); treat 5.1.0 as the supported floor. Not Kotlin-only any more: the
   Swift SDK exposes the same API from 5.2.0 behind `@_spi(PreviewDataStreams)`.
3. **NGN first.** Streams run over NGN, enabled before `DittoFactory.create` through
   `DITTO_NETWORK_ENABLE_NGN=true` (Android `Os.setenv` in `Application.onCreate()`; the
   process environment on the JVM) or, from 5.2.0, `DittoConfig(systemParameters =
   mapOf("network_enable_ngn" to true, …))` (**executed**).

Implementation guide, API table, executed error strings and the two JVM defects to code
around (`arguments()` throwing when none were sent; `topic()` returning garbage):
[data-streams.md](data-streams.md). Concepts and design patterns: the `data-streams` skill.

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
