# Object lifetimes and retention — Ditto Kotlin SDK

## Contents

- [One instance, owned for the process](#one-instance-owned-for-the-process)
- [What to retain, and the symptom if you don't](#what-to-retain-and-the-symptom-if-you-dont)
- [Where to close, per component](#where-to-close-per-component)
- [Two collections that must never be cached](#two-collections-that-must-never-be-cached)
- [Subscriptions survive sync stop/start](#subscriptions-survive-sync-stopstart)

What must be held to stay alive, what happens when it is dropped, and where to close.
The rule that changes code by default is in
[`SKILL.md` § Object lifetimes and retention](../SKILL.md#object-lifetimes-and-retention);
this file carries the per-handle table and the cleanup detail.

## One instance, owned for the process

Every resource-like type implements `DittoResource`, which extends `AutoCloseable`
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>). Closing the `Ditto` instance closes its
children — observers, subscriptions, attachment fetchers. Only one live instance may
hold a persistence directory; `close()` releases that lock for a later open.

Create **once** and hold for the process lifetime:

- **Android:** a field on the `Application` subclass, or a DI singleton
  (`@Singleton` in Hilt, `single { }` in Koin). Never per-Activity or per-ViewModel —
  configuration changes would open a second instance over the same directory. The SDK
  obtains its `Context` itself via `DittoInitializer` (AndroidX Startup), so the
  singleton needs no context plumbing ([connect.md](connect.md#android-no-context-parameter)).
- **JVM:** a lazily created `object` holder; close it in a shutdown hook so native
  resources flush ([connect.md](connect.md#ownership)).

In an app you normally never call `ditto.close()`; the instance dies with the process.
Call it for short-lived instances: tests, CLI tools, a second per-user store.

## What to retain, and the symptom if you don't

| Handle | Keep it alive by | Symptom if dropped |
|---|---|---|
| `Ditto` | app-level singleton (Android) or top-level `val` (JVM) | Everything stops: sync, observers and subscriptions end when it is closed or collected. |
| `DittoSyncSubscription` | retain the handle (field or `MutableList`) until that query should stop syncing | You cannot stop it except through `ditto.sync.subscriptions`; sync of that query continues. |
| `DittoStoreObserver` from `registerObserver` | retain and **`close()` explicitly** | Observer stays active and keeps its captures alive — a leak. No automatic cleanup. |
| `observe()` / `collect()` | collect in a lifecycle-tied scope (`viewModelScope`, `lifecycleScope`) | `GlobalScope` collection leaks for the process lifetime; a Flow stored in a `val` and never collected registers nothing (it is **cold**). |
| `DittoQueryResult` and its items | **never retain** — closed when the handler or `execute` lambda returns | `IllegalStateException: Query result item has already been closed.` on next access. |
| `DittoAttachmentFetcher` | `ditto.store.attachmentFetchers` tracks in-flight fetches | An abandoned fetch keeps running until it completes or the attachment is deleted ([attachments.md](attachments.md)). |

Child resources hold a reference to their parent, so a leaked observer also pins the
`Ditto` instance; closing the parent is the one operation that cleans up everything.

## Where to close, per component

Close at the owning scope's boundary, in this order: observers → subscriptions you own
→ `sync.stop()` (only if this is instance teardown) → `ditto.close()`.

- **ViewModel:** expose `observe(…).stateIn(viewModelScope, …)`; nothing to close. A
  `registerObserver` handle held by a ViewModel is closed in `onCleared()`.
- **Activity / Fragment:** `repeatOnLifecycle(STARTED)` around collection; the observer
  closes when the UI stops. Do not open or close `Ditto` here.
- **Compose:** `collectAsStateWithLifecycle()` on a ViewModel `StateFlow`; never create
  observers inside a composable body.
- **Application / DI singleton:** owns `Ditto` and app-wide subscriptions for the whole
  process; registers them once after `sync.start()`.
- **JVM service:** a shutdown hook closes observers, then `ditto`.

Cancelling a coroutine scope closes the Flow-based observers it collects
([concurrency.md](concurrency.md#the-eight-rules), rule 6). It does **not** close a
`registerObserver` handle — that path has no scope.

## Two collections that must never be cached

`ditto.sync.subscriptions`, `ditto.store.observers` and `ditto.store.attachmentFetchers`
are **delegated live views** over the SDK's registry
(`by implementation::subscriptions.mapEach { it.toFacade() }` — **[source-verified]**
`DittoSync.kt`, `DittoStore.kt` in the 5.1.0 sources jar). Read them at the point of use;
a copy stored in a field goes stale silently and never reflects a later registration or
close. They are the escape hatch for a handle you failed to keep, not a bookkeeping
structure.

## Subscriptions survive sync stop/start

`sync.stop()` pauses subscriptions and disconnects from peers but does not remove
anything (<https://docs.ditto.live/sdk/latest/sync/syncing-data>). Register subscriptions once at startup; a
subscription re-registered on every foreground transition just accumulates duplicates
that `ditto.sync.subscriptions` will show. Stopping sync is the switch for a "work
offline" mode, not instance teardown.
