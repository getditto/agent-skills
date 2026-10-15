# Object lifetimes and retention

## Contents

- [The one strong reference](#the-one-strong-reference)
- [What to retain, and the symptom if you don't](#what-to-retain-and-the-symptom-if-you-dont)
- [Where to cancel, per UI framework](#where-to-cancel-per-ui-framework)
- [Two collections that must never be cached](#two-collections-that-must-never-be-cached)

What must be held to stay alive, what happens when it is dropped, and where to cancel.
The rule that changes code by default is in
[`SKILL.md` § Object lifetimes and retention](../SKILL.md#object-lifetimes-and-retention);
this file carries the per-handle table and the cancellation detail.

## The one strong reference

**Hold exactly one long-lived strong reference to `Ditto`, at the application
composition root.** `store`, `sync`, `presence`, `auth`, `smallPeerInfo` and
`experimental` hold a **weak** reference to their parent, so retaining only
`ditto.store` does not keep `ditto` alive.

There is no `close()`. Releasing the last strong reference frees the persistence
directory lock, and no second instance can open that directory until it does.

## What to retain, and the symptom if you don't

| Handle | Retain it | Symptom if you get it wrong |
|---|---|---|
| `Ditto` | for the app's lifetime | The next call through `store`, `sync`, `presence`, `auth`, `smallPeerInfo` or `experimental` is `fatalError("… the corresponding `Ditto` is `nil` …")` — a crash, not a catchable error. On 4.14.6 two of those paths, `store.registerObserver` and `store.execute`, throw `useAfterCloseError` instead. `diskUsage` is the exception: it holds no parent reference and has no such path. Full list: [`errors.md`](errors.md#errors-you-cannot-catch). |
| `DittoStoreObserver`, `DittoSyncSubscription` | for the scope that consumes it, **so you can cancel it** | Dropping the handle does **not** stop it: the observer keeps firing and keeps its closure's captures alive for the whole `Ditto` lifetime, and the subscription stays registered. You have only lost the ability to cancel. |
| `DittoAttachmentFetcher` | until the fetch completes or you `stop()` it | An abandoned fetch keeps running. Its parent reference is weak, so stopping it late is a no-op, not a crash. |
| `DittoObserver` (presence, auth status), `DittoDiskUsageObserver` | for the scope that consumes it | Stopped with `stop()`, not `cancel()` — and disk usage returns its own type. |
| `AnyCancellable` (the four Combine publishers) | for the scope that consumes it | Releasing it *does* cancel — the opposite of the observer handles. |

The asymmetry in the last two rows is the trap: `AnyCancellable` follows the Combine
convention where release means cancel, and `DittoStoreObserver` does not.

## Where to cancel, per UI framework

Cancel at the owning scope's boundary, and use `[weak self]` in callback closures.

- **SwiftUI:** `.onDisappear`, or `.task(id:)` which cancels on identity change.
  `deinit` is usually **not** available — a `@MainActor @Observable` owner's stored
  properties are actor-isolated and `deinit` is not, so it cannot touch them.
- **UIKit:** `viewDidDisappear`, or the view controller's own teardown path.
- **AppKit:** the window controller's close path. The multi-window case is the hazard —
  closing one window must not deallocate an app-wide instance or leave that window's
  observers alive.
- **`deinit`:** only where the owner is *not* actor-isolated.

Ordering matters on teardown: cancel the consumer first, then the observer, then the
subscription, then stop sync. Reversing it can deliver into a cancelled consumer.

## Two collections that must never be cached

**Do not cache `ditto.sync.subscriptions` or `ditto.store.observers`.** Both are
*computed* in v5, so a snapshot goes stale silently — it will not reflect a later
registration or cancellation, and nothing reports the divergence.

Read them at the point of use, or track your own handles alongside.
