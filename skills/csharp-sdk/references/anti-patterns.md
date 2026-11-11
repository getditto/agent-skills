# C# failure patterns

Sources: [C# migration](https://docs.ditto.live/sdk/latest/migration-guides/c-sharp-v4)
and [installation](https://docs.ditto.live/sdk/latest/install-guides/c-sharp).

| Wrong shape | Correct shape and observable consequence |
|---|---|
| ExecuteAsync(query, new { id }) | Bind a Dictionary<string,object>; no matching execute overload otherwise |
| Interpolated user input in DQL | Bind values using :name; quotes and untrusted input remain values |
| using(observer) with no Cancel | Cancel in finally; disposing a v5 handle alone does not end observation |
| ViewModel holds DittoQueryResultItem | Copy managed DTOs first; disposal invalidates native access |
| async lambda stored in Action<Result> | Use Func<Result,Task>; async void loses task completion/errors |
| signalNext only on success | Signal in finally; failure otherwise stalls future delivery |
| .Result / .Wait on a UI thread | Await the operation and dispatch UI updates; blocking risks deadlock |
| Full document rewrite when toggling done | UPDATE only done; avoid overwriting concurrent field changes |
| Direct callback mutation of ObservableCollection | Marshal the snapshot to the framework dispatcher |
| net48 AnyCPU preferring 32-bit | x64/Prefer32Bit=false; prevents BadImageFormatException |
| Ditto only on a referenced Framework library | Install on startup .exe too; prevents missing native DLL |
| Uno default WebAssembly target | Select supported native targets explicitly; Ditto has no wasm runtime |
| .NET Standard means every .NET runtime works | Inspect actual native assets, OS support and published output |

Wrong forms in this table are intentionally invalid; use the compiled assets and
minimal app as the source of runnable code.
