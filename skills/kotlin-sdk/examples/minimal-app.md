# Minimal app — Ditto Kotlin SDK

## Contents

- [What it does](#what-it-does)
- [Dependency (v5, JVM)](#dependency-v5-jvm)
- [Program](#program)
- [Running it](#running-it)
- [Expected output](#expected-output)
- [The v4 leg (Android, 4.14.7)](#the-v4-leg-android-4147)
- [The v5 leg on Android (5.2.0, 5.1.0 and 5.0.3)](#the-v5-leg-on-android-520-510-and-503)
- [Verified on](#verified-on)

A complete, runnable program. Every line needed to build it is present: imports,
dependency declaration, and the enclosing `main` context. The source of truth lives in
this repository and is compiled and run:

- **v5 (JVM):** the `minimal-app` harness project — `src/main/kotlin/MainV5.kt`,
  reproduced below. Its full `build.gradle.kts` is in
  [reference-projects.md](../references/reference-projects.md#jvm-v5-project).
- **v4 (Android):** the `android-app` harness project
  ([build files](../references/reference-projects.md#android-project)) —
  4.14.x has no JVM artifact, so the v4 leg runs as an Android app on an emulator;
  transcript below.

Longer form of `SKILL.md` § *Minimum viable app*.

**This is a copy of `minimal-app/src/main/kotlin/MainV5.kt` in the fixture**, which CI
compiles and runs against 5.0.3, 5.1.0 and 5.2.0; `scripts/validate-sdk-skills.py` fails when the
program block below drifts from it.

## What it does

Configures Ditto (offline identity, no cloud), activates a license, starts sync,
registers a subscription, observes a query, writes a document, reads it back, then
closes everything in reverse order.

## Dependency (v5, JVM)

For a new app, resolve the latest stable Maven Central release using
[setup.md](../references/setup.md) and set `dittoVersion` in `gradle.properties`.
The transcripts/fixture pins below are historical validation baselines, not a
recommendation to use a fixed release. This skill knows through 5.2.0.

```kotlin
// tests/kotlin-sdk/minimal-app/build.gradle.kts (excerpt)
plugins {
    kotlin("jvm") version "2.4.21"   // includes the Kotlin build-cache security fix
    application
}

val dittoVersion: String by project // use the latest stable version checked below
dependencies {
    implementation(enforcedPlatform("io.opentelemetry:opentelemetry-bom:1.67.0"))
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
    implementation("com.ditto:ditto-kotlin:$dittoVersion")
    // Mandatory on JVM — without it DittoFactory.create throws
    // "Unable to find binary 'libdittoall.dylib' …":
    runtimeOnly("com.ditto:ditto-binaries:$dittoVersion:macos-arm64")
    // other classifiers: linux-x64 | linux-arm64 | windows-x64
}
```

## Program

```kotlin
import com.ditto.kotlin.DittoConfig
import com.ditto.kotlin.DittoFactory
import com.ditto.kotlin.Ditto
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

fun main() = runBlocking {
    val license = System.getenv("DITTO_OFFLINE_LICENSE")
        ?: error("DITTO_OFFLINE_LICENSE is not set")
    // Offline licenses are issued per database ID; use the one the license was made for.
    val databaseId = System.getenv("DITTO_DATABASE_ID") ?: "kotlin-minimal-app"

    buildDir().deleteRecursively()  // deterministic output across runs
    com.ditto.kotlin.DittoLogger.isEnabled = false

    val ditto = DittoFactory.create(
        DittoConfig(
            databaseId = databaseId,
            connect = DittoConfig.Connect.SmallPeersOnly(),
            persistenceDirectory = buildDir().absolutePath,
        )
    )
    ditto.setOfflineOnlyLicenseToken(license)
    ditto.sync.start()

    val query = "SELECT * FROM cars"
    val subscription = ditto.sync.registerSubscription(query)

    val observed = Mutex(locked = true)
    val observer = ditto.store.registerObserver(query) { result ->
        val count = result.items.size
        println("observer: $count car(s)")
        if (count > 0) observed.unlock()
    }

    ditto.store.execute(
        query = "INSERT INTO cars DOCUMENTS (:car) ON ID CONFLICT DO UPDATE",
        arguments = mapOf("car" to mapOf("_id" to "car1", "make" to "Toyota", "mileage" to 120))
    )

    // Wait for the observer to fire, then verify with a read.
    launch {
        observed.withLock { }
        val make = ditto.store.execute(
            query = "SELECT * FROM cars WHERE _id = :id",
            arguments = mapOf("id" to "car1")
        ) { result -> result.items.firstOrNull()?.value?.get("make")?.stringOrNull }
        println("read-back make: $make")
        println("SDK version: ${Ditto.VERSION}")

        observer.close()
        subscription.close()
        ditto.sync.stop()
        ditto.close()
    }.join()
}

fun buildDir(): java.io.File =
    java.io.File(System.getProperty("user.dir"), "ditto-data").apply { mkdirs() }
```

Three things this program demonstrates that bite people:

1. **The observer fires before any write** — `observer: 0 car(s)` is the initial
   delivery of the current (empty) local state, not a change event.
2. **Re-running a plain `INSERT` fails.** A second execution of the same `_id` without
   `ON ID CONFLICT DO UPDATE` throws (executed, 5.1.0):
   `DittoException.UnknownException: <dql> Query failed: … Identifier conflict on
   document "car1": using FAIL conflict policy` — see
   [../references/store.md](../references/store.md).
3. **Everything opened must be closed** — observer, subscription, sync, then the
   `Ditto` instance itself (all `AutoCloseable` via `DittoResource`).

## Running it

These repository fixture commands reproduce the recorded 5.2.0 run. For a new app,
use the stable version just resolved from Maven Central as described above.

```bash
export DITTO_OFFLINE_LICENSE=…        # repo-root .env is NOT auto-loaded here
cd tests/kotlin-sdk/minimal-app
gradle run -PdittoLine=v5 -PdittoVersion=5.2.0 --console=plain -q
```

## Expected output

Actual run, 5.2.0 (macOS arm64, OpenJDK 17), trailing lines:

```
Loading native library at path: jar:file:…/ditto-binaries-5.2.0-macos-arm64.jar!/macos/arm64/libdittoall.dylib
…
observer: 0 car(s)
observer: 1 car(s)
read-back make: Toyota
SDK version: 5.2.0
```

The same run against 5.1.0 and 5.0.3 prints `SDK version: 5.1.0` / `5.0.3` with
identical observer and read-back lines. (`DittoLogger.isEnabled = false` does not suppress the INFO init
lines the SDK prints during `DittoFactory.create` — they precede logger
configuration; see [../references/observability.md](../references/observability.md).)

## The v4 leg (Android, 4.14.7)

`live.ditto:ditto:4.14.7` is an Android AAR with no JVM variant, so the v4 program is
an `Activity` (`tests/kotlin-sdk/android-app`) that runs the same open → subscribe →
observe → write → read-back flow on a background thread and logs to logcat. Two v4
differences matter (details in [../references/versions.md](../references/versions.md)):

- Construction is `Ditto(DefaultAndroidDittoDependencies(context),
  DittoIdentity.OfflinePlayground(dependencies, appId = …))` — the identity takes the
  dependencies object first (javap-verified).
- **`ditto.disableSyncWithV3()` is required before any mutating DQL.** Without it the
  insert throws ``DittoError.StoreError: <dql> Unsupported feature: Encountered
  `INSERT` statement. … disable sync with V3 to use DQL`` (executed).

```bash
cd tests/kotlin-sdk/android-app
./gradlew installDebug -PdittoLine=v4 -PdittoVersion=4.14.7   # license from .env or DITTO_OFFLINE_LICENSE
adb shell am start -n live.ditto.minimal/.MainActivity
adb logcat -d | grep DittoMinimal
```

Actual logcat, 4.14.7, emulator `android-35` (google_apis arm64):

```
I DittoMinimal: observer: 0 car(s)
I DittoMinimal: observer: 1 car(s)
I DittoMinimal: read-back make: Toyota
I DittoMinimal: SDK version: AndJ4.14.7_7506fa2fd0
I DittoMinimal: EXIT=0
```

Note the v4 version string is platform-tagged (`AndJ4.14.7_7506fa2fd0`), not the plain
semver v5 prints.

## The v5 leg on Android (5.2.0, 5.1.0 and 5.0.3)

The same Android project builds the v5 API with `-PdittoLine=v5` (`compileSdk` 36 — the
5.x AARs enforce it). Its activity runs the JVM program's flow and adds two probes for
the claims the JVM cannot answer for Android: which thread a `registerObserver` handler
starts on, and whether `.flowOn(Dispatchers.IO)` moves an `observe()` transform.

```bash
cd tests/kotlin-sdk/android-app
./gradlew installDebug -PdittoLine=v5 -PdittoVersion=5.2.0 -PdittoAbi=arm64-v8a
adb shell am start -n live.ditto.minimal/.MainActivity
adb logcat -d | grep DittoMinimal
```

Actual logcat, 5.2.0, Pixel 10a (Android 17):

```
I DittoMinimal: observer: 0 car(s) [thread=main main=true]
I DittoMinimal: observe() transform under flowOn(IO) ran on thread=main
I DittoMinimal: observer: 1 car(s) [thread=main main=true]
I DittoMinimal: read-back make: Toyota
I DittoMinimal: SDK version: 5.2.0
I DittoMinimal: EXIT=0
```

5.1.0 and 5.0.3 print the same lines with `SDK version: 5.1.0` / `5.0.3`. Both probes confirm
[../references/concurrency.md](../references/concurrency.md): the handler is on the
main thread, and `flowOn` does not reach the transform.

## Verified on

| Line | Patch | Target | Host | Date |
|---|---|---|---|---|
| 5.2.x | 5.2.0 | JVM | macOS arm64, OpenJDK 17.0.20.1, Gradle 9.8.2; CI Linux x64 | 2026-10-27 |
| 5.2.x | 5.2.0 | Android, Pixel 10a (Android 17, arm64) | macOS, AGP 9.4.1, compileSdk 36 | 2026-10-27 |
| 5.1.x | 5.1.0 | JVM | macOS arm64, OpenJDK 17.0.20.1, Gradle 9.8.2; CI Linux x64 | 2026-10-27 |
| 5.1.x | 5.1.0 | Android, Pixel 10a (Android 17, arm64) | macOS, AGP 9.4.1, compileSdk 36 | 2026-10-27 |
| 5.0.x | 5.0.3 | JVM | macOS arm64, OpenJDK 17.0.20.1, Gradle 9.8.2; CI Linux x64 | 2026-10-27 |
| 5.0.x | 5.0.3 | Android, Pixel 10a (Android 17, arm64) | macOS, AGP 9.4.1, compileSdk 36 | 2026-10-27 |
| 4.14.x | 4.14.7 | Android emulator (API 35, arm64); Pixel 10a | macOS, AGP 9.4.1, compileSdk 35 | 2026-10-27 |

`5.2.0-rc.2` (sources identical to 5.2.0 GA) was executed the same way on both targets
before GA and printed `SDK version: 5.2.0-rc.2`.
