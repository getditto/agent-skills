# Subscriptions and sync status

## CAP-07 Subscriptions and scopes

Sources: [syncing data](https://docs.ditto.live/sdk/latest/sync/syncing-data),
[sync scopes](https://docs.ditto.live/sdk/latest/sync/sync-scopes).

v5 uses `ditto.Sync.RegisterSubscription(query, arguments)`, `Sync.Start()` and
`Sync.Stop()`. Keep the returned DittoSyncSubscription; cancel explicitly when its
owner no longer needs the data. A Store observer reads the local store and does not
create a sync subscription. Stopping sync pauses networking; it does not delete data.

Use dictionary arguments for parameter binding. Register application subscriptions once
per owner, not on every refresh. Follow the concept skill for subscription-query
restrictions and scope semantics; the SDK skill supplies the actual C# calls.
Scope/system configuration uses documented DQL through Store.ExecuteAsync; do not
invent a .NET scope builder merely because another SDK has convenience methods.

## CAP-14 Sync status and local commits

Sources: [tracking local commits](https://docs.ditto.live/sdk/latest/sync/tracking-local-commits),
[monitoring sync status](https://docs.ditto.live/sdk/latest/sync/monitoring-sync-status).

DittoQueryResult.CommitID is a nullable ulong in 5.2.0. Capture it before disposing a
mutation result. A locally accepted write and an active network connection are not
proof that the server has durably received it. Use the documented system collections
and version-specific status queries through ExecuteAsync/RegisterObserver, retaining
and cancelling those observers just like business-data observers.

Keep local pending state separate from authentication failure and disconnected state.
A subscription's IsCancelled describes that handle, not remote convergence. Two-peer
loopback replication is tested; Big Peer status semantics require the optional server
integration environment and must not be claimed from a loopback run.
