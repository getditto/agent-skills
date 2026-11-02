# Apple application configuration

Applies to Ditto SDK 5.x native Apple hosts, including Swift, RN/Expo, Flutter and .NET
adapters when their SDK supports the target. It does not imply every SDK supports macOS.

## Info.plist declarations

Merge the [plist fragment](../assets/Info.plist) into the **application target**:

| Key | Purpose |
|---|---|
| NSBluetoothAlwaysUsageDescription | Explain the app's nearby Bluetooth synchronization. |
| NSLocalNetworkUsageDescription | Explain local Wi-Fi/network synchronization. |
| NSBonjourServices | Include `_http-alt._tcp.` (with trailing dot), preserving other services. |

Use customer-facing purpose text specific to the app. Do not describe local networking
as GPS/location. Missing Bluetooth privacy text can terminate an app when the protected
API is accessed; missing local-network/Bonjour configuration can prevent discovery.
`sync.isActive` does not prove permission was granted. Test first-install and denied access.

`NSBluetoothPeripheralUsageDescription` is the legacy Bluetooth key. Add it when a
supported older deployment target requires it; it is not the replacement for the modern
Always key. Modern RN/Expo targets do not require lowering their OS minimum to match
an old Ditto podspec. Use the maximum framework/SDK/embedded-binary deployment floor.

## Background modes

If background Bluetooth is part of the product, merge `bluetooth-central` and
`bluetooth-peripheral` into UIBackgroundModes (Xcode Background Modes capability).
The Ditto Expo plugin adds these modes automatically in the checked 5.2.0 package.
These keys permit OS-controlled background opportunities; they do not guarantee
continuous sync, unlimited execution, network availability or execution after force quit.
Explain that limit in the app's background behavior.

## Entitlements and data protection

An entitlements file is usually named App.entitlements; its filename need not be
entitlement.plist. Assign it to the target through CODE_SIGN_ENTITLEMENTS and ensure
the signing profile supports the capability. Putting an entitlement into Info.plist
has no effect on signing.

If using Data Protection while allowing access after first unlock, set
`com.apple.developer.default-data-protection` to
`NSFileProtectionCompleteUntilFirstUserAuthentication` in the signed entitlements.
The [example fragment](../assets/App.entitlements) contains this optional choice.
It does not make data available before first unlock after reboot. A stricter complete
protection policy may intentionally make the store unavailable while locked; choose
with the application's data requirements. Do not silently weaken an existing policy.

Sandboxed macOS: enable `com.apple.security.network.client` for outbound sync,
`com.apple.security.network.server` for inbound peer connections, and
`com.apple.security.device.bluetooth` if using Bluetooth. Keep required privacy strings.
These App Sandbox entitlements are not a universal iOS template.

Do not add restricted `com.apple.developer.networking.multicast` for ordinary Bonjour.
Only request it when the selected multicast transport feature requires it and the
app's provisioning profile authorizes it. Never enable private capabilities by guesswork.

## Build and device verification

Confirm the built app's Info.plist contains the keys and services. Inspect signed
entitlements with codesign on the built app for device/release validation. Simulator
build signing differs; it cannot prove device provisioning or entitlement approval.
Verify permissions on a fresh install, then revoke and restore through Settings.
Test BLE/local-network discovery with two physical devices and no internet, then lock
and unlock. Record actual results rather than inferring them from the declarations.

Sources: <https://docs.ditto.live/sdk/latest/install-guides/swift>,
<https://docs.ditto.live/sdk/latest/install-guides/react-native>,
<https://developer.apple.com/documentation/bundleresources/information-property-list/nsbluetoothalwaysusagedescription>,
<https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription>,
<https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.default-data-protection>.
