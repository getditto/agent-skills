# Idiomatic C# without invented APIs

Source: published Ditto 5.2.0 Store/query-result signatures and executable fixtures.
## Language version

Use the newest C# the target framework supports. Leave `LangVersion` unset: the SDK then
selects the default for that framework, which is its newest supported version (C# 14 on
.NET 10, C# 12 on .NET 8). Do not set `latest` or `preview`, which can enable features
the target runtime does not support, and do not pin an older version out of habit.

The one exception is .NET Framework, which supports only C# 7.3. The WinForms starter
is C# 7.3 for all of its targets (net48, net481 and net10.0-windows), so one source set
builds everywhere; its shared code is [common-legacy](../assets/common-legacy/TaskStore.cs).
The Console, Avalonia, Uno and MAUI starters use the modern, nullable-annotated
[shared adapter](../assets/common/TaskStore.cs) with the same public API.

The examples in these references use C# 12 (.NET 8 and later). For .NET Framework,
adapt them: spell out `new Dictionary<string, object>` instead of `new()`, replace
`[.. items]` with `.ToList()`, use `using (...) { }` blocks instead of `using var`,
classes instead of records, block-scoped namespaces and no nullable annotations.

| C# form | Guidance |
|---|---|
| Dictionary initializers | Use Dictionary<string,object> for ExecuteAsync bindings; nested dictionaries/lists represent documents |
| Anonymous objects | On v5 only, some observer/subscription overloads accept object (4.14.x has dictionary overloads only); ExecuteAsync never does. Prefer explicit dictionaries across all three |
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
DateTimeOffset.ToString("O") and parse them at the boundary. Tests on Ditto 5.0.4–5.2.0 prove those
representations round-trip. Do not imply the SDK automatically preserves every CLR
numeric/date type or arbitrary JsonElement. For exact decimal money, choose a tested
representation such as integer minor units or invariant decimal strings; do not promise
lossless decimal-to-double conversion. Before 5.1.0, DateTimeOffset/DateOnly/TimeOnly arguments were
stored as empty objects and decimal as a CBOR decimal-fraction array (SDKS-3538); data
written by older apps may contain those shapes. Arbitrary binary values and attachments are
separate concepts; use the documented EJSON/attachment representation for the task.

## Async enumeration

[QueryStreams.cs](../assets/modern/QueryStreams.cs) is a complete modern .NET adapter.
It wraps RegisterObserver in a bounded Channel of copied JSON snapshots, keeps only
the newest pending snapshot, supports cancellation and calls Cancel in finally when
the async enumerator is disposed. An overload takes a query-arguments dictionary, so
values are bound rather than interpolated. Cancellation, cleanup and argument binding
run as tests against Ditto 5.0.4 through 5.2.0.
Copy the file into a modern project (.NET 8 or later); it is not part of any starter.
Always dispose an enumerator (await foreach does this on break/exception).

This is current-state observation with coalescing, not a lossless event stream. If
needed, provide a separate unbounded/history design with explicit memory/durability
requirements rather than changing this adapter silently.
