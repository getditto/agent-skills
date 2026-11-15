#if !DITTO_V4
using DittoTasks;
using Xunit;

public class StarterTests
{
    [Fact]
    public async Task StarterCrudPersistenceAndShutdown()
    {
        var settings = new Settings {
            DatabaseId = Environment.GetEnvironmentVariable("DITTO_DATABASE_ID") ?? DittoSDK.DittoConfig.DefaultDatabaseId,
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
            await store.CreateAsync(new TaskItem { Id = "task", Title = "Original" });
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
            DatabaseId = Environment.GetEnvironmentVariable("DITTO_DATABASE_ID") ?? DittoSDK.DittoConfig.DefaultDatabaseId,
            OfflineLicense = Environment.GetEnvironmentVariable("DITTO_OFFLINE_LICENSE")!
        };
        var path = Path.Combine(Path.GetTempPath(), "ditto-permission-" + Guid.NewGuid());
        settings.EnablePeerToPeerRadios = true; // the prompt is only requested for radios
        await Assert.ThrowsAsync<UnauthorizedAccessException>(() => store.StartAsync(settings, path,
            () => throw new UnauthorizedAccessException("permission probe")));
        settings.EnablePeerToPeerRadios = false;
        try { await store.StartAsync(settings, path); await store.CreateAsync(new TaskItem { Id = "retry", Title = "Recovered" }); }
        finally { await store.StopAsync(); }
    }

    [Fact]
    public void TaskListAppliesSnapshotsInPlaceSoSelectionSurvives()
    {
        static TaskItem T(string id, string title, bool done = false) => new() { Id = id, Title = title, Done = done };
        var items = new System.Collections.ObjectModel.ObservableCollection<TaskItem>();
        TaskList.Apply(items, new[] { T("1", "a"), T("2", "b"), T("3", "c") });
        var selected = items[1];
        var actions = new List<System.Collections.Specialized.NotifyCollectionChangedAction>();
        items.CollectionChanged += (_, e) => actions.Add(e.Action);
        TaskList.Apply(items, new[] { T("0", "0"), T("1", "a"), T("3", "c"), T("2", "z", true) });
        // The selected row is the same instance, updated in place, and nothing was rebuilt.
        Assert.Same(selected, items[3]);
        Assert.Equal("z", selected.Title);
        Assert.True(selected.Done);
        Assert.Equal(new[] { "0", "1", "3", "2" }, items.Select(i => i.Id));
        Assert.DoesNotContain(System.Collections.Specialized.NotifyCollectionChangedAction.Reset, actions);
        TaskList.Apply(items, new[] { T("0", "0") });
        Assert.Equal(new[] { "0" }, items.Select(i => i.Id));
    }

    private static Settings OfflineSettings() => new Settings {
        DatabaseId = Environment.GetEnvironmentVariable("DITTO_DATABASE_ID") ?? DittoSDK.DittoConfig.DefaultDatabaseId,
        OfflineLicense = Environment.GetEnvironmentVariable("DITTO_OFFLINE_LICENSE")!
    };

    [Fact]
    public async Task StopAsyncFromAChangedHandlerCompletes()
    {
        // No dispatcher, so Changed runs on Ditto's callback thread; stopping there used to deadlock.
        var store = new TaskStore();
        var stop = new TaskCompletionSource<Task>(TaskCreationOptions.RunContinuationsAsynchronously);
        var stopping = 0;
        // Stop from the first delivery that contains the new row. Do not count deliveries: the
        // insert can coalesce into the initial result, so there may be only one.
        store.Changed += rows =>
        {
            if (rows.Any(row => row.Id == "x") && Interlocked.Exchange(ref stopping, 1) == 0)
                stop.TrySetResult(store.StopAsync());
        };
        await store.StartAsync(OfflineSettings(), Path.Combine(Path.GetTempPath(), "ditto-stop-in-changed-" + Guid.NewGuid()));
        await store.CreateAsync(new TaskItem { Id = "x", Title = "x" });
        var stopTask = await stop.Task.WaitAsync(TimeSpan.FromSeconds(15));
        await stopTask.WaitAsync(TimeSpan.FromSeconds(15));
    }

    [Fact]
    public async Task DisposeIsIdempotentAndADisposedStoreCannotRestart()
    {
        var store = new TaskStore();
        var path = Path.Combine(Path.GetTempPath(), "ditto-dispose-" + Guid.NewGuid());
        await store.StartAsync(OfflineSettings(), path);
        store.Dispose();
        store.Dispose();
        await store.StopAsync();
        await Assert.ThrowsAsync<ObjectDisposedException>(() => store.StartAsync(OfflineSettings(), path));
    }

    private static async Task WithStarterEnvironment(Func<Task> body)
    {
        // TasksViewModel loads Settings itself; the starter reads DITTOTASKS_* overrides.
        var names = new[] { "DITTOTASKS_OFFLINE_LICENSE", "DITTOTASKS_DATABASE_ID", "DITTOTASKS_PERSISTENCE_DIRECTORY" };
        var settings = OfflineSettings();
        Environment.SetEnvironmentVariable(names[0], settings.OfflineLicense);
        Environment.SetEnvironmentVariable(names[1], settings.DatabaseId);
        Environment.SetEnvironmentVariable(names[2], Path.Combine(Path.GetTempPath(), "ditto-vm-" + Guid.NewGuid()));
        try { await body(); }
        finally { foreach (var name in names) Environment.SetEnvironmentVariable(name, null); }
    }

    [Fact]
    public Task ViewModelDrivesCrudThroughTheStore() => WithStarterEnvironment(async () =>
    {
        var model = new TasksViewModel(action => action());
        async Task Until(Func<bool> condition) => await Peer.Eventually(() => Task.FromResult(condition()));
        try
        {
            await model.StartAsync("unused-base-directory");
            await Until(() => model.Status == "0 task(s)");
            await model.SaveAsync("First");
            await Until(() => model.Items.Count == 1 && model.Status == "1 task(s)");
            var item = model.Items[0];
            await model.ToggleAsync(item);
            await Until(() => item.Done);
            await model.SaveAsync("Renamed", item);
            await Until(() => item.Title == "Renamed");
            Assert.Same(item, model.Items[0]); // updated in place, so selection survives
            await model.DeleteAsync(item);
            await Until(() => model.Items.Count == 0);
        }
        finally { await model.StopAsync(); }
    });

    [Fact]
    public Task ViewModelFailureAfterTheDispatcherStopsDoesNotThrow() => WithStarterEnvironment(async () =>
    {
        var dispatcherClosed = false;
        var model = new TasksViewModel(action =>
        {
            if (Volatile.Read(ref dispatcherClosed)) throw new InvalidOperationException("dispatcher closed");
            action();
        });
        await model.StartAsync("unused-base-directory");
        await model.StopAsync();
        Volatile.Write(ref dispatcherClosed, true);
        await model.SaveAsync("after stop"); // the store is closed and the dispatcher rejects the status update
    });

    [Fact]
    public async Task LateSubscribersReadTheCurrentSnapshot()
    {
        // An observer delivers the current result once, then only on change. A view created
        // after that (a lazily created tab) must start from Current.
        var store = new TaskStore();
        var delivered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        store.Changed += rows => { if (rows.Count == 1) delivered.TrySetResult(); };
        try
        {
            await store.StartAsync(OfflineSettings(), Path.Combine(Path.GetTempPath(), "ditto-current-" + Guid.NewGuid()));
            await store.CreateAsync(new TaskItem { Id = "early", Title = "Early" });
            await delivered.Task.WaitAsync(TimeSpan.FromSeconds(15));
            IReadOnlyList<TaskItem>? late = null;
            store.Changed += rows => late = rows; // subscribes after the delivery, sees nothing yet
            Assert.Null(late);
            Assert.Equal("early", Assert.Single(store.Current).Id);
        }
        finally { await store.StopAsync(); }
    }

    [Fact]
    public async Task TcpSettingsLetTwoStarterStoresSync()
    {
        using var probe = new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
        probe.Start();
        var port = ((System.Net.IPEndPoint)probe.LocalEndpoint).Port;
        probe.Stop();
        var kitchen = new TaskStore();
        var window = new TaskStore();
        var seen = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        kitchen.Changed += rows => { if (rows.Any(row => row.Id == "over-tcp")) seen.TrySetResult(); };
        var listening = OfflineSettings();
        listening.TcpListenPort = port;
        var connecting = OfflineSettings();
        connecting.TcpConnect = "127.0.0.1:" + port;
        try
        {
            await kitchen.StartAsync(listening, Path.Combine(Path.GetTempPath(), "ditto-tcp-a-" + Guid.NewGuid()));
            await window.StartAsync(connecting, Path.Combine(Path.GetTempPath(), "ditto-tcp-b-" + Guid.NewGuid()));
            await window.CreateAsync(new TaskItem { Id = "over-tcp", Title = "Synced" });
            await seen.Task.WaitAsync(TimeSpan.FromSeconds(30));
        }
        finally { await window.StopAsync(); await kitchen.StopAsync(); }
    }

    [Theory]
    [InlineData(-1, null)]
    [InlineData(70000, null)]
    [InlineData(0, "no-port")]
    [InlineData(0, "host:notaport")]
    public void InvalidTcpSettingsAreRejected(int listenPort, string? connect)
    {
        var settings = OfflineSettings();
        settings.TcpListenPort = listenPort;
        settings.TcpConnect = connect;
        Assert.Throws<InvalidOperationException>(() => settings.Validate());
    }

    [Fact]
    public void BothStarterCopiesTreatMissingTitlesAndDatabaseIdsAlike()
    {
        // Runs against the modern copy (Core) and the C# 7.3 copy (LegacyStarterTests).
        foreach (var json in new[] { "{\"_id\":\"x\"}", "{\"_id\":\"x\",\"title\":null}" })
            Assert.Equal("", System.Text.Json.JsonSerializer.Deserialize<TaskItem>(json)!.Title);
        Assert.Throws<InvalidOperationException>(() => Settings.StorePath("base", new Settings()));
    }

    [Fact]
    public async Task MalformedDocumentIsSkippedAndReportedWithoutHidingOthers()
    {
        var path = Path.Combine(Path.GetTempPath(), "ditto-malformed-" + Guid.NewGuid());
        using (var seed = await Peer.Open(path))
        {
            // Another peer or app version stored done as a string.
            using (await seed.Db.Store.ExecuteAsync("INSERT INTO tasks DOCUMENTS (:a), (:b)",
                new Dictionary<string, object> {
                    ["a"] = new Dictionary<string, object> { ["_id"] = "good", ["title"] = "Good", ["done"] = false },
                    ["b"] = new Dictionary<string, object> { ["_id"] = "bad", ["title"] = "Bad", ["done"] = "yes" } })) { }
        }
        var store = new TaskStore();
        IReadOnlyList<TaskItem> snapshot = Array.Empty<TaskItem>();
        string? error = null;
        store.Changed += rows => Volatile.Write(ref snapshot, rows);
        store.Failed += message => Volatile.Write(ref error, message);
        var settings = new Settings {
            DatabaseId = Environment.GetEnvironmentVariable("DITTO_DATABASE_ID") ?? DittoSDK.DittoConfig.DefaultDatabaseId,
            OfflineLicense = Environment.GetEnvironmentVariable("DITTO_OFFLINE_LICENSE")!
        };
        try
        {
            await store.StartAsync(settings, path);
            await Peer.Eventually(() => Task.FromResult(Volatile.Read(ref snapshot).Count == 1));
            await Peer.Eventually(() => Task.FromResult(Volatile.Read(ref error) != null));
            Assert.Equal("good", Volatile.Read(ref snapshot)[0].Id);
            Assert.Contains("bad", Volatile.Read(ref error));
            // Later writes still arrive despite the malformed document.
            await store.CreateAsync(new TaskItem { Id = "later", Title = "Later" });
            await Peer.Eventually(() => Task.FromResult(Volatile.Read(ref snapshot).Count == 2));
        }
        finally { await store.StopAsync(); }
    }

    [Fact]
    public async Task PermissionsAreNotRequestedWhenRadiosAreDisabled()
    {
        var store = new TaskStore();
        var settings = new Settings {
            DatabaseId = Environment.GetEnvironmentVariable("DITTO_DATABASE_ID") ?? DittoSDK.DittoConfig.DefaultDatabaseId,
            OfflineLicense = Environment.GetEnvironmentVariable("DITTO_OFFLINE_LICENSE")!
        };
        var asked = false;
        try
        {
            await store.StartAsync(settings, Path.Combine(Path.GetTempPath(), "ditto-noprompt-" + Guid.NewGuid()),
                () => { asked = true; return Task.FromResult(true); });
            Assert.False(asked);
        }
        finally { await store.StopAsync(); }
    }

    [Fact]
    public async Task EditsToMissingTasksAreReportedAndCreateNeverOverwrites()
    {
        var store = new TaskStore();
        var settings = new Settings {
            DatabaseId = Environment.GetEnvironmentVariable("DITTO_DATABASE_ID") ?? DittoSDK.DittoConfig.DefaultDatabaseId,
            OfflineLicense = Environment.GetEnvironmentVariable("DITTO_OFFLINE_LICENSE")!
        };
        try
        {
            await store.StartAsync(settings, Path.Combine(Path.GetTempPath(), "ditto-missing-" + Guid.NewGuid()));
            foreach (var edit in new Func<Task>[] {
                () => store.RenameAsync("absent", "x"), () => store.SetDoneAsync("absent", true), () => store.DeleteAsync("absent") })
                Assert.Contains("no longer exists", (await Assert.ThrowsAsync<InvalidOperationException>(edit)).Message);
            await store.CreateAsync(new TaskItem { Id = "t", Title = "Original" });
            await Assert.ThrowsAnyAsync<Exception>(() => store.CreateAsync(new TaskItem { Id = "t", Title = "Overwrite" }));
            await store.SetDoneAsync("t", true); // an existing document still updates normally
        }
        finally { await store.StopAsync(); }
    }

    [Fact]
    public async Task PermissionDenialKeepsLocalStoreOpenAndReportsIt()
    {
        var store = new TaskStore();
        string? error = null;
        store.Failed += message => Volatile.Write(ref error, message);
        var settings = new Settings {
            DatabaseId = Environment.GetEnvironmentVariable("DITTO_DATABASE_ID") ?? DittoSDK.DittoConfig.DefaultDatabaseId,
            OfflineLicense = Environment.GetEnvironmentVariable("DITTO_OFFLINE_LICENSE")!
        };
        var path = Path.Combine(Path.GetTempPath(), "ditto-denied-" + Guid.NewGuid());
        settings.EnablePeerToPeerRadios = true; // denial must then turn the radios back off
        try
        {
            await store.StartAsync(settings, path, () => Task.FromResult(false));
            Assert.Contains("permissions were denied", Volatile.Read(ref error));
            Assert.True(store.PermissionsDenied);
            await store.CreateAsync(new TaskItem { Id = "local", Title = "Still local" });
        }
        finally { await store.StopAsync(); }
    }

    [Fact]
    public async Task ObserverWaitsForDispatchedWorkBeforeNextDelivery()
    {
        // A dispatcher that queues work without running it, like a busy UI thread.
        var pending = new System.Collections.Concurrent.ConcurrentQueue<Action>();
        var store = new TaskStore(pending.Enqueue);
        var deliveries = new List<int>();
        store.Changed += rows => deliveries.Add(rows.Count);
        var settings = new Settings {
            DatabaseId = Environment.GetEnvironmentVariable("DITTO_DATABASE_ID") ?? DittoSDK.DittoConfig.DefaultDatabaseId,
            OfflineLicense = Environment.GetEnvironmentVariable("DITTO_OFFLINE_LICENSE")!
        };
        var path = Path.Combine(Path.GetTempPath(), "ditto-dispatch-" + Guid.NewGuid());
        try
        {
            await store.StartAsync(settings, path);
            await Peer.Eventually(() => Task.FromResult(!pending.IsEmpty));
            await store.CreateAsync(new TaskItem { Id = "one", Title = "One" });
            await store.CreateAsync(new TaskItem { Id = "two", Title = "Two" });
            await Task.Delay(300);
            // Only the initial result was handed over; later changes wait in Ditto.
            Assert.Single(pending);
            Assert.True(pending.TryDequeue(out var initial));
            initial();
            // After the consumer runs its work, one coalesced result arrives with the latest state.
            await Peer.Eventually(() => Task.FromResult(!pending.IsEmpty));
            Assert.True(pending.TryDequeue(out var latest));
            latest();
            Assert.Equal(new[] { 0, 2 }, deliveries);
        }
        finally { await store.StopAsync(); }
    }

    [Fact]
    public async Task RejectedDispatchDoesNotStallObserver()
    {
        var attempts = 0;
        var delivered = new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously);
        // The first post is rejected, as a shutting-down dispatcher would; later posts run.
        var store = new TaskStore(action => {
            if (Interlocked.Increment(ref attempts) == 1) throw new InvalidOperationException("dispatcher closed");
            action();
        });
        string? error = null;
        store.Failed += message => Volatile.Write(ref error, message);
        store.Changed += rows => { if (rows.Count == 1) delivered.TrySetResult(rows.Count); };
        var settings = new Settings {
            DatabaseId = Environment.GetEnvironmentVariable("DITTO_DATABASE_ID") ?? DittoSDK.DittoConfig.DefaultDatabaseId,
            OfflineLicense = Environment.GetEnvironmentVariable("DITTO_OFFLINE_LICENSE")!
        };
        var path = Path.Combine(Path.GetTempPath(), "ditto-rejected-" + Guid.NewGuid());
        try
        {
            await store.StartAsync(settings, path);
            await Peer.Eventually(() => Task.FromResult(Volatile.Read(ref attempts) >= 1));
            await store.CreateAsync(new TaskItem { Id = "after", Title = "After rejection" });
            Assert.Equal(1, await delivered.Task.WaitAsync(TimeSpan.FromSeconds(15)));
            Assert.Contains("dispatcher closed", Volatile.Read(ref error));
        }
        finally { await store.StopAsync(); }
    }
}
#endif
