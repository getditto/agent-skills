# `tests/kotlin-sdk` — executable verification for `skills/kotlin-sdk`

Every claim in the Kotlin SDK skill marked **executed** was produced here. Two Gradle
projects cover the two version lines, because `live.ditto:ditto` (4.14.x) ships only an
Android AAR and `com.ditto:ditto-kotlin` (5.x) ships Android and JVM variants:

```
minimal-app/                       v5 on the JVM — 5.0.3 and 5.1.0
  build.gradle.kts                 version from -PdittoVersion (default 5.1.0);
                                   host-detected ditto-binaries classifier; .env loading
  src/main/kotlin/MainV5.kt        the normative program in examples/minimal-app.md
  src/test/kotlin/DittoStoreTest.kt  JUnit 5: execute round-trip, observer delivery
                                   (runBlocking and runTest forms), flowOn probe
android-app/                       v4 on an Android emulator — 4.14.7
  build.gradle.kts                 AGP 9.x, minSdk 24, license via -PdittoLicense
  src/main/kotlin/live/ditto/minimal/MainActivity.kt   same flow, v4 API shape
```

## Prerequisites

- JDK 17 and Gradle 9.x (the skill's transcripts used Gradle 9.8.2, Kotlin plugin
  2.3.21). There is no committed wrapper; use an installed Gradle or
  `gradle wrapper --gradle-version 9.8.2` locally (the generated files are ignored).
- `DITTO_OFFLINE_LICENSE` in the environment or in the gitignored repo-root `.env`
  (copy `.env-sample`). Environment variables take precedence over `.env`, matching
  `tests/lib/load-env.mjs`. Everything here runs offline-only.
- JVM leg: Apple silicon macOS, Linux x64/arm64 or Windows x64. Ditto publishes no
  `macos-x64` binaries, so an Intel Mac cannot run the JVM leg.
- Android leg: Android SDK with an API 35 emulator image and `adb` on `PATH`.

## Running the JVM leg (v5)

```bash
cd tests/kotlin-sdk/minimal-app
gradle run  -PdittoVersion=5.1.0 --console=plain -q    # prints the transcript in examples/minimal-app.md
gradle test -PdittoVersion=5.1.0                       # 4 tests
gradle run  -PdittoVersion=5.0.3 --console=plain -q
gradle test -PdittoVersion=5.0.3
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

What the tests establish:

| Test | Claim it backs |
|---|---|
| `insertThenReadBack` | `execute` round-trip and typed accessors (`references/store.md`) |
| `observerReportsTheWrite` | observer delivery under `runBlocking`; `@TempDir` isolation (`references/testing.md`) |
| `observerReportsTheWriteUnderRunTest` | the `runTest` + `withContext(Dispatchers.Default)` alternative (`references/testing.md`) |
| `flowOnDoesNotReachTheObserveTransform` | `.flowOn()` does not move the `observe()` transform (`references/concurrency.md`) |

## Running the Android leg (v4)

```bash
emulator -avd <API-35 image> &            # or start one from Android Studio
cd tests/kotlin-sdk/android-app
gradle installDebug -PdittoLicense="$DITTO_OFFLINE_LICENSE"
adb shell am start -n live.ditto.minimal/.MainActivity
adb logcat -d -s DittoMinimal:I
```

Expected logcat lines: `observer: 0 car(s)`, `observer: 1 car(s)`,
`read-back make: Toyota`, `SDK version: 4.14.7`, `EXIT=0`. The license is injected as a
`BuildConfig` field from the Gradle property and never written into the repository.

**v5 on Android is not executed by this harness.** The Android project pins 4.14.7;
the 5.x legs run on the JVM. The skill's Android-specific v5 claims (handlers start on
`MainScope()`, AGP 9 built-in Kotlin, the permissions helper) are therefore marked
source- or docs-sourced in `skills/kotlin-sdk/README.md`, not executed.

## CI

`.github/workflows/kotlin-skill-tests.yml` runs the JVM leg on `ubuntu-latest` for
5.0.3 and 5.1.0 whenever `skills/kotlin-sdk/**`, `tests/kotlin-sdk/**` or the workflow
changes, using the `DITTO_OFFLINE_LICENSE` repository secret. The Android leg needs an
emulator and is run manually; its transcript is recorded in
`skills/kotlin-sdk/examples/minimal-app.md`.
