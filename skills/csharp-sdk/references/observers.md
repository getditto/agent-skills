# Observers, diffing and back-pressure

## Contents

- [CAP-11 Observers](#cap-11-observers)
  - [Manual back-pressure for fire-and-forget UI dispatch](#manual-back-pressure-for-fire-and-forget-ui-dispatch)

## CAP-11 Observers

Source: [observing data](https://docs.ditto.live/sdk/latest/crud/observing-data-changes),
Ditto 5.2.0 public DittoStore overloads, and executed observer/back-pressure fixtures.

`RegisterObserver` accepts a SELECT query and optionally dictionary arguments. There
are synchronous Action<DittoQueryResult>, asynchronous Func<DittoQueryResult,Task>,
and manual Action<DittoQueryResult,Action> callback forms. Some observer overloads
also accept an object argument container (v5 only; 4.14.x has dictionary overloads only); this does not add that overload to ExecuteAsync.
Prefer the explicit dictionary form consistently across store/subscription operations.

Normal callbacks signal readiness after returning; Task callbacks signal after their
Task completes. Neither form observes exceptions: if a Task callback faults, the
exception is rethrown on a Ditto thread and ends the process, and the next result is
never signalled. Catch inside every handler. Manual callbacks must call signalNext in finally, including decode
errors and early returns. While paused, changes may coalesce; an observer is not a
lossless audit log. Bound the work and catch exceptions inside callbacks. Do not use
an async lambda forced into Action<DittoQueryResult> by a variable/delegate cast.

### Manual back-pressure for fire-and-forget UI dispatch

`BeginInvokeOnMainThread`, `Dispatcher.UIThread.Post`, `DispatcherQueue.TryEnqueue`
and `Control.BeginInvoke` return before the UI applies the update. With the automatic
overload, Ditto then delivers the next result immediately and full-list updates can
queue up on the UI thread. Use the `Action<DittoQueryResult, Action>` overload and
signal from the dispatched work, so the next delivery waits until the UI has applied
the current one. The bundled [TaskStore](../assets/common/TaskStore.cs) uses this
pattern in every starter:

<!-- snippet: observers-backpressure -->
```csharp
// uiPost: the framework's fire-and-forget post, which must throw if it cannot accept work.
var observer = ditto.Store.RegisterObserver("SELECT * FROM tasks", (result, signalNext) =>
{
    List<string> titles;
    try
    {
        using (result) // copy to managed data, then dispose before leaving the callback
            titles = [.. result.Items.Select(item => item.Value.TryGetValue("title", out var t) && t is string s ? s : "")];
    }
    catch (Exception error)
    {
        try { Report(error); } finally { signalNext(); } // a failure must not stall delivery
        return;
    }
    try
    {
        uiPost(() =>
        {
            try { ShowTitles(titles); }
            catch (Exception error) { Report(error); }
            finally { signalNext(); } // the next, coalesced result waits until this ran
        });
    }
    catch (Exception error)
    {
        // The dispatcher rejected the work, so the finally above never runs.
        try { Report(error); } finally { signalNext(); }
    }
});
```

Call `signalNext` exactly once on every path, and always from a `finally` so an
exception from your own error handler cannot skip it. Changes that arrive while the
signal is held are coalesced into one delivery of the latest state.

The dispatcher must report rejection by throwing. `DispatcherQueue.TryEnqueue` (Uno) and
MAUI's `IDispatcher.Dispatch` return `false` instead, so those starters wrap them:

<!-- source: assets/templates/uno/MainPage.xaml.cs -->
```csharp
model = new TasksViewModel(action => {
    if (!DispatcherQueue.TryEnqueue(() => action()))
        throw new InvalidOperationException("The UI dispatcher is shutting down.");
});
```

`Control.BeginInvoke` throws once the window handle is gone. Avalonia's
`Dispatcher.UIThread.Post` cannot report rejection at all; there, cancel observers before
the dispatcher shuts down (the starter stops the store before the window closes). A
dispatcher that silently drops work leaves the observer paused until it is cancelled.
Calling `signalNext` after the observer has been cancelled and disposed is safe (run
against 5.0.4-5.2.0), so queued UI work that drains during shutdown cannot crash. The overload that also
takes a query-arguments dictionary accepts the same manual callback. The snippet uses
C# 12; the WinForms starter's C# 7.3 copy
([common-legacy/TaskStore.cs](../assets/common-legacy/TaskStore.cs)) implements the same
pattern for .NET Framework.

Dispose each delivered result after mapping to plain managed DTOs. Send DTOs to the
UI's dispatcher, not native result items. Hold the observer on the screen/service;
Cancel stops observation, and v5 Dispose releases the handle. Already queued UI work
must check whether the view model has stopped.

**An observer delivers the current result once, then only when it changes.** A consumer
that subscribes later (a lazily created tab, a second view model sharing one store) sees
nothing until the next change. Give each consumer its own observer, or keep the last
snapshot: the starter's `TaskStore.Current` holds it, so read `Current` before
subscribing to `Changed`.

The starters apply each snapshot with `TaskList.Apply`
([TasksViewModel.cs](../assets/common/TasksViewModel.cs)): an identity-based diff on the
UI thread that updates existing rows in place by `_id` and raises only real inserts,
moves and removals, so selection survives. Do not "simplify" it to `Clear()` and re-add,
which resets selection on every delivery. Check the exact DittoDiffer API before
adopting SDK diff helpers.

For IAsyncEnumerable consumers, see the application-owned adapter in
[csharp-idioms.md](csharp-idioms.md). It is not a built-in SDK stream API.
