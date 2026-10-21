# Minimal app — Ditto Kotlin SDK

A complete, runnable program. Every line needed to build it is present: imports,
dependency declaration, and the enclosing `main` context. The source of truth lives in
this repository and is compiled and run:

- **v5 (JVM):** [`tests/kotlin-sdk/minimal-app/`](../../../tests/kotlin-sdk/minimal-app) —
  `build.gradle.kts` + `src/main/kotlin/MainV5.kt`, reproduced below.
- **v4 (Android):** [`tests/kotlin-sdk/android-app/`](../../../tests/kotlin-sdk/android-app) —
  4.14.x has no JVM artifact, so the v4 leg runs as an Android app on an emulator;
  transcript below.

Longer form of `SKILL.md` § *Minimum viable app*.

## What it does

Configures Ditto (offline identity, no cloud), activates a license, starts sync,
registers a subscription, observes a query, writes a document, reads it back, then
closes everything in reverse order.

## Dependency (v5, JVM)

```kotlin
// tests/kotlin-sdk/minimal-app/build.gradle.kts (excerpt)
plugins {
    kotlin("jvm") version "2.3.21"   // 2.3.x required: 5.x artifacts embed stdlib 2.3.x metadata
    application
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
    implementation("com.ditto:ditto-kotlin:5.1.0")
    // Mandatory on JVM — without it DittoFactory.create throws
    // "Unable to find binary 'libdittoall.dylib' …":
    runtimeOnly("com.ditto:ditto-binaries:5.1.0:macos-arm64")
    // other classifiers: linux-x64 | linux-arm64 | windows-x64
}
```

## Program (v5)

```kotlin
// tests/kotlin-sdk/minimal-app/src/main/kotlin/MainV5.kt
import com.ditto.kotlin.DittoConfig
import com.ditto.kotlin.DittoFactory
import com.ditto.kotlin.Ditto
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

fun main() = runBlocking {
    val license = System.getenv("DITTO_OFFLINE_LICENSE")
        ?: error("DITTO_OFFLINE_LICENSE is not set")

    buildDir().deleteRecursively()  // deterministic output across runs
    com.ditto.kotlin.DittoLogger.isEnabled = false

    val ditto = DittoFactory.create(
        DittoConfig(
            databaseId = "kotlin-minimal-app",
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

```bash
export DITTO_OFFLINE_LICENSE=…        # repo-root .env is NOT auto-loaded here
cd tests/kotlin-sdk/minimal-app
gradle run -PdittoLine=v5 -PdittoVersion=5.1.0 --console=plain -q
```

## Expected output

Actual run, 5.1.0 (macOS arm64, OpenJDK 17), trailing lines:

```
Loading native library at path: jar:file:…/ditto-binaries-5.1.0-macos-arm64.jar!/macos/arm64/libdittoall.dylib
…
observer: 0 car(s)
observer: 1 car(s)
read-back make: Toyota
SDK version: 5.1.0
```

The same run against 5.0.3 prints `SDK version: 5.0.3` with identical observer and
read-back lines. (`DittoLogger.isEnabled = false` does not suppress the INFO init
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
  insert throws `DittoError.StoreError: <dql> Unsupported feature: Encountered
  'INSERT' statement. … disable sync with V3 to use DQL` (executed).

```bash
cd tests/kotlin-sdk/android-app
gradle installDebug -PdittoLicense="$DITTO_OFFLINE_LICENSE"
adb -s emulator-5554 shell am start -n live.ditto.minimal/.MainActivity
adb -s emulator-5554 logcat -d -s DittoMinimal
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

## Verified on

| Line | Patch | Target | Host | Date |
|---|---|---|---|---|
| 5.1.x | 5.1.0 | JVM | macOS arm64, OpenJDK 17.0.20.1, Gradle 9.8.2 | 2026-10-21 |
| 5.0.x | 5.0.3 | JVM | macOS arm64, OpenJDK 17.0.20.1, Gradle 9.8.2 | 2026-10-21 |
| 4.14.x | 4.14.7 | Android emulator (API 35, arm64) | macOS, AGP 9.4.1 | 2026-10-21 |
