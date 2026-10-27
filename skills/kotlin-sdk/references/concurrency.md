# Concurrency and threading — Ditto Kotlin SDK

## Contents

- [Where each callback runs](#where-each-callback-runs)
- [The eight rules](#the-eight-rules)
- [Android: handlers start on the main thread](#android-handlers-start-on-the-main-thread)
- [Why `flowOn` does not move the `observe()` transform](#why-flowon-does-not-move-the-observe-transform)
- [Overriding the SDK scope](#overriding-the-sdk-scope)
- [Structured concurrency on Android](#structured-concurrency-on-android)
- [Tests need real time](#tests-need-real-time)

> **Sources for this file.** <https://docs.ditto.live/sdk/latest/crud/observing-data-changes>, the
> `Back-pressure` block of <https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>, and the published
> 5.1.0 artifacts: `Ditto.android.kt` / `Ditto.jvm.kt` in `ditto-kotlin-5.1.0-sources.jar`
> and `InternalDittoStore` in `ditto-internal-jvm-5.1.0.jar` (bytecode; the
> `ditto-internal` sources jar is empty). Claims marked **[source-verified]** were read
> there. The 4.14.x callback model is summarised in [versions.md](versions.md).

Which dispatcher every SDK callback starts on, and what that forces the calling code to
do. The load-bearing rules are summarised in
[`SKILL.md` § Concurrency and threading model](../SKILL.md#concurrency-and-threading-model);
this file carries the per-API table and the reasoning. Observer mechanics (shapes,
back-pressure, diffing) are in [observers.md](observers.md).

## Where each callback runs

The SDK owns one internal `CoroutineScope`, created by `dittoCoroutineScope()`
**[source-verified]**:

| Target | SDK-internal scope | A handler starts on |
|---|---|---|
| Android | `MainScope() + CoroutineName("Ditto Android")` | **the main thread** |
| JVM | `SupervisorJob() + Dispatchers.Default + CoroutineName("Ditto JVM")` | a background pool thread |
| iOS (KMP) | `Dispatchers.Default` | a background pool thread |

| API | Where its callback or body runs |
|---|---|
| `DittoFactory.create(config)` | Synchronous, on the calling thread. Not `suspend`; there is no async open. |
| `store.execute`, `store.transaction`, `store.newAttachment`, `store.fetchAttachment` | `suspend`; callable from any dispatcher. Do not call blocking APIs from the SDK scope. |
| `store.registerObserver { result -> }` | **Launched on the SDK scope for every event** — the FFI callback does `scope.launch { handler(result) }` **[source-verified]**. Main thread on Android. |
| `store.collect { result -> }` | Same: `collect` is `suspendCancellableCoroutine` around `registerObserver`, with no context switch **[source-verified]**. The *calling* coroutine only suspends and owns cancellation. |
| `store.observe { result -> }` transform | Same as `collect`: `observe` is `callbackFlow { collect(…) { send(transform(it)) } }.buffer(RENDEZVOUS)` **[source-verified]**. Downstream operators and the collector run in the **collector's** context. |
| `auth.expirationHandler = { ditto, t -> }` | Invoked by the SDK on its scope. It is a `suspend` lambda: call `login` directly, never `launch`. |
| `auth.observeStatus()`, `presence.observe()`, `DittoLogger.observeLogEvents()`, `sync.observe…` Flows | Cold/hot Flows: your collector's context. Cancel with the collecting scope. |
| `presence.connectionRequestHandler` | SDK scope; keep it fast and side-effect free ([presence.md](presence.md)). |

## The eight rules

1. **Never assume a handler is off the main thread — on Android it *is* the main
   thread.** Treat every observer handler as UI-thread code: cheap, non-blocking.
2. **Extract inside the handler.** `DittoQueryResult` and its items are closed when the
   handler returns. Map to plain Kotlin data (`jsonString()`, typed accessors) before
   anything crosses a coroutine or scope boundary
   ([observers.md](observers.md#the-critical-memory-rule-extract-inside-the-lambda)).
3. **Do the heavy work inside the handler with `withContext(Dispatchers.IO)`.** The
   result is still open while the handler is suspended, so extraction and decode can hop
   off main and come back. **`.flowOn()` does not reach the `observe()` transform** —
   see [below](#why-flowon-does-not-move-the-observe-transform).
4. **Never let an exception escape a `registerObserver` handler.** The SDK logs it and
   closes the observer; the UI silently stops updating. Catch inside, do not rethrow.
   `collect()` rethrows into the collecting coroutine; `observe()` fails the Flow.
5. **One handler at a time is the back-pressure.** Ditto produces the next event only
   after the handler returns and the result is closed. Do not `launch` per event (loses
   ordering, trips rule 2) and do not add `.buffer()` (queues state in memory). Use
   `.conflate()` or `stateIn` for latest-only UI; use `collect()` for in-order pipelines.
6. **Cancellation is cleanup for Flows, not for handles.** Cancelling the scope that
   collects `observe()`/`collect()` closes the native observer. A `registerObserver`
   handle needs an explicit `close()` ([lifetimes.md](lifetimes.md)).
7. **The scope you pass to `DittoFactory.create` is detached.** Its `Job` is replaced by
   an unparented `SupervisorJob()` **[source-verified]**: cancelling your scope does not
   stop observers — only `ditto.close()` does. Its *dispatcher* is kept, which is the
   one supported way to change where handlers start ([below](#overriding-the-sdk-scope)).
8. **`expirationHandler` runs in a suspend context the SDK waits on.** Call
   `ditto.auth?.login(...)` directly in the body. Wrapping it in `launch { }` returns
   immediately and leaves sync unauthenticated
   ([connect.md](connect.md#cap-04-authentication-and-identity)).

## Android: handlers start on the main thread

Because the SDK scope is `MainScope()` on Android, a handler that decodes hundreds of
documents with `jsonString()` + kotlinx-serialization is CPU work on the UI thread — the
most common source of jank in Ditto-Kotlin apps. The handler is `suspend`, so hop:

```kotlin
val observer = ditto.store.registerObserver("SELECT * FROM cars") { result ->
    val cars = withContext(Dispatchers.IO) {          // result is still open here
        result.items.map { carJson.decodeFromString<Car>(it.jsonString()) }
    }
    render(cars)                                       // back on Main (Android)
}
```

Extraction from another dispatcher *inside* the handler is safe: the result is closed
only when the handler returns, and item materialisation is internally synchronised.

**Why `Dispatchers.IO` and not `Default`:** on Android and JVM both are real off-main
pools (they share threads). On Kotlin/Native (iOS) `Dispatchers.IO` is a separate
`DefaultIoScheduler` pool **[source-verified]** in kotlinx-coroutines 1.9.0 (what 5.1.0
builds against) and 1.10.x, so `IO` is the one dispatcher that is off-main on all three
KMP targets without a platform carve-out.

On JVM the reverse caution applies: handlers start on `Dispatchers.Default`, so never
touch Swing/Compose-desktop UI state from a handler; hop to the UI dispatcher.

## Why `flowOn` does not move the `observe()` transform

```kotlin
// WRONG — the transform still runs on the SDK scope (Main on Android)
ditto.store.observe("SELECT * FROM cars") { r -> r.items.map { decode(it.jsonString()) } }
    .flowOn(Dispatchers.IO)
    .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

// CORRECT — hop inside the transform; it is a suspend lambda
ditto.store.observe("SELECT * FROM cars") { r ->
    withContext(Dispatchers.IO) { r.items.map { decode(it.jsonString()) } }
}.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())
```

**[source-verified, 5.1.0 bytecode]** `observe()` is `callbackFlow { collect(query) {
result -> send(transform(result)) } }.buffer(…)`. `flowOn` changes the context of the
`callbackFlow` *producer block* — the coroutine that calls `collect` and then suspends.
But `collect` only registers an observer; each event's handler (which contains the
`transform` call) is launched by the FFI callback on the SDK scope. Nothing in that path
reads the producer's context, so the transform's dispatcher is the SDK's, not
`flowOn`'s. The docs' own warning that `observe()` "does not back-pressure" refers to
this hand-off; see [observers.md](observers.md#back-pressure-what-the-source-actually-does).

Established from the published 5.1.0 bytecode and **executed** on JVM (5.0.3 and 5.1.0,
CI): a transform that records `Thread.currentThread().name` under
`.flowOn(newSingleThreadContext("probe"))` reports a `DefaultDispatcher-worker` thread,
never `probe`.

## Overriding the SDK scope

`DittoFactory.create(config, coroutineScope = CoroutineScope(Dispatchers.Default))`
keeps your dispatcher and discards your `Job` **[source-verified]**. On Android this
moves **every** handler off the main thread at once — then each UI write inside a
handler needs an explicit `withContext(Dispatchers.Main)`, and the rule-1 assumption
flips for the whole app. Prefer the per-handler `withContext(Dispatchers.IO)` unless the
app has no UI (a service or worker process). Not executed in this skill's harness.

## Structured concurrency on Android

- **ViewModel (default):** `observe(…) { … }.stateIn(viewModelScope,
  SharingStarted.WhileSubscribed(5_000), initial)`; Compose renders with
  `collectAsStateWithLifecycle()`. Cancelling `viewModelScope` closes the observer.
- **Activity/Fragment without a ViewModel:** `lifecycleScope.launch {
  repeatOnLifecycle(Lifecycle.State.STARTED) { … .collect { } } }` — the observer closes
  when the UI stops and is re-created when it starts.
- **Never `GlobalScope`.** It leaks the observer for the process lifetime.
- **Writes** (`store.execute`) are `suspend` and safe from any scope; do them from the
  ViewModel or repository scope, not from inside an observer handler of the same query
  (that creates a write → event → write loop).

## Tests need real time

Ditto delivers observer events from real FFI threads. `runTest` fast-forwards *virtual*
time, so a `withTimeout` inside it expires before a write round-trips
(`TimeoutCancellationException: Timed out … of _virtual_ time` — executed). Use
`runBlocking` for observer tests; `runTest` is fine for pure `execute` round-trips.
Detail: [testing.md](testing.md).
