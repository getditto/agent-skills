//
// Shared helpers for the swift-sdk skill fixture.
//
// Nothing in here is skill content — it is the plumbing that lets the same test
// sources run against Ditto 4.14.6, 5.0.3 and 5.1.0 without a committed token.
//

import Foundation
#if DITTO_V4
// 4.14.x predates the `Sendable` conformances v5 added: in Swift 6 language mode
// `Ditto` and `DittoStore` cannot cross an isolation boundary without this, and the
// build fails with "sending 'ditto' risks causing data races".
@preconcurrency import DittoSwift
#else
import DittoSwift
#endif

public enum SkillTestEnvironment {
    /// Offline-only license token, required before a `.smallPeersOnly` instance will
    /// accept any work. Supplied by the gitignored repo-root `.env` (or CI secret) as
    /// `DITTO_OFFLINE_LICENSE`; never committed.
    public static var offlineLicense: String {
        get throws {
            try required("DITTO_OFFLINE_LICENSE")
        }
    }

    /// Optional: a real database ID from the portal. Falls back to the SDK's own
    /// all-zero default, which is what an offline-only peer uses when it has no
    /// portal database of its own.
    public static var databaseID: String {
        ProcessInfo.processInfo.environment["DITTO_DATABASE_ID"]?.nonEmpty
            ?? DittoConfig.defaultDatabaseID()
    }

    /// Portal "Connect via SDK" URL, used only by the online-authentication test.
    public static var serverURL: URL? {
        ProcessInfo.processInfo.environment["DITTO_URL"]?.nonEmpty.flatMap(URL.init(string:))
    }

    /// Development-provider token, used only by the online-authentication test.
    public static var developmentToken: String? {
        ProcessInfo.processInfo.environment["DITTO_TOKEN"]?.nonEmpty
    }

    /// The Ditto version this build was pinned to, as reported by the manifest.
    /// Compared against `Ditto.version` so a stale `.build` directory cannot silently
    /// make a run report the wrong line.
    public static var expectedVersion: String? {
        ProcessInfo.processInfo.environment["DITTO_SWIFT_VERSION"]?.nonEmpty
    }

    public static func required(_ key: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[key]?.nonEmpty else {
            throw SkillTestError.missingEnvironment(key)
        }
        return value
    }
}

public enum SkillTestError: Error, CustomStringConvertible {
    case missingEnvironment(String)

    public var description: String {
        switch self {
        case .missingEnvironment(let key):
            return "Missing required environment variable \(key). Copy .env-sample to .env at the repo root and fill it in."
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
