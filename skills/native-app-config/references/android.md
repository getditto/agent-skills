# Android application configuration

Shared OS requirements, independent of Kotlin, RN/Expo, Flutter or .NET syntax.
The selected SDK and framework may require a higher minSdk than the OS permission APIs.

## Manifest declarations

Merge the [manifest fragment](../assets/AndroidManifest.xml) into the app manifest.
It describes full nearby mesh capability for a modern targetSdk:

- INTERNET, ACCESS_NETWORK_STATE, CHANGE_NETWORK_STATE, ACCESS_WIFI_STATE,
  CHANGE_WIFI_STATE, CHANGE_WIFI_MULTICAST_STATE support networking/discovery.
- BLUETOOTH and BLUETOOTH_ADMIN are legacy permissions capped at API 30.
- BLUETOOTH_SCAN, BLUETOOTH_CONNECT and BLUETOOTH_ADVERTISE apply to API 31+;
  use neverForLocation for scanning only when the app makes that assertion truthfully.
- ACCESS_COARSE_LOCATION and ACCESS_FINE_LOCATION apply through API 32 for this
  BLE + Wi-Fi Aware recipe. Do not cap them at API 30 when using Aware on Android 12/12L.
- NEARBY_WIFI_DEVICES applies to API 33+; neverForLocation is appropriate for this
  sync-only recipe when no location is derived.

Inspect the **merged application manifest**, not just the SDK's source manifest.
The published JS 5.2.0 RN library manifest is empty; its Expo config plugin supplies
permissions. Kotlin/other distributions may merge different declarations. Do not
assume one package's behavior applies to another. Use tools:replace/remove only for a
specific resolved merger conflict, preserving permissions needed by other app features.
The Expo plugin leaves some legacy/location declarations uncapped; don't silently
remove location needed elsewhere merely to match this narrower template.

## Runtime permission decisions

The [pure permission plan](../assets/android-permissions.ts) covers modern target SDKs:

| Device API | Request for full nearby mesh |
|---|---|
| 23–30 | Coarse + fine location for legacy scanning/discovery |
| 31–32 | Bluetooth scan/connect/advertise, plus coarse + fine for Wi-Fi Aware |
| 33+ | Bluetooth scan/connect/advertise plus nearby Wi-Fi devices |

On Android 12+, request coarse and fine together when requesting precise location.
If only coarse is granted where Aware requires fine, do not call the transport ready.
With Aware disabled, the plan omits location on 31–32 and nearby Wi-Fi on 33+.
Permissions are necessary, not sufficient: hardware, OS services, radio switches and
location services on applicable older versions also affect discovery.

Ask after an explanation in a foreground user flow. On denial keep local functionality
or expose a clear blocked state; on never-ask-again offer Settings. Recheck after return
and revocation. A manifest entry does not satisfy runtime permission checks. Do not
request nonexistent newer permission strings on older devices.

## Background work is a separate feature

Foreground-only apps need no custom foreground service. For intentional ongoing
connected-device work, implement a real service in the app/framework's supported native
layer, not a class name copied from another SDK. Its manifest must declare
FOREGROUND_SERVICE and, on modern targets, FOREGROUND_SERVICE_CONNECTED_DEVICE;
the service declares foregroundServiceType="connectedDevice" and exported="false".
Create its notification channel and visible notification, satisfy runtime prerequisites,
and respect background-start restrictions. On Android 13+ handle notification permission
in the user flow; denial is not permission to hide the mandatory service notification.

Do not add ACCESS_BACKGROUND_LOCATION simply for ordinary foreground nearby sync.
A JS timer/background task API alone does not guarantee continuous Ditto execution.
Test release builds and current targetSdk foreground-service requirements on devices.

## Verification

Run the application's manifest merge/build; inspect the output for every selected
permission and maxSdkVersion/usesPermissionFlags. Then exercise API 30, 31/32, and 33+
permission boundaries where those OS versions are supported. Test grant, denial,
never-ask-again, revoke in Settings and resume. Two physical devices establish radio
behavior; emulator success establishes only the paths actually exercised.

Sources: <https://docs.ditto.live/sdk/latest/install-guides/react-native>,
<https://developer.android.com/develop/connectivity/bluetooth/bt-permissions>,
<https://developer.android.com/develop/connectivity/wifi/wifi-aware>,
<https://developer.android.com/build/manage-manifests>,
<https://developer.android.com/develop/background-work/services/fgs/service-types>.
