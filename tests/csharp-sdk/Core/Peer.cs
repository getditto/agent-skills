using DittoSDK;
using Xunit;

[assembly: CollectionBehavior(DisableTestParallelization = true)]

internal sealed class Peer : IDisposable
{
    public Ditto Db { get; }
    public string DirectoryPath { get; }

    private Peer(Ditto db, string path) { Db = db; DirectoryPath = path; }

    public static async Task<Peer> Open(string? path = null)
    {
        var license = Environment.GetEnvironmentVariable("DITTO_OFFLINE_LICENSE");
        if (string.IsNullOrWhiteSpace(license))
            throw new InvalidOperationException("DITTO_OFFLINE_LICENSE is required; use scripts/run.py.");
        path ??= Path.Combine(Path.GetTempPath(), "ditto-csharp-" + Guid.NewGuid());
        var id = Environment.GetEnvironmentVariable("DITTO_DATABASE_ID")
            ?? "e807f150-cb5d-4aa5-bcef-cc90e8521b91";
        var db = await Ditto.OpenAsync(new DittoConfig(id,
            new DittoConfigConnect.SmallPeersOnly(), path));
        try
        {
            db.SetOfflineOnlyLicenseToken(license);
#if DITTO_V4
            db.DisableSyncWithV3();
            using (await db.Store.ExecuteAsync("ALTER SYSTEM SET DQL_STRICT_MODE = false")) { }
#endif
            return new Peer(db, path);
        }
        catch { db.Dispose(); throw; }
    }

    public void Dispose() { Db.Dispose(); }

    public static async Task Eventually(Func<Task<bool>> condition)
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(15));
        while (!await condition()) await Task.Delay(20, deadline.Token);
    }
}
