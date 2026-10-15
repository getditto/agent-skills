# Minimal app running — Ditto

## Contents

- [Dependency](#dependency)
- [Running it](#running-it)
- [Expected output](#expected-output)
- [Verified on](#verified-on)

Topic index: [minimal-app.md](../examples/minimal-app.md). Covers Ditto SDK 4.14.x (LTS),
5.0.x and 5.1.x; version-specific notes remain inline. Read only the topic needed.

## Dependency

```swift
// Package.swift
// swift-tools-version:6.0
import PackageDescription
import Foundation

// One SPM URL serves all three supported lines; only the pin changes.
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

# The published XCFramework ships unsigned and SwiftPM copies it without signing;
# macOS will not load an unsigned library. An Xcode app target signs its embedded
# frameworks for you ONLY while signing is enabled — `CODE_SIGNING_ALLOWED = NO`
# builds cleanly and then aborts at launch. See references/setup.md.
codesign --force --sign - "$BIN/DittoSwift.framework/Versions/A/DittoSwift"

# Ditto's core reads NO_COLOR as a --disable-color flag that accepts only true/false,
# so NO_COLOR=1 panics it. See ../references/testing.md.
env -u NO_COLOR DYLD_FRAMEWORK_PATH="$BIN" "$BIN/MinimalApp"
```

In the `getditto/agent-skills` repository the same thing is one command:

```bash
cd tests/swift-sdk && ./scripts/run.sh 5.1.0 --app --offline
```

## Expected output

Real runs on macOS 27.0 / arm64, Apple Swift 6.4 (swiftlang-6.4.0.34.1). Ditto's own log
lines are omitted; the build and program output is verbatim, and the only edit anywhere
below is the redacted server hostname.

Build, 5.1.0:

```
$ DITTO_SWIFT_VERSION=5.1.0 swift build --product MinimalApp
Building for debugging...
...                                     # ~40 progress lines elided
[75 / 81] SkillSupport
[78 / 81] SkillSupport
[79 / 81] MinimalApp-product
Build complete! (5.36 sec)
```

Offline mode, all three lines:

```
Ditto 5.1.0 opened at /private/var/folders/g0/.../T/ditto-minimal-app-38A3E1F1-C8E5-448A-BC58-D2B45AA87CA3
mode: smallPeersOnly
observed 1 car(s): Toyota
done
```

```
Ditto 5.0.3 opened at /private/var/folders/g0/.../T/ditto-minimal-app-6BEDB64A-AB0B-4F59-8BC2-5062FEDE18D6
mode: smallPeersOnly
observed 1 car(s): Toyota
done
```

```
Ditto 4.14.6 opened at /private/var/folders/g0/.../T/ditto-minimal-app-981D4A7D-AF62-4D77-9CC8-CB3DBEBECAFF
mode: smallPeersOnly
observed 1 car(s): Toyota
done
```

Server mode against a real Ditto Server, 5.1.0 (host redacted):

```
Ditto 5.1.0 opened at /private/var/folders/g0/.../T/ditto-minimal-app-C012E788-2615-4E39-80FF-14B52EA1BF86
mode: server (https://REDACTED.cloud.dittolive.app)
observed 1 car(s): Toyota
done
```

The 4.14.6 build additionally emits one deprecation warning, for the
`disableSyncWithV3()` call that line requires:

```
warning: 'disableSyncWithV3()' is deprecated: `disableSyncWithV3()` will be removed in
SDK 5.0. V3 sync is no longer supported.
```

## Verified on

| Ditto | Host | Toolchain | Modes run |
|---|---|---|---|
| 4.14.6 | macOS 27.0, arm64 | Apple Swift 6.4 (swiftlang-6.4.0.34.1) | offline and server |
| 5.0.3 | macOS 27.0, arm64 | Apple Swift 6.4 (swiftlang-6.4.0.34.1) | offline and server |
| 5.1.0 | macOS 27.0, arm64 | Apple Swift 6.4 (swiftlang-6.4.0.34.1) | offline and server |

The run is checked, not just started: the harness fails unless the output contains the
opened-at line for the requested version, `observed 1 car(s): Toyota`, and `done`.

The same source also compiles for the iOS Simulator, an iOS device, and Mac Catalyst at
all three versions. Nothing here was run on `x86_64`: 5.1.0 ships no Intel slice
([versions.md](versions.md#shipped-xcframework-slices)).
