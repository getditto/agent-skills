# Idiomatic C# without invented APIs

Source: published Ditto 5.2.0 Store/query-result signatures and executable fixtures.
The bundled [shared adapter](../assets/common/TaskStore.cs) uses C# 7.3 syntax so it
also compiles in the net48 starter. Modern-only examples are separate.

| C# form | Guidance |
|---|---|
| Dictionary initializers | Use Dictionary<string,object> for ExecuteAsync bindings; nested dictionaries/lists represent documents |
| Anonymous objects | Some observer/subscription overloads accept object; ExecuteAsync does not. Prefer explicit dictionaries across all three |
| POCO / record | Deserialize item.JsonString using System.Text.Json; explicitly map _id with JsonPropertyName |
| Nullable references | An application/compiler feature, not an SDK null-safety guarantee; validate external document fields |
| LINQ Select/Where | Runs over local managed results; it does not translate to DQL or create a subscription |
| Task / async-await | Await SDK tasks; avoid sync-over-async on the UI thread |
| using / using var | Disposes supported handles/results; explicit observer/subscription Cancel is still required |
| await using | Use for an application IAsyncDisposable adapter if provided, not directly for Ditto |
| IAsyncEnumerable | Use an explicit application adapter; no SDK ObserveAsync enumerable API is assumed |
| Events / ICommand | Keep framework event handlers thin; route work into Task-returning service/view-model methods |
| DI | Own an initialized service at app/host scope; do not block an async open in a synchronous factory |

## Serialization boundaries

Use stable string IDs, or deliberately handle the actual supported document-ID type.
Do not use `ToString()` as a universal lossless conversion. Query-result numeric CLR
types can differ from the type originally supplied; use checked/range-aware conversion.
Null and missing fields are different cases. Validate nested structures before casting.

For portable GUID/time values, explicitly write Guid.ToString("D") and
DateTimeOffset.ToString("O") and parse them at the boundary. The fixture proves those
representations round-trip. Do not imply the SDK automatically preserves every CLR
numeric/date type or arbitrary JsonElement. For exact decimal money, choose a tested
representation such as integer minor units or invariant decimal strings; do not promise
lossless decimal-to-double conversion. Arbitrary binary values and attachments are
separate concepts; use the documented EJSON/attachment representation for the task.

## Async enumeration

[QueryStreams.cs](../assets/modern/QueryStreams.cs) is a complete modern .NET adapter.
It wraps RegisterObserver in a bounded Channel of copied JSON snapshots, keeps only
the newest pending snapshot, supports cancellation and calls Cancel in finally when
the async enumerator is disposed. Its cancellation/cleanup is executed by the harness.
Copy the file into a modern project; it is intentionally not part of the C# 7.3 starter.
Always dispose an enumerator (await foreach does this on break/exception).

This is current-state observation with coalescing, not a lossless event stream. If
needed, provide a separate unbounded/history design with explicit memory/durability
requirements rather than changing this adapter silently.
