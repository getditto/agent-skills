# A SwiftUI app — Ditto Swift SDK

## Contents

- [What it shows](#what-it-shows)
- [Requirements](#requirements)
- [Program](#program)
- [Wiring it to an `App`](#wiring-it-to-an-app)
- [Verified on](#verified-on)

Two screens. The list is driven by an **app-lived** observer; the detail screen creates
its observer **when a project is selected** and cancels it **when the screen goes away**.
That per-selection lifetime is the shape most Ditto apps need and the one most often got
wrong, so it is the point of this example.

This is a copy of `Sources/UIPatterns/ProjectsApp.swift` in the fixture. A plugin user has
no `tests/` tree to open, so the program is restated here in full;
`scripts/validate-sdk-skills.py` fails the build if the two ever differ by a byte.

## What it shows

| | |
|---|---|
| One long-lived `Ditto` | `ProjectsStore` owns it; everything else borrows it through `.environment` |
| Subscriptions vs observers | both subscriptions registered once; an observer alone would show only what this device already has |
| App-lived observer | all projects, registered in `start()`, lives as long as the store |
| **Per-selection observer** | `ProjectTasksStore`, started in `.onAppear`, cancelled in `.onDisappear` |
| Writes go through the store | `addProject` inserts and does **not** touch `projects`; the observer delivers it back |
| Bounded stream, one consumer | `.bufferingNewest(1)` plus a single `for await`, per [observers.md](../references/observers.md) |

## Requirements

iOS 17 / macOS 14 for `@Observable`. The SDK itself supports iOS 15 — see
[setup.md](../references/setup.md) — so on an older floor use `ObservableObject`,
`@StateObject` and `.environmentObject`, and keep every other line the same.

**Your app target must not disable code signing.** The published XCFramework ships
unsigned; if nothing re-signs it the app builds cleanly and then dies at launch. See
[setup.md](../references/setup.md#code-signing-and-the-embedded-xcframework).

## Program

```swift
#if canImport(SwiftUI)
import SwiftUI
import Foundation

#if DITTO_V4
@preconcurrency import DittoSwift
#else
import DittoSwift
#endif

// MARK: - Model

/// Extracted inside the observer callback: `DittoQueryResultItem.value` is
/// `[String: Any?]`, which is not `Sendable` and must not cross an isolation boundary.
///
/// Non-failable on purpose — a malformed document from any peer at any schema version
/// should render as a row you can see and fix, not vanish from the list.
public struct Project: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String

    public init(_ value: [String: Any?]) {
        // Collapse the outer dictionary optional explicitly before casting.
        // Swift's conditional cast can also unwrap these nested optionals.
        self.id = (value["_id"] ?? nil) as? String ?? ""
        self.name = (value["name"] ?? nil) as? String ?? "Untitled"
    }
}

public struct ProjectTask: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let isDone: Bool

    public init(_ value: [String: Any?]) {
        self.id = (value["_id"] ?? nil) as? String ?? ""
        self.title = (value["title"] ?? nil) as? String ?? "Untitled"
        // `as? Bool` is correct and sufficient. Unlike NUMBERS — which arrive as the
        // narrowest CBOR type that holds them, so `as? Int` silently drops rows — a
        // boolean round-trips as a plain `Bool` on all three lines.
        self.isDone = (value["isDone"] ?? nil) as? Bool ?? false
    }
}

// MARK: - The app-lived store

/// Owns the ONE long-lived `Ditto` reference, the subscriptions, and the observer that
/// every screen reads from. Injected with `.environment` at the composition root.
@available(iOS 17, macOS 14, macCatalyst 17, *)
@MainActor
@Observable
public final class ProjectsStore {
    public private(set) var projects: [Project] = []

    public let ditto: Ditto
    private var subscriptions: [DittoSyncSubscription] = []
    private var observer: DittoStoreObserver?
    private var consumer: Task<Void, Never>?

    public init(ditto: Ditto) { self.ditto = ditto }

    /// Registers the subscriptions and the all-projects observer. Idempotent.
    public func start() throws {
        guard observer == nil else { return }

        // A subscription asks other peers for data. An observer reads the local store.
        // You need both: an observer alone shows only what this device already has.
        subscriptions = [
            try ditto.sync.registerSubscription(query: "SELECT * FROM projects"),
            try ditto.sync.registerSubscription(query: "SELECT * FROM tasks"),
        ]

        let (stream, continuation) = AsyncStream<[Project]>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let registered = try ditto.store.registerObserver(
            query: "SELECT * FROM projects ORDER BY name"
        ) { @Sendable result in
            continuation.yield(result.items.map { item in
                defer { item.dematerialize() }
                return Project(item.value)
            })
        }
        continuation.onTermination = { [weak registered] _ in registered?.cancel() }
        observer = registered

        // ONE consumer. A `Task { @MainActor in … }` per delivery has no ordering
        // relation between deliveries, so a burst can apply out of order.
        consumer = Task { @MainActor [weak self] in
            for await next in stream { self?.projects = next }
        }
    }

    public func addProject(named name: String) async throws {
        try await ditto.store.execute(
            query: "INSERT INTO projects DOCUMENTS (:project)",
            arguments: ["project": ["_id": UUID().uuidString, "name": name]]
        )
        // No local mutation of `projects`. The observer delivers the write back, which
        // is what proves the round trip and keeps every peer's UI on the same path.
    }

    public func stop() {
        consumer?.cancel()
        observer?.cancel()
        subscriptions.forEach { $0.cancel() }
        subscriptions = []
        observer = nil
    }
}

// MARK: - The per-selection store

/// Created when a project is selected and torn down when the screen goes away.
///
/// `@Observable` + `@State` needs a no-argument `init`, but the `Ditto` handle and the
/// project id only exist once a row is tapped — so this starts empty and is STARTED on
/// appear. That is the shape, and it is why `start` has to be idempotent: `.onAppear`
/// can run more than once for the same screen.
@available(iOS 17, macOS 14, macCatalyst 17, *)
@MainActor
@Observable
public final class ProjectTasksStore {
    public private(set) var tasks: [ProjectTask] = []
    public private(set) var projectID: String?

    private var observer: DittoStoreObserver?
    private var consumer: Task<Void, Never>?

    public init() {}

    public func start(ditto: Ditto, projectID: String) throws {
        // Idempotent for the SAME project, and re-targets for a different one.
        if self.projectID == projectID, observer != nil { return }
        stop()
        self.projectID = projectID

        let (stream, continuation) = AsyncStream<[ProjectTask]>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let registered = try ditto.store.registerObserver(
            query: "SELECT * FROM tasks WHERE projectId = :projectId ORDER BY isDone, title",
            arguments: ["projectId": projectID]
        ) { @Sendable result in
            continuation.yield(result.items.map { item in
                defer { item.dematerialize() }
                return ProjectTask(item.value)
            })
        }
        continuation.onTermination = { [weak registered] _ in registered?.cancel() }
        observer = registered

        consumer = Task { @MainActor [weak self] in
            for await next in stream { self?.tasks = next }
        }
    }

    /// Cancelling is what stops an observer — dropping the handle does not. An
    /// uncancelled per-screen observer keeps decoding results, and keeps its closure's
    /// captures alive, for the whole life of the `Ditto` instance.
    public func stop() {
        consumer?.cancel()
        consumer = nil
        observer?.cancel()
        observer = nil
        projectID = nil
        tasks = []
    }
}

// MARK: - Views

@available(iOS 17, macOS 14, macCatalyst 17, *)
public struct ProjectsScreen: View {
    @Environment(ProjectsStore.self) private var store

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if store.projects.isEmpty {
                    ContentUnavailableView("No projects", systemImage: "folder")
                } else {
                    List(store.projects) { project in
                        NavigationLink(project.name) {
                            TasksScreen(project: project)
                        }
                    }
                }
            }
            .navigationTitle("Projects")
        }
    }
}

@available(iOS 17, macOS 14, macCatalyst 17, *)
public struct TasksScreen: View {
    let project: Project

    @Environment(ProjectsStore.self) private var store
    // `@State`, so the store is created once for this screen and released with it.
    @State private var tasks = ProjectTasksStore()
    @State private var failure: String?

    public init(project: Project) { self.project = project }

    public var body: some View {
        List {
            if let failure {
                Text(failure).foregroundStyle(.red)
            }
            ForEach(tasks.tasks) { task in
                Label(task.title, systemImage: task.isDone ? "checkmark.circle.fill" : "circle")
            }
        }
        .navigationTitle(project.name)
        // `.onAppear` / `.onDisappear`, NOT `deinit`: a `@MainActor @Observable` class
        // cannot cancel from `deinit` under Swift 6 without isolated-deinit gymnastics,
        // because `deinit` is nonisolated and the observer handle is actor-isolated.
        // The view's appearance is the scope that owns this observer, so bind to it.
        .onAppear {
            do { try tasks.start(ditto: store.ditto, projectID: project.id) }
            catch { failure = error.localizedDescription }
        }
        .onDisappear { tasks.stop() }
    }
}
#endif
```

## Wiring it to an `App`

Open Ditto before rendering this, and hold the phase in a composition root — the pattern
in [best-practices.md](../best-practices.md#instance-ownership). Sketch:

```swift
@main
struct ProjectsApp: App {
    @State private var store: ProjectsStore?

    var body: some Scene {
        WindowGroup {
            if let store {
                ProjectsScreen().environment(store)
            } else {
                ProgressView().task {
                    // Ditto.open is nonisolated, so awaiting it here does not block the
                    // main thread — references/connect.md#open-versus-opensync.
                    let ditto = try? await Ditto.open(config: myConfig)
                    guard let ditto else { return }
                    let created = ProjectsStore(ditto: ditto)
                    try? created.start()
                    store = created
                }
            }
        }
    }
}
```

That sketch is deliberately minimal: it has no retry, no failure surface and no
authentication. Production forms of all three — a phase machine, a bounded login, a
re-authentication handler that retries — are in
[connect.md](../references/connect.md#cap-04-authentication-and-identity) and
[best-practices.md](../best-practices.md#instance-ownership).

## Verified on

Compiled for macOS, iOS Simulator, iOS device and Mac Catalyst against Ditto **4.14.6**,
**5.0.3** and **5.1.0** — twelve builds, on every change.

`ProjectsStoreTests` executes the actual project/task observer callbacks on `MainActor`
with nonempty rows. Separate tests cover the bridge, bounded buffering, `onTermination`
and cancellation. **No test drives a real SwiftUI view** or asserts `.onDisappear`
delivery; see the remaining scope in [`README.md`](../README.md).
