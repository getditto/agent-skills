---
name: kotlin-sdk
description: >
  Use ONLY for the Ditto Kotlin SDK (not Swift, Java, JS, C#, C++, Rust, Flutter or
  Go — each has its own skill). Triggers on .kt/.kts files, build.gradle.kts,
  com.ditto:ditto-kotlin or live.ditto:ditto coordinates, DittoConfig,
  DittoFactory.create, registerObserver, ditto.store.execute, and errors like
  "Query result item has already been closed", "Unable to find binary
  'libdittoall'", "Identifier conflict … FAIL conflict policy". Android and JVM
  targets. Ditto SDK 4.14.x, 5.0.x, 5.1.x.
allowed-tools: Read, Grep, Glob, Edit, Write, Bash
---

# Ditto Kotlin SDK

Use the shipping API: on v5 everything is `DittoFactory.create(DittoConfig)`,
`ditto.sync`, `ditto.store` with DQL, and `suspend`/Flow observers; the v4
`Ditto(dependencies, identity)` constructor and legacy collection API are gone.
Establish the version line first (`com.ditto:ditto-kotlin` = v5, `live.ditto:ditto` =
v4, Android-only); emit v5 code by default and say which version you assumed. Do not
invent APIs from memory — the v4→v5 surface changed completely.

Read only the reference sections needed for the task. For long files, inspect the
contents first and read the matching section. Do not preload all references or the
README; the latter holds the capability/evidence map for coverage reviews.

## What this skill does

Writes and reviews Ditto Kotlin code: Gradle setup, initialization, authentication,
store access (DQL), sync, observers and Flows, attachments, presence, transports,
object lifetimes, threading, error types, and testing. Supports **4.14.x (LTS),
5.0.x and 5.1.x**, on **Android** (both lines) and **plain JVM** (5.x only).

## When to use this skill

Use this skill for **Kotlin** Ditto code: API shape, initialization, object
lifetimes, threading, error types, and build configuration.

Hand off rather than restating. Each row names a public docs URL because the concept
skill ships as a separate plugin and may not be installed:

| Question | Skill, if installed | Otherwise |
|---|---|---|
| DQL syntax, operators, statement semantics | `dql` | <https://docs.ditto.live/dql/dql> |
| Which CRDT type, embed vs split, document size, `dql_strict_mode` | `data-modeling` | <https://docs.ditto.live/key-concepts> |
| What a subscription is, mesh propagation | `sync-subscriptions` | <https://docs.ditto.live/sdk/latest/sync/syncing-data> |
| Transport selection strategy, platform radios | `ditto-mesh-networking` | <https://docs.ditto.live/sdk/latest/sync/customizing-transport-configurations> |

Do **not** use this skill for other languages — each SDK has its own skill.

## Supported versions and packages

Packages: `com.ditto:ditto-kotlin` (v5; KMP root — Gradle resolves `-android` / `-jvm`)
and `live.ditto:ditto` (4.14.x, Android-only). Published API reference:
<https://software.ditto.live/kotlin/ditto-kotlin/5.1.0/api-reference/>.

**[`references/versions.md`](references/versions.md) owns every fact that differs
across version lines**, including package coordinates per version and the minimum
toolchain. This section is a pointer, not a claim.

**When the user's version is unknown, emit 5.1.x code and say which version you
assumed.** v4 and v5 are different APIs, not two versions of one.

## Capability exceptions

Full twenty-row evidence map: [README.md](README.md), for capability reviews only.

| ID | Capability | Support | Required caveat |
|---|---|---|---|
| CAP-13 | Presence graph and connection requests | partial | Graph/metadata/`observe()` are docs-verified and single-device testable; `connectionRequestHandler` only fires with a second peer — docs-sourced, not executed here. [presence.md](references/presence.md) |
| CAP-20 | Preview and platform-specific APIs | preview | Data Streams is 5.1.0-only, Kotlin-only, behind `@OptIn(PreviewDataStreams::class)`, "breaking changes without notice"; multicast is beta. [preview.md](references/preview.md) |

## Minimum viable app

The shortest form that actually runs — open → subscribe → observe → write (JVM
shown; Android differs only in that no `ditto-binaries` classifier is needed):

```kotlin
fun main() = runBlocking {
    val ditto = DittoFactory.create(
        DittoConfig(
            databaseId = "my-app",
            connect = DittoConfig.Connect.SmallPeersOnly(),
            persistenceDirectory = "/tmp/ditto-data",
        )
    )
    ditto.setOfflineOnlyLicenseToken(System.getenv("DITTO_OFFLINE_LICENSE"))
    ditto.sync.start()

    val subscription = ditto.sync.registerSubscription("SELECT * FROM cars")
    val observer = ditto.store.registerObserver("SELECT * FROM cars") { result ->
        println("cars: ${result.items.size}")   // extract inside the lambda!
    }
    ditto.store.execute(
        "INSERT INTO cars DOCUMENTS (:car) ON ID CONFLICT DO UPDATE",
        mapOf("car" to mapOf("_id" to "car1", "make" to "Toyota"))
    )

    observer.close(); subscription.close(); ditto.sync.stop(); ditto.close()
}
```

Complete program with dependency declaration and real run transcripts for 5.1.0,
5.0.3 (JVM) and 4.14.7 (Android emulator):
[`examples/minimal-app.md`](examples/minimal-app.md).

## Concurrency and threading model

v5 is coroutines-native: async work is `suspend` or `Flow`, never callbacks.

- **Observer handlers run on the SDK's internal scope, which is platform-dependent**
  (source-verified, 5.0.3/5.1.0, `dittoCoroutineScope()`): **Android = `MainScope()` —
  your handler starts on the main thread**; JVM/iOS = `Dispatchers.Default`. Hop off
  the main thread for heavy extraction (`withContext(Dispatchers.Default)` or
  `.flowOn(Dispatchers.Default)`), back to `Dispatchers.Main` for View/UI writes.
- `DittoFactory.create`, `sync.start()/stop()`, `registerSubscription`,
  `registerObserver` are **not** suspend. `store.execute`, `store.collect`,
  `auth.login`, attachment fetches **are** suspend.
- `registerObserver`/`collect` handlers are **serialized with back-pressure**: Ditto
  produces the next event only after your handler returns, coalescing intermediate
  changes. `observe()` hands off rendezvous-style — never add `.buffer()`; use
  `.conflate()` for latest-only UI. Detail:
  [references/observers.md](references/observers.md).
- Cancelling the collecting scope (`viewModelScope`, `lifecycleScope`) closes the
  underlying native observer — `observe()`/`collect()` need no manual cleanup.
- `store.execute` is safe to call from any dispatcher. Do not call blocking APIs
  from the SDK's scope.

## Object lifetimes and retention

Everything resource-like implements `DittoResource` (`AutoCloseable`); closing the
`Ditto` instance closes its children.

| Object | Keep alive by | Symptom if dropped |
|---|---|---|
| `Ditto` | Application-level singleton (Android) or top-level `val` (JVM) for the process lifetime | all sync, observers and subscriptions stop when it closes or is finalized |
| `DittoSyncSubscription` | retain the handle (field/collection) until you want sync of that query to stop | you can't stop it except via `ditto.sync.subscriptions`; sync continues |
| `DittoStoreObserver` (from `registerObserver`) | retain and `close()` explicitly | observer stays active — leak; no automatic cleanup |
| `observe()`/`collect()` Flows | collect in a lifecycle-tied scope | `GlobalScope` collection leaks for the process lifetime; an uncollected cold Flow never registers |
| `DittoQueryResult` / items | **never retain** — closed when the handler/lambda returns | `IllegalStateException: Query result item has already been closed.` |
| attachment fetchers | `ditto.store.attachmentFetchers` tracks in-flight fetches | see [references/attachments.md](references/attachments.md) |

## Anti-patterns

### Returning live query results out of the handler

```kotlin
// WRONG
val cars = ditto.store.observe("SELECT * FROM cars") { result -> result.items }
```

**Symptom:** `IllegalStateException: Query result item has already been closed.` —
or, returning the `DittoQueryResult` itself, an immediate
`"You must not return DittoQueryResult from transform function. This will cause a
memory leak!"` (both source-verified).

```kotlin
// CORRECT — extract plain data inside the lambda
val cars = ditto.store.observe("SELECT * FROM cars") { result ->
    result.items.map { it.jsonString() }
}
```

### Letting an exception escape a `registerObserver` handler

```kotlin
// WRONG — if decodeFromString throws, the SDK logs and CLOSES the observer
val observer = ditto.store.registerObserver("SELECT * FROM cars") { result ->
    render(result.items.map { json.decodeFromString<Car>(it.jsonString()) })
}
```

**Symptom:** updates silently stop after one bad event; only a
`"Unhandled exception in observer event handler"` log line (source-verified:
the SDK catches, calls `onEventHandlerException`, then closes the observer).

```kotlin
// CORRECT — catch inside; never rethrow
val observer = ditto.store.registerObserver("SELECT * FROM cars") { result ->
    try { /* extract + render */ } catch (t: Throwable) { Log.e("cars", "event", t) }
}
```

### Buffering an `observe()` chain

```kotlin
// WRONG
ditto.store.observe("SELECT * FROM cars") { … }.buffer(Channel.UNLIMITED).collect { … }
```

**Symptom:** heap grows without bound under write load; UI lags further and further
behind. `observe()` already hands off one event at a time (source-verified rendezvous
channel) — the buffer is pure queue.

```kotlin
// CORRECT — latest-only UI
ditto.store.observe("SELECT * FROM cars") { … }.conflate().collect { … }
```

### Launching work per event inside a handler

```kotlin
// WRONG — breaks ordering, defeats back-pressure, then crashes on closed items
ditto.store.registerObserver("SELECT * FROM cars") { result ->
    scope.launch { process(result.items) }
}
```

**Symptom:** interleaved processing plus
`IllegalStateException: Query result item has already been closed.` Do the work in
the suspend handler — suspension is the rate limiter.

### `setExpirationHandler` / `launch` around `auth.login`

**Symptom:** `setExpirationHandler` **does not compile** (no such method);
`launch { auth.login(…) }` inside the handler races and can throw
`AuthenticationException`/`ExpirationHandlerMissing`. `expirationHandler` is a
**property** assigned a **suspend** lambda — call `login` directly in the body.
See [references/connect.md](references/connect.md).

### Plain re-INSERT of an existing `_id`

**Symptom:** `DittoException.UnknownException: <dql> Query failed: … Identifier
conflict on document "car1": using FAIL conflict policy` (executed). INSERT defaults
to the FAIL conflict policy — add `ON ID CONFLICT DO UPDATE` for upserts.

### Missing `ditto-binaries` on JVM

**Symptom:** `IllegalStateException: Unable to find binary 'libdittoall.dylib' for
Darwin ARM64 on classpath …` on the first `DittoFactory.create` (executed). Add
`runtimeOnly("com.ditto:ditto-binaries:<version>:<classifier>")` —
[references/setup.md](references/setup.md).

### Heavy decode on the Android main thread

**Symptom:** dropped frames / ANR risk during sync bursts — on Android, observer
handlers start on `MainScope()` (source-verified). Move extraction to
`Dispatchers.Default`; only plain data crosses back.

## Version differences

| Concern | 4.14.x | 5.0.x / 5.1.x |
|---|---|---|
| Package / namespace | `live.ditto:ditto`, `live.ditto.*` (Android-only) | `com.ditto:ditto-kotlin`, `com.ditto.kotlin.*` (Android + JVM) |
| Initialization | `Ditto(deps, DittoIdentity.…)` | `DittoFactory.create(DittoConfig(…))`, not suspend |
| Start sync | `ditto.startSync()` | `ditto.sync.start()` |
| Mutating DQL | requires `ditto.disableSyncWithV3()` first (else `StoreError: … disable sync with V3 …`, executed) | works by default |
| Query model | legacy collection API (deprecated) + DQL | DQL only, via `ditto.store.execute` |
| Observers | non-suspend callback, `DittoSignalNext` | suspend handler / `observe()` Flow / `collect()` |
| Errors | `DittoError` | `DittoException` sealed hierarchy |
| On-disk store | default dir `ditto` | default dir `ditto-{databaseId}` for new stores; existing v4 stores keep their layout |

Full delta, including on-disk store migration and the removed-API table:
[`references/versions.md`](references/versions.md).

## References

| If you need to know… | Read |
|---|---|
| How do I install it and what are the platform minimums? | [references/setup.md](references/setup.md) |
| How do I open Ditto, authenticate, and start syncing? | [references/connect.md](references/connect.md) |
| How do I change which transports are used? | [references/transports.md](references/transports.md) |
| How do I subscribe and check sync status? | [references/sync.md](references/sync.md) |
| How do I run DQL, transact, index, or evict? | [references/store.md](references/store.md) |
| How do I react to data changes without polling; how do Flows, cleanup and back-pressure work? | [references/observers.md](references/observers.md) |
| How do I store and fetch a file? | [references/attachments.md](references/attachments.md) |
| Who else is on the mesh right now? | [references/presence.md](references/presence.md) |
| How do I turn on logs and see disk usage? | [references/observability.md](references/observability.md) |
| What error is this and how do I recover? | [references/errors.md](references/errors.md) |
| How do I test code that uses Ditto? | [references/testing.md](references/testing.md) |
| What changed between 4.14.x and 5.x, on disk and in the API? | [references/versions.md](references/versions.md) |
| What is preview or platform-specific here? | [references/preview.md](references/preview.md) |
| How do I generate a whole runnable Gradle project? | [references/gradle-project-generation.md](references/gradle-project-generation.md) |
| Where should the instance live; which observer shape? | [best-practices.md](best-practices.md) |
