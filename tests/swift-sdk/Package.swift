// swift-tools-version:6.0
//
// Test fixture for skills/swift-sdk.
//
// The Ditto version under test is selected by the DITTO_SWIFT_VERSION environment
// variable, which is read when SwiftPM evaluates this manifest. Supported values are
// the three lines the skill documents: 4.14.6, 5.0.3 and 5.1.0. All three resolve from
// the same SPM URL, so only the pin changes between runs.
//
//   DITTO_SWIFT_VERSION=5.1.0 ./scripts/run.sh
//
// See README.md for why the framework has to be ad-hoc code signed before the test
// bundle will load.

import PackageDescription
import Foundation

let dittoVersion = ProcessInfo.processInfo.environment["DITTO_SWIFT_VERSION"] ?? "5.1.0"

// 4.14.x is a different API in a handful of places (`activated` vs `isActivated`,
// `disableSyncWithV3()`), so the sources compile against it behind an explicit flag
// rather than by probing for symbols.
let versionFlags: [SwiftSetting] =
    dittoVersion.hasPrefix("4.") ? [.define("DITTO_V4")] : []

let package = Package(
    name: "DittoSwiftSkillTests",
    platforms: [.macOS(.v13), .iOS(.v15), .macCatalyst(.v15)],
    dependencies: [
        .package(
            url: "https://github.com/getditto/DittoSwiftPackage",
            exact: Version(stringLiteral: dittoVersion)
        )
    ],
    targets: [
        .target(
            name: "SkillSupport",
            dependencies: [.product(name: "DittoSwift", package: "DittoSwiftPackage")],
            swiftSettings: versionFlags
        ),
        // UI samples from the skill, compiled for iOS/Catalyst as well as macOS so that
        // the SwiftUI, UIKit and AppKit patterns the skill teaches are type-checked.
        .target(
            name: "UIPatterns",
            dependencies: [
                "SkillSupport",
                .product(name: "DittoSwift", package: "DittoSwiftPackage"),
            ],
            swiftSettings: versionFlags
        ),
        .executableTarget(
            name: "MinimalApp",
            dependencies: [
                "SkillSupport",
                .product(name: "DittoSwift", package: "DittoSwiftPackage"),
            ],
            swiftSettings: versionFlags
        ),
        .executableTarget(
            name: "PersistenceProbe",
            dependencies: [
                "SkillSupport",
                .product(name: "DittoSwift", package: "DittoSwiftPackage"),
            ],
            swiftSettings: versionFlags
        ),
        .testTarget(
            name: "SwiftSDKSkillTests",
            dependencies: [
                "SkillSupport",
                .product(name: "DittoSwift", package: "DittoSwiftPackage"),
            ],
            swiftSettings: versionFlags
        ),
    ]
)
