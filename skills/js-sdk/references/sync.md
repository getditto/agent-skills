# Synchronization

## CAP-07 Sync subscriptions and sync scopes

Register `sync.registerSubscription(query, args)` to request remote data, and
`store.registerObserver(query, callback, args)` to observe local results. Their argument
orders differ. A local `execute` or observer does not subscribe to remote data.
Retain and cancel both handles. Keep a broad app-owned subscription for long-lived
cached scopes when navigation should not unsubscribe; then call the hook with `sync=false`.
Never use a subscription predicate as the authorization boundary.

Use a subscription-supported SELECT (the starter uses `SELECT * FROM tasks`).
Complex local projections, sorting, aggregation, or joins may need a simpler, broader
sync query. The convenience hook shares one query only when it is valid for both APIs.

## CAP-14 Sync status and local commit tracking

`sync.isActive` reports start/stop, not connectivity or remote acknowledgement.
`QueryResult.commitID` is a local commit identifier (`bigint | null`), not a delivered
flag. The published JS 5.2.0 API has no equivalent to the Swift per-query sync-status /
local-commit acknowledgement APIs. Treat this capability as partial; do not invent
`ditto.sync.observeSyncStatus` or `waitForCommit`. Presence can show connections; an
application-level receipt can acknowledge a business workflow if required.

For propagation semantics use `sync-subscriptions`, or
<https://docs.ditto.live/sdk/latest/sync/syncing-data>.

## Sources

Published `@dittolive/ditto@5.2.0`, `types/ditto.d.ts` (public API distribution);
[versioned API reference](https://software.ditto.live/js/Ditto/5.2.0/api-reference/). Examples use the same package in the executable fixture.
