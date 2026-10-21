# Testing — Ditto Kotlin SDK

Everything here is the **v5** (5.0.x / 5.1.x) form with tagged v4 asides.
[versions.md](versions.md) owns package coordinates per version line.

Sources: `sdk/latest/deployment/testing`, `sdk/latest/install-guides/kotlin`
(ProGuard + crash-reporter sections), `sdk/latest/compatibility/kotlin`
(transport support matrix). The JVM-unit-test pattern is **executed** against
5.0.3 and 5.1.0.

## CAP-18 Testing

### What the testing page documents

`sdk/latest/deployment/testing` is language-generic with per-language snippets. Its
Kotlin-relevant guidance:

- **Unit tests**: "wrap Ditto behind an interface in your app code and inject a mock
  implementation in your unit tests. When you need a real Ditto instance in a test,
  initialize it with an offline identity (no license token) and do not start sync."
- **Identity switching** (pre-production only, not production): hold the instance in a
  nullable var and swap it:

  ```kotlin
  var ditto: Ditto? = null
  ditto = Ditto(...)
  // or
  ditto?.close()
  ditto = Ditto(...)
  ```

  (The snippet is v4-shaped — v5 construction is `DittoFactory.create(DittoConfig(...))`.)
  When you switch identities, also change the persistence directory — "We suggest
  changing the persistence directory to prepend the databaseId to the path" — because
  old data in the same directory keeps syncing under the new identity.
- **Simulating offline**, two approaches:
  1. *Network level*: block `*.cloud.ditto.live` via firewall/DNS/proxy. Warning quoted
     from the page: the app "must complete authentication and obtain a valid auth token
     **before** you block the connection" — Small Peers need a valid token even for
     peer-to-peer sync.
  2. *Transport config*: the page's Kotlin snippet
     (`transportConfig.connect.webSocketURLs = mutableSetOf()`) targets the v4 mutable
     transport model. In v5 the cloud URL comes from `DittoConfig.Connect.Server(url)`,
     so the idiomatic offline test instance is simply
     `DittoConfig.Connect.SmallPeersOnly()` — no WebSocket URL ever exists.
- **Server-side isolation** for shared environments: app-per-environment, or
  collection prefixing per developer (e.g. `john_smith.orders.v3`). There is no
  mockable Ditto Server for CI ("We don't have anything to provide today").

## JVM unit and integration tests (v5)

The v5 SDK is Kotlin Multiplatform: a JVM target resolves `com.ditto:ditto-kotlin` to
its **`-jvm` variant**, so plain JUnit tests — no emulator, no Robolectric — can open
a **real** Ditto. **Executed** on 5.0.3 and 5.1.0 with exactly this pattern:
`DittoConfig.Connect.SmallPeersOnly` + `setOfflineOnlyLicenseToken`.

### Required dependencies

The JVM variant loads the native core from a separate classifier artifact. Without it,
`DittoFactory.create()` throws
`IllegalStateException: Unable to find binary 'libdittoall.dylib' … include a ditto-binaries dependency`
(**executed**; see [errors.md](errors.md)).

```kotlin
// build.gradle.kts — JVM module
dependencies {
    implementation("com.ditto:ditto-kotlin:5.1.0")
    // Pick the classifier for the CI/dev host:
    //   macos-arm64 | linux-x64 | linux-arm64 | windows-x64
    runtimeOnly("com.ditto:ditto-binaries:5.1.0:macos-arm64")

    testImplementation("org.junit.jupiter:junit-jupiter:5.10.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.1")
}
```

### Minimal test skeleton

**Executed** pattern — offline-only instance, unique temp `persistenceDirectory` per
test, `runTest` for the suspend APIs:

```kotlin
import com.ditto.kotlin.Ditto
import com.ditto.kotlin.DittoConfig
import com.ditto.kotlin.DittoFactory
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals

class DittoStoreTest {

    @TempDir
    lateinit var tempDir: File   // unique per test — two live instances on one
                                 // directory fail with a persistence-directory lock

    private fun makeDitto(): Ditto {
        val ditto = DittoFactory.create(
            DittoConfig(
                databaseId = "test-database",
                connect = DittoConfig.Connect.SmallPeersOnly(),
                persistenceDirectory = tempDir.absolutePath,  // String? in v5, not File?
            )
        )
        // Never commit a license token — read it from the environment.
        ditto.setOfflineOnlyLicenseToken(
            System.getenv("DITTO_OFFLINE_LICENSE") ?: error("DITTO_OFFLINE_LICENSE not set")
        )
        return ditto
    }

    @Test
    fun insertThenReadBack() = runTest {
        val ditto = makeDitto()
        try {
            ditto.store.execute(
                query = "INSERT INTO cars DOCUMENTS (:doc)",
                arguments = mapOf("doc" to mapOf("_id" to "car1", "color" to "blue")),
            )
            val color = ditto.store.execute(
                query = "SELECT * FROM cars WHERE _id = :id",
                arguments = mapOf("id" to "car1"),
            ) { result -> result.items.first().value["color"].stringOrNull }
            assertEquals("blue", color)
        } finally {
            ditto.close()   // v5 classes implement DittoResource (AutoCloseable)
        }
    }
}
```

Notes:

- No `sync.start()` — the instance is offline-only, which is exactly what the testing
  page prescribes for a real instance in a test. Store, observers, transactions and
  attachments all work without sync.
- A second plain `INSERT` of `_id = "car1"` in the same test throws the FAIL-conflict
  `UnknownException` catalogued in [errors.md](errors.md) — that is a convenient,
  deterministic way to test your own error paths.
- `runBlocking` works too if you are not on kotlinx-coroutines-test.

### Wait on events, never on time

An observer fires once immediately and again on every change, so a test can await the
delivery itself. With the v5 Flow API that is `observe(...)` + `first { }` under a
timeout — the timeout is what turns a regression into a failure instead of a hung suite:

```kotlin
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeout

@Test
fun observerReportsTheWrite() = runTest {
    val ditto = makeDitto()
    try {
        val counts = ditto.store.observe("SELECT * FROM cars") { result ->
            result.items.size          // plain data only — items die with the lambda
        }
        ditto.store.execute(
            "INSERT INTO cars DOCUMENTS (:doc)",
            mapOf("doc" to mapOf("_id" to "car1")),
        )
        val seen = withTimeout(10_000) { counts.first { it == 1 } }
        assertEquals(1, seen)
    } finally {
        ditto.close()
    }
}
```

**A test that asserts nothing proves nothing.** Match the specific `DittoException`
subclass/reason you mean ([errors.md](errors.md)) rather than "something threw" —
`assertFailsWith<DittoException>` passes for a bad license or a typo just as happily
as for the behaviour under test.

## Android instrumented tests

Anything that needs the Android runtime — `DittoInitializer` context handling,
permissions, the foreground service — belongs in `androidTest` on an emulator or
device.

**Two-emulator mesh testing.** Launch two AVDs and install the instrumented APK on
both (`adb -s emulator-5554 install …` / `adb -s emulator-5556 install …`). Then check
the compatibility matrix before choosing a transport — `sdk/latest/compatibility/kotlin`
marks the **Android Emulator** row `--` (unsupported) for **BLE 5.0+**, **AWDL**,
**Wi-Fi Aware** *and* **LAN**; only **WebSockets** is supported. So:

- Emulator ↔ emulator sync must travel over WebSockets — in practice a shared
  `DittoConfig.Connect.Server(url)` both emulators reach. There is no LAN/mDNS path
  between emulators per the compatibility table.
- BLE, Wi-Fi Aware and LAN mesh behaviour can only be tested on **physical devices**;
  do not write emulator tests that assert on those transports.

## ProGuard / R8

From `sdk/latest/install-guides/kotlin` (§ Proguard): a minified release build without
the keep rules crashes at runtime, typically as:

```
java.lang.NoSuchMethodError: no static method "Lcom/ditto/internal/dittoffi/DittoFFI;.someNativeMethod(...)"
```

The required rules, quoted exactly:

```
-keep class com.ditto.** { *; }
-keep, includedescriptorclasses class org.rustls.platformverifier.** { *; }
```

- `-keep class com.ditto.**` retains all SDK classes (including the JNI bindings under
  `com.ditto.internal.*`) so native callbacks resolve and presence/serialization can
  reflect on Ditto types.
- `org.rustls.platformverifier.**` must be kept so TLS connections to Ditto Server
  work in minified builds.
- `{ *; }` preserves all members.

This is why a smoke test must run against the **release-minified** build, not only
`debug` — the crash only exists post-shrink.

> **v4 aside.** v4 (`live.ditto:ditto`) needs different rules and shows a different
> crash (`sdk/v4/install-guides/kotlin`):
> `NoSuchMethodError: … Llive/ditto/internal/swig/ffi/dittoffiJNI;.SwigDirector_Retainable_retain…`.
> Its rules: `-keep class live.ditto.internal.swig.ffi.** { *; }`,
> `-keep class live.ditto.** { *; }`, `-keepnames class com.fasterxml.jackson.** { *; }`.

## Crash-reporter verification

From `sdk/latest/install-guides/kotlin` (§ Using crash reporters in Android apps) —
run this once per crash reporter (Crashlytics, Sentry, BugSnag):

1. **Setup** — integrate the reporter SDK per its own docs.
2. **Check crash collection** — trigger a panic and confirm it registers:

   ```kotlin
   DittoExperimental.triggerTestPanic()
   ```

   Without native symbols the crash will be unreadable; if nothing shows up at all,
   the reporter is misintegrated.
3. **Upload symbols** — upload the SDK's native `.so` for your target ABI, found at
   `$buildDir/intermediates/merged_native_libs/$variant/out/lib/$arch/libdittoffi.so`.
   Crashlytics' Gradle plugin uploads automatically; Sentry and BugSnag provide CLIs.
4. **Final test** — trigger another panic and confirm the report is now symbolicated.

In v5 the same panic also surfaces in-process as
`DittoException.DittoPanicException` with `nativeCrashMessage` /
`nativeCrashStackTrace` — see [errors.md](errors.md).

## v4 testing constraints

v4 (`live.ditto:ditto`, e.g. `4.14.6`) is **Android-only — there is no JVM artifact**,
so the plain-JUnit pattern above does not exist on v4. v4 tests need instrumented
tests on an emulator/device, with an offline identity
(`DittoIdentity.OfflinePlayground`) and no `startSync()` — the same "offline identity,
no sync" rule the testing page states, expressed through the v4 API.

## What a unit test cannot cover

Radio behaviour. A single-process JVM suite exercises the store, transactions,
observers, attachments and activation; it cannot exercise BLE, Wi-Fi Aware, mDNS
discovery, multi-peer convergence or connection requests. Those need two devices
(physical ones, per the compatibility matrix above) and belong in an instrumented
integration test, not this suite.
