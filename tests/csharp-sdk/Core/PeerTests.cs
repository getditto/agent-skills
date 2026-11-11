#if !DITTO_V4
using System.Net;
using System.Net.Sockets;
using DittoSDK;
using DittoSDK.Store;
using Xunit;

public class PeerTests
{
    [Fact]
    public async Task TwoPeersReplicateAndExposePresence()
    {
        using var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var port = checked((ushort)((IPEndPoint)listener.LocalEndpoint).Port);
        listener.Stop();
        using var first = await Peer.Open();
        using var second = await Peer.Open();
        foreach (var peer in new[] { first, second })
            peer.Db.UpdateTransportConfig(config => {
                config.PeerToPeer.Lan.Enabled = false;
                config.PeerToPeer.BluetoothLE.Enabled = false;
                config.PeerToPeer.Awdl.Enabled = false;
                config.PeerToPeer.WifiAware.Enabled = false;
            });
        first.Db.UpdateTransportConfig(config => {
            config.Listen.Tcp.Enabled = true;
            config.Listen.Tcp.InterfaceIp = "127.0.0.1";
            config.Listen.Tcp.Port = port;
        });
        second.Db.UpdateTransportConfig(config => config.Connect.TcpServers.Add("127.0.0.1:" + port));
        using var subscription = second.Db.Sync.RegisterSubscription("SELECT * FROM replication");
        try
        {
            first.Db.Sync.Start(); second.Db.Sync.Start();
            using (await first.Db.Store.ExecuteAsync("INSERT INTO replication DOCUMENTS (:doc)",
                new Dictionary<string, object> { ["doc"] = new Dictionary<string, object> {
                    ["_id"] = "peer-write", ["value"] = "over TCP" } })) { }
            await Peer.Eventually(async () => {
                using var result = await second.Db.Store.ExecuteAsync("SELECT * FROM replication");
                return result.Items.Count == 1 && (string)result.Items[0].Value["value"] == "over TCP";
            });
            Assert.NotEmpty(second.Db.Presence.Graph.RemotePeers);
            subscription.Cancel();
            Assert.True(subscription.IsCancelled);
        }
        finally { subscription.Cancel(); second.Db.Sync.Stop(); first.Db.Sync.Stop(); }
    }

    [Fact]
    public async Task AttachmentRoundTrip()
    {
        using var peer = await Peer.Open();
        var path = Path.Combine(peer.DirectoryPath, "payload.txt");
        await File.WriteAllTextAsync(path, "attachment payload");
        using var attachment = await peer.Db.Store.NewAttachmentAsync(path, new Dictionary<string, string> { ["kind"] = "text" });
        using (await peer.Db.Store.ExecuteAsync("INSERT INTO files DOCUMENTS (:doc)",
            new Dictionary<string, object> { ["doc"] = new Dictionary<string, object> {
                ["_id"] = "file", ["payload"] = attachment } })) { }
        using var result = await peer.Db.Store.ExecuteAsync("SELECT * FROM files");
        var token = (Dictionary<string, object>)Assert.Single(result.Items).Value["payload"];
        var completed = new TaskCompletionSource<byte[]>(TaskCreationOptions.RunContinuationsAsynchronously);
        using var fetcher = peer.Db.Store.FetchAttachment(token, evt => {
            try
            {
                if (evt is DittoAttachmentFetchEvent.Completed done)
                    using (done.Attachment) completed.TrySetResult(done.Attachment.Data());
            }
            catch (Exception e) { completed.TrySetException(e); }
        });
        Assert.Equal("attachment payload", System.Text.Encoding.UTF8.GetString(await completed.Task.WaitAsync(TimeSpan.FromSeconds(15))));
    }

    [Fact]
    public async Task AsyncObserverCompletesBeforeNextDelivery()
    {
        using var peer = await Peer.Open();
        var initial = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var changed = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        using var observer = peer.Db.Store.RegisterObserver("SELECT * FROM async_samples", async result => {
            using (result)
            {
                if (result.Items.Count == 0) { initial.TrySetResult(); await release.Task; }
                else changed.TrySetResult();
            }
        });
        try
        {
            await initial.Task.WaitAsync(TimeSpan.FromSeconds(10));
            using (await peer.Db.Store.ExecuteAsync("INSERT INTO async_samples DOCUMENTS ({'_id': 'one'})")) { }
            Assert.False(changed.Task.IsCompleted);
            release.TrySetResult();
            await changed.Task.WaitAsync(TimeSpan.FromSeconds(10));
        }
        finally { release.TrySetResult(); observer.Cancel(); }
    }
}
#endif
