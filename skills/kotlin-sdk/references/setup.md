# Setup — Kotlin

## Contents

- [CAP-01 Prerequisites and install](#cap-01-prerequisites-and-install)
- [CAP-02 Permissions and platform configuration](#cap-02-permissions-and-platform-configuration)
- [Android manifest — permissions are auto-merged](#android-manifest--permissions-are-auto-merged)
- [Runtime permissions](#runtime-permissions)
- [Foreground service (Android)](#foreground-service-android)
- [ProGuard / R8 (release builds)](#proguard--r8-release-builds)
- [JVM target](#jvm-target)

> **Sources for this file.** <https://docs.ditto.live/sdk/latest/install-guides/kotlin>,
> <https://docs.ditto.live/sdk/latest/compatibility/kotlin>, <https://docs.ditto.live/sdk/v4/install-guides/kotlin>, and executed
> builds of the JVM and Android [reference projects](reference-projects.md) (the
> Android one on an emulator) at the versions named in [versions.md](versions.md). Facts that differ
> across version lines — including the v4 coordinate — live in
> [versions.md](versions.md); this file shows the v5 form only.

## CAP-01 Prerequisites and install

For new apps/POCs, read
<https://repo.maven.apache.org/maven2/com/ditto/ditto-kotlin/maven-metadata.xml>
and choose the highest stable `major.minor.patch` in `<versions>` (exclude rc,
preview, experimental and dev builds; do not assume `<latest>` is stable). Check
that the matching `ditto-binaries` release/classifier exists for JVM. Set
`dittoVersion=<resolved version>` in `gradle.properties` or the version catalog;
use the same value for both artifacts and record the resolution. Do not use a
floating `+` dependency that can unexpectedly select a prerelease. **5.2.0 is the
latest version known to this skill.** Check newer release notes/toolchain requirements
before generating code for a newer release. Existing project pins take precedence.

**Toolchain (5.2.0 baseline):**

- JDK 17, Android `minSdk` 24 (Android 7.0), `compileSdk` 36
  (<https://docs.ditto.live/sdk/latest/install-guides/kotlin>).
- Kotlin: docs say 2.0+ (<https://docs.ditto.live/sdk/latest/compatibility/kotlin>), but
  the 5.1.0 and 5.2.0 artifacts depend on `kotlin-stdlib` **2.3.21** (5.0.3: 2.1.0 —
  Maven Central POMs), and the compiler reads metadata at most one minor version newer,
  so the practical floor is **KGP ≥ 2.2 for 5.1.0 and 5.2.0**. Security-updated JVM pin: Kotlin **2.4.21**
  with `kotlinx-coroutines` 1.11.x. On Android with AGP 9, use built-in Kotlin — do
  **not** apply `org.jetbrains.kotlin.android` (**executed**: v5 5.2.0, 5.1.0 and 5.0.3 built
  with AGP 9.4.1 and no KGP applied, run on a Pixel 10a / Android 17).
- **`compileSdk` 36 is enforced, not advisory:** the 5.x AARs declare a minimum
  `compileSdk`, and a project at 35 fails `CheckAarMetadata` with "requires libraries
  and applications that depend on it to compile against … a newer compileSdk"
  (**executed**, 5.1.0). `minSdk` 24 is unchanged.
- Repository: `mavenCentral()`.

**Security pins:** use KGP **2.4.21**; versions before 2.4.20 are affected by the
[Kotlin build-cache deserialization advisory](https://github.com/advisories/GHSA-r937-wjx7-w2jp).
AGP 9 embeds an older KGP (9.4.1 embeds 2.2.10, per its Google Maven POM). Keep built-in Kotlin enabled and
select the patched KGP through `buildscript.dependencies.classpath`, as supported by
the [AGP guidance](https://developer.android.com/build/releases/agp-9-0-0-release-notes#upgrade-to-a-higher-kgp-version):

```kotlin
buildscript {
    dependencies { classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.4.21") }
}
```

The fixture also aligns Java OpenTelemetry through BOM **1.67.0** for the
[trace-context parsing fix](https://github.com/advisories/GHSA-ccrj-gw8r-854m), and v4
Android Jackson through BOM **2.18.12**, including the
[parser resource-limit fix](https://github.com/advisories/GHSA-7hhh-6rmp-j9qf).
These are application dependency constraints; they do not change the SDK's published
POM metadata. JVM behavior is verified on 5.0.3, 5.1.0 and 5.2.0; the updated Android
dependency graphs resolve, but APK builds require a local Android SDK.

**Android app — the only Ditto dependency line you need:**

```kotlin
// build.gradle.kts (app module)
val dittoVersion: String by project // gradle.properties: version resolved from Maven Central
dependencies {
    implementation("com.ditto:ditto-kotlin:$dittoVersion")
}
```

Two non-Ditto additions the samples in this skill assume (add them when you use
those features):

```kotlin
// Whole-document decode samples (carJson.decodeFromString<Car>(…)) need:
implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")
//   plus `kotlin("plugin.serialization")` in the plugins block
// collectAsStateWithLifecycle() in Compose needs:
implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
```

`com.ditto:ditto-kotlin` is the KMP root module; an Android project resolves the
`-android` variant automatically. No `Context` wiring: the SDK initializes its Android
context itself via AndroidX Startup (`DittoInitializer`) — do **not** add a manual
`DittoInitializer` entry to your manifest, and remove one if migrating from v4
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>).

**Plain JVM (server/desktop) — two coordinates:**

```kotlin
// build.gradle.kts
val dittoVersion: String by project // gradle.properties: version resolved from Maven Central
dependencies {
    implementation("com.ditto:ditto-kotlin:$dittoVersion")
    // The JVM variant ships without native binaries; add the one for the host:
    runtimeOnly("com.ditto:ditto-binaries:$dittoVersion:macos-arm64")
    // classifiers: macos-arm64 | linux-x64 | linux-arm64 | windows-x64
}
```

Without the `ditto-binaries` classifier the first `DittoFactory.create` throws
(**executed**, 5.0.3/5.1.0/5.2.0):

```
IllegalStateException: Unable to find binary 'libdittoall.dylib' for Darwin ARM64
on classpath ... Make sure you've included a `ditto-binaries` dependency for the
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
merger adds them to your app (<https://docs.ditto.live/sdk/latest/install-guides/kotlin>):

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
(<https://docs.ditto.live/sdk/latest/install-guides/kotlin>):

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
[transports.md](transports.md), <https://docs.ditto.live/sdk/latest/install-guides/kotlin>).

### ProGuard / R8 (release builds)

Required keep rule (<https://docs.ditto.live/sdk/latest/install-guides/kotlin>):

```proguard
-keep class com.ditto.** { *; }
-keep, includedescriptorclasses class org.rustls.platformverifier.** { *; }
```

Both rules are required (<https://docs.ditto.live/sdk/latest/install-guides/kotlin>): the second keeps the TLS
platform verifier, or `Connect.Server` connections break in minified builds. Yes, the
first rule is package-wide — it is the vendor-mandated rule. The SDK's own AARs have
bundled consumer rules for their *internals* since 5.0.1 (**[source-verified]**:
`proguard.txt` in `ditto-internal-android` and `ditto-cinterop-android` keeps
`com.ditto.internal.**` / `com.ditto.dittoffi.**`) — but those do not cover the public
`com.ditto.kotlin.**` facade or the third-party rustls verifier, so keep both rules;
scope narrower only if you have minified-build-tested the result.

Symptom when missing — a release (minified) build crashes on first SDK call with
(string quoted verbatim from the install guide; `someNativeMethod` is its placeholder,
not an executed output):

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
<https://docs.ditto.live/sdk/latest/deployment/network-deployment>
(<https://docs.ditto.live/sdk/latest/deployment/network-deployment>).
