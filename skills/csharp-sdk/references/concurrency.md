# C# concurrency

Source: published Ditto 5.2.0 callback/task signatures and
[observing data](https://docs.ditto.live/sdk/latest/crud/observing-data-changes).
No UI synchronization-context guarantee is assumed by the starters.

Callback threads observed with Ditto 5.2.0 (macOS ARM64, console host):

| Callback | Thread it ran on |
|---|---|
| Store observer (all three overloads) | A Ditto-owned native thread: not the caller's, not a thread-pool thread, no SynchronizationContext |
| Attachment fetch | A Ditto-owned native thread, no SynchronizationContext |
| Presence.Observe | The **first** call ran synchronously on the calling thread, inside `Observe()`; later updates come from Ditto's threads |
| Auth status, logger | Not measured; assume an arbitrary thread |

Treat every callback as arbitrary-thread code. Never touch UI objects from one directly,
and do not assume the first presence callback is deferred.

| Operation | Application rule |
|---|---|
| OpenAsync, ExecuteAsync | **Complete synchronously on v5** (5.0.4–5.2.0 return already-finished tasks), and 4.x `OpenAsync` blocks for much of initialization. Awaiting alone keeps the work on the UI thread: from UI code, run them via `Task.Run(() => ...)`, as the starters do |
| TransactionAsync, LoginAsync | Await; do not block a UI synchronization context |
| Store callback | Copy data and dispose the result inside the callback; catch exceptions |
| Task observer callback | Return/await its Task; do not turn it into async void |
| Manual signal callback | Always signal in finally after processing |
| Presence/auth/log callback | Dispatch UI work explicitly and prevent application exceptions escaping |
| Permission prompt | Open the SDK first where required; invoke the platform helper on the main thread before sync |
| Shutdown | Cancel observation, drain application operations and dispose from an awaited path. Never dispose Ditto on one of its own callback threads (for example inside an observer or presence callback): it deadlocks. Hand teardown to the thread pool, as `TaskStore.StopAsync` does |

ExecuteAsync does not expose CancellationToken in 5.2.0. Task.WaitAsync(token) cancels
waiting, not the native query. Do not dispose the store while abandoned work is still
running; retain responsibility for observing its completion and disposing its result.
For ordinary CRUD prefer awaiting the operation directly. For bounded tests, use an
outer process watchdog in addition to callback deadlines.

ConfigureAwait(false) in an application service avoids depending on the caller's
context; it is not a promise that every line runs on a new thread. UI adapters dispatch
through Control.BeginInvoke, MainThread, DispatcherQueue or Dispatcher.UIThread.

Within a transaction, call only the transaction's query methods. Awaiting UI input,
network requests or another store transaction while holding the transaction can retain
locks or deadlock. Prepare external inputs before entering the transaction.
