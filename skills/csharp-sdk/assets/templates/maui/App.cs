namespace DittoTasks;

public sealed class App : Application
{
    protected override Window CreateWindow(IActivationState activationState)
    {
        var page = new MainPage();
        var window = new Window(page);
        window.Destroying += async (_, _) => await page.StopAsync();
        return window;
    }
}
