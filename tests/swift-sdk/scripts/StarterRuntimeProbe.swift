// Compiled together with the canonical StarterApp.swift, never a copied model.
import Foundation
#if DITTO_V4
@preconcurrency import DittoSwift
#else
import DittoSwift
#endif

private struct ProbeFailure: Error { let message: String }

@main
struct StarterRuntimeProbe {
    @MainActor
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw ProbeFailure(message: message) }
    }

    @MainActor
    static func eventually(_ message: String, _ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw ProbeFailure(message: message)
    }

    @MainActor
    static func run() async throws {
        let arguments = CommandLine.arguments
        let config = URL(fileURLWithPath: arguments[1])
        let store = URL(fileURLWithPath: arguments[2], isDirectory: true)
        try require(Ditto.version == arguments[3], "resolved SDK pin differs")

        let missing = StarterModel(configurationURL: nil, persistenceDirectory: store)
        await missing.open()
        try require(!missing.isReady && !missing.isOpening && missing.failure != nil,
                    "missing configuration must leave a retryable failure")
        print("CHECK missing configuration rejected")

        let invalidConfig = config.deletingLastPathComponent().appendingPathComponent("InvalidConfig.plist")
        for values in [["DatabaseID": "invalid-uuid", "OfflineLicense": "unused"],
                       ["DatabaseID": "00000000-0000-0000-0000-000000000000", "OfflineLicense": ""]] {
            try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
                .write(to: invalidConfig)
            let invalid = StarterModel(configurationURL: invalidConfig, persistenceDirectory: store)
            await invalid.open()
            try require(!invalid.isReady && !invalid.isOpening && invalid.failure != nil,
                        "malformed configuration must be rejected before opening")
        }
        print("CHECK malformed UUID and empty license rejected")

        let model = StarterModel(configurationURL: config, persistenceDirectory: store)
        async let first: Void = model.open()
        async let second: Void = model.open()
        _ = await (first, second)
        try require(model.isReady && !model.isOpening && model.failure == nil, "open failed")
        try await eventually("initial observer did not deliver") { model.lastDelivery != "None" }
        try require(model.notes.isEmpty, "isolated store should initially be empty")
        print("CHECK concurrent open and empty observer")

        await model.add(text: "  starter-runtime-first  ")
        try await eventually("nonempty observer failed to deliver the write") {
            model.notes.count == 1 && model.notes[0].text == "starter-runtime-first"
        }
        print("CHECK nonempty observer and local write")

        model.toggleSync()
        try require(!model.syncStarted, "pause did not stop sync")
        await model.add(text: "starter-runtime-offline")
        try await eventually("local write while paused did not deliver") { model.notes.count == 2 }
        model.toggleSync()
        try require(model.syncStarted && model.failure == nil, "resume did not start sync")
        print("CHECK local writes while paused and sync resume")

        model.close()
        try await Task.sleep(for: .milliseconds(100))
        try require(!model.isReady && model.notes.isEmpty && !model.syncStarted,
                    "close did not clear live state")
        let reopened = StarterModel(configurationURL: config, persistenceDirectory: store)
        await reopened.open()
        try require(reopened.isReady && reopened.failure == nil, "store lock not released on close")
        try await eventually("persisted notes not delivered after reopening") { reopened.notes.count == 2 }
        try require(Set(reopened.notes.map(\.text)) == ["starter-runtime-first", "starter-runtime-offline"],
                    "persisted note values differ")
        reopened.close()
        print("CHECK cleanup, lock release and persistence after reopen")
    }

    static func main() async {
        do {
            try await run()
            print("PASS canonical starter runtime")
        } catch let error as ProbeFailure {
            // Assertions use static descriptions; credentials and SDK diagnostics stay private.
            FileHandle.standardError.write(Data("FAIL \(error.message)\n".utf8))
            exit(1)
        } catch {
            FileHandle.standardError.write(Data("FAIL unexpected probe error\n".utf8))
            exit(1)
        }
    }
}
