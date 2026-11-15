namespace DittoTasks;

public sealed class App : Application
{
    // Android can create a new window in the same process (Back, then relaunch) before the
    // old window's Destroying event fires. Two stores would then open one directory, and
    // OpenAsync throws DittoPersistenceDirectoryLockedException once its short lock retry
    // runs out. So each new page starts only after the previous page's store has stopped.
    private MainPage? current;

    protected override Window CreateWindow(IActivationState? activationState)
    {
        var previous = current;
        var page = new MainPage(previous is null ? Task.CompletedTask : StopAsync(previous));
        current = page;
        var window = new Window(page);
        window.Destroying += async (_, _) => await StopAsync(page);
        return window;
    }

    // Safe to call twice for one page: the second stop is a no-op. Never throws.
    private static async Task StopAsync(MainPage page)
    {
        try { await page.StopAsync(); }
        catch (Exception error) { System.Diagnostics.Trace.TraceError("Ditto shutdown failed: " + error); }
    }
}
