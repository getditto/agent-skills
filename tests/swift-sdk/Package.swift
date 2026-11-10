// swift-tools-version:6.0
//
// Test fixture for skills/swift-sdk.
//
// The Ditto version under test is selected by the DITTO_SWIFT_VERSION environment
// variable, which is read when SwiftPM evaluates this manifest. Supported values are
// 4.14.6, 5.0.3, 5.1.0 and 5.2.0. The 5.2.0 leg also covers raw-key encryption,
// startup parameters and Data Streams. All resolve from the same SwiftPM URL, so
// only the reproducible fixture pin changes between runs.
//
//   DITTO_SWIFT_VERSION=5.1.0 ./scripts/run.sh
//
// See README.md for why the framework has to be ad-hoc code signed before the test
// bundle will load.

import PackageDescription
import Foundation

let dittoVersion = ProcessInfo.processInfo.environment["DITTO_SWIFT_VERSION"] ?? "5.2.0"

// 4.14.x is a different API in a handful of places (`activated` vs `isActivated`,
// `disableSyncWithV3()`), so the sources compile against it behind an explicit flag
// rather than by probing for symbols.
// Data Streams exist in DittoSwift from 5.2.0 only (as `@_spi(PreviewDataStreams)`), so
// Tests/SwiftSDKSkillTests/DataStreamsTests.swift compiles behind DITTO_DATA_STREAMS.
let versionFlags: [SwiftSetting] = {
    if dittoVersion.hasPrefix("4.") { return [.define("DITTO_V4")] }
    if dittoVersion.hasPrefix("5.0.") || dittoVersion.hasPrefix("5.1.") { return [] }
    return [.define("DITTO_DATA_STREAMS")]
}()

let package = Package(
    name: "DittoSwiftSkillTests",
    platforms: [.macOS(.v13), .iOS(.v15), .macCatalyst(.v15)],
    products: [
        // `UIPatterns` MUST be a product. Without one, SwiftPM's auto-generated
        // "-Package" scheme has nothing depending on it, and scripts/build-platforms.sh
        // silently compiles none of the SwiftUI/UIKit/AppKit samples for iOS, the iOS
        // Simulator or Mac Catalyst. Verified by introducing a type error into
        // Sources/UIPatterns and watching the matrix stay green.
        .library(name: "UIPatterns", targets: ["UIPatterns"]),
    ],
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
                // The tests depend on UIPatterns so the observer bridge the skill
                // recommends is exercised at runtime, not only type-checked.
                "UIPatterns",
                .product(name: "DittoSwift", package: "DittoSwiftPackage"),
            ],
            swiftSettings: versionFlags
        ),
    ]
)
