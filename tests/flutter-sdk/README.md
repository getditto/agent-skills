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

Every `ditto_live` line publishes the constraint `flutter >=3.19.0`. Pre-release
versions (`-rc`, `-dev`, `-experimental`, `-preview`) and ditto HEAD (5.3.0) are not
documented.

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

`scripts/run-fixture.sh <fixture> <device> <line> <target>...` copies the fixture to
`$TMPDIR/flutter-fixture-<line>/` with `scripts/use-version.py`, pins `ditto_live` to
that line from `versions.json`, and runs each target. The license comes from
`DITTO_OFFLINE_LICENSE` (environment, else the repo-root `.env`) as
`--dart-define=DITTO_LICENSE`. Output goes to `run-<device>-<line>.log` here
(gitignored). The committed `minimal_app/pubspec.yaml` stays at the 5.2 pin;
`use-version.py` refuses `4.14` for `minimal_app`.

```bash
tests/flutter-sdk/scripts/run-fixture.sh minimal_app macos 5.2 integration_test/minimal_app_test.dart
tests/flutter-sdk/scripts/run-fixture.sh minimal_app chrome 5.2 integration_test/minimal_app_test.dart
```

`chrome` runs `flutter drive -d chrome --headless`, which needs a chromedriver that
matches the local Chrome on port 4444. If nothing listens there, the script starts
`$CHROMEDRIVER` (default `chromedriver` on PATH). A user-local install, no sudo:

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --version   # 157.0.8103.79
npx --yes @puppeteer/browsers install chromedriver@157.0.8103.79 --path "$SCRATCH"
export CHROMEDRIVER="$SCRATCH/chromedriver/mac_arm-157.0.8103.79/chromedriver-mac-arm64/chromedriver"
```

Web builds embed `--dart-define` values in the compiled JavaScript, so never publish
web build output.

## Findings

### minimal_app, 2026-11-17

Flutter 3.50.0 (Dart 3.14.0) through FVM, macOS 27.2.1 arm64, Xcode 27.2,
CocoaPods 1.17.0, Google Chrome 157.0.8103.79 with ChromeDriver 157.0.8103.79. All
runs are debug builds.

| Line | Target | Outcome |
|---|---|---|
| 5.0.4 | macOS (`flutter test -d macos`) | pass |
| 5.1.0 | macOS (`flutter test -d macos`) | pass |
| 5.2.0 | macOS (`flutter test -d macos`) | pass |
| 5.2.0 | Chrome headless (`flutter drive`) | pass |
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

## Manual records
