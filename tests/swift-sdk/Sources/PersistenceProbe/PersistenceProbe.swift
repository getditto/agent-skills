//
// Cross-version persistence probe.
//
// Used by scripts/persistence-matrix.sh to write a document with one Ditto version and
// read it back with another, so the skill's upgrade and rollback claims are executed
// rather than inferred.
//
//   PersistenceProbe write <id> [directory]
//   PersistenceProbe read  <id> [directory]
//
// With no directory the default persistence directory is used, which is what exercises
// the v4 -> v5 legacy-path fallback. Point CFFIXED_USER_HOME at a scratch directory so
// that run does not touch the real home directory.
//

import Foundation

#if DITTO_V4
@preconcurrency import DittoSwift
#else
import DittoSwift
#endif

@main
enum PersistenceProbe {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 3, let mode = Mode(rawValue: arguments[1]) else {
            FileHandle.standardError.write(Data("usage: PersistenceProbe <write|read> <id> [directory]\n".utf8))
            exit(2)
        }
        let id = arguments[2]
        let directory = arguments.count > 3 ? URL(fileURLWithPath: arguments[3]) : nil

        let config = DittoConfig(
            databaseID: ProcessInfo.processInfo.environment["DITTO_DATABASE_ID"]
                ?? DittoConfig.defaultDatabaseID(),
            connect: .smallPeersOnly(),
            persistenceDirectory: directory
        )

        #if DITTO_V4
        if mode == .legacyWrite {
            // The deprecated 4.x identity initializer, used ONLY to create the kind of
            // database a real v4 app left behind: it defaults to
            // <Documents>/ditto, not <Application Support>/ditto-{databaseID}.
            let legacy = Ditto(identity: .offlinePlayground(appID: config.databaseID))
            try legacy.setOfflineOnlyLicenseToken(
                ProcessInfo.processInfo.environment["DITTO_OFFLINE_LICENSE"] ?? ""
            )
            try legacy.disableSyncWithV3()
            print("version=\(Ditto.version)")
            print("directory=\(legacy.absolutePersistenceDirectory.path)")
            try await legacy.store.execute(
                query: "INSERT INTO cars DOCUMENTS (:car)",
                arguments: ["car": ["_id": id, "make": "Toyota", "mileage": 120]]
            )
            print("wrote=\(id)")
            return
        }
        #endif

        let ditto = try await Ditto.open(config: config)
        try ditto.setOfflineOnlyLicenseToken(
            ProcessInfo.processInfo.environment["DITTO_OFFLINE_LICENSE"] ?? ""
        )
        #if DITTO_V4
        try ditto.disableSyncWithV3()
        #endif

        print("version=\(Ditto.version)")
        print("directory=\(ditto.absolutePersistenceDirectory.path)")

        switch mode {
        case .legacyWrite:
            fatalError("legacy-write is only available when built against 4.14.x")
        case .write:
            try await ditto.store.execute(
                query: "INSERT INTO cars DOCUMENTS (:car)",
                arguments: ["car": ["_id": id, "make": "Toyota", "mileage": 120]]
            )
            try await ditto.store.execute(query: "CREATE INDEX cars_mileage ON cars (mileage)")
            print("wrote=\(id)")
        case .read:
            let result = try await ditto.store.execute(
                query: "SELECT * FROM cars WHERE _id = :id",
                arguments: ["id": id]
            )
            print("found=\(result.items.count)")
            if let value = result.items.first?.value {
                print("make=\(value["make"] as? String ?? "?")")
            }
            let indexes = try await ditto.store.execute(query: "SELECT * FROM system:indexes")
            print("indexes=\(indexes.items.count)")
        }
    }

    enum Mode: String {
        case write
        case read
        /// 4.14.x only: write through the deprecated `Ditto(identity:)` initializer.
        case legacyWrite = "legacy-write"
    }
}
