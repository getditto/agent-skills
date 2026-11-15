using System.Text.Json;
using DittoSDK;
using Xunit;

public class StoreTests
{
    private static Dictionary<string, object> Args(string id, object? value = null) =>
        new() { ["doc"] = new Dictionary<string, object?> { ["_id"] = id, ["value"] = value } };

    private static async Task Insert(Ditto db, string id, object? value = null)
    {
        using var result = await db.Store.ExecuteAsync("INSERT INTO samples DOCUMENTS (:doc)", Args(id, value));
    }

    [Fact]
    public void LoadedVersionMatchesRequestedPackage()
    {
        var expected = Environment.GetEnvironmentVariable("DITTO_CSHARP_VERSION");
        Assert.False(string.IsNullOrEmpty(expected));
        Assert.Contains(expected!, Ditto.Version);
    }

    [Fact]
    public async Task ParameterizedCrudAndPocoMapping()
    {
        using var peer = await Peer.Open();
        await Insert(peer.Db, "quoted'identifier", "hello");
        var args = new Dictionary<string, object> { ["id"] = "quoted'identifier" };
        using (var result = await peer.Db.Store.ExecuteAsync("SELECT * FROM samples WHERE _id = :id", args))
        {
            var item = Assert.Single(result.Items);
            Assert.Equal("hello", item.Value["value"]);
            Assert.Equal("hello", JsonSerializer.Deserialize<Sample>(item.JsonString())!.value);
        }
        using (await peer.Db.Store.ExecuteAsync("UPDATE samples SET value = 'updated' WHERE _id = :id", args)) { }
        using (var result = await peer.Db.Store.ExecuteAsync("SELECT * FROM samples WHERE _id = :id", args))
            Assert.Equal("updated", Assert.Single(result.Items).Value["value"]);
        using (await peer.Db.Store.ExecuteAsync("DELETE FROM samples WHERE _id = :id", args)) { }
        using var empty = await peer.Db.Store.ExecuteAsync("SELECT * FROM samples");
        Assert.Empty(empty.Items);
    }

    public sealed class Sample { public string? value { get; set; } }

    [Theory]
    [InlineData(-123L)]
    [InlineData(9007199254740991L)]
    public async Task IntegerBinding(long value)
    {
        using var peer = await Peer.Open();
        await Insert(peer.Db, "number", value);
        using var result = await peer.Db.Store.ExecuteAsync("SELECT * FROM samples");
        Assert.Equal(value, Convert.ToInt64(Assert.Single(result.Items).Value["value"]));
    }

    [Fact]
    public async Task NullBooleanNestedAndArrayBindings()
    {
        using var peer = await Peer.Open();
        await Insert(peer.Db, "nested", new Dictionary<string, object?> {
            ["enabled"] = true, ["missing"] = null, ["tags"] = new[] { "a", "b" } });
        using var result = await peer.Db.Store.ExecuteAsync("SELECT * FROM samples");
        using var json = JsonDocument.Parse(Assert.Single(result.Items).JsonString());
        var value = json.RootElement.GetProperty("value");
        Assert.True(value.GetProperty("enabled").GetBoolean());
        Assert.Equal(JsonValueKind.Null, value.GetProperty("missing").ValueKind);
        Assert.Equal(2, value.GetProperty("tags").GetArrayLength());
    }

    [Fact]
    public async Task ObserverDeliversCopiedValuesAndCancelStopsObservation()
    {
        using var peer = await Peer.Open();
        var observed = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        var observer = peer.Db.Store.RegisterObserver("SELECT * FROM samples", result => {
            using (result)
                if (result.Items.Count > 0) observed.TrySetResult(result.Items[0].JsonString());
        });
        try
        {
            await Insert(peer.Db, "observed", "retained");
            var json = await observed.Task.WaitAsync(TimeSpan.FromSeconds(15));
            Assert.Contains("retained", json);
        }
        finally { observer.Cancel(); }
        Assert.True(observer.IsCancelled);
#if !DITTO_V4
        observer.Dispose();
#endif
    }

    [Fact]
    public async Task BackpressureWaitsForSignalAndThenDeliversLatest()
    {
        using var peer = await Peer.Open();
        var first = new TaskCompletionSource<Action>(TaskCreationOptions.RunContinuationsAsynchronously);
        var updated = new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously);
        var calls = 0;
        var observer = peer.Db.Store.RegisterObserver("SELECT * FROM samples", (result, signalNext) => {
            using (result)
            {
                if (Interlocked.Increment(ref calls) == 1) first.TrySetResult(signalNext);
                else { updated.TrySetResult(result.Items.Count); signalNext(); }
            }
        });
        try
        {
            var release = await first.Task.WaitAsync(TimeSpan.FromSeconds(15));
            await Insert(peer.Db, "one"); await Insert(peer.Db, "two");
            await Task.Delay(200);
            Assert.Equal(1, Volatile.Read(ref calls));
            release();
            Assert.Equal(2, await updated.Task.WaitAsync(TimeSpan.FromSeconds(15)));
        }
        finally { observer.Cancel();
#if !DITTO_V4
            observer.Dispose();
#endif
        }
    }

    [Fact]
    public async Task PersistenceSurvivesCloseAndReopen()
    {
        string path;
        using (var peer = await Peer.Open()) { path = peer.DirectoryPath; await Insert(peer.Db, "persist", "saved"); }
        using var reopened = await Peer.Open(path);
        using var result = await reopened.Db.Store.ExecuteAsync("SELECT * FROM samples");
        Assert.Equal("saved", Assert.Single(result.Items).Value["value"]);
    }

    [Fact]
    public async Task InvalidDqlFails()
    {
        using var peer = await Peer.Open();
        await Assert.ThrowsAnyAsync<Exception>(async () => {
            using var result = await peer.Db.Store.ExecuteAsync("THIS IS NOT DQL");
        });
    }

    [Fact]
    public async Task IndexAndEviction()
    {
        using var peer = await Peer.Open();
        await Insert(peer.Db, "evict", "indexed");
        using (await peer.Db.Store.ExecuteAsync("CREATE INDEX IF NOT EXISTS samples_value ON samples (value)")) { }
        using (var result = await peer.Db.Store.ExecuteAsync("SELECT * FROM samples WHERE value = 'indexed'"))
            Assert.Single(result.Items);
        using (await peer.Db.Store.ExecuteAsync("EVICT FROM samples WHERE _id = 'evict'")) { }
        using var empty = await peer.Db.Store.ExecuteAsync("SELECT * FROM samples");
        Assert.Empty(empty.Items);
    }

#if !DITTO_V4
#if DITTO_50
    [Fact(Skip = "Transaction probe hangs on macOS ARM64 in 5.0.3/5.0.4; reproduced with a 45-second test-host watchdog. See references/versions.md.")]
#else
    [Fact]
#endif
    public async Task TransactionsCommitAndRollback()
    {
        using var peer = await Peer.Open();
        await peer.Db.Store.TransactionAsync(async tx => {
            using var result = await tx.ExecuteAsync("INSERT INTO samples DOCUMENTS (:doc)", Args("committed"));
        });
        await peer.Db.Store.TransactionAsync(async tx => {
            using var result = await tx.ExecuteAsync("INSERT INTO samples DOCUMENTS (:doc)", Args("rolled-back"));
            return DittoSDK.Store.DittoTransactionCompletionAction.Rollback;
        });
        using var result = await peer.Db.Store.ExecuteAsync("SELECT * FROM samples");
        Assert.Equal("committed", Assert.Single(result.Items).Value["_id"]);
    }
#endif
}
