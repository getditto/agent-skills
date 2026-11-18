# Setup — Flutter

The v5 form only. Package versions per line, the 4.14.x coordinate and every other
cross-version fact live in [versions.md](versions.md).

## Contents

- [CAP-01 Prerequisites and install](#cap-01-prerequisites-and-install)
  - [Platform minimums](#platform-minimums)
  - [iOS and macOS: CocoaPods](#ios-and-macos-cocoapods)
  - [Android: Gradle](#android-gradle)
- [CAP-02 Permissions and platform configuration](#cap-02-permissions-and-platform-configuration)
  - [Declarations](#declarations)
  - [Android runtime permissions](#android-runtime-permissions)
  - [Gate platform code with kIsWeb, then Ditto.currentPlatform](#gate-platform-code-with-kisweb-then-dittocurrentplatform)

## CAP-01 Prerequisites and install

```bash
flutter pub add ditto_live
```

For a new app this resolves the latest stable `ditto_live`; 5.2.0 is the latest this skill
was checked against, not a pin to copy. Keep an existing project's pin.

**Toolchain.** The sources disagree, and none of the lower bounds was run:

| Source | Minimum |
|---|---|
| pub.dev `pubspec.yaml`, every line | `flutter: ">=3.19.0"`; 5.1.0 and 5.2.0 also Dart `>=3.5.4`, which needs Flutter 3.24.4 |
| Release-tag `pubspec.yaml`, 5.1.0 and 5.2.0 (`sdks/flutter/ditto_live/pubspec.yaml` @ `sdk-release-5.1.0`, `-5.2.0`) | `flutter: '>=3.24.5'` |
| Compatibility page (<https://docs.ditto.live/sdk/latest/compatibility/flutter>) | Flutter 3.24.0, Dart 3.5 |
| Install guide (<https://docs.ditto.live/sdk/latest/install-guides/flutter>) | "Flutter SDK (>3.24.5)"; "Ditto supports Flutter 3.24.5-3.32+" |

pub accepting Flutter 3.19 does not make it supported. Use Flutter 3.24.5 or later; this
skill was executed with **Flutter 3.50.0 (Dart 3.14.0)** only.

**Before the first Ditto call:** `await Ditto.init()`. It is required on 5.0.x and
optional from 5.1.0, where `Ditto.open` calls it; it is memoized, so call it
unconditionally. See [connect.md](connect.md#cap-03-connecting).

### Platform minimums

Minimum OS is the documented value
(<https://docs.ditto.live/sdk/latest/compatibility/flutter>); footnotes give the
plugin's own value where it differs. Peer-to-peer transports per platform are not
listed here: see the `ditto-mesh-networking` skill if installed, otherwise
<https://docs.ditto.live/sdk/latest/compatibility/flutter#transports>.

| Platform | Minimum OS | Toolchain | Network at build time | Podfile platform |
|---|---|---|---|---|
| iOS | 15 (¹) | Xcode, CocoaPods | CocoaPods fetches the `DittoFlutter` pod | `platform :ios, '15.0'` |
| Android | 7.0, API 24 (²) | Android SDK; compileSdk 36 for 5.1.0+ (below) | Gradle fetches the `com.ditto` libraries | — |
| macOS | 12, arm64 (¹) | Xcode, CocoaPods | as iOS | `platform :osx, '12.0'` |
| Windows | 10, x64 | Visual Studio 2022 with **Desktop development with C++** | CMake downloads `dittoffi.dll` from `software.ditto.live` | — |
| Linux | Ubuntu 20.04, x64 or AArch64 | Flutter's Linux desktop toolchain | CMake downloads `libdittoffi.so` from `software.ditto.live` | — |
| Web | Chrome 96, Firefox 99, Safari 15.6, Edge 96 | — | none: the WebAssembly assets ship in the package | — |

1. The plugin's `ditto_live` podspec says iOS 14.0 and macOS 11.0 (5.1.0+; 10.11 on
   5.0.4) (`sdks/flutter/ditto_live/{ios,macos}/ditto_live.podspec` @ `sdk-release-5.2.0`),
   and so does the `DittoFlutter` pod it depends on (its CocoaPods trunk specs for
   5.0.4, 5.1.0 and 5.2.0). Flutter
   3.50.0 rewrites a project's iOS 14.0 target to 15.0 and macOS 11.0 to 12.0 on every
   build (executed: it printed `Updating minimum macOS deployment target to 12.0.`), so
   commit 15.0 and 12.0.
2. The plugin itself builds with `minSdk = 23`
   (`sdks/flutter/ditto_live/android/build.gradle` @ `sdk-release-5.2.0`); set the app to 24.

The Windows and Linux downloads come from the plugin's `CMakeLists.txt`
(`sdks/flutter/ditto_live/{windows,linux}/CMakeLists.txt` @ `sdk-release-5.2.0`, `file(DOWNLOAD …)`):
an offline build machine fails there unless the environment variable `LIBDITTOFFI_PATH`
points at a local `dittoffi.dll` or `libdittoffi.so`, which skips the download (same
files, `if (DEFINED ENV{LIBDITTOFFI_PATH})`; not executed). Visual Studio 2022 is from the install guide
(<https://docs.ditto.live/sdk/latest/install-guides/flutter#windows>).

Executed builds and runs (ditto_live 5.2.0, debug unless stated): macOS desktop, Linux
(ubuntu-24.04), Windows (windows-latest), an Android API 34 emulator, the iOS Simulator,
release APKs (4.14.7 to 5.2.0), a release macOS app, and Chrome 157. Not run: a physical
iOS or Android device with radios, Linux AArch64, Firefox, Safari, Edge.

### iOS and macOS: CocoaPods

`ditto_live` supports CocoaPods only. Flutter 3.50's `flutter create` writes no Podfile,
because new projects use Swift Package Manager; the build then prints `The following
plugins do not support Swift Package Manager for macos: - ditto_live` and falls back to
CocoaPods, copying Flutter's own Podfile template into the project
(`flutter_tools/lib/src/macos/cocoapods.dart` `setupPodfile`, Flutter 3.50.0). Edit that
Podfile. `ios/Podfile`:

<!-- snippet: flutter-podfile-ios -->
<!-- Generated by scripts/sync-snippets.py from code CI runs. Edit the marked source, not this block. -->
```ruby
platform :ios, '15.0'
```
<!-- /snippet -->

Use `platform :osx, '12.0'` in `macos/Podfile`.

**iOS Simulator builds, ditto_live 5.1.0 and later.** `DittoCore` ships an arm64-only
simulator slice, and Flutter's `Generated.xcconfig` resets the Runner's
`EXCLUDED_ARCHS[sdk=iphonesimulator*]`, so `flutter build ios --simulator` fails with
`Framework 'DittoCore' not found`. Replace the Podfile's `post_install` with this
(executed: the build passes with it and fails without it on 5.2.0; `flutter run` on an
arm64 simulator and device builds are unaffected):

<!-- snippet: flutter-podfile-ios-simulator-arch -->
<!-- Generated by scripts/sync-snippets.py from code CI runs. Edit the marked source, not this block. -->
```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
  end
  # ditto_live 5.1.0+: DittoCore ships an arm64-only iOS Simulator slice.
  # Flutter's Generated.xcconfig resets EXCLUDED_ARCHS[sdk=iphonesimulator*]
  # to "i386", so exclude x86_64 on the Runner targets themselves
  # (target-level build settings win over the xcconfig).
  installer.aggregate_targets.each do |aggregate|
    aggregate.user_project.native_targets.each do |target|
      target.build_configurations.each do |config|
        config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'i386 x86_64'
      end
    end
    aggregate.user_project.save
  end
end
```
<!-- /snippet -->

`pod install` failing with `None of your spec sources contain a spec satisfying the
dependency: DittoFlutter (= <version>)` means a stale local index: run
`pod repo update trunk` (executed on 5.0.4).

### Android: Gradle

`android/app/build.gradle.kts`:

<!-- snippet: flutter-android-gradle -->
<!-- Generated by scripts/sync-snippets.py from code CI runs. Edit the marked source, not this block. -->
```kotlin
defaultConfig {
    applicationId = "live.ditto.skills.minimal_app"
    // Ditto recommends minSdk 24 (Android 7.0) for apps.
    minSdk = 24
    targetSdk = flutter.targetSdkVersion
    versionCode = flutter.versionCode
    versionName = flutter.versionName
}
```
<!-- /snippet -->

**ditto_live 5.1.0 and 5.2.0 with Flutter 3.50 (AGP 9): every APK build fails** at
`:ditto_live:checkDebugAarMetadata`: the plugin compiles with compileSdk 34 and its
`com.ditto` libraries require 36. Raising the app's own compileSdk does not help. Add
this to the root `android/build.gradle.kts`, above the `evaluationDependsOn(":app")`
block (executed: debug and release APKs pass with it on 5.1.0 and 5.2.0; without it a
fresh `flutter create` app fails on 5.1.0, 3 of 3 builds, and 5.2.0, 4 of 4; 5.0.4
builds either way):

<!-- snippet: flutter-android-compilesdk-override -->
<!-- Generated by scripts/sync-snippets.py from code CI runs. Edit the marked source, not this block. -->
```kotlin
// ditto_live 5.1.0 and 5.2.0: the plugin compiles with compileSdk 34, but the
// com.ditto Android libraries it depends on require compileSdk 36, and AGP 9
// checks this per library module. Raise the plugin's compileSdk. afterEvaluate
// runs after the plugin's own build script; keep this block above the
// evaluationDependsOn(":app") block below.
subprojects {
    afterEvaluate {
        if (name == "ditto_live") {
            extensions.configure<com.android.build.api.dsl.LibraryExtension>("android") {
                compileSdk = 36
            }
        }
    }
}
```
<!-- /snippet -->

## CAP-02 Permissions and platform configuration

### Declarations

The OS declarations themselves, and why each radio needs them, are shared with other
SDKs: see the `native-app-config` skill
([Apple](../../native-app-config/references/apple.md),
[Android](../../native-app-config/references/android.md)) if installed, otherwise
<https://docs.ditto.live/sdk/latest/install-guides/flutter#step-1-add-the-ditto-dependency>.
The Flutter files are below.

iOS `ios/Runner/Info.plist`:

<!-- snippet: flutter-ios-info-plist -->
<!-- Generated by scripts/sync-snippets.py from code CI runs. Edit the marked source, not this block. -->
```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Uses Bluetooth to sync with nearby devices.</string>
<key>NSLocalNetworkUsageDescription</key>
<string>Uses the local network to sync with nearby devices.</string>
<key>NSBonjourServices</key>
<array>
	<string>_http-alt._tcp.</string>
</array>
```
<!-- /snippet -->

macOS: Flutter keeps **two** entitlements files, and a release build reads only
`Release.entitlements`. Add these keys to both `macos/Runner/DebugProfile.entitlements`
and `macos/Runner/Release.entitlements` (executed: a `flutter build macos --release` app
with them runs the minimal app on 5.2.0):

<!-- snippet: flutter-macos-entitlements -->
<!-- Generated by scripts/sync-snippets.py from code CI runs. Edit the marked source, not this block. -->
```xml
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.network.server</key>
<true/>
<key>com.apple.security.device.bluetooth</key>
<true/>
```
<!-- /snippet -->

Without them the install guide reports `Operation not permitted (os error 1)` when
Ditto connects (<https://docs.ditto.live/sdk/latest/install-guides/flutter#step-1-add-the-ditto-dependency>;
not reproduced here). Keys added only to `DebugProfile.entitlements` are absent from
the release build. The macOS fixture has no `NSLocalNetworkUsageDescription`
or `NSBonjourServices`, so macOS LAN discovery on macOS 15 and later was not executed;
follow `native-app-config` for those keys.

Android `android/app/src/main/AndroidManifest.xml`:

<!-- snippet: flutter-android-manifest -->
<!-- Generated by scripts/sync-snippets.py from code CI runs. Edit the marked source, not this block. -->
```xml
<!-- The ditto_live plugin manifest already declares INTERNET, so every merged
     manifest (debug and release) has it; declaring it here keeps it explicit. -->
<uses-permission android:name="android.permission.INTERNET" />
```
<!-- /snippet -->

Flutter's template puts `INTERNET` only in the debug and profile manifests. The
`ditto_live` plugin manifest declares `INTERNET` and the Bluetooth, location and Wi-Fi
permissions, and they merge into every build type (executed: the merged **release**
APK manifests of 4.14.7, 5.0.4, 5.1.0 and 5.2.0 list them). The `src/main` entry above
is therefore optional; it keeps the requirement visible in the app.

**Asked to add Bluetooth permissions to `android/`?** There is nothing to add. The plugin
declares `BLUETOOTH_SCAN` (`neverForLocation`), `BLUETOOTH_CONNECT` and
`BLUETOOTH_ADVERTISE`; `BLUETOOTH` and `BLUETOOTH_ADMIN` up to API 30;
`ACCESS_FINE_LOCATION` up to API 32 and `ACCESS_COARSE_LOCATION` up to API 30; and
`NEARBY_WIFI_DEVICES` (`neverForLocation`) (`android/src/main/AndroidManifest.xml`,
ditto_live 5.2.0 from pub.dev). Do not re-declare them with other limits, and check the
merged manifest after any edit. What the app must do is
[request them at runtime](#android-runtime-permissions), before `ditto.sync.start()`.

**Windows** needs no declaration. Windows Defender Firewall may ask the user to allow
the app the first time it listens for LAN or TCP connections; this was not observed
with Ditto here (CI runners are headless).

### Android runtime permissions

Ditto never requests permissions. `DittoSyncPermissions` (5.1.0+) reports the Android
permissions its transports need and which are not granted; on every other platform both
lists are empty (executed on Chrome, 5.1.0 and 5.2.0: `[]`). Request the missing ones
with `permission_handler`, **before** `ditto.sync.start()`:

<!-- dart-version: 5.1 -->
```dart
import 'package:ditto_live/ditto_live.dart';
import 'package:permission_handler/permission_handler.dart';

/// Runtime permissions Ditto may report, by Android manifest name. The
/// others it reports (INTERNET, Wi-Fi state) are granted at install.
const _runtimePermissions = <String, Permission>{
  'android.permission.BLUETOOTH_SCAN': Permission.bluetoothScan,
  'android.permission.BLUETOOTH_CONNECT': Permission.bluetoothConnect,
  'android.permission.BLUETOOTH_ADVERTISE': Permission.bluetoothAdvertise,
  'android.permission.NEARBY_WIFI_DEVICES': Permission.nearbyWifiDevices,
  'android.permission.ACCESS_FINE_LOCATION': Permission.locationWhenInUse,
  'android.permission.ACCESS_COARSE_LOCATION': Permission.locationWhenInUse,
  'android.permission.POST_NOTIFICATIONS': Permission.notification,
};

/// ditto_live 5.1.0+: asks for the permissions Ditto reports missing and
/// returns those still missing afterwards. Empty off Android.
Future<List<String>> requestDittoPermissions() async {
  final permissions = DittoSyncPermissions();
  final missing = await permissions.missingPermissions();
  final requests = missing.map((name) => _runtimePermissions[name]).nonNulls;
  if (requests.isNotEmpty) await requests.toSet().toList().request();
  return permissions.missingPermissions();
}
```

The list varies with the API level and the manifest: `BLUETOOTH_SCAN`,
`BLUETOOTH_CONNECT` and `BLUETOOTH_ADVERTISE` on Android 12+, plus `ACCESS_FINE_LOCATION`
unless `BLUETOOTH_SCAN` asserts `neverForLocation`; `NEARBY_WIFI_DEVICES` on 13+, plus
`ACCESS_FINE_LOCATION` unless it asserts `neverForLocation`; location permissions on
older levels; `POST_NOTIFICATIONS` on 13+ only with a Ditto foreground service
(`sdks/flutter/ditto_live/lib/src/sync_permissions.dart` @ `sdk-release-5.2.0`). The
general list never contains `ACCESS_LOCAL_NETWORK`, on 5.1.0 or 5.2.0; only the
multicast list does, on Android 17+ for apps targeting API 37+. The names are
`android.permission.*` constants
(`sdks/kotlin/ditto-internal/transports/src/androidMain/kotlin/com/ditto/internal/transports/DittoSyncPermissions.kt`
@ `sdk-release-5.1.0` and `-5.2.0`). This adapter compiles against 5.1.0 and 5.2.0; the request itself
was not run on an Android device. A permission granted after sync started takes effect
on the next `ditto.sync.stop()` / `ditto.sync.start()` (the `TransportCondition`
dartdoc: "Grant the permission and restart sync to recover",
`sdks/flutter/ditto_live/lib/src/transport_conditions.dart` @ `sdk-release-5.2.0`).
Reliable UDP multicast needs its own list, `requiredMulticastPermissions()` (5.2.0).

On 5.0.x there is no `DittoSyncPermissions`; request the manifest's runtime permissions
with `permission_handler` directly. On iOS and macOS the lists are empty because the
OS prompts from the Info.plist strings (the `DittoSyncPermissions` dartdoc, same file).

### Gate platform code with kIsWeb, then Ditto.currentPlatform

1. **`kIsWeb` first.** It is a constant, so web builds drop the native branch.
2. **Then `Ditto.currentPlatform`** (`SupportedPlatform.ios`, `.android`, `.macos`,
   `.windows`, `.linux`, `.web`) for every capability decision.
3. **Never `dart:io` `Platform`:** importing `dart:io` breaks the web compile.
4. **Never `defaultTargetPlatform` for capabilities:** on web it is the browser's host
   OS (executed: `macOS` in Chrome), so a LAN gate on it turns LAN on in the browser and
   `DittoException(<validation> Expected valid TransportConfig. Invalid config: The
   following P2P transports are enabled in the transport config but are not supported
   in the current environment: LAN)` follows.

The executed gate is `enablePeerToPeer` in
[web.md](web.md#code-that-compiles-on-web).
