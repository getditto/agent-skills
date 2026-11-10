#if DITTO_DATA_STREAMS
import Foundation
import Testing
import DittoSwift
@testable import SkillSupport

@Suite("SDK 5.2 encryption, configuration and binding")
struct SDK52Tests {
    private func config(_ directory: URL, key: Data? = nil) throws -> DittoConfig {
        var config = DittoConfig(databaseID: SkillTestEnvironment.databaseID,
                                 connect: .smallPeersOnly(), persistenceDirectory: directory,
                                 systemParameters: ["transports_websocket_so_keepalive_idle_secs": .int64(60)])
        if let key { config.encryptionKey = try DittoEncryptionKey.raw(key) }
        return config
    }

    @Test("encrypted store reopens with its key, rejects wrong/missing keys and can be deleted after release")
    func encryptedLifecycle() async throws {
        let directory = TestPeer.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = Data(repeating: 0x51, count: 32) // Fixed test key; never application guidance.
        let configuration = try config(directory, key: key)
        var instance: Ditto? = try await Ditto.open(config: configuration)
        try instance!.setOfflineOnlyLicenseToken(SkillTestEnvironment.offlineLicense)
        #expect(instance!.isEncrypted)
        try await instance!.store.execute(query: "INSERT INTO secret DOCUMENTS ({'_id':'one','value':'persisted'})")
        #expect(throws: (any Error).self) {
            try Ditto.deleteStore(databaseID: SkillTestEnvironment.databaseID, persistenceDirectory: directory)
        }
        instance = nil
        for (bytes, reason) in [(nil, DittoError.EncryptionErrorReason.keyRequired),
                                (Data(repeating: 0x52, count: 32), .keyInvalid)] {
            do {
                let unexpected = try await Ditto.open(config: config(directory, key: bytes))
                _ = unexpected
                Issue.record("Opening encrypted store should fail")
            } catch let error as DittoError {
                guard case .encryptionError(let actual) = error else { throw error }
                #expect(actual == reason)
            }
        }
        instance = try await Ditto.open(config: configuration)
        try instance!.setOfflineOnlyLicenseToken(SkillTestEnvironment.offlineLicense)
        let result = try await instance!.store.execute(query: "SELECT * FROM secret")
        #expect(result.items.first?.value["value"] as? String == "persisted")
        instance = nil
        try Ditto.deleteStore(databaseID: SkillTestEnvironment.databaseID, persistenceDirectory: directory)
        instance = try await Ditto.open(config: config(directory))
        try instance!.setOfflineOnlyLicenseToken(SkillTestEnvironment.offlineLicense)
        #expect(!instance!.isEncrypted)
        #expect(try await instance!.store.execute(query: "SELECT * FROM secret").items.isEmpty)
        instance = nil
    }

    @Test("JSONSerialization booleans remain booleans and startup parameter is effective")
    func bindingAndStartup() async throws {
        let directory = TestPeer.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ditto = try await Ditto.open(config: config(directory))
        try ditto.setOfflineOnlyLicenseToken(SkillTestEnvironment.offlineLicense)
        let arguments = try JSONSerialization.jsonObject(with: Data(#"{"doc":{"_id":"one","enabled":true}}"#.utf8)) as! [String: Any]
        try await ditto.store.execute(query: "INSERT INTO flags DOCUMENTS (:doc)", arguments: arguments)
        let result = try await ditto.store.execute(query: "SELECT * FROM flags WHERE enabled = true")
        #expect(result.items.count == 1)
        let parameter = try await ditto.store.execute(query: "SHOW transports_websocket_so_keepalive_idle_secs")
        #expect((parameter.items.first?.value["transports_websocket_so_keepalive_idle_secs"] as? NSNumber)?.intValue == 60)
        #expect(throws: (any Error).self) { try DittoEncryptionKey.raw(Data(repeating: 0, count: 31)) }
    }

    @Test("invalid startup parameters fail at open")
    func invalidStartup() async throws {
        let directory = TestPeer.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var configuration = try config(directory)
        configuration.systemParameters = ["not_a_ditto_system_parameter": .bool(true)]
        await #expect(throws: (any Error).self) { try await Ditto.open(config: configuration) }
    }
}
#endif
