# Store, transactions and storage

## CAP-08 Executing DQL

Source: [C# DQL migration](https://docs.ditto.live/sdk/latest/migration-guides/c-sharp-dql),
[CRUD](https://docs.ditto.live/sdk/latest/crud/read), and the examples below, which run
against Ditto 5.0.4, 5.1.0 and 5.2.0.

`Store.ExecuteAsync(string query, Dictionary<string, object> arguments = default)`
returns Task<DittoQueryResult>. Use `:name` placeholders with dictionary keys `name`.
Keep collection/field identifiers in trusted query text; placeholders represent values.
Anonymous objects are not an ExecuteAsync argument overload. Do not assume Entity
Framework, DbContext, IQueryable or a LINQ-to-DQL translator is part of Ditto.

The result's Items are DittoQueryResultItem objects. `Value` exposes a dictionary;
`JsonString()` supports application-owned POCO/record deserialization. Dispose the
result, including mutation results. Copy values inside its lifetime. JSON mapping is
not free and should not run repeatedly on every UI property access.

A typed DTO for `JsonString()` (records need C# 9 or later; the net48 starter uses a
class with the same attributes):

<!-- snippet: store-dto -->
```csharp
public sealed record TaskDto(
    [property: JsonPropertyName("_id")] string Id,
    [property: JsonPropertyName("title")] string Title,
    [property: JsonPropertyName("done")] bool Done);
```

Insert, read and update with bound arguments, checking that an update found its document:

<!-- snippet: store-crud -->
```csharp
using (await ditto.Store.ExecuteAsync("INSERT INTO tasks DOCUMENTS (:task)",
    new() {
        ["task"] = new Dictionary<string, object> { ["_id"] = "t1", ["title"] = "Buy milk", ["done"] = false } })) { }

List<TaskDto> open;
using (var result = await ditto.Store.ExecuteAsync(
    "SELECT * FROM tasks WHERE done = :done", new() { ["done"] = false }))
{
    // Copy into managed objects while the result is alive, then let it dispose.
    open = [.. result.Items.Select(item => JsonSerializer.Deserialize<TaskDto>(item.JsonString())!)];
}

// Update only the field that changed, so concurrent edits to other fields survive.
using (var updated = await ditto.Store.ExecuteAsync("UPDATE tasks SET done = :done WHERE _id = :id",
    new() { ["id"] = "t1", ["done"] = true }))
{
    // No mutated IDs means the document is gone, for example deleted by another peer.
    if (updated.MutatedDocumentIds.Count == 0)
        throw new InvalidOperationException("Task t1 no longer exists.");
}
```

`MutatedDocumentIds` is empty when a mutation matched nothing. Updating only `done` or
`title` leaves other fields alone; writing a whole stale DTO back would overwrite them.
The bundled TaskStore/TaskItem sources show the same calls in a complete adapter.

## CAP-09 Transactions

Source: [transactions](https://docs.ditto.live/sdk/latest/crud/transactions) and the
published DittoStore.TransactionAsync overloads. v5 offers a Task callback, generic
Task<T> callback, and a callback returning DittoTransactionCompletionAction. Use the
transaction's ExecuteAsync for every statement. Dispose each query result.
Return Commit or Rollback explicitly when using the completion-action overload.
Do not perform nested transactions or call the outer store from the callback.

A plain Task callback commits when it returns and rolls back when it throws. Every
overload also takes `hint` (a label for logs) and `isReadOnly`. Ditto runs one
read-write transaction at a time, so keep transactions short: prepare inputs before
entering, and never await UI or network work inside one.

<!-- snippet: store-transaction -->
```csharp
await ditto.Store.TransactionAsync(async tx =>
{
    // Run every statement on tx: never the outer ditto.Store, never a nested transaction.
    long balance;
    using (var account = await tx.ExecuteAsync("SELECT * FROM accounts WHERE _id = :id",
        new() { ["id"] = "alice" }))
        balance = Convert.ToInt64(account.Items[0].Value["balance"]);
    if (balance < amount)
        throw new InvalidOperationException("Insufficient funds."); // throwing rolls back
    using (await tx.ExecuteAsync("UPDATE accounts SET balance = :balance WHERE _id = :id",
        new() { ["id"] = "alice", ["balance"] = balance - amount })) { }
    // Returning normally commits.
}, hint: "withdraw");
```

**Use Ditto 5.1.0 or later for transactions.** On 5.0.x, `TransactionAsync` can hang
while completing or while the instance is disposed (DEVX-918, fixed in 5.1.0); the
rollback path above reproduces it on 5.0.4. Write the read-then-update form shown here:
5.0.x rejects an UPDATE that references the document's own field
(`SET balance = balance - :amount` fails with "Document references in mutation values").

On 5.1.0 and 5.2.0, tests check that committed documents exist and rolled-back ones do
not. A timeout or native shutdown failure must remain a failure, not an accepted result. Consult
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
