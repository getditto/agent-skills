# flutter-sdk test harness

Verification for `skills/flutter-sdk`. The pins live in `versions.json` and `.fvmrc`;
every fixture, script and CI job reads them from there.

```json
{"flutter": "3.50.0", "flutter_lints": "6.0.0", "lines": {"4.14": "4.14.7", "5.0": "5.0.4", "5.1": "5.1.0", "5.2": "5.2.0"}}
```

## Contents

- [Pins and rationale](#pins-and-rationale)
- [Local toolchain](#local-toolchain)
- [Running fixtures](#running-fixtures)
- [Findings](#findings)
- [Findings that changed a research lead](#findings-that-changed-a-research-lead)
- [Manual records](#manual-records)

## Pins and rationale

Checked against pub.dev and the Flutter release manifest on 2026-11-17. The
dependency-age policy is that a pinned tool must be at least 72 hours old.

| Pin | Version | Released | Why |
|---|---|---|---|
| `ditto_live` 4.14 line | 4.14.7 | 2026-10-07 | Newest stable 4.14.x; not retracted |
| `ditto_live` 5.0 line | 5.0.4 | 2026-11-10 | Newest stable 5.0.x; not retracted |
| `ditto_live` 5.1 line | 5.1.0 | 2026-08-19 | Newest stable 5.1.x; not retracted |
| `ditto_live` 5.2 line | 5.2.0 | 2026-10-27 | Newest stable (pub.dev `latest`); not retracted |
| Flutter | 3.50.0 (Dart 3.14.0) | 2026-11-11 | Newest stable on the macOS release manifest that is at least 72 hours old |
| `flutter_lints` | 6.0.0 | 2025-05-27 | Newest stable on pub.dev; needs Dart `^3.8.0`, which Dart 3.14.0 satisfies |

Every `ditto_live` line publishes the constraint `flutter >=3.19.0`, but the Dart SDK
constraint each line also publishes sets a higher floor on 5.1 and 5.2. Flutter
versions are mapped to their bundled Dart version from the Flutter macOS release
manifest:

| Line | Published `environment` | Lowest Flutter that satisfies both |
|---|---|---|
| 4.14.7 | `flutter: ">=3.19.0"`, `sdk: ">=3.3.0 <4.0.0"` | 3.19.0 (Dart 3.3.0) |
| 5.0.4 | `flutter: ">=3.19.0"`, `sdk: '>=3.3.0 <4.0.0'` | 3.19.0 (Dart 3.3.0) |
| 5.1.0 | `flutter: ">=3.19.0"`, `sdk: '>=3.5.4 <4.0.0'` | 3.24.4 (Dart 3.5.4) |
| 5.2.0 | `flutter: ">=3.19.0"`, `sdk: '>=3.5.4 <4.0.0'` | 3.24.4 (Dart 3.5.4) |

These floors come from the published pubspecs; only Flutter 3.50.0 was executed.
Pre-release versions (`-rc`, `-dev`, `-experimental`, `-preview`) and ditto HEAD
(5.3.0) are not documented.

The fixture packages (`minimal_app`, `snippet_check`) declare `sdk: ^3.8.0`, the floor
of the pinned `flutter_lints` 6.0.0.

## Local toolchain

Flutter is installed through FVM (`brew install fvm`, 4.3.2) so the globally installed
Flutter is never touched. From this directory:

```bash
fvm install 3.50.0
fvm flutter --version     # Flutter 3.50.0, Dart 3.14.0
fvm flutter doctor -v
```

`fvm flutter doctor -v` on 2026-11-17 (macOS 27.2.1, arm64) reported no issues:

| Target | Availability |
|---|---|
| Flutter | 3.50.0 stable, Dart 3.14.0 |
| Android | Android SDK 36.1.0, build-tools 36.1.0, licenses accepted, a physical device attached |
| iOS and macOS | Xcode 27.2, CocoaPods 1.17.0, physical iOS devices attached, macOS desktop enabled |
| Web | Google Chrome 157 |
| Windows and Linux desktop | Feature flags enabled, but no host available locally; not executable here |

## Running fixtures

`scripts/run-fixture.sh <fixture> <device> <line> <target>...` copies the fixture with
`scripts/use-version.py` to `flutter-fixture-<user>/<line>/<fixture>/` under the system
temporary directory, pins `ditto_live` to that line from `versions.json`, and runs each
target. The license comes from `DITTO_OFFLINE_LICENSE` (environment, else the
repo-root `.env`). It reaches Flutter as `DITTO_LICENSE` through
`--dart-define-from-file`, a mode-600 temporary file deleted when the script exits, so
it is never a command-line argument. Each target's output goes to
`run-<fixture>-<device>-<line>-<target>.log` here (gitignored); its header lists the
non-secret defines (`DITTO_VERSION`, `DITTO_PLATFORM`, `PROBE_DEFAULT_LOGGING`). The
committed `minimal_app/pubspec.yaml` stays at the 5.2 pin; `use-version.py` refuses
`4.14` for `minimal_app`.

**Never cache or upload the fixture copies or any `build/` directory.** Compiled
builds embed every define, the license included. `use-version.py` creates the per-user
directory mode 0700 and refuses one that is a symlink, owned by another user, or
accessible to others.

Time bounds: every probe file sets a 2-minute per-test timeout (`integration_test`
otherwise has none), and `run-fixture.sh` wraps each `flutter` invocation in
`timeout` (`FIXTURE_TIMEOUT`, default 1800 s) when the command exists. `PYTHON`
(default `python3`) and `FLUTTER` (default `fvm flutter`) select the interpreters;
Python output is stripped of `\r` for Git Bash on Windows. Windows and Linux runs of
these scripts are untested.

```bash
tests/flutter-sdk/scripts/run-fixture.sh minimal_app macos 5.2 integration_test/minimal_app_test.dart
tests/flutter-sdk/scripts/run-fixture.sh minimal_app chrome 5.2 integration_test/minimal_app_test.dart
```

`chrome` runs `flutter drive -d chrome --headless`, which needs a chromedriver that
matches the local Chrome on port 4444. If nothing listens there, the script starts
`$CHROMEDRIVER` (default `chromedriver` on PATH). `edge` and `web-server` are refused.
A user-local install, no sudo:

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --version   # 157.0.8103.79
npx --yes @puppeteer/browsers install chromedriver@157.0.8103.79 --path "$SCRATCH"
export CHROMEDRIVER="$SCRATCH/chromedriver/mac_arm-157.0.8103.79/chromedriver-mac-arm64/chromedriver"
```

Web builds embed `--dart-define` values in the compiled JavaScript, so never publish
web build output.

The native behavior probes live in `minimal_app/integration_test/probes/`. Version-gated
code is split by directory, never by `skip:`: a line runs every directory at or below
its version (5.0: `v50`; 5.1: `v50 v51`; 5.2: `v50 v51 v52`). `init_once` runs first,
alone, in its own process, because nothing may call `Ditto.init()` before it.
`scripts/run-probes.sh` runs exactly that list through `run-fixture.sh`:

```bash
tests/flutter-sdk/scripts/run-probes.sh macos 5.0
tests/flutter-sdk/scripts/run-probes.sh macos 5.1
tests/flutter-sdk/scripts/run-probes.sh macos 5.2
```

Every probe uses `probes/harness.dart` `withDitto`: a fresh temporary directory, the
license, each peer-to-peer transport turned off one by one, `close()` in `finally`, and
the directory deleted (retried for a few seconds, and also when `Ditto.open` throws). The harness also turns
Ditto logging off unless `PROBE_DEFAULT_LOGGING=true` is set in the environment
(passed as `--dart-define=PROBE_DEFAULT_LOGGING=true`); see Finding 1 in
[Findings that changed a research lead](#findings-that-changed-a-research-lead).

## Findings

### minimal_app, 2026-11-17

Flutter 3.50.0 (Dart 3.14.0) through FVM, macOS 27.2.1 arm64, Xcode 27.2,
CocoaPods 1.17.0, Google Chrome 157.0.8103.79 with ChromeDriver 157.0.8103.79. All
runs are debug builds.

| Line | Target | Outcome |
|---|---|---|
| 5.0.4 | macOS (`flutter test -d macos`) | pass, with the earlier `onChange` version of the program |
| 5.1.0 | macOS (`flutter test -d macos`) | pass, with the earlier `onChange` version of the program |
| 5.2.0 | macOS (`flutter test -d macos`) | pass, current program |
| 5.2.0 | Chrome headless (`flutter drive`) | pass, current program |
| 5.0.4, 5.1.0 | Chrome | not run |
| all | iOS, Android, Windows, Linux | not run |

- **Desktop `integration_test` against pub.dev `ditto_live` works on macOS.** The
  feasibility spike (`run-fixture.sh minimal_app macos 5.2` with a throwaway
  `Ditto.open` test) passed on the first run with no entitlement or Podfile
  changes: `SPIKE version=iOSF5.2.0_f6bdf023fa platform=macos`, `All tests passed!`.
  `Ditto.version` is the core string, not the pub version, as the spec says.
- **Bundled web assets work under `flutter drive -d chrome --headless`.** The same
  spike passed on Chrome 5.2.0 without serving `lib/assets` separately, so
  `serve-web-assets.sh` and the `DITTO_WASM_BASE` define were not needed.
- **Flutter 3.50.0 raises the Apple deployment targets on every build.** With
  `platform :osx, '11.0'` and `MACOSX_DEPLOYMENT_TARGET = 11.0` in the fixture, the
  build printed `Updating minimum macOS deployment target to 12.0.`,
  `Upgrading project.pbxproj`, `Upgrading Podfile`. Its iOS migration does the same
  for 14.0 (to 15.0; `ios_deployment_target_migration.dart` in flutter_tools 3.50.0).
  The fixture therefore commits iOS 15.0 and macOS 12.0, which satisfy the
  `DittoFlutter` podspec minimums (iOS 14.0; macOS 11.0 from 5.1, 10.11 on 5.0.4).
- **`flutter create` on 3.50.0 writes no Podfile.** Projects default to Swift Package
  Manager; `ditto_live` has no SwiftPM support, so the build prints `The following
  plugins do not support Swift Package Manager for macos: - ditto_live` and falls
  back to CocoaPods. The committed Podfiles are Flutter's own CocoaPods templates
  with the platform line set.
- **`package:flutter/material.dart` is deprecated in 3.50.0** (`Use
  package:material_ui/material_ui.dart instead`), which fails
  `flutter analyze --fatal-infos`. `lib/main.dart` uses `package:flutter/widgets.dart`
  only, so the fixture needs no extra package.
- **`flutter pub get` rewrites `analysis_options.yaml`** to exclude `build/**` and the
  platform directories; the fixture keeps those excludes on top of the
  `snippet_check` options.
- **5.0.4 needs a current CocoaPods index.** The first 5.0 run failed in
  `pod install` with `None of your spec sources contain a spec satisfying the
  dependency: DittoFlutter (= 5.0.4)`; `pod repo update trunk` fixed it.

### Native behavior probes, 2026-11-17

Same toolchain as above. macOS desktop, debug builds, `scripts/run-probes.sh macos <line>`
with `PROBE_DEFAULT_LOGGING` unset. Every probe name below passed on every line listed;
nothing else was run. **Ditto logging disabled in the harness (see Finding 1)**: every
probe except `init_once` (which does not use the harness) ran with
`DittoLogger.isEnabled = false`, so these results do not describe an app with Ditto's
default logging.

| Line | Directories | Outcome |
|---|---|---|
| 5.0.4 | `init_once` (1 test), `v50` (26) | pass; Ditto logging disabled in the harness (see Finding 1) |
| 5.1.0 | `init_once` (1), `v50` (26), `v51` (7) | pass; Ditto logging disabled in the harness (see Finding 1) |
| 5.2.0 | `init_once` (1), `v50` (26), `v51` (7), `v52` (2) | pass; Ditto logging disabled in the harness (see Finding 1) |
| all | iOS, Android, Chrome, Windows, Linux | not run |

Recorded outcomes. Each is asserted exactly, so a change breaks the probe; where a
line differs, the probe asserts each line's value. Except for
`DittoLogger getter before init`, each was observed with Ditto logging disabled in the
harness (see Finding 1):

- `DittoLogger getter before init`: `DittoLogger.isEnabled` throws synchronously
  ``DittoError(Ditto not initialized. Call `Ditto.init()` and await the `Future` before using any Ditto functionality)``,
  on all three lines.
- `api after close throws DittoClosedException`: `store.execute` does not throw at the
  call; its Future fails with `DittoClosedException`. `sync.start()` and
  `store.registerObserver` throw `DittoClosedException` synchronously.
- `login failure in AuthResponse.exception`: deterministic offline. With
  `DittoConfigConnectServer(url: 'https://REPLACE_ME.invalid')`, `auth.login` returns
  `exception` whose `toString()` is
  `DittoException(Error logging in. Status code 1. Client info: null)`, compared per
  line; the same string on all three lines.
- `signalNext gates delivery and coalesces` (5.1.0, 5.2.0): callbacks deliver item
  counts `[0]`, nothing more for 2 s after three inserts while the first render is
  unfinished, then exactly `[0, 3]` once that render ends (by throwing; the feed logs
  it and still calls `signalNext()`): the three writes arrive in one callback.
- `observeTransportConditions emits within 5 s` (5.1.0, 5.2.0): with every
  peer-to-peer transport off and `sync.start()`, no event arrives within 5 s, on the
  callback or the stream.
- `doc written on A syncs to B`: the connecting peer's observer reports exactly the
  `_id` written on the listening peer (`car-from-listener`).
- `handler deny blocks` / `handler throw denies`: the connecting peer's handler is
  invoked first with the listening peer's `peerKey` (asserted) within 20 s when one
  peer listens on TCP loopback and the other connects; denying or throwing keeps the
  listener's document off the connecting peer for the 5 s window.
- `ConnectionType switch compiles`: four values on 5.0.4, five on 5.1.0 and 5.2.0. The
  `v50` switch carries a wildcard arm (`// ignore: unreachable_switch_case`), since an
  exhaustive four-value switch does not compile on 5.1+.
- `v1 observer isCancelled after close, per line`: after `close()`, a V1 observer's
  `isCancelled` stays `false` on 5.0.4 and is `true` on 5.1.0 and 5.2.0.
- `close and customLogCallback, per line`: `close()` leaves
  `DittoLogger.customLogCallback` set on 5.0.4 and resets it to `null` on 5.1.0 and
  5.2.0.
- `observer without onChange: eager on 5.0, on first listen 5.1+`: an observer
  registered without `onChange`, with one insert before the first `changes.listen`,
  delivers item counts `[0, 1]` on 5.0.4 (the live query started at registration and
  the stream buffered both results) and `[1]` on 5.1.0 and 5.2.0 (it started on the
  listen).

### SDK defects the fixture records, 2026-11-17

- **V1 and V2 observers registered with `onChange` buffer every result in their
  unlistened `changes` stream** (V1: 5.0.4, 5.1.0, 5.2.0; V2 `registerObserverV2` and
  `registerObserverWithSignalNext`: 5.1.0, 5.2.0; macOS debug, logging disabled in the
  harness). `StoreObserver` and `StoreObserverV2` add each `QueryResult` to a
  single-subscription controller as well as passing it to `onChange`, and nothing
  listens, so the stream keeps them all; a V2 auto-mode stream with no listener is not
  paused, so delivery never slows. Probes `SDK defect: v1 onChange observer buffers
  every result for a late listener` (v50) and `SDK defect: registerObserverV2 …` /
  `SDK defect: registerObserverWithSignalNext …` (v51, the signal-next `onChange`
  signals each time): 6 callbacks (the initial result and five inserts), then a late
  `changes.listen` receives exactly 6 replayed results. The published observer,
  Repository, signal-next and minimal app patterns therefore register without
  `onChange`, hold the one `changes` subscription (the signal-next feed calls
  `observer.signalNext()` after each render, also when it throws), and cancel it while
  Ditto is open.
- **5.0.x `setAllPeerToPeerEnabled(false)` / `withAllPeerToPeerEnabled(false)` leave
  AWDL and Wi-Fi Aware on** (source: `lib/src/transport_config.dart` in 5.0.4 assigns
  `true` to both instead of the argument; 5.1.0 assigns the argument). Not executed
  here. The harness and the minimal app turn each transport off one by one instead.

### Native builds, 2026-11-17

Flutter 3.50.0 (AGP 9.3.1, Gradle 9.5.0 from its template), Xcode 27.2, CocoaPods
1.17.0, macOS 27.2.1 arm64. `flutter build` on `use-version.py` copies of
`minimal_app`; builds only, nothing was installed or run on a device or simulator.

| Line | Command | Outcome |
|---|---|---|
| 5.2.0 | `flutter build apk --debug` / `--release` | pass / pass (196.0 MB) |
| 5.1.0 | `flutter build apk --debug` / `--release` | pass / pass (178.9 MB) |
| 5.0.4 | `flutter build apk --debug` | pass |
| 5.2.0 | `flutter build ios --simulator --debug` | pass; `Runner.debug.dylib` is `arm64` |
| 5.0.4 | `flutter build ios --simulator --debug` | pass; `Runner.debug.dylib` is `arm64` |
| 5.2.0 | both, without the two workarounds below (negative control) | apk: fail at `:ditto_live:checkDebugAarMetadata`; iOS: fail, `Framework 'DittoCore' not found` |

- **Android, ditto_live 5.1.0 and 5.2.0: the plugin compiles with `compileSdk = 34`,
  but its `com.ditto` Android libraries require compileSdk 36**, and AGP 9 runs
  `checkAarMetadata` on the `:ditto_live` library module, so every APK build fails.
  Raising the app's compileSdk does not help. The fixture's root
  `android/build.gradle.kts` raises the plugin's compileSdk to 36 in a
  `subprojects { afterEvaluate { … } }` block placed before
  `evaluationDependsOn(":app")` (region `flutter-android-compilesdk-override`). 5.0.4
  is unaffected; the override is harmless there.
- **iOS Simulator, ditto_live 5.1.0+: `DittoCore` ships an arm64-only simulator
  slice**, and the 5.1+ podspec excludes x86_64 for the simulator, but Flutter's
  `Generated.xcconfig` resets `EXCLUDED_ARCHS[sdk=iphonesimulator*]` to `i386` on the
  Runner, so the Runner still links x86_64 and fails. Excluding x86_64 on the pod
  targets alone does not help. The fixture's `ios/Podfile` `post_install` sets
  `EXCLUDED_ARCHS[sdk=iphonesimulator*] = 'i386 x86_64'` on the Runner (user
  project) targets (region `flutter-podfile-ios-simulator-arch`).
- **Android INTERNET:** the `ditto_live` plugin's own manifest declares
  `android.permission.INTERNET` (5.0.4 and 5.2.0), so the merged manifest of every
  build type has it; the fixture's main-manifest declaration is explicit, not required.

## Findings that changed a research lead

- **Finding 1: re-opening Ditto in one process can abort or hang it when the GC
  finalizes a native handle from the earlier instance.** A new hazard that awaiting
  `close()` does not prevent; it does not refute the Known-hazards lead about awaiting
  `close()`. Observed on macOS, debug builds only, when one process closes Ditto and
  then opens it again (`v50/store_test.dart` opens a fresh instance per test). The
  crash report and `sample` frames show the native log callback being invoked from
  inside a GC finalizer: a GC (`ScavengerVisitor` or `MarkingVisitor`) →
  `MournFinalizerEntry` →
  `dittoffi_transaction_free` (an internal `Transaction`) or the drop of an
  `FfiSyncSubscription` → native core teardown → `sqlite3_log` (from `verifyDbFile`)
  or the `TaskRuntime` drop → `ditto_logger_set_custom_log_cb::call_callback` →
  `DLRT_GetFfiCallbackMetadata`.
  - 5.0.4: `EXC_CRASH (SIGABRT)` at `dart::Assert::Fail` under
    `DLRT_GetFfiCallbackMetadata`, in 3 of 3 runs. In 5.0.4 the log `NativeCallable.listener` is
    created once and never freed (`lib/src/logger.dart`, `_setLogCallbackWithCore`
    discards the freeable), so this is not the closed-`NativeCallable` hazard; the
    callback is live and is entered from inside the GC.
  - 5.1.0 and 5.2.0: a deadlock instead (5.1.0 in 3 of 3 runs, 5.2.0 in 2 of 3). The main thread waits in `Thread::join`
    under `dittoffi_transaction_free` (inside the GC); a tokio worker waits in
    `IsolateGroup::EnterTemporaryIsolate` under the same log callback. In these
    versions `close()` unregisters the log callback and frees it after a 500 ms drain
    (`cleanupLogger`), and the next `Ditto.open` registers it again
    (`privateSetupLogCallback` in `_constructorPreamble`), which fits a hang that
    appears only once the process re-opens Ditto.
  - Reproduction counts and commands: [Manual records](#manual-records).
  - Workaround in the harness only, not a recommendation: `withDitto` sets
    `DittoLogger.isEnabled = false` unless `--dart-define=PROBE_DEFAULT_LOGGING=true`
    (`PROBE_DEFAULT_LOGGING=true` in the environment of `run-fixture.sh` or
    `run-probes.sh`). `logging_test.dart` turns logging back on inside its single test.
- **The expiration handler can run after `close()`, and `login()` then throws**
  (5.0.4, `v50/auth_test.dart`, first run). The handler set with
  `setExpirationHandler` was delivered after the test closed Ditto; `ditto.auth.login`
  inside it threw `DittoClosedException` (from `PrivateDittoPtrExtension.ptr`) as an
  uncaught async error that failed the test. Overturns the CAP-04 lead "`login` never
  throws": it reports login failures in `AuthResponse.exception`, but a closed
  instance throws. The published handler now returns early when `ditto.isClosed`.
  Seen on 5.0.4 only; 5.1.0 and 5.2.0 ran only the guarded version.

## Manual records

### Finding 1 reproduction, 2026-11-17

macOS 27.2.1 arm64, Flutter 3.50.0, debug. `v50/store_test.dart` with Ditto logging at
its default (`PROBE_DEFAULT_LOGGING=true`), three attempts per line, each bounded by
`timeout 240`. A hung app is killed afterwards. Recorded before the probes' published
code moved into named functions; the five test names are unchanged, the collections,
documents and the rollback test's statements have changed since. From the repository root:

```bash
for line in 5.0 5.1 5.2; do
  for attempt in 1 2 3; do
    PROBE_DEFAULT_LOGGING=true timeout 240 tests/flutter-sdk/scripts/run-fixture.sh \
      minimal_app macos "$line" integration_test/probes/v50/store_test.dart
    echo "$line attempt $attempt: exit $?"
    pkill -f "flutter-fixture-[^/]*/$line/minimal_app/build/macos" || true
  done
done
```

| Line | Attempts | Outcome |
|---|---|---|
| 5.0.4 | 3 | 3 crashed (exit 1). The app aborted during test 2, `rollback action rolls back`; each run left a SIGABRT crash report |
| 5.1.0 | 3 | 3 hung, killed by `timeout 240` (exit 124). Last progress: twice in test 2, once in test 5, `CREATE INDEX and EVICT via execute succeed` |
| 5.2.0 | 3 | 2 hung, killed by `timeout 240` (exit 124), stopped in test 2 and test 4. 1 passed all 5 tests (exit 0) |

One more bounded attempt per line on 5.1.0 and 5.2.0 was sampled with `sample <pid> 2`
90 s in. Both hung in test 2 and were killed at 240 s.

Trimmed faulting frames, 5.0.4 (all three `.ips` reports are identical in these frames):

```text
libsystem_c.dylib  abort
FlutterMacOS       dart::Assert::Fail
FlutterMacOS       DLRT_GetFfiCallbackMetadata
DittoCore          dittoffi::logger::ditto_logger_set_custom_log_cb::call_callback
DittoCore          sqlite3_log
DittoCore          verifyDbFile
DittoCore          dittoffi_transaction_free
FlutterMacOS       dart::MournFinalizerEntry<dart::MarkingVisitor>
FlutterMacOS       dart::MarkingVisitor::FinalizeMarking
```

Trimmed `sample` frames, 5.2.0 (5.1.0 shows the same frames):

```text
main thread   dart::MournFinalizerEntry<dart::MarkingVisitor>
              dittoffi_transaction_free
              <dittoffi::runtime::TaskRuntime as Drop>::drop
              std::sys::thread::unix::Thread::join  -> __ulock_wait
tokio worker  verifyDbFile -> sqlite3_log
              dittoffi::logger::ditto_logger_set_custom_log_cb::call_callback
              DLRT_GetFfiCallbackMetadata
              dart::IsolateGroup::EnterTemporaryIsolate
              dart::Thread::AddActiveThread -> ConditionVariable::WaitMicros
```

Earlier the same day, a `v50/presence_two_peer_test.dart` crash on 5.0.4 showed the
finalizer path through the drop of an `FfiSyncSubscription`, and the log line from the
`TaskRuntime` drop. That run used logging at its default and ran before the harness
workaround existed.
