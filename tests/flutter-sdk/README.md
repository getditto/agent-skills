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
Python output is stripped of `\r` for Git Bash on Windows, and the defines file is
passed as a `cygpath -m` path there. CI runs these scripts on macOS, Linux (under
`xvfb-run`) and Windows (Git Bash).

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
web build output. `run-fixture.sh` checks that ChromeDriver answers `/status` on
:4444 before driving, and stops with `ChromeDriver did not come up on 127.0.0.1:4444`
otherwise.

The Flutter Web probes live in `minimal_app/integration_test/web/`. A web
`flutter drive` target's directory is its app root (`org-dartlang-app:///`), so a
target cannot import files above `integration_test/web/`; the web probes therefore
have their own harness, `web/web_harness.dart`, with no `dart:io`, no temporary
directory (`persistenceDirectory: null`) and Ditto logging at its default.
The drive targets are `web_all_test.dart` (5.0+), `web_51_test.dart` (5.1+) and
`web_license_test.dart` (5.0+; one probe that needs a fresh page). The chrome leg's
EXIT trap deletes the debug web build output (`.dart_tool/flutter_build`, `build/web`)
from the fixture copy, since it embeds the license:

```bash
tests/flutter-sdk/scripts/run-fixture.sh minimal_app chrome 5.2 integration_test/web/web_all_test.dart \
  integration_test/web/web_51_test.dart integration_test/web/web_license_test.dart
```

`scripts/web-probe.py --line <line>` builds `integration_test/web/probe_app.dart` in
release mode (dart2js, `--wasm`, `--base-href /app/`), serves each bundle with the
headers a probe needs, loads it in headless Chrome through ChromeDriver (an existing
one on :4444, else `$CHROMEDRIVER` on a free port), and asserts the transcript the app
publishes. The license reaches Flutter only through a mode-600
`--dart-define-from-file` file; every bundle, and the intermediate output under
`.dart_tool/flutter_build` and `build/web`, is deleted before the script exits.
`--skip-manual` skips the timing probe `web_large_result_jank`.
`scripts/test_web_probe.py` checks its secret handling, server and timing helpers.
Results per probe ID, with versions and build modes, are in `web-results/5.2.0.md`.

`v4_app/` is the 4.14 fixture (`use-version.py` runs it on the 4.14 line only): the
`flutter-v4-open` region (`OfflinePlaygroundIdentity`, `SiteID.fromInt`,
`setOfflineOnlyLicenseToken`, `startSync()`) and `integration_test/v4_test.dart`, which
writes one car and expects `v4 read-back make: Toyota`. Its platform configuration is
`minimal_app`'s (Podfiles, Info.plist keys, entitlements, Android manifest, minSdk,
the compileSdk override and the simulator `EXCLUDED_ARCHS` fix), with its own bundle
ID and without the snippet markers:

```bash
tests/flutter-sdk/scripts/run-fixture.sh v4_app macos 4.14 integration_test/v4_test.dart
```

`scripts/run-migration.sh <device>` runs
`minimal_app/integration_test/migration/migrate_default_dir_test.dart` three times, one
process each: `MIGRATION_PHASE=wipe` (5.1) deletes `{Documents}/ditto-<id>` and
`{Application Support}/ditto-<id>`; `write` (5.1) runs the published minimal app, which
opens the SDK default directory; `read` (5.2) opens the default directory the same way
(`DittoConfig(persistenceDirectory: null)`) and expects the car. `run-fixture.sh`
passes `MIGRATION_PHASE` as a define, adds it to the log name, and adds
`--no-uninstall`, because `flutter test` otherwise uninstalls the app from a phone or
simulator after each run, deleting its data. Nothing else may open the default
directory on that device in between:

```bash
tests/flutter-sdk/scripts/run-migration.sh macos
DITTO_PLATFORM=ios tests/flutter-sdk/scripts/run-migration.sh <simulator-udid>
```

`scripts/run-macos-release.sh <line>` builds `minimal_app` for macOS with
`flutter build macos --release` (so `Release.entitlements` applies), runs the built
app's executable without the shell's `DITTO_*` variables, and checks the transcript
`lib/main.dart` prints on stdout (`flutter: transcript: ...`). The release build embeds
the license; the script deletes the build output on exit.

`build-from-skill.py <out-dir>` builds a project from `flutter create` plus only what
`skills/flutter-sdk` publishes: the program and dependencies from
`examples/minimal-app.md`, and the Podfile, Info.plist, entitlements, Gradle and
manifest snippets from `references/setup.md`. CI's `from-skill` job analyzes it and
builds an APK and an iOS Simulator app.

`scripts/hot-restart.py --device macos|chrome --mode v1|v2|holder [--peer]` runs
`integration_test/hot_restart/hot_restart_app.dart` with `flutter run` (debug), sends
`R` once the app is ready, watches, sends `q` and kills what is left. The records it
produced are in [Manual records](#manual-records).

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
- `server connect without expiration handler: sync.start throws DittoException`
  (rerun alone, `v50/auth_test.dart`, 5.0.4, 5.1.0, 5.2.0, after the exact string was
  added): `DittoException(<authentication> The operation failed because an
  authentication expiration handler has not yet been set.)`, the same on all three lines.
- Widget integration (`v50/widgets_test.dart`, rerun alone on 5.0.4, 5.1.0 and 5.2.0
  after these were added; regions `flutter-widgets-1` to `-3`, `flutter-transports-1`):
  `DittoService closes the instance when configure throws` (the failed open rethrows and
  the same directory opens again; all four peer-to-peer flags read back `false` after
  `disablePeerToPeer`); `CarsApp: lifecycle stops and restarts sync, exit closes`
  (lifecycle states driven through the test binding: `paused` stops sync, back to
  `resumed` restarts it; `handleRequestAppExit()` returns `AppExitResponse.exit` with
  Ditto closed; on-device lifecycle delivery not exercised); `CarCountScreen:
  re-entering works, dispose cancels`.
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
- **Under `flutter build web --wasm` (dart2wasm), every query result after the first
  is the first one again** (5.1.0, 5.2.0; release; Chrome 157 headless;
  `web-probe.py` `web_wasm_build`). Ditto initializes and opens, but a second
  `INSERT` reports the first `INSERT`'s mutated IDs (`[blue-toyota]` for a document
  with `_id` `red-honda`) and `SELECT * FROM cars` returns 0 items, with or without
  COOP/COEP. The web bridge keys its pointer registry on
  `Object.hashAll([JSString type, JSNumber addr])`
  (`sdks/flutter/ditto_live/lib/src/bridge/wasm/types.dart:168` @ `sdk-release-5.2.0`,
  `_JSPointer._hashCode`), and in the same dart2wasm bundle every JS value hashes to 0,
  strings and numbers alike (`'a'.toJS`, `'b'.toJS`, `1.toJS` and `2.toJS` all report
  `hashCode` 0): every pointer of one type gets the same key, so the registry hands back
  the first wrapper. dart2js is unaffected (`web_default_build`).
- **After a hot restart, an orphaned observer crashes the app when a remote change
  reaches it** (macOS debug, `flutter run`, one launch per run; standalone repro in
  [Manual records](#manual-records), "Hot restart, repeated runs"). V2
  (`registerObserverV2`): 5.1.0 4/4, 5.2.0 4/4. V1 (`registerObserver`): 5.1.0 3/3,
  5.0.4 0/3, 5.2.0 0/3. Each crash is `EXC_BAD_ACCESS`, `SIGBUS KERN_PROTECTION_FAILURE`
  or `SIGSEGV KERN_INVALID_ADDRESS`, on a `live query callback 1`–`3` thread whose top
  frame is a non-code address, 0.1–0.2 s after the second instance's insert. On 5.2.0
  V2, connecting without inserting crashed 0/3, so the trigger is the remote change, not
  the connection. 5.1.0 V1 and every V2 path deliver through a `NativeCallable.listener`
  (`sdks/flutter/ditto_live/lib/src/bridge/native/store.dart` @ `sdk-release-5.1.0`
  and `@ sdk-release-5.2.0`); 5.0.4 and 5.2.0 V1 post to a `Dart_PostCObject` port.
  That the faulting address is the freed trampoline is an inference. The fixture's own
  `hot-restart.py --mode v2 --peer` run crashed once (n=1) the same way.

- **ditto_live 4.14.7, Android: the first `flutter build apk` after `pub get` fails**
  (Flutter 3.50.0, AGP 9.3.1, `v4_app`, release). The plugin downloads `ditto.jar` and
  `libdittoffi.so` from `software.ditto.live` into its pub-cache directory while Gradle
  configures, after the Jetifier transform has been set up on the missing file:
  `Execution failed for JetifyTransform: .../ditto_live-4.14.7/android/libs/ditto.jar.
  > Transform's input file does not exist`. The second build (files present) passes.
  Reproduced locally twice (macOS, a warm Gradle daemon) by deleting the downloaded
  files. On a fresh CI runner (ubuntu-24.04, `android-release` 4.14) the first build
  downloaded the same files and passed, so the failure is not unconditional. The CI leg
  retries once, on 4.14 only and only when the build output has that `Transform's
  input file does not exist: ...ditto_live-4.14.7/android/libs/ditto.jar` error, and
  emits a `::warning::` when it does.

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
| 5.1.0, 5.2.0, 5.0.4 | fresh `flutter create --platforms=android` app plus `flutter pub add ditto_live:<version>`, nothing else, `flutter build apk --debug` / `--release` (separate negative control) | 5.1.0: fail at `:ditto_live:check{Debug,Release}AarMetadata` 3/3 (2 debug, 1 release); 5.2.0: same 4/4 (2 debug, 1 release, 1 debug on AGP 9.1.1); 5.0.4: builds 3/3 |

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

### Flutter Web probes, 2026-11-17

Flutter 3.50.0, Google Chrome 157.0.8103.79 headless with ChromeDriver 157.0.8103.79,
macOS 27.2.1 arm64. Every probe ID's outcome, with build mode and version, is in
`web-results/5.2.0.md`; this is the summary.

| Line | Target | Build mode | Outcome |
|---|---|---|---|
| 5.2.0 | `web_all_test.dart` (12), `web_51_test.dart` (2), `web_license_test.dart` (1) | debug (DDC), `flutter drive` | pass |
| 5.1.0 | `web_all_test.dart` (12), `web_51_test.dart` (2), `web_license_test.dart` (1) | debug (DDC), `flutter drive` | pass |
| 5.0.4 | `web_all_test.dart` (12), `web_license_test.dart` (1) | debug (DDC), `flutter drive` | pass |
| 5.2.0, 5.1.0 | `web-probe.py` (7 probes) | release: dart2js, dart2wasm | pass; the dart2wasm probes assert the defect in [SDK defects](#sdk-defects-the-fixture-records-2026-11-17) |
| all | Firefox, Safari, Edge; a hosted CDN | — | not run |

- **The published `enablePeerToPeer` gate** (region `flutter-web-1`, in
  `integration_test/web/p2p_gate.dart`) also runs natively: `v50/p2p_gate_test.dart`
  asserts `bluetoothLE=true lan=true awdl=true wifiAware=false` on macOS (5.0.4, 5.1.0,
  5.2.0, debug, sync not started). Its Android, Linux and Windows branches are untested.
- **Gate P2P with `kIsWeb` first.** `defaultTargetPlatform` is the host OS on web
  (`macOS` here), so a capability gate on it enables LAN in the browser. Enabling any
  peer-to-peer transport on web throws `DittoException(<validation> Expected valid
  TransportConfig. Invalid config: The following P2P transports are enabled in the
  transport config but are not supported in the current environment: <LAN|BluetoothLE>)`:
  from `sync.start()` on 5.2.0, from `updateTransportConfig` itself on 5.0.4 and 5.1.0.
  The published `enablePeerToPeer` (region `flutter-web-1`) returns early on `kIsWeb`.
- **A web app below the site root needs `wasmShimUrl`.** The shim's default URL is the
  absolute `/assets/packages/ditto_live/lib/assets/ditto.wasm.js`; under
  `--base-href /app/` it 404s and `Ditto.init()` throws `Failed to initialize Ditto
  WebAssembly`. `Ditto.init(wasmShimUrl: './assets/packages/ditto_live/lib/assets/ditto.wasm.js')`
  (region `flutter-web-2`) works; without the `./` it fails with
  `Failed to resolve module specifier`.
- **Hosting:** Ditto needs no COOP/COEP headers. A CSP must allow
  `'wasm-unsafe-eval'`: without it Flutter's bootstrap fails to compile its own
  WebAssembly renderer (`CompileError`, CSP violation `script-src` / `wasm-eval` from
  `flutter_bootstrap.js`) and `main()` never runs. Ditto is never reached, so its own
  requirement is masked rather than observed.
- **Large results (dart2js, 5.2.0):** for 5,000 documents, `execute` took 20 ms;
  reading every `item.value` as well took 79 ms in one long task, the longest frame gap
  67 ms (an earlier run: 66 ms, 50 ms). With `LIMIT 50` it took 2 ms and no long task.

### v4 fixture and default-directory migration, 2026-11-17

Flutter 3.50.0, macOS 27.2.1 arm64, Xcode 27.2, an iPhone 18 Pro simulator (iOS 27.1),
debug builds.

| Line | Target | Outcome |
|---|---|---|
| 4.14.7 | `v4_app` `v4_test.dart`, macOS | pass: `v4 read-back make: Toyota`, `v4 SDK version: 4.14.7`, `v4 closed: true` |
| 4.14.7 | `v4_app` `flutter build ios --simulator --no-codesign` | pass |
| 4.14.7 | `v4_app` `flutter build apk --release` | locally: fail on the first build after `pub get`, pass on the second (SDK defect below) |
| 5.1.0 then 5.2.0 | `migrate_default_dir`, macOS | pass |
| 5.1.0 then 5.2.0 | `migrate_default_dir`, iOS Simulator | pass with `--no-uninstall`; fail without it |
| 5.2.0 | `run-macos-release.sh` (release build, `.app` run directly) | pass |

- **5.2.0 reads a 5.1.0 default directory in place** (the read phase asserts it:
  `absolutePersistenceDirectory` is `{Documents}/ditto-<id>` and no
  `{Application Support}/ditto-<id>` exists). The 5.1.0 write put the store in
  `{Documents}/ditto-00000000-0000-0000-0000-000000000000` (Application Support had
  none). The 5.2.0 read, with no `persistenceDirectory`, reported
  `absolutePersistenceDirectory` = that same Documents path and returned the car;
  nothing was moved to Application Support. Same on macOS (sandbox container) and the
  iOS Simulator. With logging on, 5.2.0 logs `Conflicting pre-existing default
  persistence directories found. Since the v5 default contains no ditto data,
  defaulting to legacy v4.` and names both paths.
- **`flutter test` uninstalls the app from a simulator after each run**, deleting its
  data container, so the first iOS Simulator migration run read `[]` (and found neither
  directory) on 5.2.0. `flutter test --no-uninstall` keeps it; with it, the container's
  data survives the 5.1.0 → 5.2.0 reinstall (the container path changes, its contents
  move with it).
- **The 5.1.0 write phase is the first run of the published program with the SDK
  default directory** (every other fixture run passes a temporary one): pass on macOS
  and the iOS Simulator.
- **Ditto reads `DITTO_*` variables from the process environment.** Running the
  release `.app` from a shell that exported `DITTO_OFFLINE_LICENSE` logged `The Ditto
  environment variable offline_license is set, but it is not a known system parameter,
  so it is being ignored`. So no harness script lets a `DITTO_*` variable reach
  flutter or the app it launches: `run-fixture.sh` (`env -u` for every `DITTO_*`,
  including `.env` keys such as `DITTO_TOKEN`, after writing the defines file),
  `run-macos-release.sh`, `use-version.py`, `web-probe.py` and `hot-restart.py`. The
  license is a define only.

### Windows desktop, 2026-11-17

CI `windows` job, windows-latest, Flutter 3.50.0, ditto_live 5.2.0, debug,
`run-fixture.sh` through Git Bash with `flutter test -d windows`. The first run
(before the cleanup change below): `init_once`, `v51` and `v52` passed;
`minimal_app_test.dart` printed the full transcript (`platform: windows`, `closed:
true`) yet failed, and `v50` passed 22 of 27; all 6 failures (1 + 5) were the tests' own cleanup:

- **After `await ditto.close()`, the persistence directory stays locked on Windows.**
  Deleting it failed for 5 s of retries with `PathAccessException: Deletion failed ...
  (OS Error: The process cannot access the file because it is being used by another
  process, errno = 32)`, in `minimal_app_test.dart` and in `store_test.dart`
  (`transaction throw rolls back`, `rollback action rolls back`, `store.execute inside
  transaction throws`) and `presence_two_peer_test.dart` (`handler deny blocks`,
  `handler throw denies`); every other probe's directory deleted. Which file stays
  open was not determined. That the transaction probes are among them fits Finding 1's
  observation that an internal `Transaction` is freed by a GC finalizer, but this is an
  inference. The harness and `temp_dir_io.dart` therefore leave such a directory behind
  on Windows only, printing `cleanup: still locked after close: ...`, which the CI job
  repeats as warnings; on every other platform a failed delete still fails the test.

### CI runners, 2026-11-17

`flutter-skill-tests.yml` on GitHub-hosted runners, Flutter 3.50.0 (subosito/flutter-action),
debug builds unless stated:

| Job | Runner | ditto_live | Outcome |
|---|---|---|---|
| `linux` (`xvfb-run`, `flutter test -d linux`) | ubuntu-24.04 | 5.2.0 | pass: `init_once`, minimal app, `v50`, `v51`, `v52` |
| `windows` (Git Bash, `flutter test -d windows`) | windows-latest | 5.2.0 | pass after the cleanup change in [Windows desktop](#windows-desktop-2026-11-17): `init_once`, minimal app, `v50` (27), `v51` (7), `v52` (2); 5 and 6 directories left locked on the two later runs |
| `android-emulator` (API 34 x86_64 `google_apis`) | ubuntu-24.04 | 5.2.0 | pass: minimal app, `v50/store_test.dart`, `v50/observers_test.dart` |
| `android-release` (`flutter build apk --release`, aapt2) | ubuntu-24.04 | 4.14.7, 5.0.4, 5.1.0, 5.2.0 | pass; the merged release manifests list INTERNET and the Bluetooth, location and Wi-Fi permissions |
| `ios-sim` (iPhone 17 Pro, iOS 26.5) | macos-26 arm64 | 5.2.0 | pass on the third run (below): minimal app, `v50/store_test.dart`, `v50/observers_test.dart` |
| `ios-build` (`--simulator --no-codesign`) | macos-26 arm64 | 4.14.7, 5.2.0 | pass |
| `macos` | macos-26 arm64 | 5.0.4, 5.1.0, 5.2.0 | pass: `init_once`, minimal app, every probe directory at or below the line |
| `v4` | macos-26 arm64 | 4.14.7 | pass |
| `from-skill` (analyze, `build apk --debug`, `build ios --simulator --debug`) | ubuntu-24.04, macos-26 arm64 | 5.2.0 | pass |
| `migration`, macOS then iPhone 17 Pro (iOS 26.5) | macos-26 arm64 | 5.1.0 → 5.2.0 | pass |
| `macos-release` | macos-26 arm64 | 5.2.0 | pass |
| `web` (`flutter drive` targets, `web-probe.py --skip-manual`) | ubuntu-24.04, the image's Chrome and ChromeDriver | 5.1.0, 5.2.0 | pass |

- **iOS Simulator: the first `flutter test` after a fresh boot can hang.** On the first
  CI run the leg picked the first iPhone in `simctl list` and hung after `Xcode build
  done` until cancelled (no GNU `timeout` on the runner then). On the second, with the
  newest runtime's iPhone 17 Pro (iOS 26.5) and a 20-minute bound, the first target
  (`minimal_app_test.dart`) ended with `Error waiting for a debug connection: The log
  reader failed unexpectedly` (exit 124) and the next two targets passed in under a
  minute each. `scripts/boot-simulator.sh` now launches a stock app and reads the log
  once after boot, and the iOS legs set `FIXTURE_RETRIES=1`: `run-fixture.sh` re-runs a
  target once, with a `::warning::`, only when the timeout stopped it (exit 124) after
  `The log reader failed unexpectedly` or after a hang following `Xcode build done`
  with no test output. Any other failure or timeout is never retried. On the third
  and fourth runs every iOS target passed on its first attempt, so the retry has not
  been exercised in CI.

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
- **Web, `setOfflineOnlyLicenseToken` with an invalid token does not throw** (5.0.4,
  5.1.0, 5.2.0; Chrome, debug; `bad offline license on web`, run alone in
  `web_license_test.dart`: a fresh page, `DittoConfig(databaseID:
  '11111111-2222-4333-8444-555555555555')`, no valid license set before it). It logs
  `setOfflineOnlyLicenseToken is a no-op on the web platform.` and returns. The source
  (`sdks/flutter/ditto_live/lib/src/ditto.dart:252-260` @ `sdk-release-5.2.0`) logs that
  warning when `kIsWeb` and then still calls
  `core.dittoFfiTryVerifyLicense(ptr, licenseToken).extract()`, which would throw on an
  error result; for `'not-a-license'` the web core returned none. So the Correction is
  right that the call still verifies; that it throws for an invalid token was not
  observed (one invalid token tried, on all three lines).
- **Web, the in-memory store outlives `close()` within a page** (5.0.4, 5.1.0, 5.2.0;
  debug; `close then reopen in the same page keeps data`, named `... loses data` in the
  task brief). A document written before
  `close()` is there after a new `Ditto.open(DittoConfig())` in the same page; only a
  page load clears it (`web_reload_persistence`: 1 document before, 0 after, release).
  Refines the lead "in-memory, lost on reload": lost on reload, not on close.
- **Web, `Attachment.copyToPath` fails with a `DittoException`, not an
  `UnsupportedError`**, through its Future: `DittoException(Retrieving a filesystem path
  for attachments is not supported on the Web.)`. `newAttachment(path)` likewise fails
  through its Future (`DittoException(Creating attachments from files is not supported
  on Flutter Web.)`), while `DittoLogger.exportLogs` throws `UnsupportedError: Not
  supported on the web platform` **synchronously** at the call, so `await`ing it in a
  `try` catches it but `.catchError` on its Future does not (5.0.4, 5.1.0, 5.2.0).
- **Web, enabling a P2P transport throws in `updateTransportConfig` on 5.0.4 and 5.1.0**,
  not only in `sync.start()` as the lead says (5.2.0). See
  [Flutter Web probes](#flutter-web-probes-2026-11-17).
- **Web, `--wasm` is not usable with 5.1.0 or 5.2.0** (wrong query results). The lead
  only called the docs ambiguous; see
  [SDK defects](#sdk-defects-the-fixture-records-2026-11-17).
- **Hot restart does not "work" on native, and re-opening fails on web too.** After `R`,
  `Ditto.open` on the same directory fails with `DittoException(File already locked,
  ...)` on 5.0.4 (macOS 3/3) and 5.2.0 (macOS 5/5, Chrome 2/2), and never completes on
  5.1.0 (macOS 4/4): the restart orphans the open instance,
  which keeps its directory (web: its in-memory store) locked. Neither an app-scoped
  holder (statics are reset by the restart) nor a retry for 20 s recovers; only a full
  restart does. Details: [Manual records](#manual-records).

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

### Hot restart, 2026-11-17

**Driven by script, not by hand:** `scripts/hot-restart.py` runs `flutter run` with
stdin attached and types the keys. macOS 27.2.1 arm64, Flutter 3.50.0, ditto_live 5.2.0,
debug builds, Ditto logging at its default, the SDK default persistence directory
(`DittoConfig()`). Chrome 157 ran headless (`--web-browser-flag=--headless=new`). Each
run was bounded by `timeout 1500`; the script kills the `flutter run` process group and,
on macOS, any app left from the fixture copy. Each run was its own command, from the
repository root; these loops issue the same commands:

```bash
for mode in v1 v2 holder; do
  timeout 1500 python3 tests/flutter-sdk/scripts/hot-restart.py --device macos --mode "$mode" --observe 40
  timeout 1500 python3 tests/flutter-sdk/scripts/hot-restart.py --device chrome --mode "$mode" --observe 40
done
for mode in v1 v2; do
  timeout 1500 python3 tests/flutter-sdk/scripts/hot-restart.py --device macos --mode "$mode" --observe 40 --peer
done
```

(The first macOS `v1` run used `--observe 30`; the Chrome `v1` run also used 30.)

Steps the app and script take: open Ditto, register the observer (V1
`registerObserver`, or V2 `registerObserverV2`), listen to `changes`, insert one
document, update it every 2 s, print `HR: ready`; the script waits 5 s, sends `R`,
watches, sends `q`. `holder` opens through an app-scoped static holder that retries
`Ditto.open` every 500 ms for 20 s. `--peer` also makes the first run listen on TCP
127.0.0.1:45631 with a subscription; after the restart, when the default directory
cannot be opened, a second instance in its own directory connects there and inserts a
document, which reaches the orphaned instance as a remote change would.

| Device | Mode | After `R` | Crash |
|---|---|---|---|
| macOS | `v1` | `Ditto.open` fails 1.1 s later (error below); the old observer prints nothing more | none in 30 s |
| macOS | `v2` | the same error | none in 40 s |
| macOS | `holder` | attempt 1 fails with the same error; still failing at 20 s (`open failed`) | none in 40 s |
| macOS | `v1 --peer` | the same error; the peer connects to the orphaned instance (1 remote peer) and inserts | none in 40 s |
| macOS | `v2 --peer` | the same error; the peer inserts (presence: 0 connected peers yet), and 0.2 s later `Lost connection to device.` | **yes, once (n=1)**: `EXC_BAD_ACCESS (SIGBUS)`, `KERN_PROTECTION_FAILURE`, thread `live query callback 2`; trigger isolated in "Hot restart, repeated runs" below |
| Chrome | `v1` | `Ditto.open` fails at once (error below) | none in 30 s |
| Chrome | `v2` | the same error | none in 40 s |
| Chrome | `holder` | attempt 1 fails; still failing at 20 s | none in 40 s |

The re-open error, macOS (the home directory shortened to `~`):

```text
flutter: HR: open failed: DittoException: DittoException(File already locked, working dir = ~/Library/Containers/live.ditto.skills.minimalApp/Data/Library/Application Support/live.ditto.skills.minimalApp/ditto-00000000-0000-0000-0000-000000000000, retried 5 times.
flutter: Multiple Ditto instances cannot run at the same time within the same working directory. Either use unique working directories for each instance, or consider managing your Ditto instance as a singleton instead.)
```

Chrome:

```text
HR: open failed: DittoException: DittoException(File already locked, working dir = ditto-00000000-0000-0000-0000-000000000000/__ditto_lock_file, retried 0 times.
Multiple Ditto instances cannot run at the same time within the same working directory. Either use unique working directories for each instance, or consider managing your Ditto instance as a singleton instead.)
```

The V2 crash, trimmed (`v2 --peer`; the report's faulting thread):

```text
[  19.2s] flutter: HR: peer: inserted a document for the orphaned instance
[  19.4s] Lost connection to device.
Exception Type:  EXC_BAD_ACCESS (SIGBUS), KERN_PROTECTION_FAILURE at 0x0000000124d40198
Thread name:     live query callback 2
Frame 0:         0x124d40198, in an untagged rw- region (not code)
Frame 1:         DittoCore std::sys::backtrace::__rust_begin_short_backtrace
```

Mitigations: **neither works in-process.** A hot restart resets every Dart static, so
an app-scoped holder cannot hand the old instance to the new `main()`, and nothing in
the old isolate runs to close it first; `holder` shows a retry does not help either,
because the orphaned instance never releases its directory (or, on web, its in-memory
store). What recovered every time was a full restart: each new `flutter run` launch
opened the same directory at once and saw the documents of the earlier runs (the
observer's first item count grows run to run: 0, 1, 2, 3, ...). The Finding 1
GC-finalizer hazard did not show in these runs, which re-open nothing successfully in
the same process.

### Hot restart, repeated runs, 2026-11-17

Standalone `flutter create` apps (macOS desktop, plus `--platforms=web` for Chrome),
`ditto_live` pinned per line, Flutter 3.50.0, Xcode 27.2, macOS 27.2.1 arm64, Chrome 157
headless, debug. Driven like `scripts/hot-restart.py`: a script runs
`flutter run -d <device> --debug` with stdin attached (`--web-browser-flag=--headless=new`
for Chrome), waits for the app's ready line, waits 5 s, sends `R`, prints output for the
observe window, sends `q` and kills what is left. Each run is a new `flutter run` with a
unique run ID, so each starts from fresh directories. The license comes from
`--dart-define-from-file`. Between lines, `macos/Podfile.lock`, `macos/Pods` and `build/`
were deleted.

**Re-open app.** `main()` opens `{systemTemp}/<run-id>` (web: the store name `<run-id>`)
with `DittoConfig(persistenceDirectory: ...)`, sets the license, turns each
peer-to-peer transport off, inserts one document, prints the count, and never closes.
After `R` the same `main()` runs again. Modes: `plain` (open once, print the result or
the error), `retry` (retry `Ditto.open` every 500 ms for 20 s), `per-launch`
(`kDebugMode` only: append `DateTime.now().microsecondsSinceEpoch` taken at the start
of that `main()` to the directory):

```bash
python3 hot_restart.py <app> macos  --dart-define-from-file=license.json --dart-define=RUN=$(date +%s) --observe 15
python3 hot_restart.py <app> chrome --dart-define-from-file=license.json --dart-define=RUN=$(date +%s) --observe 20
python3 hot_restart.py <app> macos  --dart-define-from-file=license.json --dart-define=RUN=$(date +%s) --dart-define=MODE=retry --observe 30
python3 hot_restart.py <app> macos  --dart-define-from-file=license.json --dart-define=RUN=$(date +%s) --dart-define=MODE=per-launch --observe 15
```

| Line | Device | Mode | After `R` | Runs |
|---|---|---|---|---|
| 5.0.4 | macOS | plain | `File already locked` | 3/3 |
| 5.1.0 | macOS | plain | `Ditto.open` never completes or throws (one run watched for 60 s) | 4/4 |
| 5.2.0 | macOS | plain | `File already locked`, about 1 s after `main()` restarts | 5/5 |
| 5.2.0 | Chrome | plain | `File already locked ... retried 0 times`, at once | 2/2 |
| 5.2.0 | macOS, Chrome | retry | still `File already locked` after 20 s (14 and 41 attempts) | 1/1 each |
| 5.2.0 | macOS | per-launch | open succeeds in the new, empty directory | 2/2 |
| 5.2.0 | Chrome | per-launch | open succeeds in the new, empty store | 1/1 |
| 5.2.0 | macOS | full restart (`q`, then `flutter run` with the same run ID) | opens at once, both earlier documents present | 1/1 |
| 5.0.4, 5.1.0 | Chrome | — | not run | — |

The per-launch runs leave every earlier directory on disk: nothing in the pattern
deletes them.

**Observer-crash app.** First `main()`: open instance A in `{systemTemp}/<run-id>/a`,
turn peer-to-peer off, listen on TCP `127.0.0.1:45700`, register a subscription on
`restarts`, start sync, register an observer on `SELECT * FROM restarts` (`MODE=v2`:
`registerObserverV2`; `v1`: `registerObserver`, no `onChange`), listen to its `changes`,
write a marker file, print ready. After `R`, `main()` finds the marker, opens instance B
in `{systemTemp}/<run-id>/b`, connects it to `127.0.0.1:45700`, subscribes, starts sync
and inserts one document into `restarts`, which reaches A's orphaned observer as a
remote change. "Crash" means `Lost connection to device.` plus a new `.ips` report:

```bash
python3 hot_restart.py <app> macos --dart-define-from-file=license.json --dart-define=MODE=v2 --dart-define=RUN=$(date +%s) --observe 25
python3 hot_restart.py <app> macos --dart-define-from-file=license.json --dart-define=MODE=v1 --dart-define=RUN=$(date +%s) --observe 25
ls -t ~/Library/Logs/DiagnosticReports/<app>-*.ips | head -1
```

| Line | Observer | Crash | Exception per run |
|---|---|---|---|
| 5.2.0 | V2 | 4/4 | SIGBUS, SIGSEGV, SIGSEGV, SIGBUS; fault address `...0198`, thread `live query callback 1`–`3` |
| 5.2.0 | V2, B connects but does not insert | 0/3 | (B sees 1 remote peer; the app stays up for 25 s) |
| 5.2.0 | V1 | 0/3 | (B sees 1 remote peer and inserts; the app stays up) |
| 5.1.0 | V2 | 4/4 | SIGSEGV, SIGSEGV, SIGBUS, SIGBUS; address `...01a0` |
| 5.1.0 | V1 | 3/3 | SIGBUS, SIGSEGV, SIGSEGV; address `...01a0` |
| 5.0.4 | V1 (no V2 API) | 0/3 | (B connects and inserts) |
