# Avalonia

Sources: [Avalonia project creation](https://docs.avaloniaui.net/docs/get-started/create-your-first-project),
[platform support](https://docs.avaloniaui.net/docs/supported-platforms),
[Ditto compatibility](https://docs.ditto.live/sdk/latest/compatibility/c-sharp).

The bundled desktop starter uses Avalonia 12.1.6, .NET 10, a XAML view and a small
INotifyPropertyChanged view model. It does not require ReactiveUI or a particular MVVM
framework. Preserve the user's existing MVVM/DI stack when integrating into an app.

```bash
dotnet restore
dotnet run
```

MainWindow binds Items and Status. SDK callbacks produce DTO snapshots; the adapter
queues changes with Dispatcher.UIThread.Post. ObservableCollection changes occur on
the UI thread. Avoid native objects in data templates and property getters.
Closing is cancelled until StopAsync completes, then retried once. Reject queued state
updates after the view model closes.

Publish for Windows x64, macOS ARM64 or supported Linux x64/ARM64. Validate native
library loading on the destination. Avalonia's browser target does not make Ditto
.NET WebAssembly available. Mobile Avalonia targets likewise need separate Ditto
asset/permission/lifecycle verification; the included starter is desktop-only.

For tests, headless view-model/dispatcher tests can validate binding behavior but cannot
prove native window rendering, packaged native-library lookup or physical radios.
Exercise the real window and published output before claiming those are runtime-tested.
