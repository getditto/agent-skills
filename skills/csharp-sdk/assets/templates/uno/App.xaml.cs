using Microsoft.UI.Xaml;

namespace DittoTasks;

public sealed partial class App : Application
{
    private Window window;
    private bool closing;
    private bool canClose;
    public App() { InitializeComponent(); }
    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        var page = new MainPage();
        window = new Window { Content = page };
        window.AppWindow.Closing += (_, args) => {
            if (canClose) return;
            // Cancellation must happen synchronously, before scheduling async teardown.
            args.Cancel = true;
            if (closing) return;
            closing = true;
            window.DispatcherQueue.TryEnqueue(async () => {
                try { await page.StopAsync(); }
                catch (Exception) { System.Diagnostics.Trace.TraceError("Ditto shutdown failed."); }
                finally { canClose = true; window.Close(); }
            });
        };
        window.Activate();
    }
}
