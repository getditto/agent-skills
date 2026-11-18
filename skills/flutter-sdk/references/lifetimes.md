# Object lifetimes and retention — Flutter

What must be held to stay alive, what happens when it is dropped, and where to cancel.
The rule that changes code by default is in
[`SKILL.md` § Object lifetimes and retention](../SKILL.md#object-lifetimes-and-retention);
this file carries the table. Widget wiring: [widget-integration.md](widget-integration.md).

## Contents

- [The one strong reference](#the-one-strong-reference)
- [What to retain, and the symptom if you don't](#what-to-retain-and-the-symptom-if-you-dont)
- [Where to cancel](#where-to-cancel)

## The one strong reference

**Hold one `Ditto` for the life of the process**, opened before `runApp` and owned by a
service object ([connect.md](connect.md#open-configure-close-on-failure)). `ditto.store`,
`ditto.sync`, `ditto.presence` and `ditto.auth` are parts of that instance, not separate
resources: they are only usable while it is open.

- **Use after close is a catchable error,** not a crash: `close()` marks the instance
  closed and every later call fails with `DittoClosedException`, thrown at the call for
  synchronous APIs and through the `Future` for `execute` (executed, macOS, 5.0.4 to
  5.2.0).
- **Losing the `Ditto` reference does not close it.** While the native instance is
  alive it keeps its directory locked, and a second `Ditto.open` of that directory fails
  with `DittoException(File already locked, …)` (executed, with the first instance
  still referenced, and after a hot restart, which drops every Dart reference). Call
  `close()`, or let the process end.
- **Do not close and re-open in one process.** A handle of the closed instance freed
  later by the garbage collector aborted the app (5.0.4, 3 of 3 runs) or deadlocked it
  (5.1.0 3 of 3, 5.2.0 2 of 3) on macOS debug with logging on, after `await close()`
  ([connect.md](connect.md#shutdown-and-ownership)). After a failed open or configure,
  close and have the user relaunch.
- **A hot restart orphans the instance.** It is never closed, keeps running and
  syncing, and keeps its directory locked, so the new `main()` cannot open it; Dart
  statics are reset, so no holder survives
  ([widget-integration.md](widget-integration.md#hot-restart)).

## What to retain, and the symptom if you don't

**Dropping a handle never cancels anything.** Every handle below keeps working after its
last Dart reference is gone, because the native side or the `Store` owns it. Keep the
handle so you can cancel it.

| Handle | Retain it | Symptom if you get it wrong |
|---|---|---|
| `Ditto` | A service object for the whole process | Lost: the directory stays locked and the next open fails with `File already locked`. Closed early: every call throws `DittoClosedException` |
| `StoreObserver` (V1) and its `changes` subscription | The repository or `State` that needs the data; cancel the subscription, then the observer | Listener cancelled only: the observer keeps running and `onChange` keeps firing (executed). Listener never attached (5.1.0+): it never starts. Re-listening: `StateError` |
| `StoreObserverV2` (5.1.0+) | The `StreamSubscription` on `changes` | Cancelling the subscription cancels the observer (executed); dropping it without cancelling leaves it running |
| `SyncSubscription` | The object that owns the data need | Dropped: still registered, and so still active, until cancelled through `ditto.sync.subscriptions` (executed) |
| `PresenceObserver` | Whoever shows presence; call `stop()` | Dropped: the callback keeps firing until `stop()` or `close()` (5.2.0 source) |
| `AttachmentFetcher` | The screen waiting for the bytes, to `stop()` an abandoned fetch | Dropped: the fetch runs to completion; the store tracks it in `attachmentFetchers` (source) |
| `TransportConditionsObserver` (5.1.0+) | Whoever logs conditions; `stop()` | Dropping it was not tested; `close()` ends it (source) |
| `QueryResult` / `QueryResultItem` | Do not keep them in widget or view-model state: map `items` once to plain maps (or your model) and keep that | Keeping one keeps its native result alive, and every pass over `items` builds new items and decodes again (`value` is cached per item object only; `store/execute.dart` @ `sdk-release-5.2.0`). `mutatedDocumentIDs()` is recomputed on each call |
| `Transaction` | Never: only inside the `transaction` callback | Using it after the callback returns is unsupported (dartdoc) |

On 5.2.0, `ditto.store.observers` lists the V1 observers still alive, which finds
observers you dropped without cancelling
([observers.md](observers.md#finding-leaked-observers-520)). A listener closure keeps
what it captures alive (a `State`, a controller) for as long as the observer runs.

## Where to cancel

**Cancel while Ditto is open.** After `close()`, `cancel()` on a V1 observer throws
`DittoClosedException` on 5.0.4 and 4.14.7 and does nothing on 5.1.0+, and on every line
the `changes` stream of a still-live observer is never closed, so `onDone` never runs
(source; [observers.md](observers.md#cancelling)).

| Owner | Cancel in | Notes |
|---|---|---|
| Repository (default pattern) | Its `dispose()`, called by the root `State.dispose()` or on exit, before `ditto.close()` | Listener first, then the observer |
| A screen's `State` (small apps) | `State.dispose()`: `unawaited(subscription.cancel())`, then `observer.cancel()` | `dispose` cannot await; Ditto must still be open |
| App shutdown | `AppLifecycleListener.onExitRequested` (desktop): cancel, then `await ditto.close()` | Never `close()` in `State.dispose()`, `onPause` or `onDetach` |
| Tests | Inside the test body, before the helper closes Ditto | [testing.md](testing.md#ditto-in-the-loop-integration_test) |

The one handle whose release semantics invert the others: a **V2** observer is cancelled
by cancelling its stream subscription; a **V1** observer is not.
