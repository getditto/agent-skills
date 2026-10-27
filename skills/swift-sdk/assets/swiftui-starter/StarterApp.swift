import SwiftUI
import Foundation
import Combine
#if DITTO_V4
@preconcurrency import DittoSwift
#else
import DittoSwift
#endif

struct Note: Identifiable, Sendable {
    let id: String
    let text: String
}

@MainActor
final class StarterModel: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published private(set) var status = "Not opened"
    @Published private(set) var failure: String?
    @Published private(set) var isOpening = false
    @Published private(set) var syncStarted = false
    @Published private(set) var peerCount = 0
    @Published private(set) var connectionTypes = "None observed"
    @Published private(set) var localPeer = "Not opened"
    @Published private(set) var lastDelivery = "None"
    @Published private(set) var storePath = "Not opened"
    private var ditto: Ditto?
    private var observer: DittoStoreObserver?
    private var subscription: DittoSyncSubscription?
    private var continuation: AsyncStream<[Note]>.Continuation?
    private var consumer: Task<Void, Never>?
    private let configurationURL: URL?
    private let persistenceDirectory: URL?

    init(configurationURL: URL? = Bundle.main.url(forResource: "LocalConfig", withExtension: "plist"),
         persistenceDirectory: URL? = nil) {
        self.configurationURL = configurationURL
        self.persistenceDirectory = persistenceDirectory
    }

    var isReady: Bool { ditto != nil }

    func open() async {
        guard ditto == nil, !isOpening else { return }
        isOpening = true
        failure = nil
        defer { isOpening = false }
        var opened: Ditto?
        do {
            guard let url = configurationURL,
                  let values = NSDictionary(contentsOf: url) as? [String: String],
                  let databaseID = values["DatabaseID"], UUID(uuidString: databaseID) != nil,
                  let license = values["OfflineLicense"], !license.isEmpty else {
                throw StarterFailure.configuration
            }
            let directory = try persistenceDirectory ?? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            ).appendingPathComponent(Bundle.main.bundleIdentifier ?? "DittoStarter", isDirectory: true)
                .appendingPathComponent("Ditto", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            DittoLogger.isEnabled = true
            DittoLogger.minimumLogLevel = .warning
            let instance = try await Ditto.open(config: DittoConfig(
                databaseID: databaseID, connect: .smallPeersOnly(), persistenceDirectory: directory
            ))
            opened = instance
            try instance.setOfflineOnlyLicenseToken(license)
            #if DITTO_V4
            try instance.disableSyncWithV3()
            #endif
            // The demo's small, unfiltered collection is intentional. Scope production
            // subscriptions to the documents the screen actually needs.
            subscription = try instance.sync.registerSubscription(query: "SELECT * FROM notes")
            let (stream, output) = AsyncStream<[Note]>.makeStream(bufferingPolicy: .bufferingNewest(1))
            continuation = output
            let registered = try instance.store.registerObserver(
                query: "SELECT * FROM notes ORDER BY _id"
            ) { @Sendable result in
                // SDK 5.0.x can deliver off-main even with the default queue. An
                // explicitly Sendable handler prevents inherited MainActor isolation.
                let snapshot = result.items.map { item in
                    defer { item.dematerialize() }
                    return Note(id: (item.value["_id"] ?? nil) as? String ?? "",
                                text: (item.value["text"] ?? nil) as? String ?? "Untitled")
                }
                output.yield(snapshot)
            }
            output.onTermination = { [weak registered] _ in registered?.cancel() }
            observer = registered
            try instance.sync.start()
            ditto = instance
            storePath = directory.path
            status = "Local store ready"
            consumer = Task { @MainActor [weak self] in
                for await snapshot in stream {
                    self?.notes = snapshot
                    self?.lastDelivery = Date().formatted()
                }
            }
            refreshDiagnostics()
        } catch {
            consumer?.cancel()
            observer?.cancel()
            continuation?.finish()
            subscription?.cancel()
            consumer = nil
            observer = nil
            continuation = nil
            subscription = nil
            opened?.sync.stop()
            opened = nil
            failure = error.localizedDescription
            status = "Open failed"
        }
    }

    func add(text: String) async {
        guard let ditto else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            try await ditto.store.execute(query: "INSERT INTO notes DOCUMENTS (:note)",
                arguments: ["note": ["_id": UUID().uuidString, "text": text]])
            // The observer updates the list; this deliberately exercises the write/read path.
            failure = nil
        } catch { failure = error.localizedDescription }
    }

    func toggleSync() {
        guard let ditto else { return }
        do {
            if ditto.sync.isActive { ditto.sync.stop() }
            else { try ditto.sync.start() }
            failure = nil
        } catch { failure = error.localizedDescription }
        refreshDiagnostics()
    }

    func refreshDiagnostics() {
        guard let ditto else { return }
        let graph = ditto.presence.graph
        syncStarted = ditto.sync.isActive
        localPeer = graph.localPeer.deviceName
        peerCount = graph.remotePeers.count
        connectionTypes = Set(graph.allConnectionsByID().values.map { String(describing: $0.type) })
            .sorted().joined(separator: ", ")
        if connectionTypes.isEmpty { connectionTypes = "None observed" }
    }

    func close() {
        consumer?.cancel()
        consumer = nil
        observer?.cancel()
        observer = nil
        continuation?.finish()
        continuation = nil
        subscription?.cancel()
        subscription = nil
        ditto?.sync.stop()
        ditto = nil
        notes = []
        syncStarted = false
        peerCount = 0
        connectionTypes = "None observed"
        status = "Closed; stored notes retained"
    }
}

enum StarterFailure: LocalizedError {
    case configuration
    var errorDescription: String? {
        "Set DatabaseID and OfflineLicense in App/LocalConfig.plist, then rebuild. See README.md."
    }
}

struct StarterView: View {
    @ObservedObject var model: StarterModel
    @State private var text = ""
    @State private var diagnostics = false

    var body: some View {
        NavigationView {
            VStack {
                if let failure = model.failure { Text(failure).foregroundColor(.red).padding() }
                if model.isReady {
                    HStack {
                        TextField("Write a note", text: $text)
                        Button("Add") {
                            let submitted = text
                            Task { await model.add(text: submitted) }
                            text = ""
                        }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }.padding()
                    List(model.notes) { note in Text(note.text) }
                } else {
                    Text(model.status).padding()
                    Button(model.isOpening ? "Opening…" : "Open local store") {
                        Task { await model.open() }
                    }.disabled(model.isOpening)
                }
            }
            .navigationTitle("Ditto Notes")
            .toolbar { Button("Diagnostics") { diagnostics = true } }
            .sheet(isPresented: $diagnostics) { DiagnosticsView(model: model) }
        }
        .task { await model.open() }
    }
}

struct DiagnosticsView: View {
    @ObservedObject var model: StarterModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack {
            Form {
                Section(header: Text("Local store")) {
                    Text(model.status)
                    Text("Documents displayed: \(model.notes.count)")
                    Text("Last observer delivery: \(model.lastDelivery)")
                    Text(model.storePath).font(.caption).textSelection(.enabled)
                }
                Section(header: Text("Mesh — refresh for a current snapshot")) {
                    Text("Sync requested: \(model.syncStarted ? "yes" : "no")")
                    Text("Reachable remote peers: \(model.peerCount)")
                    Text("Observed connections: \(model.connectionTypes)")
                    Text("Local device: \(model.localPeer)")
                    Text("Sync requested does not prove connectivity or delivery.").font(.caption)
                    Button("Refresh diagnostics") { model.refreshDiagnostics() }
                    Button(model.syncStarted ? "Pause sync (simulation)" : "Resume sync") {
                        model.toggleSync()
                    }.disabled(!model.isReady)
                }
                if let failure = model.failure {
                    Section(header: Text("Last operation error")) { Text(failure).foregroundColor(.red) }
                }
                Section(header: Text("Ownership")) {
                    Button("Close local store") { model.close() }.disabled(!model.isReady)
                    Text("Closing retains data. Reopening creates one new instance; it does not erase the store.")
                        .font(.caption)
                }
            }
            Button("Done") { dismiss() }.padding()
        }.frame(minWidth: 300, minHeight: 400)
        .onAppear { model.refreshDiagnostics() }
    }
}

#if !DITTO_STARTER_TESTING
@main
struct DittoStarterApp: App {
    @StateObject private var model = StarterModel()
    var body: some Scene { WindowGroup { StarterView(model: model) } }
}
#endif
