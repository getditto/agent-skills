# Best practices — Ditto Kotlin SDK

Idiom and judgement, not API reference. If a claim here were about the API surface it
would live in `references/`; these are the choices between two approaches that both
compile. Anything with a named symptom (exception, compiler error, profiler symbol) is
in `SKILL.md` § Anti-patterns instead — that section is always loaded, this file is
not.

## Instance ownership

One `Ditto` instance per app, created once and owned for the process lifetime:

- **Android:** lazily from the `Application` class (or your DI graph's singleton
  scope), *not* in an Activity/ViewModel — configuration changes and process restarts
  must not create a second instance over the same persistence directory. The SDK gets
  its `Context` itself via `DittoInitializer` (AndroidX Startup), so the singleton
  needs no context plumbing.
- **JVM/server:** a top-level singleton created at startup; close it in a shutdown
  hook (`Runtime.addShutdownHook` or your framework's stop callback) so native
  resources flush cleanly.

Creating two live instances over one persistence directory is the failure to avoid;
if you truly need a second store, give it a distinct `persistenceDirectory`.

## Structuring async work

Everything async is `suspend` or `Flow` — structure around scopes, not callbacks:

- ViewModels expose `StateFlow`s built with
  `observe(…) { … }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), …)`;
  Compose/Views collect them lifecycle-aware. The observer's native resources die with
  the scope — there is nothing to remember to close.
- Reach for `registerObserver` (manual handle) only when the consumer is genuinely
  imperative — a non-coroutine API boundary, a test, or lifetime tied to something
  other than a coroutine scope.
- Reach for `collect()` when downstream work must fully complete before Ditto produces
  the next event (e.g. applying events to another store in order). Suspension is the
  rate limiter; don't re-implement it with channels.

## Retaining handles

Keep what you must later close, in the same place you keep everything else with a
lifetime:

- Subscriptions: a `MutableList<DittoSyncSubscription>` (or individual `var`s) on the
  same singleton that owns `Ditto`. Register them once at startup; they survive
  `sync.stop()`/`start()` cycles, so re-registering on every foreground transition
  just accumulates duplicates (`ditto.sync.subscriptions` shows them).
- Observers from `observe()`/`collect()`: nothing to retain — the scope is the handle.
- Observers from `registerObserver`: retain and close in the owner's `close()`/
  `onCleared()`. If you didn't keep the handle, `ditto.store.observers` is the escape
  hatch.

## Writes

- Always bind arguments (`mapOf("id" to id)`), never interpolate values into DQL
  strings — correctness (escaping) first, plan reuse second.
- Decide the conflict policy deliberately: plain `INSERT` fails on an existing `_id`
  (FAIL policy — see SKILL.md §8); use `ON ID CONFLICT DO UPDATE` when the write is
  an upsert.
- A `store.transaction { }` earns its cost when several statements must commit or roll
  back together, or when read-modify-write must not interleave with other writers.
  Don't wrap single statements. Never call `ditto.store.execute` from inside the
  transaction block ([references/store.md](references/store.md)).
- Writes are local commits — they do not wait for any peer. Design UI that renders
  from the store, not from write acknowledgements.

## Reads and observers

- Prefer **one observer per screen's query**, not one per row or per field: each
  observer re-runs its query on every relevant change, so ten narrow observers cost
  more than one well-shaped one — and latest-state coalescing means you weren't going
  to get finer granularity anyway.
- Use the `(result, diff)` overload only where a UI widget consumes incremental
  updates (a diffable list). The differ holds a second result set in memory for the
  observer's lifetime; for a `TextView` it's pure overhead.
- `observe()` + `conflate()` for UI; `collect()` for pipelines. Never `.buffer()` —
  see [references/observers.md](references/observers.md) for the source-level reason.

## Error handling

- Catch `DittoException` and branch on the sealed subclass (`when`), not on message
  text — messages are not a stable API ([references/errors.md](references/errors.md)).
- Retry: network/transport hiccups are self-healing — sync resumes; don't build retry
  loops around `execute`. Surface: authentication failures and invalid-config crashes.
  Fatal: `DittoException.FatalException` — log, crash-report, and let the app
  restart rather than trying to continue on a possibly-corrupt instance.

## Sync handling

- Start sync once, at app start, after auth is configured; leave it running. Stop it
  for user sign-out, data-usage gating, or a deliberate "offline mode" toggle — not on
  every backgrounding (the OS already suspends you; on Android the
  `DefaultDittoForegroundService` exists for when background sync is the point —
  [references/transports.md](references/transports.md)).
- "Started" is not "connected" — sync state comes from presence and the
  `system:data_sync_info` collection, not from `sync.start()` returning
  ([references/sync.md](references/sync.md), [references/presence.md](references/presence.md)).

## Performance

- On Android, observer handlers start on the main thread (source-verified
  `MainScope()`): keep handler bodies cheap and push extraction/deserialization and
  I/O to `Dispatchers.IO`. Unlike `Dispatchers.Default`, `IO` is a real off-main pool
  on **all three** KMP targets — including iOS/Native (source-verified,
  kotlinx-coroutines 1.9.0 and 1.10.x), so it's the one dispatcher you can recommend
  in shared KMP code without a platform carve-out. A observer decoding hundreds of documents per
  emission on main is the most common Ditto-Kotlin jank source. (Unmeasured claim —
  profile before optimizing; the dispatcher facts themselves are verified.)
- Evict on a cadence, not on every write: `EVICT` is a maintenance operation
  ([references/store.md](references/store.md)).
- Keep documents small enough for your slowest transport — sizing guidance is owned by
  the `ditto-mesh-networking` skill (<https://docs.ditto.live/sdk/latest/sync/customizing-transport-configurations>).

## Common mistakes

Architectural ones without a single symptom (the symptomatic ones are in SKILL.md §8):

- **Treating the store as a cache of last-known server state.** It's the local
  database; sync is a property of the mesh, not a request/response layer. Model data
  as if offline is the normal case.
- **Re-registering subscriptions on lifecycle events.** Register once at startup;
  subscriptions outlive sync stop/start.
- **A repository layer that converts observers to one-shot suspending calls.**
  `first()` on an observer Flow gives you the initial local state — correct for
  "read current value", wrong if you actually wanted "wait until sync delivers".
  Use `first { predicate }` with a timeout and say which you meant.
- **One giant `observe("SELECT * FROM huge")` feeding the whole app.** Shape queries
  per screen; the observer re-runs the whole query on any matching change.
