#if !DITTO_V4
// Every ```csharp block in skills/csharp-sdk references and SKILL.md is copied from a
// region below (between "// <snippet name=...>" and "// </snippet>"). The regions run
// against the real SDK unless they are marked compile-only. scripts/verify-snippets.py
// fails when a published block drifts from its region or has no source.
using System.Net;
using System.Net.Sockets;
using System.Text.Json;
using System.Text.Json.Serialization;
using DittoSDK;
using DittoSDK.Auth;
using DittoSDK.Store;
using DittoSDK.Sync;
using DittoSDK.Transport;
using Xunit;

// <snippet name="store-dto">
public sealed record TaskDto(
    [property: JsonPropertyName("_id")] string Id,
    [property: JsonPropertyName("title")] string Title,
    [property: JsonPropertyName("done")] bool Done);
// </snippet>

// <snippet name="store-composite-id-dto">
public sealed record OrderKey(
    [property: JsonPropertyName("store_id")] string StoreId,
    [property: JsonPropertyName("order_id")] string OrderId);

public sealed record OrderDto(
    [property: JsonPropertyName("_id")] OrderKey Id,
    [property: JsonPropertyName("status")] string Status);
// </snippet>

public class ReferenceSnippetTests
{
    private static string License() => Environment.GetEnvironmentVariable("DITTO_OFFLINE_LICENSE")
        ?? throw new InvalidOperationException("DITTO_OFFLINE_LICENSE is required; use scripts/run.py.");
    private static string DatabaseId() => Environment.GetEnvironmentVariable("DITTO_DATABASE_ID")
        ?? DittoConfig.DefaultDatabaseId;
    private static string TempDirectory() => Path.Combine(Path.GetTempPath(), "ditto-snippet-" + Guid.NewGuid());

    [Fact]
    public async Task MinimalOpenSubscribeObserveWrite()
    {
        var databaseId = DatabaseId();
        var offlineLicense = License();
        var persistenceDirectory = TempDirectory();
        // <snippet name="skill-minimal">
        var ditto = await Ditto.OpenAsync(new DittoConfig(databaseId,
            new DittoConfigConnect.SmallPeersOnly(), persistenceDirectory));
        ditto.SetOfflineOnlyLicenseToken(offlineLicense);
        var subscription = ditto.Sync.RegisterSubscription("SELECT * FROM cars");
        var observer = ditto.Store.RegisterObserver("SELECT * FROM cars", result =>
        {
            using (result) // copy what you need: items are invalid after disposal
                Console.WriteLine($"cars: {result.Items.Count}");
        });
        ditto.Sync.Start();
        using (await ditto.Store.ExecuteAsync("INSERT INTO cars DOCUMENTS (:car)",
            new() {
                ["car"] = new Dictionary<string, object> { ["_id"] = "car1", ["make"] = "Toyota" } })) { }

        // Shutdown: cancel handles, stop sync, then dispose. Never touch a handle after Dispose.
        observer.Cancel();
        observer.Dispose();
        subscription.Cancel();
        subscription.Dispose();
        ditto.Sync.Stop();
        ditto.Dispose();
        // </snippet>
    }

    [Fact]
    public async Task OpenOffline()
    {
        var databaseId = DatabaseId();
        var offlineLicense = License();
        var persistenceDirectory = TempDirectory();
        // <snippet name="connect-offline">
        var config = new DittoConfig(databaseId, new DittoConfigConnect.SmallPeersOnly(),
            persistenceDirectory); // a stable per-app directory, one instance per directory
        var ditto = await Ditto.OpenAsync(config);
        ditto.SetOfflineOnlyLicenseToken(offlineLicense);
        Console.WriteLine($"store: {ditto.AbsolutePersistenceDirectory}");
        ditto.Sync.Start();
        // </snippet>
        // Compare the leaf: macOS resolves /var to /private/var.
        Assert.Equal(Path.GetFileName(persistenceDirectory), Path.GetFileName(ditto.AbsolutePersistenceDirectory.TrimEnd('/', '\\')));
        ditto.Sync.Stop();
        ditto.Dispose();
    }

    // Compile-only: server login needs a Portal URL and real credentials.
    private static async Task OpenServerCompileOnly(string databaseId, string portalSdkUrl,
        string persistenceDirectory, DittoAuthenticationProvider provider,
        Func<Task<string>> FetchUserTokenAsync, Action<Exception> Report)
    {
        // <snippet name="connect-server">
        var ditto = await Ditto.OpenAsync(new DittoConfig(databaseId,
            new DittoConfigConnect.Server(new Uri(portalSdkUrl)), persistenceDirectory));
        // Required for server connections: Sync.Start throws ExpirationHandlerMissingException
        // without it. Ditto also calls it for the initial login, with a zero TimeSpan.
        ditto.Auth.ExpirationHandler = async (instance, timeUntilExpiry) =>
        {
            try { await instance.Auth.LoginAsync(await FetchUserTokenAsync(), provider); }
            catch (Exception error) { Report(error); } // never let it escape into native code
        };
        var status = ditto.Auth.ObserveStatus(s => Console.WriteLine($"authenticated: {s.IsAuthenticated}"));
        ditto.Sync.Start();
        // ... on shutdown:
        status.Dispose();
        // </snippet>
        ditto.Sync.Stop();
        ditto.Dispose();
    }

    [Fact]
    public async Task CrudWithParametersAndMutationCheck()
    {
        using var peer = await Peer.Open();
        var ditto = peer.Db;
        // <snippet name="store-crud">
        using (await ditto.Store.ExecuteAsync("INSERT INTO tasks DOCUMENTS (:task)",
            new() {
                ["task"] = new Dictionary<string, object> { ["_id"] = "t1", ["title"] = "Buy milk", ["done"] = false } })) { }

        List<TaskDto> open;
        using (var result = await ditto.Store.ExecuteAsync(
            "SELECT * FROM tasks WHERE done = :done", new() { ["done"] = false }))
        {
            // Copy into managed objects while the result is alive, then let it dispose.
            open = [.. result.Items.Select(item => JsonSerializer.Deserialize<TaskDto>(item.JsonString())!)];
        }

        // Update only the field that changed, so concurrent edits to other fields survive.
        using (var updated = await ditto.Store.ExecuteAsync("UPDATE tasks SET done = :done WHERE _id = :id",
            new() { ["id"] = "t1", ["done"] = true }))
        {
            // No mutated IDs means the document is gone, for example deleted by another peer.
            if (updated.MutatedDocumentIds.Count == 0)
                throw new InvalidOperationException("Task t1 no longer exists.");
        }
        // </snippet>
        Assert.Equal("Buy milk", Assert.Single(open).Title);
        using var missing = await ditto.Store.ExecuteAsync("UPDATE tasks SET done = :done WHERE _id = :id",
            new Dictionary<string, object> { ["id"] = "absent", ["done"] = true });
        Assert.Empty(missing.MutatedDocumentIds);
    }

    [Fact]
    public async Task CompositeIdInsertLookupFilterAndDecode()
    {
        using var peer = await Peer.Open();
        var ditto = peer.Db;
        // <snippet name="store-composite-id">
        // An object _id groups documents by scope; bind it as a nested dictionary.
        var id = new Dictionary<string, object> { ["store_id"] = "store-7", ["order_id"] = "A1" };
        using (await ditto.Store.ExecuteAsync("INSERT INTO orders DOCUMENTS (:order)",
            new() { ["order"] = new Dictionary<string, object> { ["_id"] = id, ["status"] = "placed" } })) { }

        // Look up one document by its whole _id, or filter on one of its fields.
        using (var one = await ditto.Store.ExecuteAsync("SELECT * FROM orders WHERE _id = :id", new() { ["id"] = id }))
        using (var forStore = await ditto.Store.ExecuteAsync(
            "SELECT * FROM orders WHERE _id.store_id = :store", new() { ["store"] = "store-7" }))
        {
            // Map the object _id to a nested record, not a string.
            var order = JsonSerializer.Deserialize<OrderDto>(one.Items[0].JsonString())!;
            Console.WriteLine($"{order.Id.StoreId}/{order.Id.OrderId}: {order.Status}, {forStore.Items.Count} for store");
        }
        // </snippet>
        using var check = await ditto.Store.ExecuteAsync("SELECT * FROM orders WHERE _id.store_id = :store", new() { ["store"] = "store-7" });
        var decoded = JsonSerializer.Deserialize<OrderDto>(Assert.Single(check.Items).JsonString())!;
        Assert.Equal(("store-7", "A1", "placed"), (decoded.Id.StoreId, decoded.Id.OrderId, decoded.Status));
    }

    [Fact]
    public async Task GuardedStatusTransition()
    {
        using var peer = await Peer.Open();
        var ditto = peer.Db;
        using (await ditto.Store.ExecuteAsync("INSERT INTO orders DOCUMENTS (:o)", new() {
            ["o"] = new Dictionary<string, object> { ["_id"] = "A1", ["status"] = "placed" } })) { }
        async Task<bool> MoveAsync(string orderId, string from, string to)
        {
            // <snippet name="store-guarded-transition">
            // Check-and-set: the UPDATE only matches while the order is still in the expected phase.
            using var result = await ditto.Store.ExecuteAsync(
                "UPDATE orders SET status = :to, status_at = :at WHERE _id = :id AND status = :from",
                new() { ["id"] = orderId, ["from"] = from, ["to"] = to, ["at"] = DateTimeOffset.UtcNow.ToString("O") });
            return result.MutatedDocumentIds.Count == 1; // false: not found, or not in `from` any more
            // </snippet>
        }
        Assert.True(await MoveAsync("A1", "placed", "preparing"));
        Assert.False(await MoveAsync("A1", "placed", "preparing")); // already moved
        Assert.False(await MoveAsync("A1", "ready", "completed"));  // wrong phase
        Assert.True(await MoveAsync("A1", "preparing", "ready"));
    }

    [Fact]
    public async Task SignalNextAfterTheObserverIsDisposedIsSafe()
    {
        using var peer = await Peer.Open();
        var signal = new TaskCompletionSource<Action>(TaskCreationOptions.RunContinuationsAsynchronously);
        var observer = peer.Db.Store.RegisterObserver("SELECT * FROM late", (result, signalNext) =>
        {
            using (result) signal.TrySetResult(signalNext);
        });
        var signalNext = await signal.Task.WaitAsync(TimeSpan.FromSeconds(15));
        observer.Cancel();
        observer.Dispose();
        signalNext(); // queued UI work may run after shutdown; this must not crash the process
    }

#if DITTO_50
    [Fact(Skip = "TransactionAsync can hang on 5.0.x (DEVX-918, fixed in 5.1.0); the rollback path trips the 45-second watchdog.")]
#else
    [Fact]
#endif
    public async Task TransactionCommitsOnReturnAndRollsBackOnThrow()
    {
        using var peer = await Peer.Open();
        var ditto = peer.Db;
        using (await ditto.Store.ExecuteAsync("INSERT INTO accounts DOCUMENTS (:a)", new Dictionary<string, object> {
            ["a"] = new Dictionary<string, object> { ["_id"] = "alice", ["balance"] = 100 } })) { }
        async Task Withdraw(long amount)
        {
            // <snippet name="store-transaction">
            await ditto.Store.TransactionAsync(async tx =>
            {
                // Run every statement on tx: never the outer ditto.Store, never a nested transaction.
                long balance;
                using (var account = await tx.ExecuteAsync("SELECT * FROM accounts WHERE _id = :id",
                    new() { ["id"] = "alice" }))
                    balance = Convert.ToInt64(account.Items[0].Value["balance"]);
                if (balance < amount)
                    throw new InvalidOperationException("Insufficient funds."); // throwing rolls back
                using (await tx.ExecuteAsync("UPDATE accounts SET balance = :balance WHERE _id = :id",
                    new() { ["id"] = "alice", ["balance"] = balance - amount })) { }
                // Returning normally commits.
            }, hint: "withdraw");
            // </snippet>
        }
        await Withdraw(30);
        await Assert.ThrowsAsync<InvalidOperationException>(() => Withdraw(500));
        using var result = await ditto.Store.ExecuteAsync("SELECT * FROM accounts");
        Assert.Equal(70L, Convert.ToInt64(Assert.Single(result.Items).Value["balance"]));
    }

    [Fact]
    public async Task SubscriptionAndCommitId()
    {
        using var peer = await Peer.Open();
        var ditto = peer.Db;
        // <snippet name="sync-subscription">
        var subscription = ditto.Sync.RegisterSubscription(
            "SELECT * FROM tasks WHERE done = :done", new Dictionary<string, object> { ["done"] = false });
        ditto.Sync.Start();
        // ... when the owner no longer needs this data:
        subscription.Cancel();
        subscription.Dispose();
        // </snippet>
        // <snippet name="sync-commit-id">
        ulong? commitId;
        using (var inserted = await ditto.Store.ExecuteAsync("INSERT INTO tasks DOCUMENTS (:task)",
            new() { ["task"] = new Dictionary<string, object> { ["_id"] = "t2" } }))
        {
            commitId = inserted.CommitID; // read it before the result is disposed
        }
        // </snippet>
        Assert.NotNull(commitId);
        ditto.Sync.Stop();
    }

    [Fact]
    public async Task ObserverLifetime()
    {
        using var peer = await Peer.Open();
        var ditto = peer.Db;
        var seen = 0;
        // <snippet name="lifetimes-observer">
        DittoStoreObserver? observer = ditto.Store.RegisterObserver("SELECT * FROM tasks", result =>
        {
            using (result) Interlocked.Increment(ref seen);
        });
        try
        {
            // ... the owning screen or service is active
        }
        finally
        {
            observer.Cancel();   // stops delivery; Dispose alone does not
            observer.Dispose();  // releases the native handle
            observer = null;     // any member access after Dispose can crash the process
        }
        // </snippet>
        // A delivery already running when Cancel returns may still finish; let it settle,
        // then prove that no new change is delivered after cancellation.
        await Task.Delay(200);
        var before = Volatile.Read(ref seen);
        using (await ditto.Store.ExecuteAsync("INSERT INTO tasks DOCUMENTS ({'_id': 'after'})")) { }
        await Task.Delay(200);
        Assert.Equal(before, Volatile.Read(ref seen));
    }

    [Fact]
    public async Task PresenceObserveAndStop()
    {
        using var peer = await Peer.Open();
        var ditto = peer.Db;
        var delivered = new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously);
        Action<Action> dispatch = action => action();
        void ShowPeers(List<string> names) => delivered.TrySetResult(names.Count);
        // <snippet name="presence-observe">
        var presence = ditto.Presence.Observe(graph =>
        {
            // Copy what the UI needs, then dispatch it to the UI thread yourself.
            List<string> names = [.. graph.RemotePeers.Select(p => p.DeviceName)];
            dispatch(() => ShowPeers(names));
        });
        ditto.Presence.SetPeerMetadata(new() { ["role"] = "kiosk" });
        // ... later. Presence observers are not IDisposable: Stop() ends observation.
        presence.Stop();
        // </snippet>
        Assert.Equal(0, await delivered.Task.WaitAsync(TimeSpan.FromSeconds(15)));
    }

    [Fact]
    public async Task TcpTransportReplicates()
    {
        using var probe = new TcpListener(IPAddress.Loopback, 0);
        probe.Start();
        var port = checked((ushort)((IPEndPoint)probe.LocalEndpoint).Port);
        probe.Stop();
        using var first = await Peer.Open();
        using var second = await Peer.Open();
        var ditto = first.Db;
        var otherDitto = second.Db;
        // <snippet name="transports-tcp">
        // Listening peer: radios off, TCP on a known port (Port is a ushort).
        ditto.UpdateTransportConfig(config =>
        {
            config.PeerToPeer.BluetoothLE.Enabled = false;
            config.PeerToPeer.Awdl.Enabled = false;
            config.PeerToPeer.WifiAware.Enabled = false;
            config.PeerToPeer.Lan.Enabled = false;
            config.Listen.Tcp.Enabled = true;
            config.Listen.Tcp.InterfaceIp = "127.0.0.1";
            config.Listen.Tcp.Port = port;
        });
        // Connecting peer: same database ID, its own directory, connects to host:port.
        otherDitto.UpdateTransportConfig(config =>
        {
            config.PeerToPeer.BluetoothLE.Enabled = false;
            config.PeerToPeer.Awdl.Enabled = false;
            config.PeerToPeer.WifiAware.Enabled = false;
            config.PeerToPeer.Lan.Enabled = false;
            config.Connect.TcpServers.Add($"127.0.0.1:{port}");
        });
        // </snippet>
        using var subscription = otherDitto.Sync.RegisterSubscription("SELECT * FROM relay");
        try
        {
            ditto.Sync.Start(); otherDitto.Sync.Start();
            using (await ditto.Store.ExecuteAsync("INSERT INTO relay DOCUMENTS ({'_id': 'tcp'})")) { }
            await Peer.Eventually(async () => {
                using var result = await otherDitto.Store.ExecuteAsync("SELECT * FROM relay");
                return result.Items.Count == 1;
            });
        }
        finally { subscription.Cancel(); otherDitto.Sync.Stop(); ditto.Sync.Stop(); }
    }

    [Fact]
    public async Task AttachmentCreateAndFetch()
    {
        using var peer = await Peer.Open();
        var ditto = peer.Db;
        var filePath = Path.Combine(peer.DirectoryPath, "photo.jpg");
        await File.WriteAllBytesAsync(filePath, new byte[] { 1, 2, 3 });
        var uniqueStagingPath = Path.Combine(peer.DirectoryPath, "staging-" + Guid.NewGuid());
        var done = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        void Report(Exception error) => done.TrySetException(error);
        // <snippet name="attachments">
        using (var attachment = await ditto.Store.NewAttachmentAsync(filePath,
            new Dictionary<string, string> { ["name"] = "photo.jpg" })) // metadata values are strings
        using (await ditto.Store.ExecuteAsync("INSERT INTO photos DOCUMENTS (:photo)",
            new() { ["photo"] = new Dictionary<string, object> {
                ["_id"] = "p1", ["image"] = attachment } })) { }

        Dictionary<string, object> token;
        using (var result = await ditto.Store.ExecuteAsync("SELECT * FROM photos WHERE _id = :id",
            new() { ["id"] = "p1" }))
            token = (Dictionary<string, object>)result.Items[0].Value["image"];

        var fetcher = ditto.Store.FetchAttachment(token, fetchEvent =>
        {
            try
            {
                if (fetchEvent is DittoAttachmentFetchEvent.Completed completed)
                    using (completed.Attachment)
                    {
                        completed.Attachment.CopyToPath(uniqueStagingPath); // must not exist yet
                        done.TrySetResult();
                    }
            }
            catch (Exception error) { Report(error); } // never throw into native code
        });
        // Keep the fetcher until completion. Stop() abandons a pending fetch.
        // </snippet>
        try
        {
            await done.Task.WaitAsync(TimeSpan.FromSeconds(15));
            Assert.Equal(new byte[] { 1, 2, 3 }, await File.ReadAllBytesAsync(uniqueStagingPath));
        }
        finally { fetcher.Stop(); fetcher.Dispose(); }
    }

    [Fact]
    public async Task ManualBackPressureFromUiDispatch()
    {
        using var peer = await Peer.Open();
        var ditto = peer.Db;
        var shown = new TaskCompletionSource<List<string>>(TaskCreationOptions.RunContinuationsAsynchronously);
        var pending = new System.Collections.Concurrent.ConcurrentQueue<Action>();
        Action<Action> uiPost = pending.Enqueue;
        void Report(Exception error) => shown.TrySetException(error);
        void ShowTitles(List<string> titles) { if (titles.Count == 1) shown.TrySetResult(titles); }
        // <snippet name="observers-backpressure">
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
        // </snippet>
        try
        {
            await Peer.Eventually(() => Task.FromResult(!pending.IsEmpty));
            using (await ditto.Store.ExecuteAsync("INSERT INTO tasks DOCUMENTS ({'_id': 'a', 'title': 'A'})")) { }
            await Task.Delay(200);
            Assert.Single(pending); // the change waits in Ditto until the UI work runs
            while (!shown.Task.IsCompleted)
            {
                if (pending.TryDequeue(out var work)) work();
                else await Task.Delay(20);
            }
            Assert.Equal(new[] { "A" }, await shown.Task.WaitAsync(TimeSpan.FromSeconds(15)));
        }
        finally { observer.Cancel(); observer.Dispose(); }
    }

    // Compile-only wrong/right pairs for references/anti-patterns.md. The wrong forms are
    // never executed: some of them crash or hang by design.
    private static async Task AntiPatternsCompileOnly(Ditto ditto, string title, string userInput, Action<Exception> Report)
    {
        {
            // <snippet name="anti-dispose-wrong">
            using var observer = ditto.Store.RegisterObserver("SELECT * FROM tasks", r => r.Dispose());
            // Leaving scope disposes the handle, but callbacks keep firing.
            // </snippet>
        }
        {
            // <snippet name="anti-dispose-right">
            var observer = ditto.Store.RegisterObserver("SELECT * FROM tasks", r => r.Dispose());
            try { /* ... */ }
            finally { observer.Cancel(); observer.Dispose(); }
            // </snippet>
        }
        {
            var observer = ditto.Store.RegisterObserver("SELECT * FROM tasks", r => r.Dispose());
            // <snippet name="anti-after-dispose-wrong">
            observer.Cancel();
            observer.Dispose();
            Console.WriteLine(observer.IsCancelled); // native crash (SIGSEGV), not an exception
            // </snippet>
        }
        {
            var observer = ditto.Store.RegisterObserver("SELECT * FROM tasks", r => r.Dispose());
            // <snippet name="anti-after-dispose-right">
            observer.Cancel();
            Console.WriteLine(observer.IsCancelled); // read state before disposing
            observer.Dispose();
            observer = null;
            // </snippet>
        }
        {
            // <snippet name="anti-async-void-wrong">
            Action<DittoQueryResult> handler = async result =>
            {
                using (result) await SaveAsync(result.Items.Count); // async void, nothing caught
            };
            var observer = ditto.Store.RegisterObserver("SELECT * FROM tasks", handler);
            // </snippet>
            observer.Cancel(); observer.Dispose();
        }
        {
            // <snippet name="anti-async-void-right">
            var observer = ditto.Store.RegisterObserver("SELECT * FROM tasks", async result =>
            {
                try
                {
                    using (result) await SaveAsync(result.Items.Count); // Func<DittoQueryResult, Task>
                }
                catch (Exception error) { Report(error); } // an escaping exception ends the process
            });
            // ... Cancel() and Dispose() the observer when its owner stops.
            // </snippet>
            observer.Cancel(); observer.Dispose();
        }
        {
            // <snippet name="anti-interpolation-wrong">
            using (await ditto.Store.ExecuteAsync($"SELECT * FROM tasks WHERE title = '{userInput}'")) { }
            // </snippet>
        }
        {
            // <snippet name="anti-interpolation-right">
            using (await ditto.Store.ExecuteAsync("SELECT * FROM tasks WHERE title = :title",
                new() { ["title"] = userInput })) { }
            // </snippet>
        }
        {
            // <snippet name="anti-rewrite-wrong">
            // Writes every field from a possibly stale copy, overwriting concurrent edits.
            using (await ditto.Store.ExecuteAsync("INSERT INTO tasks DOCUMENTS (:task) ON ID CONFLICT DO UPDATE",
                new Dictionary<string, object> { ["task"] = new Dictionary<string, object> {
                    ["_id"] = "t1", ["title"] = title, ["done"] = true } })) { }
            // </snippet>
        }
        {
            // <snippet name="anti-rewrite-right">
            using (await ditto.Store.ExecuteAsync("UPDATE tasks SET done = :done WHERE _id = :id",
                new() { ["id"] = "t1", ["done"] = true })) { }
            // </snippet>
        }
    }

    private static Task SaveAsync(int count) => Task.CompletedTask;
}

// <snippet name="testing-fixture">
// xUnit creates a new instance per test, so every test gets its own store directory.
public sealed class TaskQueryTests : IAsyncLifetime
{
    private readonly string directory = Path.Combine(Path.GetTempPath(), "ditto-test-" + Guid.NewGuid());
    private Ditto ditto = null!;

    public async Task InitializeAsync()
    {
        // DITTOAPP_, not DITTO_: Ditto's native core reads DITTO_* variables itself.
        var license = Environment.GetEnvironmentVariable("DITTOAPP_OFFLINE_LICENSE")
            ?? throw new InvalidOperationException("Set DITTOAPP_OFFLINE_LICENSE.");
        ditto = await Ditto.OpenAsync(new DittoConfig(DittoConfig.DefaultDatabaseId,
            new DittoConfigConnect.SmallPeersOnly(), directory));
        ditto.SetOfflineOnlyLicenseToken(license);
    }

    public Task DisposeAsync()
    {
        ditto.Dispose();
        Directory.Delete(directory, recursive: true);
        return Task.CompletedTask;
    }

    [Fact]
    public async Task ObserverSeesInsert()
    {
        var seen = new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously);
        var observer = ditto.Store.RegisterObserver("SELECT * FROM tasks", result =>
        {
            using (result) if (result.Items.Count > 0) seen.TrySetResult(result.Items.Count);
        });
        try
        {
            using (await ditto.Store.ExecuteAsync("INSERT INTO tasks DOCUMENTS (:task)",
                new() { ["task"] = new Dictionary<string, object> { ["_id"] = "t1" } })) { }
            // Await the observation with a deadline; never sleep and hope.
            Assert.Equal(1, await seen.Task.WaitAsync(TimeSpan.FromSeconds(10)));
        }
        finally { observer.Cancel(); observer.Dispose(); }
    }
}
// </snippet>
#endif
