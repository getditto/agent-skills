# Observers, Flows and back-pressure — Ditto Kotlin SDK

## Contents

- [The three observer shapes](#the-three-observer-shapes)
- [Choosing a shape](#choosing-a-shape)
- [The critical memory rule: extract inside the lambda](#the-critical-memory-rule-extract-inside-the-lambda)
- [Exceptions kill observers](#exceptions-kill-observers)
- [Threads: where the handler runs](#threads-where-the-handler-runs)
- [Back-pressure: what the source actually does](#back-pressure-what-the-source-actually-does)
- [Flow lifecycle: cancellation destroys the native observer](#flow-lifecycle-cancellation-destroys-the-native-observer)
- [Diffing with `DittoDiff`](#diffing-with-dittodiff)
- [Query constraints](#query-constraints)
- [Migrating from v4](#migrating-from-v4)

> **Sources for this file.** <https://docs.ditto.live/sdk/latest/crud/observing-data-changes> and the
> `OBSERVERS` / `Observer Changes` / `Back-pressure` blocks in
> <https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>. Sections marked **[source-verified]** were
> checked against the SDK source at tags `sdk-release-5.1.0` / `sdk-release-5.0.3`
> (`sdks/kotlin/api/ditto-kotlin`, `sdks/kotlin/ditto-internal`) — where docs and
> source disagree, this file follows the source and says so. DQL semantics belong to
> the `write-dql` skill — see <https://docs.ditto.live/dql/dql>.

This is where most Kotlin Ditto apps live, and where correct-looking code crashes with
`IllegalStateException`, silently stops receiving updates, or floods a slow collector.
Read [`SKILL.md` § Concurrency and threading](../SKILL.md#concurrency-and-threading-model)
first; this file is the detail.

## CAP-11 Observers, diffing and back-pressure

### The three observer shapes

v5 replaces v4's single callback model with three shapes, all under `ditto.store`
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>). The handler is `suspend`; the
`DittoQueryResult` is managed by the observer (auto-closed when the lambda returns),
so you do **not** need a `use { }` block.

**1. `registerObserver` — suspend handler, manual lifetime:**

```kotlin
val observer = ditto.store.registerObserver(
    query = "SELECT * FROM cars WHERE color = :color",
    arguments = mapOf("color" to "blue"),
) { result ->
    // try/catch is NOT optional: a throw here closes the observer (see below).
    try {
        val cars = result.items.map { carJson.decodeFromString<Car>(it.jsonString()) }
        /* handle change with `cars` (plain data) */
    } catch (t: Throwable) { /* log; observer survives */ }
}
```

Returns a `DittoStoreObserver` — you own it and must call `observer.close()` when done
(<https://docs.ditto.live/sdk/latest/crud/observing-data-changes>). It stays active until you close it or the
owning `Ditto` instance is closed.

**2. `observe` — cold `Flow<T>`, scope-managed lifetime:**

```kotlin
// repeatOnLifecycle(STARTED): collection stops while the UI is STOPPED.
// (In a ViewModel, prefer viewModelScope + stateIn — see "Flow lifecycle" below.)
lifecycleScope.launch {
    repeatOnLifecycle(Lifecycle.State.STARTED) {
        ditto.store.observe(
            "SELECT * FROM cars WHERE color = :color",
            mapOf("color" to "red")
        ) { result ->   // transform MUST return plain Kotlin data, not result/items
            result.items.map { carJson.decodeFromString<Car>(it.jsonString()) }
        }.collect { cars -> this@MyActivity.cars = cars }
    }
}
// No manual cleanup needed — cancelled with lifecycleScope
```

**3. `collect` — suspend function, fully serialized delivery:**

```kotlin
lifecycleScope.launch {
    ditto.store.collect(
        "SELECT * FROM cars WHERE color = :color",
        mapOf("color" to "blue"),
    ) { result ->
        // Android: this handler starts on the MAIN thread — hop off for the work
        // (see Threads below); withContext(Dispatchers.Main) alone is a no-op here.
        val cars = withContext(Dispatchers.IO) {
            result.items.map { carJson.decodeFromString<Car>(it.jsonString()) }
        }
        expensiveOperation(cars); updateUI(cars)   // updateUI is back on the handler's dispatcher
    }
}
```

Ditto only signals the core to produce the next event after the handler returns —
coroutine suspension *is* the back-pressure (<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>).

### Choosing a shape

| You need… | Use |
|---|---|
| Flow operators (`map`, `stateIn`, `combine`, `conflate`), lifecycle-tied UI state | `observe()` |
| Every event processed to completion before the next is produced (ordered pipelines, batching writes downstream) | `collect()` |
| An imperative handle to start/stop independent of any coroutine scope | `registerObserver()` |

All three have a `(result, diff)` overload — see [Diffing](#diffing-with-dittodiff).
All three deliver **immediately with the current local state**, then again on every
change: on an empty store the first emission is an empty result set, not silence —
design handlers to render the empty state.

### The critical memory rule: extract inside the lambda

> **A `DittoQueryResult` and the `DittoQueryResultItem`s it owns are native resources
> whose lifetime is bound to the observer's current event.** When your handler returns
> they are closed — before the next event is requested. **[source-verified]** 5.1.0
> closes the result in a `finally` *before* `signalNext`; 5.0.3 re-arms first but
> closes it either way — the rule holds on both (`InternalDittoStore.kt`).

Returning `result.items` from the lambda, storing them in a `var`, or capturing them in
another coroutine throws on next access:

```
IllegalStateException: Query result item has already been closed.
```

(exact string, `InternalDittoQueryResultItem.getPointer()` — **[source-verified]**;
also in <https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>). Treat results like database cursors:
extract immediately; never keep live references between emissions.

Two extraction paths, both inside the lambda:

```kotlin
// Path A — whole-document JSON + kotlinx-serialization (recommended for complex objects)
val cars = result.items.map { carJson.decodeFromString<Car>(it.jsonString()) }
// Path B — typed accessors on item.value (a DittoCborSerializable.Dictionary):
// .stringOrNull, .intOrNull, .longOrNull, .doubleOrNull, .booleanOrNull,
// .listOrNull, .dictionaryOrNull, .attachmentTokenOrNull, .isNull
val colors = result.items.map { it.value["color"].stringOrNull ?: "unknown" }
```

Do **not** cast `item.value["field"] as SomeType` — in v5 `value` is a
`DittoCborSerializable.Dictionary`, not a `Map<String, Any>`, and the cast throws at
runtime. Use the typed accessors or `jsonString()`. Full detail:
[store.md](store.md) (<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>).

The same rule applies to the `observe()` transform: it must return plain Kotlin data.
Returning the `DittoQueryResult` itself from the transform throws immediately —
`"You must not return DittoQueryResult from transform function. This will cause a
memory leak!"` (**[source-verified]**, `DittoStore.kt`).

If you extracted only a few fields, `item.dematerialize()` drops the item's
materialized Kotlin-heap value early (it re-materializes on next access to `value`;
the native buffer is freed when the result closes regardless).

### Exceptions kill observers

**[source-verified]** — this is the least documented and most damaging behavior:

- **`registerObserver`**: if your handler throws, the SDK calls
  `onEventHandlerException` (default: logs `"Unhandled exception in observer event
  handler"` via `DittoLog`) **and then closes the observer**. Your app keeps running;
  the UI simply never updates again — no crash, just a log line.
  (`InternalDittoStore.registerObserver`: `catch (t) { onEventHandlerException(t);
  storeObserver.close() }`, same in 5.0.3 and 5.1.0.)
- **`collect()`**: a handler exception is re-thrown into the collecting coroutine —
  it propagates like normal coroutine failure (closing the observer on the way out).
- **`observe()`**: a transform exception terminates the Flow with that exception; use a
  `catch { }` operator (or `retryWhen`) if one bad event must not kill the stream.

**Defense: never let an exception escape a `registerObserver` handler** — catch
inside, as in shape 1 above, and do NOT rethrow (rethrowing closes the observer).

For `observe()`, decide explicitly whether a terminated stream should be re-collected
(`retryWhen`) — Flows do not restart themselves.

### Threads: where the handler runs

**[source-verified]** every handler — `registerObserver`, `collect`, and the `observe()`
transform — is launched on the SDK's scope: **`MainScope()` on Android (the main
thread)**, `Dispatchers.Default` on JVM and iOS. Per-API table, the `Dispatchers.IO`
rationale and the scope-override option: [concurrency.md](concurrency.md#where-each-callback-runs).

Consequences for observers:

- **On Android, heavy work inside the handler janks the UI** unless you hop. The handler
  is `suspend` and the result stays open while it is suspended, so move decode to
  `Dispatchers.IO` and come back:

```kotlin
val observer = ditto.store.registerObserver("SELECT * FROM cars") { result ->
    val cars = withContext(Dispatchers.IO) {
        result.items.map { carJson.decodeFromString<Car>(it.jsonString()) }
    }
    updateUI(cars) // back on the SDK scope's dispatcher (Main on Android)
}
```

  Extraction from another dispatcher *inside* the handler is safe: the result is only
  closed when the handler returns, and item materialization is internally synchronized.
- **With `observe()`, hop inside the transform the same way.** `.flowOn(Dispatchers.IO)`
  on the returned Flow does **not** move the transform: it runs inside the SDK-launched
  handler, not in the Flow's producer
  ([why](concurrency.md#why-flowon-does-not-move-the-observe-transform)).
- On JVM the reverse caution applies: never touch Swing/Compose-desktop UI state
  directly from the handler; hop to the UI dispatcher.
- `DittoFactory.create(config, coroutineScope = …)` overrides the scope — but the SDK
  **detaches your scope's `Job`** (unparented `SupervisorJob()`, **[source-verified]**
  `InternalDittoResource.kt`): cancelling it does NOT cancel observers; `ditto.close()` does.

This replaces v4's `runOnUiThread { ... }` (<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>).

### Back-pressure: what the source actually does

`registerObserver()` and `collect()` provide back-pressure automatically: while their
`suspend` handler is running or suspended, Ditto does not produce the next event.
**[source-verified]**: the FFI callback launches the handler on the SDK scope, and
`signalNext.call()` — which re-arms the core's observer — runs only after the handler
returns and the query result is closed.

> **Coalescing**: changes that occur while your handler is running are merged — the
> next callback delivers the **latest state, not every intermediate change**
> (<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>). Never treat deliveries as an event log;
> your handler must be correct against "latest state".

**`observe()` — the docs overstate the risk; the source is more precise.** The
migration guide says `observe()` "does not back-pressure" because the Flow "signals
Ditto to produce the next event right after emitting succeeds"
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>). **[source-verified]** the implementation
(`InternalDittoStore.observe`, 5.0.3 and 5.1.0) is `callbackFlow { collect(…) { result
-> send(transform(result)) } }.buffer(Channel.RENDEZVOUS)`.

Because `send` is suspending and the channel is rendezvous (capacity 0), Ditto cannot
run ahead of the collector by more than **one received-but-unprocessed element** — it
re-arms when the collector *takes* an event, not when it finishes *processing* it. So
with a plain terminal `collect { }`, `observe()` is effectively one-at-a-time. The
flooding the docs warn about happens when **you** insert a buffering operator:

```kotlin
ditto.store.observe("SELECT * FROM cars") { result ->
    result.items.map { carJson.decodeFromString<Car>(it.jsonString()) }
}
    // .buffer()                       // ❌ default capacity 64: events queue in memory
    // .buffer(Channel.UNLIMITED)      // ❌ unbounded queue — the classic OOM
    .conflate()                        // ✅ UI: keep only the latest while collector is busy
    .collect { cars -> updateUI(cars) }
```

Rules of thumb:

- UI snapshots (only latest state matters): `.conflate()` or `stateIn(scope,
  SharingStarted.WhileSubscribed(), initial)` — both drop intermediates safely.
- Every event fully processed before the next is produced: use `collect()`, not
  `observe()` + operators.
- Never add `.buffer()` (any capacity) unless you have measured the queue depth you
  actually need.
- `collectLatest { }` is safe for "cancel in-flight work on new state" UI logic; it
  does not queue.

### Flow lifecycle: cancellation destroys the native observer

**[source-verified]** — cleanup is automatic *if you collect in a scoped coroutine*:

- `collect()` wraps the observer in `suspendCancellableCoroutine` with
  `invokeOnCancellation { observer.close() }`: cancelling the collecting coroutine
  closes the native observer. `observe()` is a `callbackFlow` whose producer runs
  `collect(...)` — cancelling the collecting scope cancels the producer and runs the
  same path.
- `registerObserver()` has **no** automatic cleanup: you must call `observer.close()`
  (or close the owning `Ditto`, which closes its child resources).

The idiomatic Android patterns that get this right:

```kotlin
// ViewModel — recommended default
class CarsViewModel(private val ditto: Ditto) : ViewModel() {
    val cars: StateFlow<List<Car>> = ditto.store
        .observe("SELECT * FROM cars ORDER BY make") { result ->
            withContext(Dispatchers.IO) {     // decode off the main thread (see Threads)
                result.items.map { carJson.decodeFromString<Car>(it.jsonString()) }
            }
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())
    // viewModelScope cancellation closes the observer — nothing else to do.
}
```

In Compose, render that `StateFlow` with `collectAsStateWithLifecycle()`; without a
ViewModel, wrap collection in `lifecycleScope.launch { repeatOnLifecycle(
Lifecycle.State.STARTED) { … } }` — the observer closes when the UI stops and is
re-created when it starts again.

Anti-pattern: `observe()` collected with `GlobalScope.launch { … }` (leaks the observer
for the process lifetime) or stored in a `val` and never collected (the Flow is **cold**
— nothing registers until collection). Introspect live registrations with
`ditto.store.observers` (<https://docs.ditto.live/sdk/latest/crud/observing-data-changes>).

Wrong/right forms for the mistakes seen in the field are collected in
[anti-patterns.md](anti-patterns.md).

### Diffing with `DittoDiff`

Available from v4.11+ (<https://docs.ditto.live/sdk/latest/crud/observing-data-changes>). All three observer
shapes have an overload whose lambda takes a second `DittoDiff` parameter:

```kotlin
// In v5 the differ is owned by the observer — you do not construct one yourself, and
// closing the observer frees its native resources. Extract plain data inside the
// lambda; never return result.items.
var previousDocumentIds: List<String> = emptyList() // extracted IDs only

val observer = ditto.store.registerObserver("SELECT * FROM cars") { result, diff ->
    val currentDocumentIds = result.items.map { item ->
        val id = item.value["_id"].stringOrNull ?: "unknown"
        item.dematerialize() // Release the materialized value early
        id
    }
    // Deletions index into the PREVIOUS emission; insertions/updates into the CURRENT one.
    diff.deletions.forEach { i -> previousDocumentIds.getOrNull(i)?.let { println("Deleted $it") } }
    diff.insertions.forEach { i -> currentDocumentIds.getOrNull(i)?.let { println("Inserted $it") } }
    diff.updates.forEach { i -> currentDocumentIds.getOrNull(i)?.let { println("Updated $it") } }
    previousDocumentIds = currentDocumentIds // IDs only — no live references!
}
```

`DittoDiff` exposes `insertions`, `deletions` and `updates` (each a `Set<Int>` of
indices) plus `moves: List<DittoDiff.Move>` (index pairs for items that changed
position). The differ deep-compares each item's **value**; it does not give you the old
and new items — retain whatever you need (e.g. the IDs above) yourself
(<https://docs.ditto.live/sdk/latest/crud/observing-data-changes>).

**v5 change:** the standalone `com.ditto.kotlin.DittoDiffer()` is no longer
user-constructible — its lifecycle is managed by the SDK (**[source-verified]**:
created as a child of the `Ditto` instance, closed in the observer's `onClose` —
`InternalDittoStore.kt`). Migrating manual
`DittoDiffer().diff(result.items)` code means switching to the `(result, diff)`
overload, which also closes a v4 native-memory leak footgun
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>).

Costs, stated plainly (<https://docs.ditto.live/sdk/latest/crud/observing-data-changes>):

- **Memory.** The differ keeps the previous result set in memory — two result sets'
  worth of state for the observer's lifetime. Opt in only where you consume the diff.
- **CPU.** Diffing is expensive and synchronous — a large result set can block.
  Debounce out-of-band at a cadence that suits the use case.
- **Semantics.** Only net value changes between emissions are reported (a value that
  changes and changes back does not appear in `updates`); metadata is not compared.

### Query constraints

Observers run **`SELECT` queries only** — writes (INSERT/UPDATE/DELETE) and DDL are
not observable statements. For DQL semantics see the `write-dql` skill or
<https://docs.ditto.live/dql/dql>.

### Migrating from v4

Short asides only — the extended tables live in [versions.md](versions.md)
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>):

- **v4's `registerObserver` callback was not `suspend`.** v5 handlers are `suspend`;
  replace `runOnUiThread { ... }` with `withContext(Dispatchers.Main)` — but read
  [Threads](#threads-where-the-handler-runs) first: on Android the
  handler already starts on the main thread; the hop you usually need is *off* it.
- **`DittoSignalNext` back-pressure is removed.** v4's
  `registerObserver(query, args) { result, signalNext -> }` overload and the
  `DittoSignalNext` / `DittoSignalNextCallback` / `DittoChangeHandler*` types are gone;
  back-pressure is now automatic via the `suspend` handler.
- **`DittoLiveQuery` and `DittoLiveQueryEvent` are removed**, along with
  `find(q).observeLocal { docs, event -> ... }`. Use a store observer
  (<https://docs.ditto.live/dql/replacing-live-queries>).
- **v4's manual `DittoDiffer()` is no longer user-constructible** — use the
  `(result, diff)` overloads.
