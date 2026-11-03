# Anti-patterns — the wrong form, the right form, and the symptom

## Contents

- [Returning live query results out of the handler](#returning-live-query-results-out-of-the-handler)
- [Letting an exception escape a `registerObserver` handler](#letting-an-exception-escape-a-registerobserver-handler)
- [Buffering an `observe()` chain](#buffering-an-observe-chain)
- [Launching work per event inside a handler](#launching-work-per-event-inside-a-handler)
- [Using `flowOn` to move decoding off the main thread](#using-flowon-to-move-decoding-off-the-main-thread)
- [Heavy decode on the Android main thread](#heavy-decode-on-the-android-main-thread)
- [Casting `item.value["field"]` to a Kotlin type](#casting-itemvaluefield-to-a-kotlin-type)
- [`setExpirationHandler` or `launch` around `auth.login`](#setexpirationhandler-or-launch-around-authlogin)
- [Plain re-INSERT of an existing `_id`](#plain-re-insert-of-an-existing-_id)
- [Missing `ditto-binaries` on JVM](#missing-ditto-binaries-on-jvm)
- [Collecting in `GlobalScope`, or never collecting](#collecting-in-globalscope-or-never-collecting)
- [Treating deliveries as an event log](#treating-deliveries-as-an-event-log)

Each of these compiles. Most produce no error at runtime either — the symptom is a
frozen screen, a leak, or an exception on the *next* access. The one-line rules are in
[`SKILL.md` § Anti-patterns](../SKILL.md#anti-patterns); this file carries the code and
the diagnosis. Strings marked **(executed)** were produced by the harness; those marked
**[source-verified]** were read in the published 5.1.0 sources.

## Returning live query results out of the handler

```kotlin
// WRONG
val cars = ditto.store.observe("SELECT * FROM cars") { result -> result.items }

// CORRECT — extract plain data inside the lambda
val cars = ditto.store.observe("SELECT * FROM cars") { result ->
    result.items.map { it.jsonString() }
}
```

**Symptom:** `IllegalStateException: Query result item has already been closed.` on the
next access **[source-verified]** — or, returning the `DittoQueryResult` itself from an
`observe()` transform, an immediate `"You must not return DittoQueryResult from
transform function. This will cause a memory leak!"` **[source-verified]** `DittoStore.kt`.
Storing items in a `var`, or reading them from a coroutine launched inside the handler,
fails the same way. Treat results like database cursors.

## Letting an exception escape a `registerObserver` handler

```kotlin
// WRONG — if decodeFromString throws, the SDK logs and CLOSES the observer
val observer = ditto.store.registerObserver("SELECT * FROM cars") { result ->
    render(result.items.map { json.decodeFromString<Car>(it.jsonString()) })
}

// CORRECT — catch inside; never rethrow
val observer = ditto.store.registerObserver("SELECT * FROM cars") { result ->
    try { render(result.items.map { json.decodeFromString<Car>(it.jsonString()) }) }
    catch (t: Throwable) { Log.e("cars", "event", t) }
}
```

**Symptom:** updates silently stop after one bad event; the only trace is an
`"Unhandled exception in observer event handler"` log line **[source-verified]**: the
SDK catches, calls `onEventHandlerException`, then closes the observer. `collect()`
rethrows into the collecting coroutine instead; `observe()` terminates the Flow — add
`catch { }` or `retryWhen` if one bad event must not kill the stream.

## Buffering an `observe()` chain

```kotlin
// WRONG
ditto.store.observe("SELECT * FROM cars") { … }.buffer(Channel.UNLIMITED).collect { … }

// CORRECT — latest-only UI
ditto.store.observe("SELECT * FROM cars") { … }.conflate().collect { … }
```

**Symptom:** heap grows without bound under write load; the UI lags further and further
behind. `observe()` already hands off one event at a time through a rendezvous channel
**[source-verified]** — a `.buffer()` of any capacity is pure queue.
`stateIn(scope, SharingStarted.WhileSubscribed(), initial)` and `collectLatest { }` are
the safe alternatives for UI.

## Launching work per event inside a handler

```kotlin
// WRONG — breaks ordering, defeats back-pressure, then crashes on closed items
ditto.store.registerObserver("SELECT * FROM cars") { result ->
    scope.launch { process(result.items) }
}
```

**Symptom:** interleaved processing plus
`IllegalStateException: Query result item has already been closed.` when the launched
coroutine reads items after the handler returned. Do the work in the `suspend` handler
— suspension is the rate limiter; hop with `withContext`, not `launch`.

## Using `flowOn` to move decoding off the main thread

```kotlin
// WRONG — the transform still runs on the SDK scope (Main on Android)
ditto.store.observe(q) { r -> r.items.map { decode(it.jsonString()) } }
    .flowOn(Dispatchers.IO)

// CORRECT — hop inside the transform
ditto.store.observe(q) { r -> withContext(Dispatchers.IO) { r.items.map { decode(it.jsonString()) } } }
```

**Symptom:** jank persists on Android with `flowOn` in place; a profiler shows decode on
`main`. `flowOn` moves the `callbackFlow` producer, not the SDK-launched handler that
contains the transform — see
[concurrency.md](concurrency.md#why-flowon-does-not-move-the-observe-transform).

## Heavy decode on the Android main thread

**Symptom:** dropped frames or ANR risk during sync bursts. On Android every observer
handler starts on `MainScope()` **[source-verified]** `Ditto.android.kt`. Move
extraction and I/O to `Dispatchers.IO` inside the handler; only plain data comes back to
main ([concurrency.md](concurrency.md#android-handlers-start-on-the-main-thread)).

## Casting `item.value["field"]` to a Kotlin type

```kotlin
val color = item.value["color"] as String            // WRONG — v5 value is not a Map
val color = item.value["color"].stringOrNull ?: ""    // CORRECT — typed accessor
val car   = json.decodeFromString<Car>(item.jsonString())   // CORRECT — whole document
```

**Symptom:** `ClassCastException` at runtime. In v5 `item.value` is a
`DittoCborSerializable.Dictionary`; its elements expose `.stringOrNull`, `.intOrNull`,
`.longOrNull`, `.doubleOrNull`, `.booleanOrNull`, `.listOrNull`, `.dictionaryOrNull`,
`.attachmentTokenOrNull`, `.isNull` ([store.md](store.md)).

## `setExpirationHandler` or `launch` around `auth.login`

```kotlin
// WRONG — does not compile; there is no such method
ditto.auth?.setExpirationHandler { … }

// WRONG — returns immediately, abandons the login
auth.expirationHandler = { ditto, t -> CoroutineScope(Dispatchers.IO).launch { ditto.auth?.login(token, provider) } }

// CORRECT — a property holding a suspend lambda; call login directly
auth.expirationHandler = { ditto, _ -> ditto.auth?.login(token, DittoAuthenticationProvider.development()) }
```

**Symptom:** the first form fails to compile; the second races and can throw
`DittoException.AuthenticationException` with reason `ExpirationHandlerMissing` when
sync starts unauthenticated ([connect.md](connect.md#cap-04-authentication-and-identity)).

## Plain re-INSERT of an existing `_id`

**Symptom (executed):** `DittoException.UnknownException: <dql> Query failed: …
Identifier conflict on document "car1": using FAIL conflict policy`. `INSERT` defaults to
the FAIL policy — write `INSERT INTO cars DOCUMENTS (:car) ON ID CONFLICT DO UPDATE` for
an upsert ([store.md](store.md)).

## Missing `ditto-binaries` on JVM

**Symptom (executed):** `IllegalStateException: Unable to find binary 'libdittoall.dylib'
for Darwin ARM64 on classpath …` on the first `DittoFactory.create`. Add
`runtimeOnly("com.ditto:ditto-binaries:<version>:<classifier>")` with the host's
classifier ([setup.md](setup.md#cap-01-prerequisites-and-install)). Android needs none.

## Collecting in `GlobalScope`, or never collecting

```kotlin
GlobalScope.launch { ditto.store.observe(q) { … }.collect { } }   // WRONG — leaks for the process
val flow = ditto.store.observe(q) { … }                            // WRONG alone — cold; registers nothing
```

**Symptom:** the first keeps a native observer alive for the process lifetime; the
second never fires. Collect in `viewModelScope` or under `repeatOnLifecycle`
([lifetimes.md](lifetimes.md#where-to-close-per-component)).

## Treating deliveries as an event log

**Symptom:** "missing" intermediate states. Changes that occur while the handler runs are
coalesced; the next delivery is the **latest state**, not every change
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>). Derive progress or history from your own
writes, not from observer emissions; use the `(result, diff)` overload for what changed
([observers.md](observers.md#diffing-with-dittodiff)).
