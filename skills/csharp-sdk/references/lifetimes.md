# Handle ownership

Source: [Ditto 5.2.0 published package](https://www.nuget.org/packages/Ditto/5.2.0)
and its public handle APIs; callback delivery/cancellation are also exercised against
that package by the fixture. See
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
| Presence observer | Retain and dispose according to the selected version's API |

An observer's using block is not its cancellation scope: retain a cancellable handle
and call Cancel in finally. Avoid reference cycles from callbacks capturing an entire
window. Unsubscribe application events and reject queued UI updates after teardown.

The starter's async StopAsync is an application method. Ditto itself is IDisposable,
not evidence that `await using var ditto` is supported. Prefer an explicit async service
shutdown followed by normal SDK disposal.
