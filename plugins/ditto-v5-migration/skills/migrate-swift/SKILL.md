---
name: migrate-swift
description: Use when migrating Ditto Swift/iOS/macOS SDK applications from v4.14 to v5.0. Covers DittoConfig initialization, async/await patterns, expirationHandler closure, AsyncSequence observer migration, sync sub-object API, and DQL migration from legacy Query Builder. Also covers APIs removed with no replacement.
---

# Ditto Swift SDK: v4.14 → v5.0 Migration Reference

## Quick Summary of Changes

| Area | v4.14 | v5.0 |
|------|-------|------|
| Init | `Ditto(identity: .onlinePlayground(...))` | `try await Ditto.open(config: DittoConfig(...))` |
| Sync | `ditto.startSync()` / `stopSync()` | `ditto.sync.start()` / `sync.stop()` |
| Auth | `DittoAuthenticationDelegate` protocol | `ditto.auth?.expirationHandler` closure |
| Observers | Callback with `DittoStoreObserver?` + `deinit` | `for try await` AsyncSequence in `Task {}` |
| Peer key | `peerKeyString: String` | `peerKey: String` |
| Cloud connected | `isConnectedToDittoCloud` | `isConnectedToDittoServer` |
| Disk usage | `DiskUsage` | `DittoDiskUsage` |

---

## 1. Initialization

**v4.14:**
```swift
let ditto = Ditto(identity: .onlinePlayground(
    appID: "my-app-id",
    enableDittoCloudSync: true
))
try? ditto.startSync()
```

**v5.0:**
```swift
let config = DittoConfig(
    databaseID: "my-app-id",
    connect: .server(url: URL(string: "https://my-app-id.cloud.ditto.live")!)
)
let ditto = try await Ditto.open(config: config)

//authenticate
ditto.auth?.expirationHandler = { dittoAuth, secondsRemaining in
    dittoAuth.auth?.login(token: "your-token", provider: .development) { clientInfo, error in
        if let error = error {
            print("Ditto auth failed: \(error), client info: \(String(describing: clientInfo)), seconds remaining: \(secondsRemaining)")
        }
    }
}

try ditto.sync.start()
```

### Identity Type Mapping

| v4.14 Identity | v5.0 DittoConfig |
|----------------|-----------------|
| `.onlinePlayground(appID:enableDittoCloudSync:customAuthURL:)` | `DittoConfig(databaseID: appID, connect: .server(url:))` |
| `.onlineWithAuthentication(appID:enableDittoCloudSync:customAuthURL:)` | `DittoConfig(databaseID: appID, connect: .server(url:))` + auth handler |
| `.offlinePlayground(appID:)` | `DittoConfig(databaseID: appID, connect: .smallPeersOnly(privateKey: nil))` |
| `.sharedKey(appID:sharedKey:)` | `DittoConfig(databaseID: appID, connect: .smallPeersOnly(privateKey: sharedKey))` |
| `.manual(certificateConfig:)` | **No replacement** — removed in v5 |

### Remove These v4 Workarounds
```swift
// DELETE ALL OF THESE — not needed in v5:
ditto.updateTransportConfig { config in
    config.connect.webSocketURLs.insert("wss://...")
}
ditto.disableSyncWithV3()
try? ditto.store.execute(query: "ALTER SYSTEM SET DQL_STRICT_MODE = false")
```

---

## 2. Sync API

```swift
// v4.14
try? ditto.startSync()
ditto.stopSync()
let active = ditto.isSyncActive

// v5.0
try ditto.sync.start()
ditto.sync.stop()
let active = ditto.sync.isActive
```

---

## 3. Authentication Handler

**v4.14 — delegate protocol:**
```swift
class MyAuthDelegate: DittoAuthenticationDelegate {
    func authenticationRequired(authenticator: DittoAuthenticator) {
        authenticator.loginWithToken("my-token", provider: "my-provider") { clientInfo, error in
            print("Auth result: \(String(describing: error))")
        }
    }
    func authenticationExpiringSoon(authenticator: DittoAuthenticator, secondsRemaining: Double) {
        // refresh token
    }
}
ditto.delegate = MyAuthDelegate()
```

**v5.0 — closure:**
```swift
ditto.auth?.expirationHandler = { dittoAuth, secondsRemaining in
    if secondsRemaining == 0 {
        // Initial auth or expired
        dittoAuth.login(token: "my-token", provider: "my-provider") { clientInfo, error in
            if let error = error {
                print("Auth failed: \(error)")
            }
        }
    } else {
        // Token expiring soon — refresh
        fetchNewToken { newToken in
            dittoAuth.login(token: newToken, provider: "my-provider") { _, _ in }
        }
    }
}
```

Use `.development` provider for playground/test tokens:
```swift
dittoAuth.login(token: token, provider: .development) { _, _ in }
```

---

## 4. Observers — AsyncSequence Migration

**v4.14 — callback with manual cleanup:**
```swift
var observer: DittoStoreObserver?

observer = ditto.store.registerObserver(
    query: "SELECT * FROM cars WHERE color = :color",
    arguments: ["color": "red"]
) { result in
    DispatchQueue.main.async {
        self.cars = result.items.compactMap { Car($0.jsonData()) }
    }
}

deinit {
    observer?.stop()  // manual cleanup required
}
```

**v5.0 — AsyncSequence with `for try await`:**
```swift
Task {
    for try await result in ditto.store.registerObserver(
        query: "SELECT * FROM cars WHERE color = :color",
        arguments: ["color": "red"]
    ) {
        await MainActor.run {
            self.cars = result.items.compactMap { Car($0.jsonData()) }
        }
    }
}
// No manual .stop() needed — Task cancellation handles cleanup
```

**SwiftUI — use `.task` modifier for automatic lifecycle management:**
```swift
.task {
    for try await result in ditto.store.registerObserver(
        query: "SELECT * FROM cars",
        arguments: [:]
    ) {
        cars = result.items.compactMap { Car($0.jsonData()) }
    }
}
```

**Memory management with `dematerialize()`:**
```swift
Task {
    for try await result in ditto.store.registerObserver(query: "SELECT * FROM cars") {
        let items = result.items.compactMap { item -> Car? in
            let car = Car(item.jsonData())
            item.dematerialize()  // Free native memory — do not use item after this
            return car
        }
        await MainActor.run { self.cars = items }
    }
}
```

---

## 5. Back Pressure (Signal Next)

Use `registerObserver(query:arguments:deliverOn:handlerWithSignalNext:)` when your handler needs time to process results. The SDK waits until you call `signalNext()` before delivering the next update.

**Coalescing**: changes that occur while your handler is processing are coalesced — you get one callback with the latest state, not every intermediate change.

**Standard observer (auto-signals):**
```swift
// signalNext() is called automatically after handler returns
let observer = try ditto.store.registerObserver(
    query: "SELECT * FROM cars WHERE color = :color",
    arguments: ["color": "blue"]
) { result in
    updateUI(result.items)
}
```

**Signal-next observer (manual control):**
```swift
let observer = try ditto.store.registerObserver(
    query: "SELECT * FROM cars",
    arguments: nil,
    handlerWithSignalNext: { result, signalNext in
        Task {
            await expensiveRenderOperation(result.items)
            signalNext()  // Must call this to receive the next update
        }
    }
)
```

Types:
- `DittoSignalNext = () -> Void`
- `DittoStoreObservationHandlerWithSignalNext = (_ result: DittoQueryResult, _ signalNext: @escaping DittoSignalNext) -> Void`

---

## 6. DQL Strict Mode — CRITICAL BREAKING CHANGE

⚠️ **Silent data behavior change**: v5 defaults to `DQL_STRICT_MODE=false`. v4 default was `true`.

| Mode | Object behavior |
|------|----------------|
| `strict=true` (v4 default) | Objects treated as REGISTER (whole-object replacement) |
| `strict=false` (v5 default) | Objects auto-inferred as MAP (field-level merging) |

**If your v4 app used the default (strict=true)**, set strict mode before starting sync:
```swift
let ditto = try await Ditto.open(config: config)
// MUST set BEFORE sync.start() and BEFORE any queries
try await ditto.store.execute("ALTER SYSTEM SET DQL_STRICT_MODE = true")
try ditto.sync.start()
```

**If your v4 app explicitly set strict=false**, no change needed — v5 default matches.

---

## 7. Persistence Directory

v5 default directory: `ditto-{databaseID}` (was `ditto` in v4)

To preserve v4 data path:
```swift
let config = DittoConfig(
    databaseID: "my-app-id",
    connect: .server(url: URL(string: "https://...")!),
    persistenceDirectory: URL(fileURLWithPath: "/app/sandbox/ditto")  // v4 path
)
```

---

## 8. DQL Migration — Legacy Query Builder → DQL

For help with migrations to DQL (Ditto Query Language) assistance for queries, subscriptions, and data operations - it's recommended to use the [DQL plugin](../ditto-dql).

All `.collection()` APIs are **removed**. Replace with `store.execute()`.

### Query

```swift
// v4.14
let cars = ditto.store.collection("cars").find("color == 'blue'").exec()
let car = ditto.store.collection("cars").findByID(id).exec()

// v5.0
let result = try await ditto.store.execute(
    query: "SELECT * FROM cars WHERE color = :color",
    arguments: ["color": "blue"])
let result = try await ditto.store.execute(
    query: "SELECT * FROM cars WHERE _id = :id",
    arguments: ["id": id])
```

### Insert

```swift
// v4.14
ditto.store.collection("cars").upsert(["_id": id, "color": "blue", "make": "Toyota"])

// v5.0
try await ditto.store.execute(
    query: "INSERT INTO cars DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE",
    arguments: ["doc": ["_id": id, "color": "blue", "make": "Toyota"]])
```

### Update

```swift
// v4.14
ditto.store.collection("cars").findByID(id).update { doc in
    doc?["color"].set("green")
}

// v5.0
try await ditto.store.execute(
    query: "UPDATE cars SET color = :color WHERE _id = :id",
    arguments: ["color": "green", "id": id])
```

### Delete

```swift
// v4.14
ditto.store.collection("cars").findByID(id).remove()

// v5.0
try await ditto.store.execute(
    query: "DELETE FROM cars WHERE _id = :id",
    arguments: ["id": id])
```

### Evict

```swift
// v4.14
ditto.store.collection("cars").findByID(id).evict()

// v5.0
try await ditto.store.execute(
    query: "EVICT FROM cars WHERE _id = :id",
    arguments: ["id": id])
```

### Observers

```swift
// v4.14
liveQuery = ditto.store.collection("cars")
    .find("_id.locationId == '\(locationId)'")
    .observeLocal { docs, event in
        switch event {
        case .initial: handleInitial(docs)
        case .update(let changes): handleUpdate(docs, changes)
        }
    }

// v5.0
Task {
    for try await result in ditto.store.registerObserver(
        query: "SELECT * FROM cars WHERE _id.locationId = :locationId",
        arguments: ["locationId": locationId]
    ) {
        let cars = result.items.compactMap { item -> Car? in
            let car = Car(item.jsonData())
            item.dematerialize()
            return car
        }
        await MainActor.run { self.updateUI(cars) }
    }
}
```

### Sync Subscriptions

```swift
// v4.14
let sub = ditto.store.collection("cars")
    .find("color == 'red'")
    .subscribe()

// v5.0
let sub = try ditto.sync.registerSubscription(
    query: "SELECT * FROM cars WHERE color = :color",
    arguments: ["color": "red"])
```

### Counters

```swift
// v4.14
ditto.store.collection("cars").findByID(id).update { doc in
    doc?["viewCount"].counter?.increment(by: 1.0)
}

// v5.0 — DO NOT initialize counter field in document
try await ditto.store.execute(
    query: "UPDATE cars APPLY viewCount PN_INCREMENT BY :n WHERE _id = :id",
    arguments: ["n": 1, "id": id])
// Decrement: pass negative value ["n": -1]
```

---

## 9. Other API Changes

| v4.14 | v5.0 |
|-------|------|
| `peerKeyString: String` | `peerKey: String` |
| `isConnectedToDittoCloud: Bool` | `isConnectedToDittoServer: Bool` |
| `DiskUsage` | `DittoDiskUsage` |
| `diskUsage.exec` | `diskUsage.item` |
| `DiskUsageObserverHandle` | `DittoDiskUsageObserver` |
| `ditto.observePeers(_:)` | `ditto.presence.observe(didChangeHandler:)` |
| `ditto.activated` | `ditto.isActivated` |
| `Log` class | `Logger` class |
| `Log.setLogFile()` | Removed — file logging not directly supported |
| `DittoDiskUsage` property on `ditto` | `ditto.diskUsage: DittoDiskUsage`  |

---

## 10. APIs Removed With No Replacement

These v4 APIs are gone in v5 with no equivalent:

- `ditto.transportDiagnostics()` — low-level transport debug info
- `ditto.runGarbageCollection()` — CRDT GC controls
- `ditto.disableSyncWithV3()` — v3 protocol fully dropped
- `ditto.isHistoryTrackingEnabled` — history tracking removed
- `DittoIdentity.manual(certificateConfig:)` — manual identity type
- `Connection.approximateDistanceInMeters` — peer distance estimation
- `staticContentPath` on HTTP listen config — static file serving
- Query hash / fingerprint methods — hash-based query deduplication
- Connection priority — peer connection priority
- `DittoSwiftError` typealias
- `migrationError` error case

## 11. New APIs in v5

- **`Ditto.openSync(config:)`** — synchronous factory alternative to async `Ditto.open(config:)`
- **`ditto.config: DittoConfig`** — read the config used to open this instance
- **`ditto.isActivated: Bool`** — replaces `ditto.activated`
- **`DittoStore.newAttachment(data: Data, metadata:)`** — create attachment from in-memory `Data` (v4 was file path only)
- **`DittoStore.registerObserver(query:arguments: some Codable, ...)`** — overloads accepting `Codable` query arguments
- **`DittoSync.registerSubscription(query:arguments: some Codable)`** — overload accepting `Codable` arguments
- **`DittoDiskUsageObserver`** — standalone observer class (was nested `DiskUsage.DiskUsageObserverHandle`)
- **`DittoDiskUsageItem`** — renamed from `DiskUsageItem`
- **`DittoSyncSubscription.queryArgumentsCBORData`** / **`.queryArgumentsJSONData`** / **`.id`** — new properties for introspection
- **`DittoConnection`** now conforms to `Identifiable`, `Equatable`, `Hashable`, and `Sendable`
- All public types now `final` and `Sendable` for Swift concurrency
- `DittoConfig` and `DittoConfigConnect` now conform to `Sendable` and `Codable`

---

## 12 Other changes

### 12.1 `DittoConnection` Property Renames (CRITICAL)

```markdown
## DittoConnection Property Renames (v5)

| v4.14 | v5.0 |
|-------|------|
| `connection.peerKeyString1` | `connection.peer1` |
| `connection.peerKeyString2` | `connection.peer2` |
| `connection.approximateDistanceInMeters` | **REMOVED — no replacement** |
```

The `approximateDistanceInMeters` removal is especially important because:
- Apps using it must store `nil` now or remove the property from their own models
- UI displaying "distance to peer" must be gracefully hidden
- It was the only way to display physical proximity between devices

### 12.2 `DittoPeer.osV2` → `DittoPeer.os` 

```markdown
## DittoPeer Property Renames (v5)

| v4.14 | v5.0 |
|-------|------|
| `peer.peerKeyString` | `peer.peerKey` |
| `peer.osV2: DittoPeerOS?` | `peer.os: DittoPeerOS?` |
| `peer.isConnectedToDittoCloud` | `peer.isConnectedToDittoServer` |
```

### 12.3 `DittoConnection` New Protocol Conformances and Swift 6 `filter` Ambiguity

```markdown
## Breaking: DittoConnection Conformances Cause Swift 6 `filter` Ambiguity

In v5, `DittoConnection` gains `Identifiable`, `Equatable`, `Hashable`, and `Sendable` conformances.
In Swift 6, `Foundation.filter(_:Predicate)` takes precedence over `Sequence.filter(_:)` when the
element type conforms to these protocols, causing an unexpected compile error.

**Error:** `trailing closure passed to parameter of type 'Predicate<DittoConnection>'`

**Fix:** Annotate the closure parameter type explicitly:
```swift
// BROKEN in Swift 6
connections.filter { $0.peer1 == localKey }

// FIXED
connections.filter { (conn: DittoConnection) in conn.peer1 == localKey }
```
```

### 12.4 Auth Handler — Swift 6 Actor Isolation

```markdown
## Auth Handler: Swift 6 Actor Isolation Requirement

If your `DittoManager` (or whatever class holds the `Ditto` instance) is an `actor`,
the `expirationHandler` closure is `@Sendable` and executes off the actor. Any access
to actor-isolated state inside a `Task { }` block requires `await`:

```swift
// BROKEN — Swift 6 strict concurrency error
ditto.auth?.expirationHandler = { dittoAuth, secondsRemaining in
    if let error = someError {
        Task {
            self.myActorIsolatedProperty = error  // ← error: actor-isolated
        }
    }
}

// FIXED
ditto.auth?.expirationHandler = { dittoAuth, secondsRemaining in
    if let error = someError {
        Task {
            await self.myActorIsolatedProperty = error  // ← correct
        }
    }
}
```
```

### 12.5 Callback `registerObserver` — Clarify It Is Deprecated, Not Removed

```markdown
## Observer Migration: Callback Form Still Compiles in v5

The callback-based `registerObserver` overload is **deprecated but NOT removed** in v5.  Code using the callback pattern will still compile. The `for try await` AsyncSequence pattern is the preferred v5 API and should be adopted for new code, but existing callback-based observers do not need to be migrated immediately.

The types also change: `DittoStoreObserver` still exists but `Task<Void, any Error>` is the idiomatic holder for AsyncSequence-based observer lifecycles.
```

### 12.6 `DittoDiskUsageItem` Property Stability

```markdown
## DittoDiskUsageItem Property Names (v5, Unchanged)

Despite the type rename from `DiskUsageItem` to `DittoDiskUsageItem`, the property names
are **unchanged** in v5:

- `.path: String` — unchanged
- `.sizeInBytes: Int` — unchanged
- `.childItems: [DittoDiskUsageItem]` — unchanged (type renamed, property name same)
```

### 12.7 `Log` → `Logger` Clarification

```markdown
## `Log` → `Logger` Rename: Clarification

The `DittoSwift.Log` SDK class is renamed to `DittoSwift.Logger` in v5.

**Important:** This only affects code that directly imports and uses the Ditto SDK's `Log` type.
Apps that define their own `Log` wrapper (e.g., a CocoaLumberjack facade) are unaffected.
Apps that use `DittoLogger` for SDK log configuration are also unaffected — `DittoLogger`
is a separate type that does not change name.

To check if you're affected, search for `import DittoSwift` files that also reference `Log.`
(not `DittoLogger.`).
```


## 13. Migration Checklist

### Initialization
- [ ] Replace `Ditto(identity:)` with `try await Ditto.open(config:)`
- [ ] Create `DittoConfig` using the appropriate init (`onlinePlayground:`, `onlineWithAuthentication:`, etc.)
- [ ] Add `connect: .server(url:)` for cloud-connected configs
- [ ] Remove `updateTransportConfig` calls
- [ ] Remove `disableSyncWithV3()` calls
- [ ] Set `DQL_STRICT_MODE=true` BEFORE `sync.start()` if maintaining v4 data behavior
- [ ] Update `startSync()` → `sync.start()`

### Authentication
- [ ] Remove `DittoAuthenticationDelegate` conformance
- [ ] Set `ditto.auth?.expirationHandler` closure after `Ditto.open()`
- [ ] Use `secondsRemaining == 0` check for initial auth vs refresh

### Observers
- [ ] Convert all `registerObserver(query:arguments:) { result in }` to `for try await`
- [ ] Wrap in `Task {}` or use `.task {}` SwiftUI modifier
- [ ] Replace `DispatchQueue.main.async` with `await MainActor.run`
- [ ] Remove manual `observer?.stop()` in `deinit`
- [ ] Remove `DittoStoreObserver?` stored properties
- [ ] Call `item.dematerialize()` after extracting data from `DittoQueryResultItem`
- [ ] If processing is expensive, use `handlerWithSignalNext:` for back-pressure control

### Data Operations
- [ ] Replace all `.collection("x").find(...)` chains with `store.execute()` DQL
- [ ] Use parameterized queries with `:paramName` — never string interpolation
- [ ] Replace `.upsert()` with `INSERT INTO ... ON ID CONFLICT DO UPDATE`
- [ ] Replace `.update {}` closures with `UPDATE SET` DQL
- [ ] Replace `.remove()` with `DELETE FROM`
- [ ] Replace `.evict()` with `EVICT FROM`
- [ ] Replace `.observeLocal {}` with `store.registerObserver()` + `for try await`
- [ ] Replace `.subscribe()` with `sync.registerSubscription()`
- [ ] Replace `counter?.increment(by:)` with `UPDATE APPLY ... PN_INCREMENT BY`

### Breaking Changes
- [ ] Set `persistenceDirectory` if maintaining v4 data directory structure
- [ ] Update `peerKeyString` → `peerKey`
- [ ] Update `isConnectedToDittoCloud` → `isConnectedToDittoServer`
- [ ] Update `DiskUsage` → `DittoDiskUsage` type references
- [ ] Update `Log` → `Logger`

### Verification
- [ ] Project builds with zero errors
- [ ] No deprecated API warnings
- [ ] Observers fire on initial load
- [ ] Authentication completes before first sync
- [ ] No memory leaks (Instruments: Allocations, Leaks)

---

## Common Pitfalls

1. **DQL_STRICT_MODE silent change**: Not setting `DQL_STRICT_MODE=true` when your v4 app used the default. Objects that were replaced whole will now merge at field level — causes unexpected data merging.

2. **Forgetting `try await`**: `Ditto.open(config:)` is async. Not awaiting it causes a compile error.

3. **Storing `DittoQueryResultItem` outside callback**: These hold native memory. Always call `dematerialize()` and extract your model before the Task iteration ends.

4. **String interpolation in queries**: Never `"SELECT * FROM cars WHERE color = '\(color)'"`. Always use `arguments: ["color": color]`.

5. **Counter initialization**: Don't put `DittoCounter()` or `0` in insert documents. Counters are created on first `PN_INCREMENT`. Inserting `0` creates a REGISTER, not a COUNTER.

6. **Missing `ON ID CONFLICT`**: INSERT fails if document `_id` already exists without a conflict clause.

7. **Not checking `secondsRemaining`** in auth handler: Handler is called for both initial auth (0) and token refresh (>0). Handle both cases.

---

## Official Documentation

- Swift V4→V5 Guide: https://docs.ditto.live/sdk/latest/migration-guides/swift-v4
- Swift DQL Migration: https://docs.ditto.live/sdk/latest/migration-guides/swift-dql
- DQL Reference: https://docs.ditto.live/dql/dql
