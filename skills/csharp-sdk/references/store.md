# Store, transactions and storage

## CAP-08 Executing DQL

Source: [C# DQL migration](https://docs.ditto.live/sdk/latest/migration-guides/c-sharp-dql),
[CRUD](https://docs.ditto.live/sdk/latest/crud/read), and the executed fixture.

`Store.ExecuteAsync(string query, Dictionary<string, object> arguments = default)`
returns Task<DittoQueryResult>. Use `:name` placeholders with dictionary keys `name`.
Keep collection/field identifiers in trusted query text; placeholders represent values.
Anonymous objects are not an ExecuteAsync argument overload. Do not assume Entity
Framework, DbContext, IQueryable or a LINQ-to-DQL translator is part of Ditto.

The result's Items are DittoQueryResultItem objects. `Value` exposes a dictionary;
`JsonString()` supports application-owned POCO/record deserialization. Dispose the
result, including mutation results. Copy values inside its lifetime. JSON mapping is
not free and should not run repeatedly on every UI property access.

See the runnable TaskStore/TaskItem sources bundled with the templates for typed
mapping and parameterized insert/update/delete. Updates to `done` and `title` modify
only that field; editing a stale DTO should not overwrite an unrelated field.

## CAP-09 Transactions

Source: [transactions](https://docs.ditto.live/sdk/latest/crud/transactions) and the
published DittoStore.TransactionAsync overloads. v5 offers a Task callback, generic
Task<T> callback, and a callback returning DittoTransactionCompletionAction. Use the
transaction's ExecuteAsync for every statement. Dispose each query result.
Return Commit or Rollback explicitly when using the completion-action overload.
Do not perform nested transactions or call the outer store from the callback.

The harness checks both committed and absent rolled-back documents. A timeout or
native shutdown failure must remain a failure, not an accepted transcript. Consult
[versions](versions.md) for exact runtime evidence and known version failures before
recommending transaction error behavior to an existing application.

## CAP-10 Indexing

Issue index DQL through ExecuteAsync, for example CREATE INDEX IF NOT EXISTS on the
queried fields. Execute EXPLAIN/ADVISE the same way and inspect/dispose the returned
rows. Composite indexes and ADVISE require the appropriate v5 line; use
[version coverage](versions.md) and the `write-dql` skill/public
[index documentation](https://docs.ditto.live/dql/indexing) for grammar and planning.
Create application indexes once during startup/migration, not for every render.

## CAP-17 Device storage management

`EVICT FROM collection WHERE ...` is executed through the same parameterized API;
it is not a synonym for DELETE. Before evicting, consider subscriptions that could
bring the data back. Read [device storage management](https://docs.ditto.live/sdk/latest/sync/device-storage-management)
for semantics. Disk-usage observation is separate from issuing eviction queries.
Do not delete the store directory while an instance is open, and do not equate cache
clearing with a safe on-disk version downgrade.
