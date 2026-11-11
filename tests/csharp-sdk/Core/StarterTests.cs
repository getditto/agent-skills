#if !DITTO_V4
using DittoTasks;
using Xunit;

public class StarterTests
{
    [Fact]
    public async Task StarterCrudPersistenceAndShutdown()
    {
        var settings = new Settings {
            DatabaseId = Environment.GetEnvironmentVariable("DITTO_DATABASE_ID") ?? "e807f150-cb5d-4aa5-bcef-cc90e8521b91",
            OfflineLicense = Environment.GetEnvironmentVariable("DITTO_OFFLINE_LICENSE")!
        };
        var path = Path.Combine(Path.GetTempPath(), "ditto-starter-" + Guid.NewGuid());
        var store = new TaskStore();
        IReadOnlyList<TaskItem> snapshot = Array.Empty<TaskItem>();
        string? error = null;
        store.Changed += rows => Volatile.Write(ref snapshot, rows);
        store.Failed += message => Volatile.Write(ref error, message);
        async Task Seen(Func<IReadOnlyList<TaskItem>, bool> condition)
        {
            await Peer.Eventually(() => Task.FromResult(condition(Volatile.Read(ref snapshot))));
            Assert.Null(Volatile.Read(ref error));
        }
        try
        {
            await store.StartAsync(settings, path);
            await store.SaveAsync(new TaskItem { Id = "task", Title = "Original" });
            await Seen(rows => rows.Count == 1 && rows[0].Title == "Original");
            await store.SetDoneAsync("task", true);
            await Seen(rows => rows.Count == 1 && rows[0].Done);
            await store.RenameAsync("task", "Renamed");
            await Seen(rows => rows.Count == 1 && rows[0].Title == "Renamed" && rows[0].Done);
            await store.StopAsync();
            Volatile.Write(ref snapshot, Array.Empty<TaskItem>());
            await store.StartAsync(settings, path);
            await Seen(rows => rows.Count == 1 && rows[0].Title == "Renamed");
            await store.DeleteAsync("task");
            await Seen(rows => rows.Count == 0);
        }
        finally { await store.StopAsync(); }
        await Assert.ThrowsAsync<InvalidOperationException>(() => store.DeleteAsync("task"));
    }

    [Fact]
    public async Task PermissionFailureRollsBackAndAllowsRetry()
    {
        var store = new TaskStore();
        var settings = new Settings {
            DatabaseId = Environment.GetEnvironmentVariable("DITTO_DATABASE_ID") ?? "e807f150-cb5d-4aa5-bcef-cc90e8521b91",
            OfflineLicense = Environment.GetEnvironmentVariable("DITTO_OFFLINE_LICENSE")!
        };
        var path = Path.Combine(Path.GetTempPath(), "ditto-permission-" + Guid.NewGuid());
        await Assert.ThrowsAsync<UnauthorizedAccessException>(() => store.StartAsync(settings, path,
            () => throw new UnauthorizedAccessException("permission probe")));
        try { await store.StartAsync(settings, path); await store.SaveAsync(new TaskItem { Id = "retry", Title = "Recovered" }); }
        finally { await store.StopAsync(); }
    }
}
#endif
