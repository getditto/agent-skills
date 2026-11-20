# Release builds — Flutter

What changes between `flutter run` and a released app, and how to find out why a release
build does not sync. Platform files and the reasons for each key:
[setup.md](setup.md#cap-02-permissions-and-platform-configuration).

## Contents

- [What a release build changes](#what-a-release-build-changes)
- [A release build that cannot sync](#a-release-build-that-cannot-sync)
- [Android: R8](#android-r8)

## What a release build changes

| Platform | Debug run | Release build |
|---|---|---|
| macOS | `DebugProfile.entitlements` | `Release.entitlements`: a key in one file only is missing from the other build |
| Android | `src/debug` and `src/profile` manifests merge in; no code shrinking | Only `src/main` and library manifests; R8 shrinks and obfuscates |
| iOS | The project's one Info.plist | The same file; signing and the provisioning profile differ |
| Every platform | Defines from your `flutter run` command | Defines from the release build command: pass the same `--dart-define-from-file` |
| Every platform | A debug-only per-launch persistence directory, if you use one for hot restart | The SDK default directory ([widget-integration.md](widget-integration.md#hot-restart)) |

Executed release builds: a macOS 5.2.0 `.app`, run directly (the minimal app, then two
instances syncing over TCP loopback, in CI; once by hand without the network
entitlements and once without the license define); release APKs of 4.14.7 to 5.2.0, built and their
merged manifests inspected, not run; release web bundles on 5.1.0 and 5.2.0
([web.md](web.md#build-modes)). No iOS release build was made.

## A release build that cannot sync

It syncs under `flutter run` and not once released. Check in this order; the last column
says what this skill observed.

| Symptom | Likely cause | Check | Evidence |
|---|---|---|---|
| macOS release app: no peers; Ditto logs `Failed to start TCP server error=bind() failed: Operation not permitted (os error 1)` and `failed to connect to peer error=Connect failed because of an IO Error: Operation not permitted (os error 1)` | The network keys are only in `DebugProfile.entitlements` | `codesign -d --entitlements - <App>.app` lists `network.client`, `network.server` and, for Bluetooth, `device.bluetooth` | Executed, 5.2.0: with the keys a release app syncs two instances over TCP loopback; with both network keys removed it logs those lines and never syncs. No exception reaches Dart: `sync.start()` returns normally |
| Any platform: `setOfflineOnlyLicenseToken` throws `DittoException(<activation> The license failed verification. Obtain a valid license token at https://portal.ditto.live.)` | The release build command has no `--dart-define-from-file`, so `String.fromEnvironment` is empty | Build with the same define file as the debug run | Executed, macOS release, 5.2.0 |
| Android: opens and writes, never finds a peer | Runtime permissions not granted: Ditto never asks | `await DittoSyncPermissions().missingPermissions()` is empty (5.1.0+); then `sync.stop()` and `sync.start()` | Source and dartdoc; the request was not run on a device |
| Android: a permission is missing from the release APK only | It was declared in `src/debug` or `src/profile`, like Flutter's template `INTERNET` | `aapt2 dump permissions app-release.apk` | Executed: the plugin's own manifest puts Ditto's permissions in every release APK |
| Android release only, debug works | R8 ([below](#android-r8)) | Rebuild without minification | Not executed |
| iOS: no permission prompt, no LAN or Bluetooth peers | The Info.plist keys are missing from the built app | `plutil -p Runner.app/Info.plist` shows the three keys | The fixture's simulator app builds with the keys (executed); the built plist was not inspected, and no prompt or radio sync was run |
| A transport stays off (5.1.0+) | A condition Ditto can report: a missing permission, a radio off | Log `observeTransportConditions` events that are not `ok` ([transports.md](transports.md#cap-06-customizing-transports)) | No event with every transport off (executed); a failing condition was not produced |

## Android: R8

`flutter build apk --release` shrinks and obfuscates Java
and Kotlin code with R8. Release APKs of 4.14.7, 5.0.4, 5.1.0 and 5.2.0 build with
Flutter 3.50's default configuration and no extra keep rules (executed), but **none was
installed or run**, so this skill has no evidence that Ditto works after shrinking, and
no ProGuard rules to offer: the `ditto_live` plugin's `android/` directory ships none
(5.2.0 from pub.dev), and whether the `com.ditto` libraries carry their own was not
checked. Run a release build on a device before shipping. If it fails where the debug
build works, rebuild once with `isMinifyEnabled = false` and `isShrinkResources = false`
in the `release` build type to learn whether R8 is the cause (not executed). Neither
`flutter test` nor a non-web `flutter drive` runs in release mode, so an
`integration_test` suite cannot stand in for that run.
