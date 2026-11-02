# Setup — Ditto Swift SDK

Everything here is the **5.1.x** form. Package shape, platform minimums and toolchain
floors differ per line and are owned by [versions.md](versions.md).

## CAP-01 Prerequisites, toolchain, package install

**Toolchain:** Xcode 16.0 or later, Swift 6.0 or later
(<https://docs.ditto.live/sdk/latest/compatibility/swift>).

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

Shared Apple declarations are maintained in the
[native-app-config Apple reference](../../native-app-config/references/apple.md):
Info.plist privacy/Bonjour keys, optional background modes and data protection,
macOS sandbox entitlements, and restricted multicast capabilities. Apply them to the
application target. These OS settings also serve React Native, Expo, Flutter and .NET
hosts; this Swift skill owns SwiftPM, target linking and signing below.

If only the standalone Swift skill is installed, use the public
[Swift install guide](https://docs.ditto.live/sdk/latest/install-guides/swift) or
install the `ditto-native-config` companion. Keep existing protection policies explicit;
background modes do not guarantee continuous sync or execution after force quit.

### Code signing and the embedded XCFramework

**Never disable code signing on a target that embeds DittoSwift.** The published
XCFramework ships **unsigned**, and neither SwiftPM nor Xcode re-signs a binary
dependency on its own — signing the app is what signs the frameworks it embeds. Turn that
off and the build still succeeds; the app dies at launch:

```
dyld[…]: Library not loaded: @rpath/DittoSwift.framework/DittoSwift
  Reason: tried: … not valid for use in process: Trying to load an unsigned library
```

`CODE_SIGNING_ALLOWED = NO` is the usual way in — it is the obvious setting for a
Simulator-only target with no signing identity, and a common CI default. For the
Simulator, ad-hoc signing is enough and costs nothing:

```
CODE_SIGN_IDENTITY = "-"
CODE_SIGNING_REQUIRED = YES
CODE_SIGNING_ALLOWED = YES
```

A clean build followed by a `dyld` abort at launch is the signature of this; the reason
string names the unsigned library.

Command-line tools built with `swift build` have the same problem and no app target to
fix it — there, sign the framework yourself after building. See
[minimal-app-running.md](minimal-app-running.md#running-it).

### Crash reporting

Release builds need Ditto's symbols uploaded alongside your own, or a crash inside the
SDK is unreadable. The `.xcarchive`'s `dSYMs` folder contains `DittoSwift.framework.dSYM`
(and `DittoObjC.framework.dSYM` on 4.14.x). `DittoExperimental.triggerTestPanic()` forces
a panic so you can confirm the pipeline works
(<https://docs.ditto.live/sdk/latest/install-guides/swift>).
