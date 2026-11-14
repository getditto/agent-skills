# C# failure patterns

Sources: [C# migration](https://docs.ditto.live/sdk/latest/migration-guides/c-sharp-v4)
and [installation](https://docs.ditto.live/sdk/latest/install-guides/c-sharp).

| Wrong shape | Correct shape and observable consequence |
|---|---|
| ExecuteAsync(query, new { id }) | Bind a Dictionary<string,object>; no matching execute overload otherwise |
| Interpolated user input in DQL | Bind values using :name; quotes and untrusted input remain values |
| using(observer) with no Cancel | Cancel in finally; disposing a v5 handle alone does not end observation |
| ViewModel holds DittoQueryResultItem | Copy managed DTOs first; disposal invalidates native access |
| async lambda stored in Action<Result> | Use Func<Result,Task> and catch inside it; async void signals the next result too early, and an escaping exception ends the process in either form |
| signalNext only on success | Signal in finally; failure otherwise stalls future delivery |
| .Result / .Wait on a UI thread | Await the operation and dispatch UI updates; blocking risks deadlock |
| Full document rewrite when toggling done | UPDATE only done; avoid overwriting concurrent field changes |
| Direct callback mutation of ObservableCollection | Marshal the snapshot to the framework dispatcher |
| net48 AnyCPU preferring 32-bit | x64/Prefer32Bit=false; prevents BadImageFormatException |
| Ditto only on a referenced Framework library | Install on startup .exe too; prevents missing native DLL |
| Uno default WebAssembly target | Select supported native targets explicitly; Ditto has no wasm runtime |
| .NET Standard means every .NET runtime works | Inspect actual native assets, OS support and published output |

Some wrong shapes in the table do not compile at all (for example the anonymous-object
argument). The pairs below do compile: each is built against every supported v5 package,
and the wrong forms are never executed because they misbehave by design.

## Wrong and right code

### Disposing an observer without cancelling it

Leaving a `using` scope disposes the v5 handle, but the callback keeps firing.

Wrong:

<!-- snippet: anti-dispose-wrong -->
```csharp
using var observer = ditto.Store.RegisterObserver("SELECT * FROM tasks", r => r.Dispose());
// Leaving scope disposes the handle, but callbacks keep firing.
```

Right:

<!-- snippet: anti-dispose-right -->
```csharp
var observer = ditto.Store.RegisterObserver("SELECT * FROM tasks", r => r.Dispose());
try { /* ... */ }
finally { observer.Cancel(); observer.Dispose(); }
```

### Touching a handle after Dispose

Any member access on a disposed v5 observer or subscription crashes the process natively (SIGSEGV). No managed exception is thrown, so try/catch cannot help.

Wrong:

<!-- snippet: anti-after-dispose-wrong -->
```csharp
observer.Cancel();
observer.Dispose();
Console.WriteLine(observer.IsCancelled); // native crash (SIGSEGV), not an exception
```

Right:

<!-- snippet: anti-after-dispose-right -->
```csharp
observer.Cancel();
Console.WriteLine(observer.IsCancelled); // read state before disposing
observer.Dispose();
observer = null;
```

### An async lambda stored as Action<DittoQueryResult>

It compiles as async void: Ditto signals the next delivery before the work finishes, and an exception ends the process. The Task overload fixes the signalling but does not observe exceptions either: a fault is rethrown on a Ditto thread and terminates the app, so catch inside every async handler.

Wrong:

<!-- snippet: anti-async-void-wrong -->
```csharp
Action<DittoQueryResult> handler = async result =>
{
    using (result) await SaveAsync(result.Items.Count); // async void, nothing caught
};
var observer = ditto.Store.RegisterObserver("SELECT * FROM tasks", handler);
```

Right:

<!-- snippet: anti-async-void-right -->
```csharp
var observer = ditto.Store.RegisterObserver("SELECT * FROM tasks", async result =>
{
    try
    {
        using (result) await SaveAsync(result.Items.Count); // Func<DittoQueryResult, Task>
    }
    catch (Exception error) { Report(error); } // an escaping exception ends the process
});
// ... Cancel() and Dispose() the observer when its owner stops.
```

### Interpolating input into DQL

Quotes in the input change the query. Bind values with `:name` placeholders instead.

Wrong:

<!-- snippet: anti-interpolation-wrong -->
```csharp
using (await ditto.Store.ExecuteAsync($"SELECT * FROM tasks WHERE title = '{userInput}'")) { }
```

Right:

<!-- snippet: anti-interpolation-right -->
```csharp
using (await ditto.Store.ExecuteAsync("SELECT * FROM tasks WHERE title = :title",
    new() { ["title"] = userInput })) { }
```

### Rewriting the whole document to change one field

An upsert from a stale copy overwrites concurrent edits and can resurrect a deleted document.

Wrong:

<!-- snippet: anti-rewrite-wrong -->
```csharp
// Writes every field from a possibly stale copy, overwriting concurrent edits.
using (await ditto.Store.ExecuteAsync("INSERT INTO tasks DOCUMENTS (:task) ON ID CONFLICT DO UPDATE",
    new Dictionary<string, object> { ["task"] = new Dictionary<string, object> {
        ["_id"] = "t1", ["title"] = title, ["done"] = true } })) { }
```

Right:

<!-- snippet: anti-rewrite-right -->
```csharp
using (await ditto.Store.ExecuteAsync("UPDATE tasks SET done = :done WHERE _id = :id",
    new() { ["id"] = "t1", ["done"] = true })) { }
```

