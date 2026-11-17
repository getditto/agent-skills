# Concurrency and threading — Ditto Rust SDK

## Contents

- [Where each callback runs](#where-each-callback-runs)
- [Which calls block, which suspend](#which-calls-block-which-suspend)
- [The six rules](#the-six-rules)
- [Cancellation safety](#cancellation-safety)
- [Transactions serialize writers](#transactions-serialize-writers)
- [The auth expiration handler](#the-auth-expiration-handler)
- [Connection-request handlers](#connection-request-handlers)
- [Panics abort the process](#panics-abort-the-process)

Detail behind `SKILL.md` § *Concurrency and threading model*. Patterns that apply these
facts: [tokio.md](tokio.md). "Executed" means asserted by the skill's test suite on
5.0.4, 5.1.0 and 5.2.0; other claims cite `dittolive-ditto` 5.2.0 source (crates.io).

## Where each callback runs

| Callback | Signature bound | Thread | Evidence |
|---|---|---|---|
| `Store::register_observer` | `FnMut(QueryResult) + Send + Sync + 'static` | Ditto thread `live query callback N`; no Tokio context | executed |
| `register_observer_with_signal_next` | `FnMut(QueryResult, Box<dyn SignalNext>) + Send + Sync + 'static` | same | executed |
| `Store::fetch_attachment` events | `Fn(DittoAttachmentFetchEvent) + Send + Sync + 'static` | Ditto thread | executed |
| `Presence::register_observer` | `Fn(&PresenceGraph) + Send + Sync + 'static` | Ditto thread | source (`src/presence/mod.rs`) |
| `DiskUsage::observe` | `FnMut(DiskUsageItem) + Send + 'static` | Ditto thread | source (`src/disk_usage/mod.rs`) |
| `DittoLogger::set_custom_log_callback` | `Fn(LogLevel, &str) + Send + Sync + 'static` | the thread that logged | executed (callback fires) |
| `set_connection_request_handler` | `Fn(ConnectionRequest) -> ConnectionRequestAuthorization` | Ditto "background hook" thread, 10 s deny timeout | source (`src/presence/mod.rs`) |
| `set_connection_request_handler_async` | `Fn(ConnectionRequest) -> impl Future` | one process-wide current-thread runtime, one request at a time | source (`src/presence/mod.rs`) |
| `DittoAuthenticator::set_expiration_handler` | `DittoAuthExpirationHandler` (`Send` future) | 5.1.0+: Ditto thread inside a temporary runtime; 5.0.4: an app runtime worker | executed |
| `Store::transaction` closure | `AsyncFnOnce(&Transaction)` | **your** task, inline | executed |

Store observer callbacks for one observer are never concurrent: the SDK wraps the
closure in a `Mutex` (`src/store/observer.rs`). Different observers can run at the same
time on different threads, and consecutive callbacks of one observer may arrive on
different threads.

## Which calls block, which suspend

| Call | Kind | What happens |
|---|---|---|
| `Ditto::open(config).await` | truly async | waits on a completion callback |
| `Ditto::open_sync(config)` | blocking | blocks the caller for the whole open; no internal `block_on`, so no nested-runtime panic |
| `store().execute(q).await` | `async`, blocks inside | runs the query synchronously in the first `poll` (executed: `Ready` on first poll) |
| `store().new_attachment*(..).await` | `async`, blocks inside | copies/hashes synchronously |
| `store().transaction(..).await`, `txn.execute(..).await` | truly async | begin/execute/complete via completion callbacks |
| `register_observer`, `register_subscription`, `sync().start()`, `cancel()` | sync, quick | FFI call |
| `DittoAuthenticator::login` | sync | FFI call; may perform network I/O (inference) |
| `DittoLogger::export_to_file(..).await` | truly async | completion callback |

A future that is never polled does nothing (executed: an un-awaited `execute` inserts
nothing). None of these require a Tokio runtime, but none of them may be polled from a
Ditto callback either: that thread belongs to Ditto.

## The six rules

1. **Callbacks hand off, async code works.** Decode in the callback if you like, then
   `watch::Sender::send_replace`, `mpsc::Sender::try_send` or `UnboundedSender::send`.
   `tokio::spawn` inside a callback panics with no runtime (executed: the process
   aborts); a `Handle` captured *before* registration works (executed).
2. **Do not block a callback.** It delays that observer's next delivery and holds a
   Ditto thread. `blocking_send` on a full channel is a block.
3. **Do not panic in a callback.** It aborts the process ([below](#panics-abort-the-process)).
4. **Heavy `execute` goes to `spawn_blocking`.** It runs inside the poll
   ([tokio.md](tokio.md#heavy-queries-off-the-async-workers)).
5. **Never race `Ditto::open` or a transaction** with `timeout`/`select!`
   ([below](#cancellation-safety)).
6. **Inside a transaction use `txn.execute` only** ([below](#transactions-serialize-writers)).

## Cancellation safety

`Ditto::open` and the transaction futures complete through a one-shot channel that the
FFI completion callback sends into. If the future was dropped, the send fails, and
`src/utils/mod.rs` (`make_continuation`) panics on that failure — on a Ditto thread,
where a panic aborts. Executed outcomes:

- `tokio::time::timeout(Duration::from_micros(1), Ditto::open(config))` → the process
  dies with SIGABRT when the open finishes.
- A `transaction` future dropped by `timeout` while its closure awaits → the next
  `transaction` never starts (the child test is killed by its watchdog after 8 s).
- `execute` is unaffected: it has already completed when first polled.

Request handlers in axum/tonic are dropped when the client disconnects. If a handler
runs a transaction, move it into `tokio::spawn` and await the `JoinHandle`, so the
transaction always runs to completion even if the request future is dropped.

## Transactions serialize writers

Only one read-write transaction runs at a time; others wait (`src/store/transactions/api.rs`).
A plain `ditto.store().execute(..)` write issued while a transaction is open waits
behind it. Issued *from inside that transaction's closure*, it waits on itself
(executed: deadlock). Keep transaction closures short, do no unrelated I/O in them, and
use `transaction_with_options` with `is_read_only = true` for read-only work.

## The auth expiration handler

`set_expiration_handler` takes a `DittoAuthExpirationHandler`: a type implementing it, or
a stateless `async` closure. On 5.1.0 and 5.2.0 Ditto calls it on its own thread (executed:
`tokio-rt-worker`, not your runtime's `tokio-runtime-worker`). The SDK looks for a Tokio
runtime with `Handle::try_current()`, finds none there, builds a temporary current-thread
runtime and `block_on`s the handler (`src/ditto/init/mod.rs`, `dispatch_auth_handler`).
On 5.0.4 it ran on a worker of the app's runtime (executed). Consequences:

- The first call arrives right after the handler is set, with `remaining` of zero:
  log in on every call, not only on expiry.
- Tasks spawned inside it run on that short-lived runtime and may be dropped with it.
  Do the work inline: fetch the token, then call `auth.login(&token, provider)`.
- It holds a Ditto thread while it runs: bound your token fetch with a timeout.

## Connection-request handlers

`set_connection_request_handler_async` futures all run on one process-wide
current-thread runtime, awaited one after another (`src/presence/mod.rs`). A slow
handler delays every later request against the 10-second deny timeout. Decide from
`ConnectionRequest::peer_metadata()` without I/O where you can.

## Panics abort the process

Ditto's core installs a process-wide panic hook during `Ditto::open` that logs and then
calls `abort()`. Executed:

| Panic site | Before `Ditto::open` | After `Ditto::open` |
|---|---|---|
| `tokio::spawn` task | `JoinError::is_panic()` | **SIGABRT** |
| Observer callback | — | **SIGABRT** |
| Any code after the app calls `std::panic::set_hook` itself | unwinds | unwinds (Ditto's hook is replaced) |

stderr shows `ERROR tracing_config: Panic: …` followed by `Process aborting due to
panic`. So `catch_unwind`, Tokio's `JoinError` and tower's `CatchPanic` do not work
while Ditto's hook is installed: the hook runs before unwinding starts. Treat the
program as `panic = "abort"`. Replacing the hook restores unwinding for your own code,
but a panic inside a Ditto callback still aborts (it would unwind across the FFI
boundary), and you lose Ditto's crash log. The trade-off is in
[best-practices.md](../best-practices.md#panics).
