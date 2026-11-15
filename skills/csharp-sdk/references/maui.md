# .NET MAUI

## Contents

- [Targets and toolchains](#targets-and-toolchains)
  - [Solution layout for a tested app](#solution-layout-for-a-tested-app)
- [Permissions and lifecycle](#permissions-and-lifecycle)
- [Release validation](#release-validation)
- [New SDK, older workload manifests](#new-sdk-older-workload-manifests)
- [IDE cannot find the Mac Catalyst bundle](#ide-cannot-find-the-mac-catalyst-bundle)

Sources: [Ditto installation and permissions](https://docs.ditto.live/sdk/latest/install-guides/c-sharp),
[MAUI quickstart](https://docs.ditto.live/sdk/latest/quickstarts/dotnet-maui), and
published 5.2.0 platform assemblies. The helper lives in DittoSDK.Sync.

## Targets and toolchains

**Choose the framework from the Xcode you build Apple targets with.** `create-app.py maui`
takes `--framework net10.0` or `net11.0` and defaults to the active SDK's major
(`dotnet --version`, which honours global.json):

| Framework | Apple targets build with | Mac Catalyst minimum | MAUI Controls | Scene setup |
|---|---|---|---|---|
| net10.0 | Xcode 26.x | 16.4 | 10.0.1 | Not needed |
| net11.0 | Xcode 27 or later | 17.0 | `$(MauiVersion)` (from the workload) | UIApplicationSceneManifest + SceneDelegate, included |

`dotnet workload update` cannot make a net10.0 Apple pack accept Xcode 27: generate with
net11.0 instead. Android builds with either. Both include Windows x64 when built on
Windows. Other minimums: Android 24, iOS 15.4, Windows 10.0.17763.0. macOS uses
maccatalyst-arm64, not osx-arm64.

**Use Ditto 5.2.0 or later.** Before 5.2.0, .NET 10 Android apps (which resolve
Xamarin.Kotlin 2.x) abort at startup with "Built-in class kotlin.Any is not found";
5.2.0 also fixed an armeabi-v7a open crash and a RequestPermissionsAsync
background-thread crash. `create-app.py` rejects older versions for MAUI.

Build one target at a time when the host cannot build the others (replace net10.0 with
your framework):

```bash
dotnet build -f net10.0-android -p:TargetFrameworks=net10.0-android
dotnet build -f net10.0-ios -p:TargetFrameworks=net10.0-ios -r iossimulator-arm64
dotnet build -f net10.0-maccatalyst -p:TargetFrameworks=net10.0-maccatalyst
dotnet build -f net10.0-windows10.0.19041.0 -p:TargetFrameworks=net10.0-windows10.0.19041.0
```

`-p:TargetFrameworks` applies to every referenced project, so use it only for the
single-project starter. Once the app references a class library, build with `-f` alone
(it fails with NETSDK1005 otherwise) and install the workloads for every listed target.

Install matching .NET/MAUI workloads, Android SDK/JDK, and Xcode as appropriate.
Physical iOS deployment additionally needs signing. Use a real canonical filesystem path
for builds on macOS; building through a symlinked path such as /tmp (which points to
/private/tmp) can drop generated icon resources.

### Solution layout for a tested app

Keep Ditto logic in a plain `netX.0` class library that both the MAUI app and an xUnit
project reference; a test project cannot reference the MAUI app itself. Reference the
`Ditto` package from the library **and** the MAUI app: the library compiles against
Ditto's .NET assembly, while the app deploys the platform assemblies and native assets.
`DittoSyncPermissions` exists only in the mobile assemblies, so call it from the MAUI
app and pass it to the library as a `Func<Task<bool>>`, as the starter does.

## Permissions and lifecycle

AndroidManifest.xml contains the Bluetooth, network and location declarations for the
relevant Android API ranges. Apple Info.plist declares Bluetooth usage, local network
usage and Bonjour services. Check these against the selected transports and app needs.
Mac Catalyst also declares sandbox network-client/server and Bluetooth entitlements.
Declarations alone do not grant runtime permission.

The required sequence is OpenAsync → main-thread permission request → check returned
bool → start sync. Android's DittoSyncPermissions helper needs initialized native
transports. The shared adapter opens first; MainThread.InvokeOnMainThreadAsync invokes
the permission helper and returns its bool. The adapter asks only when
EnablePeerToPeerRadios is true; the MAUI template's appsettings.json sets it (the Settings
class itself defaults to false, so a config file without the key turns radios off). A denial is not fatal: the store stays
open, Bluetooth and Wi-Fi peer-to-peer transports are turned off, LAN and server sync
still start, and the status line keeps showing the denial (`TaskStore.PermissionsDenied`). Offer a way to request again
rather than treating the first answer as final. Windows builds must not reference the mobile-only helper.

UI updates go through the page's `IDispatcher.Dispatch`, which returns false when it
cannot accept work; the starter turns that into the exception the store's back-pressure
needs (see [observers](observers.md)). The starter owns its view model per window and
stops it on destruction. Do not keep restarting the instance for each page appearance.

On Android a window can be destroyed and recreated in the same process (Back then
relaunch, or the system reclaiming the activity), and the new window's `CreateWindow` and
`OnAppearing` run *before* the old window's `Destroying`. `OpenAsync` retries a locked
directory only briefly (about a second on a 5.2.0 emulator) and then throws
`DittoPersistenceDirectoryLockedException`, so a slow teardown leaves the new window
without a store. The starter's `App` therefore stops the previous page's store before
the new page starts; keep that ordering if you restructure it. If you move the store to an
app-scoped service, make its start and stop re-entrant (a stop must allow the next start)
and create window-owned pages per window rather than reusing singleton pages or Shell.

The starter does not promise continuous background sync. If required, follow the
official Android foreground-service setup (including notification resources/runtime
permission) and, on iOS/Mac Catalyst, add `bluetooth-central` and `bluetooth-peripheral`
to `UIBackgroundModes`; Ditto logs a warning naming them when BLE runs without them.
Verify background behavior on hardware.

## Release validation

Compile all advertised targets and execute at least the intended deployment target.
Check a real device for permission denial/retry, app suspension/resumption, BLE/AWDL/
Wi-Fi Aware and background behavior. Emulator success is insufficient for radio claims.
Test trimming/AOT and serializer behavior in the actual release artifact; the baseline
Apple starter uses MtouchLink=None instead of an invalid PublishTrimmed=false setting.

## New SDK, older workload manifests

A newly installed .NET SDK can still select older workload packs. Check
`dotnet workload --version`, `dotnet workload list` and the Apple pack the build selects
before concluding that Xcode must change, and keep the Xcode checks enabled. Choose the
framework by the table above rather than by updating workloads.

When a user asks for a newer framework than the template offers, update the target
frameworks, workload set, Microsoft.Maui.Controls, Apple minimums and the platform entry
points together: compare native entry points and plist files with a fresh
`dotnet new maui --no-restore` project for that SDK, keep the Ditto permission entries,
and build each target. An outdated entry point fails with errors such as MT7199.

## IDE cannot find the Mac Catalyst bundle

Compare the IDE's requested `.app` path with the actual build output. Some Apple SDKs
name the Mac Catalyst bundle after ApplicationTitle while an IDE launcher requests the
assembly/project name, so a successful build does not guarantee a successful IDE launch
(see the related [Rider report](https://youtrack.jetbrains.com/issue/RIDER-139849/Debugging-MAUI-MacCatalyst-error-with-App-Naming)).
Set ApplicationTitle to the project name only when TargetFramework contains
`-maccatalyst`, and keep the friendly name with an explicit CFBundleDisplayName in
Platforms/MacCatalyst/Info.plist. Rebuild and remove only the obsolete generated bundle;
renaming an output directory alone does not fix subsequent builds.
