---
name: migrate-kotlin
description: Use when migrating Ditto Kotlin/Android SDK applications from v4.14 to v5.0. Covers the full package rename (live.ditto.* → com.ditto.kotlin.*), DittoFactory.create(DittoConfig), Flow-based observers, .toDittoCbor() serialization requirement, DittoException rename, and DQL migration from legacy Query Builder.
---

# Ditto Kotlin/Android SDK: v4.14 → v5.0 Migration Reference

## Quick Summary of Changes

| Area | v4.14 | v5.0 |
|------|-------|------|
| Package | `live.ditto.*` | `com.ditto.kotlin.*` |
| Init | `Ditto(deps, DittoIdentity.OnlinePlayground(...))` | `DittoFactory.create(DittoConfig(...))` or `Ditto.open(config)` |
| Sync | `ditto.startSync()` / `stopSync()` | `ditto.sync.start()` / `sync.stop()` |
| Auth | `DittoAuthenticationCallback` interface | `ditto.auth?.setExpirationHandler { ... }` suspend lambda |
| Observers | Callback + manual `.close()` | `registerObserver().collect {}` Flow in `lifecycleScope.launch {}` |
| Errors | `DittoError` sealed class | `DittoException` sealed class |
| Params | Plain Kotlin values | All values need `.toDittoCbor()` |
| Transport | Mutable `TransportConfig` | Immutable builder pattern |

---

## 1. Package Rename — Update ALL Imports

Every file needs import updates. This is the most pervasive change.

```kotlin
// v4.14 — remove all of these
import live.ditto.*
import live.ditto.sync.*
import live.ditto.store.*

// v5.0 — replace with
import com.ditto.kotlin.*
import com.ditto.kotlin.sync.*
import com.ditto.kotlin.store.*
```

Use IDE Find & Replace: `live.ditto` → `com.ditto.kotlin` across the entire project.

---

## 2. Initialization

**v4.14:**
```kotlin
val androidDeps = DefaultAndroidDittoDependencies(context)
val ditto = Ditto(
    androidDeps,
    DittoIdentity.OnlinePlayground(
        dependencies = androidDeps,
        appId = "my-app-id",
        token = "my-token",
        customAuthUrl = "https://my-app-id.cloud.ditto.live"
    )
)
ditto.startSync()
```

**v5.0:**
```kotlin
val config = DittoAndroidConfig(
    context,
    databaseId = "my-app-id",
    connect = DittoConfigConnect.Server(url = URL("https://my-app-id.cloud.ditto.live"))
)
val ditto = Ditto.open(config)

//authenticate
ditto.auth?.expirationHandler = { ditto, _ ->
    ditto.auth?.login(token = "your-token", provider = DittoAuthenticationProvider.development())
}

ditto.sync.start()
```

### Identity Type Mapping

| v4.14 DittoIdentity | v5.0 DittoAndroidConfig connect |
|---------------------|----------------------------------|
| `OnlinePlayground(appId:token:customAuthUrl:)` | `DittoConfigConnect.Server(url = URL(...))` |
| `OnlineWithAuthentication(appId:customAuthUrl:)` | `DittoConfigConnect.Server(url = URL(...))` + auth handler |
| `OfflinePlayground(appId:)` | `DittoConfigConnect.SmallPeersOnly(privateKey = null)` |
| `SharedKey(appId:sharedKey:)` | `DittoConfigConnect.SmallPeersOnly(privateKey = sharedKey)` |

### Remove These v4 Workarounds
```kotlin
// DELETE ALL OF THESE — not needed in v5:
ditto.updateTransportConfig { config ->
    config.connect.websocketUrls.add(webSocketURL)
}
ditto.disableSyncWithV3()
ditto.store.execute("ALTER SYSTEM SET DQL_STRICT_MODE = false")
```

---

## 3. Sync API

```kotlin
// v4.14
ditto.startSync()
ditto.stopSync()
val active = ditto.isSyncActive

// v5.0
ditto.sync.start()
ditto.sync.stop()
val active = ditto.sync.isActive
```

---

## 4. Authentication Handler

**v4.14 — interface:**
```kotlin
class MyAuthCallback : DittoAuthenticationCallback {
    override fun authenticationRequired(authenticator: DittoAuthenticator) {
        authenticator.loginWithToken("my-token", "my-provider") { clientInfo, error ->
            error?.let { println("Auth failed: $it") }
        }
    }
    override fun authenticationExpiringSoon(authenticator: DittoAuthenticator, secondsRemaining: Long) {
        // refresh
    }
}
ditto.callback = MyAuthCallback()
```

**v5.0 — property assignment:**
```kotlin
ditto.auth?.expirationHandler = { ditto, secondsRemaining ->
    if (secondsRemaining == 0L) {
        // Initial auth or expired
        ditto.auth?.login(
            token = "my-token",
            provider = DittoAuthenticationProvider.development()
        )
    } else {
        // Token expiring soon — refresh
        val newToken = fetchNewToken()
        ditto.auth?.login(token = newToken, provider = DittoAuthenticationProvider.development())
    }
}
```

Custom provider:
```kotlin
ditto.auth?.login(
    token = token,
    provider = DittoAuthenticationProvider.create("my-custom-provider")
)
```

---

## 5. Observers — Flow Migration

**v4.14 — callback with manual cleanup:**
```kotlin
var observer: DittoStoreObserver? = null

observer = ditto.store.registerObserver(
    "SELECT * FROM cars WHERE color = :color",
    mapOf("color" to "red")
) { result ->
    runOnUiThread {
        cars = result.items
    }
}

override fun onDestroy() {
    super.onDestroy()
    observer?.close()  // manual cleanup
}
```

**v5.0 — Flow with `collect`:**
```kotlin
lifecycleScope.launch {
    ditto.store.registerObserver(
        "SELECT * FROM cars WHERE color = :color",
        mapOf("color" to "red".toDittoCbor())
    ).collect { result ->
        withContext(Dispatchers.Main) {
            cars = result.items
        }
    }
}
// Lifecycle-aware: automatically cancelled when scope is destroyed
```

### Back Pressure (Coroutine Suspension)

Kotlin v5 uses **coroutine suspension** as the backpressure mechanism — no separate `signalNext` API is exposed.

- Use `store.collect()` for natural backpressure: while your `suspend` lambda executes, no new events are delivered. When it returns, Ditto automatically delivers the next event.
- Use `store.registerObserver().collect{}` (Flow) when you want all events as fast as possible — signals immediately after emit.

```kotlin
// store.collect() — backpressure via suspension
lifecycleScope.launch {
    ditto.store.collect(
        "SELECT * FROM cars WHERE color = :color",
        mapOf("color" to "blue".toDittoCbor())
    ) { result ->
        expensiveOperation(result.items)  // No new events while this runs
    }
}

// registerObserver().collect{} — high throughput, no backpressure
lifecycleScope.launch {
    ditto.store.registerObserver(query, args).collect { result ->
        updateUI(result.items)
    }
}
```

Changes are coalesced while the handler executes — you receive the latest state, not every intermediate change.

---

## 6. Serialization — `.toDittoCbor()` REQUIRED

⚠️ **Critical**: ALL values in DQL parameter maps must call `.toDittoCbor()`. Missing this causes `ClassCastException` at runtime.

```kotlin
// v4.14 — no serialization needed
ditto.store.execute(
    "INSERT INTO cars DOCUMENTS (:doc)",
    mapOf("doc" to mapOf("color" to "red", "year" to 2023))
)

// v5.0 — EVERY value needs .toDittoCbor()
ditto.store.execute(
    "INSERT INTO cars DOCUMENTS (:doc)",
    mapOf("doc" to mapOf(
        "_id" to "car-1".toDittoCbor(),
        "color" to "red".toDittoCbor(),
        "year" to 2023.toDittoCbor()
    ).toDittoCbor())  // outer map also needs it
)

// Query arguments also need .toDittoCbor()
ditto.store.execute(
    "SELECT * FROM cars WHERE color = :color",
    mapOf("color" to "red".toDittoCbor())
)
```

Types that need `.toDittoCbor()`: `String`, `Int`, `Long`, `Float`, `Double`, `Boolean`, `Map`, `List`, and any nested collections.

---

## 7. Error Handling — DittoException

```kotlin
// v4.14
try {
    ditto.sync.start()
} catch (e: DittoError) {
    println("Error: ${e.message}")
}

// v5.0
try {
    ditto.sync.start()
} catch (e: DittoException) {
    println("Error: ${e.message}")
}
```

Update all `catch (e: DittoError)` blocks to `catch (e: DittoException)`.

---

## 8. Transport Config — Builder Pattern

```kotlin
// v4.14 — mutable config
ditto.updateTransportConfig { config ->
    config.connect.websocketUrls.add("wss://...")
    config.enableAllPeerToPeer()
}

// v5.0 — immutable builder
val transportConfig = TransportConfig.Builder()
    .addWebsocketUrl("wss://...")
    .enableBluetooth(true)
    .enableLan(true)
    .build()
ditto.setTransportConfig(transportConfig)
```

---

## 9. DQL Strict Mode — CRITICAL BREAKING CHANGE

⚠️ **Silent data behavior change**: v5 defaults to `DQL_STRICT_MODE=false`. v4 default was `true`.

| Mode | Object behavior |
|------|----------------|
| `strict=true` (v4 default) | Objects treated as REGISTER (whole-object replacement) |
| `strict=false` (v5 default) | Objects auto-inferred as MAP (field-level merging) |

**If your v4 app used the default (strict=true)**:
```kotlin
val ditto = Ditto.open(config)
// MUST set BEFORE sync.start() and BEFORE any queries
ditto.store.execute("ALTER SYSTEM SET DQL_STRICT_MODE = true")
ditto.sync.start()
```

---

## 10. DQL Migration — Legacy Query Builder → DQL

For help with migrations to DQL (Ditto Query Language) assistance for queries, subscriptions, and data operations - it's recommended to use the [DQL plugin](../ditto-dql).

### Query

```kotlin
// v4.14
val cars = ditto.store.collection("cars").find("color == 'blue'").exec()
val car = ditto.store.collection("cars").findByID(id).exec()

// v5.0
val result = ditto.store.execute(
    "SELECT * FROM cars WHERE color = :color",
    mapOf("color" to "blue".toDittoCbor()))
val result = ditto.store.execute(
    "SELECT * FROM cars WHERE _id = :id",
    mapOf("id" to id.toDittoCbor()))
```

### Insert (Upsert)

```kotlin
// v4.14
ditto.store.collection("cars").upsert(mapOf("_id" to id, "color" to "blue"))

// v5.0
ditto.store.execute(
    "INSERT INTO cars DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE",
    mapOf("doc" to mapOf(
        "_id" to id.toDittoCbor(),
        "color" to "blue".toDittoCbor()
    ).toDittoCbor()))
```

### Update

```kotlin
// v4.14
ditto.store.collection("cars").findByID(id).update { doc ->
    doc["color"] = "green"
}

// v5.0
ditto.store.execute(
    "UPDATE cars SET color = :color WHERE _id = :id",
    mapOf("color" to "green".toDittoCbor(), "id" to id.toDittoCbor()))
```

### Delete

```kotlin
// v4.14
ditto.store.collection("cars").findByID(id).remove()

// v5.0
ditto.store.execute(
    "DELETE FROM cars WHERE _id = :id",
    mapOf("id" to id.toDittoCbor()))
```

### Evict

```kotlin
// v4.14
ditto.store.collection("cars").findByID(id).evict()

// v5.0
ditto.store.execute(
    "EVICT FROM cars WHERE _id = :id",
    mapOf("id" to id.toDittoCbor()))
```

### Observers

```kotlin
// v4.14
liveQuery = ditto.store.collection("cars")
    .find("_id.locationId == '$locationId'")
    .observeLocal { docs, event ->
        runOnUiThread { updateUI(docs) }
    }

// v5.0
lifecycleScope.launch {
    ditto.store.registerObserver(
        "SELECT * FROM cars WHERE _id.locationId = :locationId",
        mapOf("locationId" to locationId.toDittoCbor())
    ).collect { result ->
        withContext(Dispatchers.Main) { updateUI(result.items) }
    }
}
```

### Sync Subscriptions

```kotlin
// v4.14
val sub = ditto.store.collection("cars").find("color == 'red'").subscribe()

// v5.0
val sub = ditto.sync.registerSubscription(
    "SELECT * FROM cars WHERE color = :color",
    mapOf("color" to "red".toDittoCbor()))
```

### Counters

```kotlin
// v4.14
ditto.store.collection("cars").findByID(id).update { doc ->
    doc["viewCount"].counter.increment(1.0)
}

// v5.0 — DO NOT initialize counter field in document
ditto.store.execute(
    "UPDATE cars APPLY viewCount PN_INCREMENT BY :n WHERE _id = :id",
    mapOf("n" to 1.toDittoCbor(), "id" to id.toDittoCbor()))
```

---

## 11. Other API Changes

| v4.14 | v5.0 |
|-------|------|
| `peerKeyString: String` | `peerKey: String` |
| `isConnectedToDittoCloud` | `isConnectedToDittoServer` |
| `ditto.callback: DittoCallback?` | `ditto.transportCondition: Flow<DittoTransportConditionEvent>` |
| `presence.observe(handler)` callback | `presence.observe()` returns `Flow` |
| `DittoAuthenticationCallback` interface | `setExpirationHandler` suspend lambda |
| `DefaultAndroidDittoDependencies` | Removed — no dependency object needed |
| `enableAllPeerToPeer()` | Removed — configure each transport explicitly via builder |

---

## 12. New APIs in v5

- **`DittoAndroidConfig`** — Android-specific config accepting `Context` as first parameter
- **`DittoConfigConnect.Server`** / **`DittoConfigConnect.SmallPeersOnly`** — connect mode types
- **`DittoException`** — replaces `DittoError` as the sealed exception hierarchy
- **`ditto.sync`** sub-object with `start()`, `stop()`, `isActive`, `registerSubscription()`
- **`ditto.transportCondition: Flow<DittoTransportConditionEvent>`** — replaces `ditto.callback`
- **`auth.observeStatus(): StateFlow`** — observe authentication status as a Flow
- **`store.registerObserver()`** — now returns `Flow` (was callback-based)
- **`presence.observe()`** — now returns `Flow` (was callback-based)
- **Data Streams API (preview)** — streaming data subscription model
- **Transport config Builder pattern** — all transport config types now use immutable builders

## 13. Migration Checklist

### Package & Imports
- [ ] Replace ALL `live.ditto.*` imports with `com.ditto.kotlin.*`
- [ ] Run Find & Replace: `live.ditto` → `com.ditto.kotlin` project-wide

### Initialization
- [ ] Replace `Ditto(deps, DittoIdentity.OnlinePlayground(...))` with `Ditto.open(DittoAndroidConfig(context, ...))`
- [ ] Remove `DefaultAndroidDittoDependencies` parameter
- [ ] Update identity types to `DittoConfigConnect.*` variants
- [ ] Remove `updateTransportConfig`, `disableSyncWithV3()` calls
- [ ] Set `DQL_STRICT_MODE=true` BEFORE `sync.start()` if maintaining v4 behavior
- [ ] Update `startSync()` → `sync.start()`

### Authentication
- [ ] Remove `DittoAuthenticationCallback` interface implementations
- [ ] Set `ditto.auth?.setExpirationHandler` suspend lambda
- [ ] Use `DittoAuthenticationProvider.development()` for playground tokens
- [ ] Handle both `secondsRemaining == 0L` (initial) and `> 0` (refresh)

### Observers
- [ ] Convert all observer callbacks to `.collect {}` Flow pattern
- [ ] Wrap in `lifecycleScope.launch {}`
- [ ] Replace `runOnUiThread` with `withContext(Dispatchers.Main)`
- [ ] Remove manual `observer?.close()` calls

### Serialization
- [ ] Add `.toDittoCbor()` to ALL values in DQL parameter maps
- [ ] Add `.toDittoCbor()` to nested maps and collections
- [ ] Check INSERT, UPDATE, SELECT, observer `arguments` maps

### Error Handling
- [ ] Replace all `catch (e: DittoError)` with `catch (e: DittoException)`

### Data Operations
- [ ] Replace all `.collection("x").find(...)` chains with `store.execute()` DQL
- [ ] Use parameterized queries — never string interpolation
- [ ] Replace `.upsert()` with `INSERT INTO ... ON ID CONFLICT DO UPDATE`
- [ ] Replace `.update {}` closures with `UPDATE SET` DQL
- [ ] Replace `.remove()` with `DELETE FROM`
- [ ] Replace `.evict()` with `EVICT FROM`
- [ ] Replace `.observeLocal {}` with `store.registerObserver().collect {}`
- [ ] Replace `.subscribe()` with `sync.registerSubscription()`

### Breaking Changes
- [ ] Update `peerKeyString` → `peerKey`
- [ ] Update `isConnectedToDittoCloud` → `isConnectedToDittoServer`

### Verification
- [ ] Project builds with zero errors (especially `ClassCastException` for missing `.toDittoCbor()`)
- [ ] All `DittoError` catch blocks updated to `DittoException`
- [ ] Observer Flow collects data correctly
- [ ] Auth handler called before sync starts

---

## Common Pitfalls

1. **Missing `.toDittoCbor()`**: The most common v5 Kotlin bug. `ClassCastException` at runtime if any value in a parameter map lacks `.toDittoCbor()`. Apply to EVERY value, including nested maps.

2. **Import not updated**: Forgetting to update `live.ditto.*` imports causes `ClassNotFoundException` or unresolved reference errors at compile time.

3. **DQL_STRICT_MODE silent change**: Objects that were replaced whole in v4 will merge field-by-field in v5 if strict mode isn't set.

4. **Counter initialization**: Don't use `DittoCounter()` or `0.toDittoCbor()` for counter fields in insert documents. Use `PN_INCREMENT` on first write.

5. **`DittoError` catch blocks**: The rename to `DittoException` means old catch blocks silently fail to catch exceptions.

6. **`runOnUiThread` in Flow**: Replace with `withContext(Dispatchers.Main)` inside the `collect {}` block.

---

## Official Documentation

- Kotlin V4→V5 Guide: https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4
- Kotlin DQL Migration: https://docs.ditto.live/sdk/latest/migration-guides/kotlin-dql
- DQL Reference: https://docs.ditto.live/dql/dql
