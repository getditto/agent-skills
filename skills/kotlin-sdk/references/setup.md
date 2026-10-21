# Setup — Kotlin

> **Sources for this file.** `sdk/latest/install-guides/kotlin`,
> `sdk/latest/compatibility/kotlin`, `sdk/v4/install-guides/kotlin`, and executed
> builds of `tests/kotlin-sdk/minimal-app` (JVM) and `tests/kotlin-sdk/android-app`
> (emulator) at the versions named in [versions.md](versions.md). Facts that differ
> across version lines — including the v4 coordinate — live in
> [versions.md](versions.md); this file shows the v5 form only.

## CAP-01 Prerequisites and install

**Toolchain (v5):**

- JDK 17, Android `minSdk` 24 (Android 7.0), `compileSdk` 36
  (sdk/latest/install-guides/kotlin).
- Kotlin: docs say 2.0+ (N−4 support window, sdk/latest/compatibility/kotlin), but the
  **executed floor is 2.3.x** — the 5.0.3/5.1.0 artifacts embed stdlib 2.3.x metadata
  and the harness failed to compile under Kotlin 2.0.x. Use the Kotlin Gradle plugin
  2.3.x with `kotlinx-coroutines` 1.10.x (executed: 2.3.21 + 1.10.2).
- Repository: `mavenCentral()`.

**Android app — the only dependency line you need:**

```kotlin
// build.gradle.kts (app module)
dependencies {
    implementation("com.ditto:ditto-kotlin:5.1.0")
}
```

`com.ditto:ditto-kotlin` is the KMP root module; an Android project resolves the
`-android` variant automatically. No `Context` wiring: the SDK initializes its Android
context itself via AndroidX Startup (`DittoInitializer`) — do **not** add a manual
`DittoInitializer` entry to your manifest, and remove one if migrating from v4
(sdk/latest/migration-guides/kotlin-v4).

**Plain JVM (server/desktop) — two coordinates:**

```kotlin
// build.gradle.kts
dependencies {
    implementation("com.ditto:ditto-kotlin:5.1.0")
    // The JVM variant ships without native binaries; add the one for the host:
    runtimeOnly("com.ditto:ditto-binaries:5.1.0:macos-arm64")
    // classifiers: macos-arm64 | linux-x64 | linux-arm64 | windows-x64
}
```

Without the `ditto-binaries` classifier the first `DittoFactory.create` throws
(**executed**, 5.0.3/5.1.0):

```
IllegalStateException: Unable to find binary 'libdittoall.dylib' for Darwin ARM64
on classpath ... Make sure you've included a 'ditto-binaries' dependency for the
correct platform.
```

For CI matrices, select the classifier from `os.name`/`os.arch`. Android needs no
classifier — the AAR bundles `arm64-v8a`, `armeabi-v7a`, `x86` and `x86_64`
(verified from the published AAR contents).

**First call:** nothing needs to be awaited before `DittoFactory.create(config)` — it
is not `suspend` (see [connect.md](connect.md)).

**4.14.x:** different coordinate (`live.ditto:ditto`), Android-only — see
[versions.md](versions.md#package-coordinates-per-version-line).

## CAP-02 Permissions and platform configuration

### Android manifest — permissions are auto-merged

The SDK's own manifest declares every permission its transports need, and manifest
merger adds them to your app (sdk/latest/install-guides/kotlin):

```xml
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="32" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
<uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" android:usesPermissionFlags="neverForLocation" />
```

To strip one (e.g. you ship a cloud-only app), use
`<uses-permission … tools:node="remove" />` with `xmlns:tools` — details and the
per-transport mapping: [transports.md](transports.md). Why each radio needs a
permission is owned by the `ditto-mesh-networking` skill —
<https://docs.ditto.live/sdk/latest/sync/customizing-transport-configurations>.

### Runtime permissions

Bluetooth/Wi-Fi Aware permissions are *runtime* permissions. The SDK ships a helper
(sdk/latest/install-guides/kotlin):

```kotlin
import com.ditto.kotlin.transports.DittoSyncPermissions

val missing = DittoSyncPermissions(context).missingPermissions()
if (missing.isNotEmpty()) {
    // request them (Activity Result API), then:
    ditto.refreshPermissions()   // picks up grants without an app restart
}
```

Symptom when missing: P2P sync silently never starts — the app looks "offline" with
no error. Check `ditto.transportCondition` ([transports.md](transports.md)) before
blaming the mesh.

### Foreground service (Android)

`sync.start()` can run `DefaultDittoForegroundService` so sync survives backgrounding;
declare it in your manifest (full snippet and behavior:
[transports.md](transports.md), sdk/latest/install-guides/kotlin).

### ProGuard / R8 (release builds)

Required keep rule (sdk/latest/install-guides/kotlin):

```proguard
-keep class com.ditto.** { *; }
```

Symptom when missing — a release (minified) build crashes on first SDK call with:

```
java.lang.NoSuchMethodError: no static method "Lcom/ditto/internal/dittoffi/DittoFFI;.someNativeMethod(...)"
```

The rule retains the JNI bindings under `com.ditto.internal.*` so native callbacks
resolve. Debug builds do not minify, so this only surfaces in release — always
smoke-test a minified build ([testing.md](testing.md)).

### JVM target

None of the Android items above apply: no permissions, no manifest, no ProGuard (the
native binary loads from the `ditto-binaries` JAR at runtime). Firewall/proxy egress
rules for the Big Peer are platform-neutral — see
`sdk/latest/deployment/network-deployment`
(<https://docs.ditto.live/sdk/latest/deployment/network-deployment>).
