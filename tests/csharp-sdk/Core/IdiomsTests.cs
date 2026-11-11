#if !DITTO_V4
using System.Text.Json;
using System.Text.Json.Serialization;
using DittoTasks;
using Xunit;

public class IdiomsTests
{
    private sealed record Document([property: JsonPropertyName("_id")] string Id,
        [property: JsonPropertyName("title")] string Title);

    [Fact]
    public async Task RecordsAndExplicitPortableConversions()
    {
        using var peer = await Peer.Open();
        var id = Guid.NewGuid();
        var instant = DateTimeOffset.Parse("2026-01-02T03:04:05Z");
        var args = new Dictionary<string, object> { ["doc"] = new Dictionary<string, object> {
            ["_id"] = id.ToString("D"), ["title"] = "record", ["when"] = instant.ToString("O"),
            ["amountMinorUnits"] = 12345L, ["exactDecimal"] = 123.45m.ToString(System.Globalization.CultureInfo.InvariantCulture)
        } };
        using (await peer.Db.Store.ExecuteAsync("INSERT INTO idioms DOCUMENTS (:doc)", args)) { }
        using var result = await peer.Db.Store.ExecuteAsync("SELECT * FROM idioms");
        var item = Assert.Single(result.Items);
        var record = JsonSerializer.Deserialize<Document>(item.JsonString())!;
        Assert.Equal(id.ToString("D"), record.Id);
        Assert.Equal("record", record.Title);
        Assert.Equal(instant, DateTimeOffset.Parse((string)item.Value["when"]));
        Assert.Equal(12345L, Convert.ToInt64(item.Value["amountMinorUnits"]));
        Assert.Equal("123.45", item.Value["exactDecimal"]);
    }

    [Fact]
    public async Task AsyncEnumerationCancellationCancelsObserver()
    {
        using var peer = await Peer.Open();
        using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        var before = peer.Db.Store.Observers.Count;
        await using (var stream = QueryStreams.ObserveJsonAsync(peer.Db, "SELECT * FROM stream_items", cancellation.Token).GetAsyncEnumerator())
        {
            Assert.True(await stream.MoveNextAsync());
            Assert.Empty(stream.Current);
            using (await peer.Db.Store.ExecuteAsync("INSERT INTO stream_items DOCUMENTS ({'_id': 'one'})")) { }
            Assert.True(await stream.MoveNextAsync());
            Assert.Single(stream.Current);
            cancellation.Cancel();
            await Assert.ThrowsAnyAsync<OperationCanceledException>(async () => await stream.MoveNextAsync());
        }
        Assert.Equal(before, peer.Db.Store.Observers.Count);
    }
}
#endif
