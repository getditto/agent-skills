using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using DittoTasks;

internal static class Program
{
    private static async Task<int> Main()
    {
        var store = new TaskStore();
        var observed = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        store.Changed += rows => {
            if (rows.Any(row => row.Id == "legacy" && row.Title == "Framework native runtime"))
                observed.TrySetResult(true);
        };
        store.Failed += message => observed.TrySetException(new InvalidOperationException(message));
        try
        {
            await store.StartAsync(new Settings {
                DatabaseId = string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("DITTO_DATABASE_ID"))
                    ? "e807f150-cb5d-4aa5-bcef-cc90e8521b91" : Environment.GetEnvironmentVariable("DITTO_DATABASE_ID"),
                OfflineLicense = Environment.GetEnvironmentVariable("DITTO_OFFLINE_LICENSE")
            }, Path.Combine(Path.GetTempPath(), "ditto-net48-" + Guid.NewGuid()));
            await store.SaveAsync(new TaskItem { Id = "legacy", Title = "Framework native runtime" });
            if (await Task.WhenAny(observed.Task, Task.Delay(TimeSpan.FromSeconds(15))) != observed.Task)
                throw new TimeoutException("No observer delivery on .NET Framework.");
            await observed.Task;
            await store.DeleteAsync("legacy");
            Console.WriteLine("PASS net48 native runtime and starter CRUD: " + DittoSDK.Ditto.Version);
            return 0;
        }
        finally { await store.StopAsync(); }
    }
}
