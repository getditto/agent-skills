# Minimal app running — Ditto

## Contents

- [Dependency](#dependency)
- [Running it](#running-it)
- [Expected output](#expected-output)
- [Verified on](#verified-on)

Topic index: [minimal-app.md](../examples/minimal-app.md). Covers Ditto SDK 4.14.x (LTS),
5.0.x, 5.1.x and 5.2.x; version-specific notes remain inline. Read only the topic needed.

## Dependency

```swift
// Package.swift
// swift-tools-version:6.0
import PackageDescription
import Foundation

// One SPM URL serves all four supported lines; only the pin changes.
let dittoVersion = ProcessInfo.processInfo.environment["DITTO_SWIFT_VERSION"] ?? "5.1.0"

// 4.14.x needs `@preconcurrency import DittoSwift` and `disableSyncWithV3()`, both of
// which the program below selects with `#if DITTO_V4`. Without this setting, pinning
// 4.14.6 compiles the v5 branch and fails.
let versionFlags: [SwiftSetting] =
    dittoVersion.hasPrefix("4.") ? [.define("DITTO_V4")] : []

let package = Package(
    name: "MinimalApp",
    platforms: [.macOS(.v13), .iOS(.v15), .macCatalyst(.v15)],
    dependencies: [
        .package(
            url: "https://github.com/getditto/DittoSwiftPackage",
            exact: Version(stringLiteral: dittoVersion)
        )
    ],
    targets: [
        .executableTarget(
            name: "MinimalApp",
            dependencies: [.product(name: "DittoSwift", package: "DittoSwiftPackage")],
            swiftSettings: versionFlags
        )
    ]
)
```

An app targeting only 5.1.x can drop the environment variable and the flag, and pin
`from: "5.1.0"`. In Xcode, add the same package URL through **File → Add Package
Dependencies…** and add the `DittoSwift` product to the target — see
[setup.md](setup.md).

## Running it

```bash
export DITTO_OFFLINE_LICENSE="REPLACE_ME_WITH_YOUR_OFFLINE_LICENSE"
# Optional — switches the program to server mode:
# export DITTO_URL="REPLACE_ME_WITH_YOUR_CONNECT_URL"
# export DITTO_TOKEN="REPLACE_ME_WITH_YOUR_DEVELOPMENT_TOKEN"
# export DITTO_DATABASE_ID="REPLACE_ME_WITH_YOUR_DATABASE_ID"

export DITTO_SWIFT_VERSION=5.1.0
swift build --product MinimalApp
BIN="$(swift build --product MinimalApp --show-bin-path)"

# The published XCFrameworks ship unsigned and SwiftPM copies them without signing;
# macOS will not load an unsigned library. An Xcode app target signs its embedded
# frameworks for you ONLY while signing is enabled — `CODE_SIGNING_ALLOWED = NO`
# builds cleanly and then aborts at launch. See references/setup.md.
# Sign every built framework: 4.14.x also copies DittoObjC.framework, and signing
# only DittoSwift leaves the v4 dependency unsigned and the executable unlaunchable
# (run.sh signs them all; references/testing.md requires the same).
for f in "$BIN"/*.framework; do
  name="$(basename "$f" .framework)"
  codesign --force --sign - "$f/Versions/A/$name"
done

# The SDK accepts only true/false for NO_COLOR, so clear it before launching.
# See references/testing.md.
env -u NO_COLOR DYLD_FRAMEWORK_PATH="$BIN" "$BIN/MinimalApp"
```

For a SwiftUI app in an Xcode project rather than a command-line program, use the
bundled project generator — see [getting-started.md](getting-started.md).

## Expected output

Offline mode prints the opened version and directory, the mode, the observed document and
`done`. Ditto's own log lines are omitted, and the persistence path varies per run:

```
Ditto 5.1.0 opened at <temporary directory>/ditto-minimal-app-<UUID>
mode: smallPeersOnly
observed 1 car(s): Toyota
done
```

5.0.3 and 4.14.6 print the same lines with their own version number. Server mode prints
`mode: server (<your connect URL>)` in place of `mode: smallPeersOnly`.

The 4.14.6 build additionally emits one deprecation warning, for the
`disableSyncWithV3()` call that line requires:

```
warning: 'disableSyncWithV3()' is deprecated: `disableSyncWithV3()` will be removed in
SDK 5.0. V3 sync is no longer supported.
```

## Verified on

| Ditto | Host | Toolchain | Modes run |
|---|---|---|---|
| 4.14.6 | macOS 27.0, arm64 | Apple Swift 6.4 | offline and server |
| 5.0.3 | macOS 27.0, arm64 | Apple Swift 6.4 | offline and server |
| 5.1.0 | macOS 27.0, arm64 | Apple Swift 6.4 | offline and server |
| 5.2.0-rc.2 | macOS 27.0, arm64 | Apple Swift 6.4 | offline and server |

The same source also compiles for the iOS Simulator, an iOS device, and Mac Catalyst at
all four versions. Nothing here was run on `x86_64`: 5.1.0 and 5.2.0-rc.2 ship no Intel
slice ([versions.md](versions.md#shipped-xcframework-slices)).
