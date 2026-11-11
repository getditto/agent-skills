# C# concurrency

Source: published Ditto 5.2.0 callback/task signatures and
[observing data](https://docs.ditto.live/sdk/latest/crud/observing-data-changes).
No UI synchronization-context guarantee is assumed by the starters.

| Operation | Application rule |
|---|---|
| OpenAsync, ExecuteAsync, TransactionAsync, LoginAsync | Await; do not block a UI synchronization context |
| Store callback | Copy data and dispose the result inside the callback; catch exceptions |
| Task observer callback | Return/await its Task; do not turn it into async void |
| Manual signal callback | Always signal in finally after processing |
| Presence/auth/log callback | Dispatch UI work explicitly and prevent application exceptions escaping |
| Permission prompt | Open the SDK first where required; invoke the platform helper on the main thread before sync |
| Shutdown | Cancel observation, drain application operations and dispose from an awaited path |

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
