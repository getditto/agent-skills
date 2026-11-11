# Observers, diffing and back-pressure

## CAP-11 Observers

Source: [observing data](https://docs.ditto.live/sdk/latest/crud/observing-data-changes),
Ditto 5.2.0 public DittoStore overloads, and executed observer/back-pressure fixtures.

`RegisterObserver` accepts a SELECT query and optionally dictionary arguments. There
are synchronous Action<DittoQueryResult>, asynchronous Func<DittoQueryResult,Task>,
and manual Action<DittoQueryResult,Action> callback forms. Some observer overloads
also accept an object argument container; this does not add that overload to ExecuteAsync.
Prefer the explicit dictionary form consistently across store/subscription operations.

Normal callbacks signal readiness after returning; Task callbacks signal after their
Task completes. Manual callbacks must call signalNext in finally, including decode
errors and early returns. While paused, changes may coalesce; an observer is not a
lossless audit log. Bound the work and catch exceptions inside callbacks. Do not use
an async lambda forced into Action<DittoQueryResult> by a variable/delegate cast.

Dispose each delivered result after mapping to plain managed DTOs. Send DTOs to the
UI's dispatcher, not native result items. Hold the observer on the screen/service;
Cancel stops observation, and v5 Dispose releases the handle. Already queued UI work
must check whether the view model has stopped.

The starter replaces an ObservableCollection snapshot for clarity. For larger lists,
apply an identity-based diff on the UI thread; preserve selection and avoid positional
identity. Check the exact DittoDiffer API before adopting SDK diff helpers. A full
snapshot and a diff require different UI update logic.

For IAsyncEnumerable consumers, see the application-owned adapter in
[csharp-idioms.md](csharp-idioms.md). It is not a built-in SDK stream API.
