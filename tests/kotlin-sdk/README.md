# `tests/kotlin-sdk` — executable verification for `skills/kotlin-sdk`

Every claim in the Kotlin SDK skill marked **executed** was produced here. Two Gradle
projects cover the two version lines, because `live.ditto:ditto` (4.14.x) ships only an
Android AAR and `com.ditto:ditto-kotlin` (5.x) ships Android and JVM variants:

```
minimal-app/                       v5 on the JVM — 5.0.3 and 5.1.0
  gradlew, gradle/wrapper/         Gradle 9.8.2 wrapper (committed)
  build.gradle.kts                 version from -PdittoVersion (default 5.1.0);
                                   host-detected ditto-binaries classifier; .env loading
  src/main/kotlin/MainV5.kt        the normative program in examples/minimal-app.md
  src/test/kotlin/DittoStoreTest.kt  JUnit 5: execute round-trip, observer delivery
                                   (runBlocking and runTest forms), flowOn probe
android-app/                       both lines on a device or emulator
  gradlew, gradle/wrapper/         Gradle 9.8.2 wrapper (committed)
  build.gradle.kts                 -PdittoLine=v4|v5 selects dependency, source set and
                                   compileSdk (35 / 36); AGP 9.4.1 built-in Kotlin
  src/v4/kotlin/.../MainActivity.kt   4.14.7 flow, v4 API shape
  src/v5/kotlin/.../MainActivity.kt   5.x flow plus the on-device thread probes
```

## Prerequisites

- JDK 17. The committed wrapper downloads Gradle 9.8.2 (AGP 9.4.1 needs ≥ 9.6).
- `DITTO_OFFLINE_LICENSE` in the environment or in the gitignored repo-root `.env`
  (copy `.env-sample`). Environment variables take precedence over `.env`, matching
  `tests/lib/load-env.mjs`. Everything here runs offline-only. If the license is bound
  to a database ID, set `DITTO_DATABASE_ID` too; both projects pass it through.
- JVM leg: Apple silicon macOS, Linux x64/arm64 or Windows x64. Ditto publishes no
  `macos-x64` binaries, so an Intel Mac cannot run the JVM leg.
- Android leg: Android SDK (`ANDROID_HOME`) with platform 36 installed, `adb` on
  `PATH`, and a connected device or booted emulator.

## Running the JVM leg (v5)

```bash
cd tests/kotlin-sdk/minimal-app
./gradlew run  -PdittoVersion=5.1.0 --console=plain -q    # prints the transcript in examples/minimal-app.md
./gradlew test -PdittoVersion=5.1.0                       # 4 tests
./gradlew run  -PdittoVersion=5.0.3 --console=plain -q
./gradlew test -PdittoVersion=5.0.3
```

Expected `run` output (the observer fires once with the empty store, then with the write):

```
observer: 0 car(s)
observer: 1 car(s)
read-back make: Toyota
SDK version: 5.1.0
```

The program text below `// MARK: - begin documented program` in `MainV5.kt` must stay
byte-identical to the `## Program` block in `skills/kotlin-sdk/examples/minimal-app.md`;
`python3 scripts/validate-sdk-skills.py` fails when they drift.

| Test | Claim it backs |
|---|---|
| `insertThenReadBack` | `execute` round-trip and typed accessors (`references/store.md`) |
| `observerReportsTheWrite` | observer delivery under `runBlocking`; `@TempDir` isolation (`references/testing.md`) |
| `observerReportsTheWriteUnderRunTest` | the `runTest` + `withContext(Dispatchers.Default)` alternative (`references/testing.md`) |
| `flowOnDoesNotReachTheObserveTransform` | `.flowOn()` does not move the `observe()` transform (`references/concurrency.md`) |

## Running the Android leg (v4 and v5)

```bash
cd tests/kotlin-sdk/android-app
./gradlew installDebug -PdittoLine=v5 -PdittoVersion=5.1.0 -PdittoAbi=arm64-v8a
./gradlew installDebug -PdittoLine=v5 -PdittoVersion=5.0.3 -PdittoAbi=arm64-v8a
./gradlew installDebug -PdittoLine=v4 -PdittoVersion=4.14.7 -PdittoAbi=arm64-v8a
# after each install:
adb shell am start -n live.ditto.minimal/.MainActivity
adb logcat -d | grep DittoMinimal
```

`-PdittoAbi` is optional and keeps only that ABI: the SDK bundles four, which makes the
debug APK ~220 MB and can exhaust a small emulator image. Use `-PdittoLicense=…` to
override the license for one build. With several devices attached, install the APK from
`build/outputs/apk/debug/` with `adb -s <serial> install -r`.

Expected logcat, v5 (the two bracketed probes are what the JVM cannot answer for Android):

```
observer: 0 car(s) [thread=main main=true]
observe() transform under flowOn(IO) ran on thread=main
observer: 1 car(s) [thread=main main=true]
read-back make: Toyota
SDK version: 5.1.0
EXIT=0
```

Expected logcat, v4: `observer: 0 car(s)`, `observer: 1 car(s)`, `read-back make: Toyota`,
`SDK version: AndJ4.14.7_7506fa2fd0`, `EXIT=0`.

Recorded runs: Pixel 10a (Android 17) for 5.1.0, 5.0.3 and 4.14.7; emulator API 35 for
4.14.7. A `compileSdk` 35 build of the v5 leg fails `CheckAarMetadata` — the 5.x AARs
enforce 36 — which is why `compileSdk` follows the line.

## 5.2.0-rc.2

`com.ditto:ditto-kotlin:5.2.0` GA is not on Maven Central yet (only `5.2.0-rc.2`), so the
release candidate is the 5.2 target: both legs run against `-PdittoVersion=5.2.0-rc.2`
(JVM locally and in CI, Android on the Pixel 10a) and the skill marks it as such.
Switch the pin to `5.2.0` and re-run both legs when GA publishes.

## CI

`.github/workflows/kotlin-skill-tests.yml` runs the JVM leg on `ubuntu-latest` for
5.0.3, 5.1.0 and 5.2.0-rc.2 whenever `skills/kotlin-sdk/**`,
`tests/kotlin-sdk/**` or the workflow changes, using the `DITTO_OFFLINE_LICENSE`
repository secret. The Android leg needs a device and is run manually; its transcripts
are recorded in `skills/kotlin-sdk/examples/minimal-app.md`.
