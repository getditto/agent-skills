# Handle ownership

Source: [Ditto 5.2.0 published package](https://www.nuget.org/packages/Ditto/5.2.0)
and its public handle APIs. Callback delivery, Cancel and Dispose behavior below run as
tests against Ditto 5.0.4, 5.1.0 and 5.2.0. See
[C# migration](https://docs.ditto.live/sdk/latest/migration-guides/c-sharp-v4).

| Handle | End of lifetime |
|---|---|
| Ditto | Stop sync and dispose after application operations finish |
| DittoQueryResult | Dispose after copying/processing items, also for mutations |
| DittoQueryResultItem | Do not retain beyond the owning result's lifetime |
| Store observer | Explicit Cancel, then Dispose on v5; v4 observer is not IDisposable |
| Sync subscription | Explicit Cancel, then Dispose where supported |
| Attachment fetcher | Stop a pending fetch; dispose its handle |
| Attachment | Retain while reading/copying its data, then dispose |
| Auth status observer | Dispose the returned IDisposable |
| Presence observer | Call Stop(); it is not IDisposable |
| Disk-usage observer | Call Stop(); it is also IDisposable on v5 |

An observer's using block is not its cancellation scope: retain a cancellable handle
and call Cancel in finally.

<!-- snippet: lifetimes-observer -->
```csharp
DittoStoreObserver? observer = ditto.Store.RegisterObserver("SELECT * FROM tasks", result =>
{
    using (result) Interlocked.Increment(ref seen);
});
try
{
    // ... the owning screen or service is active
}
finally
{
    observer.Cancel();   // stops delivery; Dispose alone does not
    observer.Dispose();  // releases the native handle
    observer = null;     // any member access after Dispose can crash the process
}
```

The `signalNext` callback is separate: calling it after the observer is cancelled and
disposed is safe (run against 5.0.4-5.2.0).

Never use a v5 store observer or subscription after Dispose: any member access,
including `IsCancelled`, crashes the process natively (SIGSEGV) instead of throwing. Avoid reference cycles from callbacks capturing an entire
window. Unsubscribe application events and reject queued UI updates after teardown.

The starter's async StopAsync is an application method. Ditto itself is IDisposable,
not evidence that `await using var ditto` is supported. Prefer an explicit async service
shutdown followed by normal SDK disposal.
