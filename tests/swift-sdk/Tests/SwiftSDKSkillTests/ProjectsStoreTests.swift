// Exercise the actual inline callbacks in the published SwiftUI example. Testing
// ObserverBridge alone misses MainActor isolation inferred at these call sites.
import Foundation
import Testing
import UIPatterns
#if DITTO_V4
@preconcurrency import DittoSwift
#else
import DittoSwift
#endif
@testable import SkillSupport

@Suite("SwiftUI inline observers")
struct ProjectsStoreTests {
    @Test("MainActor stores deliver nonempty project and selected-task snapshots")
    @MainActor
    func inlineObserversDeliverValues() async throws {
        guard #available(macOS 14, *) else { return }
        let peer = try await TestPeer.open()
        defer { peer.tearDown() }
        try await peer.ditto.store.execute(query: "INSERT INTO projects DOCUMENTS (:project)",
            arguments: ["project": ["_id": "project-1", "name": "Observer regression"]])
        try await peer.ditto.store.execute(query: "INSERT INTO tasks DOCUMENTS (:task)",
            arguments: ["task": ["_id": "task-1", "projectId": "project-1", "title": "First task", "isDone": false]])
        let projects = ProjectsStore(ditto: peer.ditto)
        let tasks = ProjectTasksStore()
        defer { tasks.stop(); projects.stop() }
        try projects.start()
        try tasks.start(ditto: peer.ditto, projectID: "project-1")
        for _ in 0..<100 {
            if !projects.projects.isEmpty && !tasks.tasks.isEmpty { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(projects.projects.map(\.name) == ["Observer regression"])
        #expect(tasks.tasks.map(\.title) == ["First task"])
        tasks.stop()
        try tasks.start(ditto: peer.ditto, projectID: "other-project")
        for _ in 0..<100 {
            if tasks.tasks.isEmpty { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(tasks.projectID == "other-project")
        #expect(tasks.tasks.isEmpty)
    }
}
