---
name: swift-sdk
description: >
  Use ONLY for the Ditto Swift SDK (not Kotlin, Java, JS, C#, C++, Rust, Flutter or Go —
  each has its own skill). Triggers on .swift files, Package.swift, .xcodeproj/.xcworkspace,
  DittoSwiftPackage, `import DittoSwift`, DittoConfig, Ditto.open, registerObserver,
  DittoDiffer, and the errors "storeError(reason: .queryNotSupported", "sending 'ditto'
  risks causing data races" and "persistenceDirectoryLocked". iOS, iPadOS, macOS/AppKit
  and Mac Catalyst. Ditto SDK 4.14.x, 5.0.x, 5.1.x.
allowed-tools: Read, Grep, Glob, Edit, Write
---

# Ditto Swift SDK

Ditto is an offline-first, peer-to-peer database. The Swift SDK puts it in an iOS, iPadOS,
macOS or Mac Catalyst app: one app-lived `Ditto` instance owns a local store, a sync
session and a mesh presence, and the app reads through DQL queries and store observers
rather than network calls.

Three things make Swift different from the other eight SDKs, and are where this skill
spends its budget: **object lifetime** (using an aggregate after its `Ditto` is released
is a `fatalError`), **Swift 6 concurrency** (observer callbacks are not
main-actor-isolated, and `deliverOn:` is ignored on 5.0.x), and **result decoding**
(`[String: Any?]` is not `Sendable`, and a number's Swift type depends on its value).

## What this skill does

Writes and reviews Ditto **Swift** code — API shape, initialization, object lifetimes,
threading, error types and Xcode/SwiftPM build configuration — for
`https://github.com/getditto/DittoSwiftPackage`. Covers Ditto SDK **4.14.x (LTS), 5.0.x
and 5.1.x** across iOS, iPadOS, macOS (AppKit) and Mac Catalyst, with SwiftUI, UIKit and
AppKit.

## When to use this skill

Use it for Swift Ditto code. Hand off rather than restating; each row names a public docs
URL because the concept skill ships as a separate plugin and may not be installed:

| Question | Skill, if installed | Otherwise |
|---|---|---|
| DQL syntax, operators, statement semantics | `dql` | <https://docs.ditto.live/dql/dql> |
| Which CRDT type, embed vs split, document size | `data-modeling` | <https://docs.ditto.live/key-concepts> |
| What a subscription is, mesh propagation | `sync-subscriptions` | <https://docs.ditto.live/sdk/latest/sync/syncing-data> |
| Transport selection strategy, platform radios | `ditto-mesh-networking` | <https://docs.ditto.live/sdk/latest/sync/customizing-transport-configurations> |
| The v4 → v5 migration procedure | — | <https://docs.ditto.live/sdk/latest/migration-guides/swift-v4> and <https://docs.ditto.live/sdk/latest/migration-guides/swift-dql> |

This skill writes the `Info.plist` keys and entitlements an app needs — build
configuration — but does not restate which platform carries which radio. Do **not** use it
for the Kotlin, Java, JavaScript/React Native, C#, C++, Rust, Flutter or Go SDKs.

## Supported versions and packages

Package: `https://github.com/getditto/DittoSwiftPackage` (SwiftPM), product `DittoSwift`.
Published API reference for 5.1.0:
<https://software.ditto.live/swift/DittoSwift/5.1.0/api-reference/documentation/dittoswift/>
— the host path is version-gated and the 4.14.x reference is a different shape; see
[`references/versions.md`](references/versions.md#published-api-reference).

**[`references/versions.md`](references/versions.md) owns every fact that differs across
version lines** — package shape, platform minimums, shipped architectures, API renames,
concurrency behaviour and on-disk migration. This section is a pointer, not a claim.

**When the project's version cannot be determined, emit 5.1.x code and say which version
you assumed** — look in `Package.resolved` or the Xcode package pin first, or ask. v4 and
v5 are different APIs, not two versions of one.

## Capability exceptions

| ID | Capability | Support | Detail |
|----|-----------|---------|--------|
| CAP-03 | Connecting: config, opening, persistence directory | preview | On **4.14.x only**, `DittoConfig` and `Ditto.open`/`openSync` are labelled preview (`sdk/v4/release-notes/swift.mdx:419,421`); there is no opt-in flag, just the type. They are GA on 5.0.x and 5.1.x, and this skill recommends them on all three lines because the alternative — the identity initializer — is deprecated on 4.14.x and removed in v5. |
| CAP-04 | Authentication and identity | preview | On **4.14.x only**, `DittoAuthenticator`, `DittoAuthenticationProvider`, `DittoAuthenticationExpirationHandler` and `DittoAuthenticator.expirationHandler` are labelled preview (`sdk/v4/release-notes/swift.mdx:423,425,429`), replacing the phased-out `DittoAuthenticationDelegate`. No opt-in flag. All are GA on 5.0.x and 5.1.x. |
| CAP-13 | Presence graph and connection requests | partial | The graph, peer metadata and `presence.observe` are fully available and executed. The **connection-request path** (`presence.connectionRequestHandler`) needs a second peer and could not be executed here; it is documented from SDK source. |
| CAP-20 | Preview and platform-specific APIs | preview | `DittoConfigExperimental.passphrase` carries the SDK's own "should not be used in production" warning; `DittoMulticastBetaConfig` / `DittoPeerToPeer.multicastBeta` are **5.1.0-only private beta**, off by default, iOS/macOS only, and need Apple's restricted `com.apple.developer.networking.multicast` entitlement. Data Streams is **not exposed by the Swift SDK** — `sdk/latest/sync/data-streams.mdx` is Kotlin-only. Detail: [references/preview.md](references/preview.md). |


## Minimum viable app

```swift
import DittoSwift
import Foundation  // v5 does not re-export Foundation

@MainActor
final class CarsModel: ObservableObject {
    @Published private(set) var makes: [String] = []
    private var ditto: Ditto?
    private var subscription: DittoSyncSubscription?
    private var observer: DittoStoreObserver?
    private var consumer: Task<Void, Never>?

    func start() async throws {   // call from SwiftUI's .task, not from App.init
        let ditto = try await Ditto.open(config: DittoConfig(
            databaseID: "REPLACE_ME_WITH_YOUR_DATABASE_ID",
            connect: .server(url: URL(string: "REPLACE_ME_WITH_YOUR_CONNECT_URL")!)
        ))
        self.ditto = ditto

        // Install the handler BEFORE sync.start(), or start throws
        // DittoError.authenticationError(.expirationHandlerMissing).
        ditto.auth?.expirationHandler = { ditto, _ in
            ditto.auth?.login(token: "REPLACE_ME_WITH_YOUR_TOKEN", provider: .development) { _, _ in }
        }
        try ditto.sync.start()

        let query = "SELECT * FROM cars WHERE mileage > :minimumMileage ORDER BY mileage"
        let arguments: [String: Any?] = ["minimumMileage": 100]
        subscription = try ditto.sync.registerSubscription(query: query, arguments: arguments)

        // One bounded stream, one consumer: ordered, unlike a Task per delivery.
        let (updates, continuation) = AsyncStream<[String]>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let observer = try ditto.store.registerObserver(query: query, arguments: arguments) { result in
            continuation.yield(result.items.compactMap { item in
                defer { item.dematerialize() }
                return item.value["make"] as? String   // [String: Any?] is not Sendable
            })
        }
        self.observer = observer
        continuation.onTermination = { _ in observer.cancel() }
        consumer = Task { @MainActor [weak self] in
            for await makes in updates { self?.makes = makes }
        }

        try await ditto.store.execute(
            query: "INSERT INTO cars DOCUMENTS (:car)",
            arguments: ["car": ["_id": "car-1", "make": "Toyota", "mileage": 120]]
        )
    }

    // Teardown is the reverse: consumer?.cancel(); observer?.cancel();
    // subscription?.cancel(); ditto?.sync.stop(). See §Object lifetimes.
}
```

Complete program, twenty-row capability map, and real build-and-run transcripts:
[`examples/minimal-app.md`](examples/minimal-app.md) and [`README.md`](README.md).

## Concurrency and threading model

| API | Where its callback runs |
|---|---|
| `Ditto.open(config:)`, `store.execute(query:arguments:)` | `async throws`; resume on the caller's executor |
| `Ditto.openSync(config:)` | `throws`; **blocks** — never on an iOS app's main thread |
| `store.registerObserver(…, deliverOn:)`, `store.fetchAttachment(…, deliverOn:)` | the given `DispatchQueue`, default `.main` — **`registerObserver` ignores it on 5.0.x** |
| `sync.registerSubscription` | synchronous, `throws`; no callback |
| `presence.observe(didChangeHandler:)`, `DittoLogger.setCustomLogCallback` | an SDK thread; not `@Sendable`, not main-queue-guaranteed |
| `auth.login(…, completion:)` | an SDK thread; the completion **is** `@Sendable` on 5.0.x and 5.1.x, and is not on 4.14.x |
| `auth.expirationHandler`, `presence.connectionRequestHandler` | `@Sendable`, `async`, off the main actor |

Rules that follow from that table:

1. **Never assume a callback is on the main actor.** `deliverOn:` is honoured on 4.14.6
   and 5.1.0 and silently ignored on 5.0.3, where using it with Swift concurrency is a
   documented crash (#SDKS-3856). Hop explicitly inside the handler and one source file
   is correct on all three lines.
2. **Convert before you cross.** `DittoQueryResultItem.value` is `[String: Any?]`, which
   is not `Sendable`. Extract into a value type *inside* the callback and send that.
3. **Do the expensive work in the callback, not after the hop.** Decoding, diffing and
   sorting belong off the main actor; only the final assignment is main-actor work.
4. **Hop with one consumer, not one `Task` per delivery.** Unstructured `Task`s have no
   ordering guarantee, so a burst can apply out of order and leave the UI on a stale
   result. Yield into an `AsyncStream(bufferingPolicy: .bufferingNewest(1))` and drain it
   from a single long-lived `@MainActor` task.
5. **Do not wrap `Ditto` in an actor.** `Ditto` and `DittoStore` are `Sendable` on v5;
   an actor adds hops without adding safety. Use actors for your own mutable async state.
6. **On 4.14.x, `@preconcurrency import DittoSwift`** — that line predates the `Sendable`
   conformances, and Swift 6 language mode rejects the same code without it.
7. **`signalNext()` must be called exactly once per delivery**, from whichever context
   finishes the work; put the `defer` first in the hopped body.
8. **`auth.expirationHandler` must not touch UI state** — it is `@Sendable`, `async`, and
   runs off the main actor.

## Object lifetimes and retention

**Hold exactly one long-lived strong reference to `Ditto`, at the application composition
root.** `store`, `sync`, `presence`, `auth`, `diskUsage`, `smallPeerInfo` and
`experimental` hold a **weak** reference to their parent, so retaining only `ditto.store`
does not keep `ditto` alive.

| Handle | Retain it | Symptom if you get it wrong |
|---|---|---|
| `Ditto` | for the app's lifetime | The next call through any aggregate is `fatalError("… the corresponding `Ditto` is `nil` …")` — a crash, not a catchable error. On 4.14.6 two of those paths, `store.registerObserver` and `store.execute`, throw `useAfterCloseError` instead; everything else crashes on every line. |
| `DittoStoreObserver`, `DittoSyncSubscription` | for the scope that consumes it, **so you can cancel it** | Dropping the handle does **not** stop it: the observer keeps firing and keeps its closure's captures alive for the whole `Ditto` lifetime, and the subscription stays registered. You have only lost the ability to cancel. |
| `DittoAttachmentFetcher` | until the fetch completes or you `stop()` it | An abandoned fetch keeps running. Its parent reference is weak, so stopping it late is a no-op, not a crash. |
| `DittoObserver` (presence, auth status), `DittoDiskUsageObserver` | for the scope that consumes it | Stopped with `stop()`, not `cancel()` — and disk usage returns its own type. |
| `AnyCancellable` (the four Combine publishers) | for the scope that consumes it | Releasing it *does* cancel — the opposite of the observer handles. |

Cancel at the owning scope's boundary — `deinit`, `viewDidDisappear`, `.onDisappear` — and
use `[weak self]` in callback closures. **Do not cache `ditto.sync.subscriptions` or
`ditto.store.observers`**: both are *computed* in v5, so a snapshot goes stale silently.
There is no `close()` — releasing the last strong reference frees the persistence
directory lock, and no second instance can open that directory until it does.

## Anti-patterns

### Assuming a floating-point field is `Double`

```swift
let price = item.value["price"] as? Double                  // WRONG
let price = (item.value["price"] as? NSNumber)?.doubleValue // CORRECT

// BETTER — let Codable widen it
struct Car: Codable { let price: Double }
let car = try JSONDecoder().decode(Car.self, from: item.jsonData())
```

**Symptom:** `nil` for some rows and a value for others *in the same column* — a value
that fits binary32 (`19999.5`) comes back as `Float`, one that does not (`0.1`) as
`Double`. A `guard let` just skips the row: no error, no log.

### Forgetting `signalNext()` on an exit path

```swift
try ditto.store.registerObserver(query: q) { [weak self] result, signalNext in
    guard let self else { return }   // WRONG — signalNext is never called
    self.apply(result.items)
    signalNext()
}

try ditto.store.registerObserver(query: q) { [weak self] result, signalNext in
    defer { signalNext() }           // CORRECT — every exit path, exactly once
    guard let self else { return }
    self.apply(result.items)
}
```

**Symptom:** the observer stops delivering forever — no error, no log, no crash. The
screen silently freezes on stale data.

### Assigning a fresh `DittoTransportConfig()`

```swift
var config = DittoTransportConfig()                                  // WRONG
config.connect.webSocketURLs = ["wss://REPLACE_ME_WITH_YOUR_HOST"]
ditto.transportConfig = config

ditto.updateTransportConfig {                                        // CORRECT
    $0.connect.webSocketURLs = ["wss://REPLACE_ME_WITH_YOUR_HOST"]
}
```

**Symptom:** every peer-to-peer transport is turned off — a live instance has
`bluetoothLE`, `lan` and `awdl` enabled, a default-constructed value has them all
`false`. No error, `sync.isActive == true`, and the device never finds a peer again.

### Dematerializing before diffing

```swift
// CORRECT — diff first, then extract. Reversing these two statements is the mistake.
let diff = differ.diff(items)
let cars = items.map { item in defer { item.dematerialize() }; return Car(item.value) }
```

**Symptom:** `DittoDiffer.diff(_:)` needs the items materialized and decodes with `try!`,
so a failure is a crash, not a throw. `map`, never `compactMap`: the index sets are
computed over `items`, so dropping a row desynchronises them from your data source and
`performBatchUpdates` raises *"invalid number of rows in section 0"*.

### A retroactive `Sendable` shim on v5

```swift
extension Ditto: @unchecked Sendable {}   // WRONG on 5.0.x / 5.1.x
```

**Symptom:** `error: conformance of 'Ditto' to protocol 'Sendable' was already stated in
the type's module 'DittoSwift'`. Delete the shim. On 4.14.x use
`@preconcurrency import DittoSwift` instead; without it the compiler says
`error: sending 'ditto' risks causing data races`.

### Treating `sync.isActive` as "connected"

**Symptom:** a UI reporting "online" on an offline-only peer with every radio disabled.
`isActive` means *sync was started*. Read
`presence.graph.localPeer.isConnectedToDittoServer` and `graph.remotePeers` instead.

### Building the server URL from the database ID

`connect: .server(url: URL(string: "https://\(databaseID).cloud.ditto.live")!)`

**Symptom:** authentication never succeeds. Copy the portal's *Connect via SDK* value
verbatim — an `https://` URL, not derived from the database ID. `.server(url:)` takes a
`URL`, not a `String`, and `databaseID` has an uppercase `ID`.

## Version differences

| Concern | 4.14.x | 5.0.x / 5.1.x |
|---|---|---|
| Package products | `DittoSwift` + `DittoObjC`, tools 5.8.1 | `DittoSwift` only, tools 6.0 |
| Initialization | `DittoConfig` + `Ditto.open`/`openSync` (**preview**); identity initializer deprecated | same, GA |
| Start sync | `ditto.sync.start()`; `startSync()` deprecated | `ditto.sync.start()` |
| Mutating DQL | requires `try ditto.disableSyncWithV3()` first | works out of the box |
| Concurrency | no `Sendable` conformances — needs `@preconcurrency import` | `Sendable`; `deliverOn:` ignored on 5.0.x, fixed in 5.1.0 |
| Use after release | `throws useAfterCloseError` | **`fatalError`** |
| Architectures | `arm64` + `x86_64` | `arm64` + `x86_64` on 5.0.x; **`arm64` only** on 5.1.x |
| On-disk store | — | index format changes in 5.1; downgrade via 5.0.2+ or 4.14.6+ |

Full delta, including the on-disk upgrade and rollback results:
[`references/versions.md`](references/versions.md).

## References

| If you need to know… | Read |
|---|---|
| How do I install it and what are the platform minimums? | [references/setup.md](references/setup.md) |
| How do I open Ditto, authenticate, and start syncing? | [references/connect.md](references/connect.md) |
| How do I change which transports are used? | [references/transports.md](references/transports.md) |
| How do I subscribe, set sync scopes, and check sync status? | [references/sync.md](references/sync.md) |
| How do I run DQL, transact, index, or evict? | [references/store.md](references/store.md) |
| How do I react to data changes without polling? | [references/observers.md](references/observers.md) |
| How do I store and fetch a file? | [references/attachments.md](references/attachments.md) |
| Who else is on the mesh right now? | [references/presence.md](references/presence.md) |
| How do I turn on logs and see disk usage? | [references/observability.md](references/observability.md) |
| What error is this and how do I recover? | [references/errors.md](references/errors.md) |
| How do I test code that uses Ditto? | [references/testing.md](references/testing.md) |
| What changed between 4.14.x and 5.x in the API? | [references/versions.md](references/versions.md) |
| What happens to the store on disk when I upgrade or roll back? | [references/storage.md](references/storage.md) |
| What is preview or platform-specific here? | [references/preview.md](references/preview.md) |
| Where should the instance live; which observer shape? | [best-practices.md](best-practices.md) |
