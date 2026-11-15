# Object lifetimes and retention — Ditto Rust SDK

## Contents

- [Handle table](#handle-table)
- [Drop does not cancel observers or subscriptions](#drop-does-not-cancel-observers-or-subscriptions)
- [The `Ditto` instance](#the-ditto-instance)
- [Query results](#query-results)
- [Live views are snapshots](#live-views-are-snapshots)

Detail behind `SKILL.md` § *Object lifetimes and retention*. "Executed" rows are
assertions in the skill's test suite on 5.0.4, 5.1.0 and 5.2.0.

## Handle table

| Value | Returned as | Dropping the last reference | Stop it with | Evidence |
|---|---|---|---|---|
| `Ditto` | `Ditto` (not `Clone`) | stops sync, shuts down; later calls through `Weak` children fail `ReleasedDittoInstance` | `drop` / `close(self)` | executed |
| `StoreObserver` | `Arc<StoreObserver>` | **nothing** — keeps firing, stays in `observers()` | `cancel()` | executed |
| `SyncSubscription` | `Arc<SyncSubscription>` | **nothing** — stays in `subscriptions()` | `cancel()` | executed |
| `PresenceObserver` | `PresenceObserver` | not verified; the `Ditto::presence` rustdoc says drop cancels, but the type has no `Drop` impl | `cancel()` | source (`src/presence/observer.rs`) |
| `DittoAttachmentFetcher` (V2) | value, `Clone` | nothing — the fetch continues to completion | `cancel()` | source (`src/store/attachment/fetcher.rs`) |
| `DiskUsageObserverHandle` | `Arc<…>` | stops observation | `drop` | source (`src/disk_usage/mod.rs`) |
| Data Streams `Acceptor` | value | unbinds the topic | `drop` | source (preview) |
| `QueryResult` / `QueryResultItem` | owned values, `Send + Sync` | frees the result | — | executed |

Rule of thumb: **anything with a `cancel()` method must have it called**, either
explicitly or through a guard ([tokio.md](tokio.md#cancel-on-drop-guard)).

## Drop does not cancel observers or subscriptions

The `register_observer` rustdoc says an observer stays active "until the
`StoreObserver` handle gets dropped". In 5.0.4–5.2.0 it does not stop: the Rust handle
has no `Drop`, and the core keeps the observer registered on its own. The
`register_subscription` rustdoc does say drop won't cancel. Executed:

```rust
let _ = ditto.store().register_observer("SELECT * FROM cars", |r| println!("{}", r.item_count()))?;
// `let _ =` drops the Arc here — and the observer keeps printing on every change.
```

The symptom is a leak that looks like a feature working: duplicate deliveries after a
component is recreated, rising CPU as observers pile up, or subscriptions that keep
pulling data from peers after the screen that wanted it closed. Count them with
`ditto.sync().subscriptions().len()` while debugging.

Correct forms: keep the `Arc` and call `cancel()` at teardown, or wrap it in
`Cancelling<T>` and let the owner's drop do it. Cancelling an observer after the
`Ditto` is gone is a safe no-op.

## The `Ditto` instance

- **One per process and persistence directory.** A second `open` on the same directory
  fails after about a second with `CoreApi(LockedDittoWorkingDirectory)`: "Multiple
  Ditto instances cannot run at the same time within the same working directory".
- **Share it as `Arc<Ditto>`** (`Send + Sync`, not `Clone`). `Store` is `Clone` (it holds
  its own reference), so a task that only queries can hold a `Store`.
- **Keep it alive.** Dropping it stops sync and shuts the instance down. A `main` that
  returns right after `sync().start()` syncs nothing.
- **Shut down in order:** cancel observers and subscriptions (or drop their guards),
  `sync().stop()`, then drop the last `Arc<Ditto>`.
- `Ditto` derefs to a `#[doc(hidden)]` `DittoFields`; ignore what that exposes.

## Query results

`QueryResult` owns its data and is `Send + Sync`: unlike some other SDKs, you may move it
out of an observer callback, send it through a channel, or keep it. Items materialize
lazily; `QueryResultItem::value()` caches the decoded map until `dematerialize()`.
Prefer decoding inside the callback (`deserialize_value::<T>()`) and sending owned `T`s:
that bounds memory to what you use and keeps CBOR handling at one place.

## Live views are snapshots

`ditto.sync().subscriptions()` returns a fresh `HashSet<SyncSubscription>` each call.
`ditto.store().observers()` returns a snapshot too, despite its rustdoc's mention of a
read lock; its return type exposes the hidden `SetArc`, so do not build on it. Keep your
own handles instead of looking them up. Dropping the snapshot does not cancel anything
(executed).
