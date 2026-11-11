# .NET MAUI

Sources: [Ditto installation and permissions](https://docs.ditto.live/sdk/latest/install-guides/c-sharp),
[MAUI quickstart](https://docs.ditto.live/sdk/latest/quickstarts/dotnet-maui), and
published 5.2.0 platform assemblies. The helper lives in DittoSDK.Sync.

## Targets and toolchains

The starter targets .NET 10 Android/iOS/Mac Catalyst, plus Windows x64 on Windows.
Its minimums follow the package assets conservatively: Android 24, iOS 15.4,
Mac Catalyst 16.4, Windows 10.0.17763.0. macOS uses maccatalyst-arm64, not osx-arm64.
Restore only the selected target when the host cannot build the other targets.

```bash
dotnet build -f net10.0-android -p:TargetFrameworks=net10.0-android
dotnet build -f net10.0-ios -p:TargetFrameworks=net10.0-ios -r iossimulator-arm64
dotnet build -f net10.0-maccatalyst -p:TargetFrameworks=net10.0-maccatalyst
dotnet build -f net10.0-windows10.0.19041.0 -p:TargetFrameworks=net10.0-windows10.0.19041.0
```

Install matching .NET/MAUI workloads, Android SDK/JDK, and Xcode as appropriate.
Xcode and Apple workload versions must match; a successful override probe is not a
supported toolchain recommendation. Physical iOS deployment additionally needs signing.
Use a real canonical filesystem path for builds on macOS; the /tmp to /private/tmp
symlink caused generated icon resources to be deleted/missed in local MAUI builds.

## Permissions and lifecycle

AndroidManifest.xml contains the Bluetooth, network and location declarations for the
relevant Android API ranges. Apple Info.plist declares Bluetooth usage, local network
usage and Bonjour services. Check these against the selected transports and app needs.
Mac Catalyst also declares sandbox network-client/server and Bluetooth entitlements.
Declarations alone do not grant runtime permission.

The required sequence is OpenAsync → main-thread permission request → check returned
bool → start sync. Android's DittoSyncPermissions helper needs initialized native
transports. The shared adapter opens first; MainThread.InvokeOnMainThreadAsync invokes
the permission helper. A denied result throws an actionable startup failure and triggers
rollback. Windows builds must not reference the mobile-only helper.

UI updates use MainThread.BeginInvokeOnMainThread. The starter owns its view model per
window and stops it on destruction. It does not promise continuous background sync.
If required, follow the official Android foreground-service setup (including notification
resources/runtime permission) and Apple background-mode requirements, then verify on
hardware. Do not keep restarting the instance for each page appearance.

## Release validation

Compile all advertised targets and execute at least the intended deployment target.
Check a real device for permission denial/retry, app suspension/resumption, BLE/AWDL/
Wi-Fi Aware and background behavior. Emulator success is insufficient for radio claims.
Test trimming/AOT and serializer behavior in the actual release artifact; the baseline
Apple starter uses MtouchLink=None instead of an invalid PublishTrimmed=false setting.
