# Setup — Ditto Swift SDK

Everything here is the **5.1.x** form. Package shape, platform minimums and toolchain
floors differ per line and are owned by [versions.md](versions.md).

## CAP-01 Prerequisites, toolchain, package install

**Toolchain:** Xcode 16.0 or later, Swift 6.0 or later
(`sdk/latest/compatibility/swift.mdx`).

**Deployment targets:** iOS/iPadOS 15.0+, Mac Catalyst 15.0+, macOS (AppKit) 12.0+.

**Architectures:** Apple silicon (`arm64`) only from 5.1.0 — the published XCFramework
has no `x86_64` slice for macOS, the iOS Simulator, or Mac Catalyst. 5.0.3 and 4.14.6
still ship `x86_64`. See [versions.md](versions.md#shipped-xcframework-slices).

**Not supported:** watchOS and visionOS on any line; tvOS on any v5 line.

### Swift Package Manager is the only installation path

This skill documents one way to add Ditto to a Swift project, on every supported
version line.

In Xcode: **File → Add Package Dependencies…**, paste
`https://github.com/getditto/DittoSwiftPackage`, choose a **Dependency Rule** (pin an
exact version or *Up to Next Major Version*), and add the `DittoSwift` product to your
app target.

For a package of your own:

```swift
// Package.swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [.iOS(.v15), .macOS(.v12), .macCatalyst(.v15)],
    dependencies: [
        .package(url: "https://github.com/getditto/DittoSwiftPackage", from: "5.1.0")
    ],
    targets: [
        .target(
            name: "MyApp",
            dependencies: [.product(name: "DittoSwift", package: "DittoSwiftPackage")]
        )
    ]
)
```

The package identity is `DittoSwiftPackage`; the product is `DittoSwift`. On 4.14.x there
is a second product, `DittoObjC`, which does not exist in v5 — see
[versions.md](versions.md#package-and-toolchain).

### `import Foundation` is now your responsibility

v5 no longer re-exports `Foundation` from `DittoSwift`. A file that used `URL`, `Data`,
`UUID` or `Date` through the Ditto import alone stops compiling:

```swift
import DittoSwift
import Foundation  // required in v5; was implicit in v4
```

### Nothing to initialize before the first call

There is no global `init()` to await. The first Ditto call is `Ditto.open(config:)` —
see [connect.md](connect.md).

## CAP-02 Platform permissions, entitlements, build config

The declarations below are build configuration and belong to this skill. *Why* each
radio needs a permission, and which platforms carry which radios, belongs to the
`ditto-mesh-networking` skill, or
<https://docs.ditto.live/sdk/latest/sync/customizing-transport-configurations>.

### iOS, iPadOS and Mac Catalyst `Info.plist`

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Uses Bluetooth to connect and sync with nearby devices</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>Uses Bluetooth to connect and sync with nearby devices</string>
<key>NSLocalNetworkUsageDescription</key>
<string>Uses Wi-Fi to connect and sync with nearby devices</string>
<key>NSBonjourServices</key>
<array>
  <string>_http-alt._tcp.</string>
</array>
```

**Symptom when one is missing:** sync never starts over that transport and no error is
raised. A missing `NSLocalNetworkUsageDescription` or `NSBonjourServices` entry means
mDNS discovery silently finds no peers; a missing Bluetooth string means the system
never prompts and BLE stays dark. `ditto.sync.isActive` is still `true` — it reports that
*sync was started*, not that any transport came up.

`NSBonjourServices` must list `_http-alt._tcp.` exactly, including the trailing dot.

### Background sync on iOS

Add the **Background Modes** capability to the app target and enable both:

- *Uses Bluetooth LE accessories*
- *Acts as a Bluetooth LE accessory*

Without these, sync stops when the app is backgrounded or the device locks.

### Data protection entitlement

If the app enables Data Protection, set it to
`NSFileProtectionCompleteUntilFirstUserAuthentication`. Ditto's persistence directory has
to be readable while the device is locked but after the first unlock following a restart;
the stricter `NSFileProtectionComplete` makes the store unreadable in the background.

### macOS (AppKit)

A sandboxed Mac app needs both network entitlements, and keeps the local-network
`Info.plist` keys above:

```xml
<key>com.apple.security.network.client</key><true/>
<key>com.apple.security.network.server</key><true/>
```

`com.apple.security.network.client` is what lets the app reach Ditto Server;
`com.apple.security.network.server` is what lets peers reach it.
**Symptom when missing:** `Operation not permitted (os error 1)` when Ditto tries to
connect. This is documented for the macOS build under the Flutter install guide
(`sdk/latest/install-guides/flutter.mdx:98-124`) — it is a property of the macOS
framework, not of Flutter, and `sdk/latest/install-guides/swift.mdx` does not repeat it.

A sandboxed Mac app that uses the Bluetooth transport also needs Apple's
`com.apple.security.device.bluetooth` App Sandbox entitlement. That requirement comes
from Apple's sandbox, not from Ditto's documentation.

### Multicast entitlement (5.1 beta transport only)

`DittoMulticastBetaConfig` additionally requires Apple's restricted
`com.apple.developer.networking.multicast` entitlement, which Apple grants per app on
request. See [preview.md](preview.md) before using it at all.

### Crash reporting

Release builds need Ditto's symbols uploaded alongside your own, or a crash inside the
SDK is unreadable. The `.xcarchive`'s `dSYMs` folder contains `DittoSwift.framework.dSYM`
(and `DittoObjC.framework.dSYM` on 4.14.x). `DittoExperimental.triggerTestPanic()` forces
a panic so you can confirm the pipeline works
(`sdk/latest/install-guides/swift.mdx`).
