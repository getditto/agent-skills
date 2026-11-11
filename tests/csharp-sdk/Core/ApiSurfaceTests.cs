#if !DITTO_V4
using System.Reflection;
using DittoSDK;
using DittoSDK.Logging;
using Xunit;

public class ApiSurfaceTests
{
    [Fact]
    public void PublicPackageDoesNotExposeDataStreams()
    {
        // Deliberately fail when the public surface changes: revisit CAP-20 then.
        var types = typeof(Ditto).Assembly.GetExportedTypes();
        Assert.DoesNotContain(types, type => type.Name.Contains("DataStream", StringComparison.OrdinalIgnoreCase));
        Assert.DoesNotContain(typeof(Ditto).GetMembers(BindingFlags.Public | BindingFlags.Instance),
            member => member.Name.Contains("Stream", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public async Task DiagnosticsAndLocalCommitHaveDocumentedShapes()
    {
        using var peer = await Peer.Open();
        // The native core canonicalizes parent symlinks (e.g. /var -> /private/var).
        Assert.True(Path.IsPathRooted(peer.Db.AbsolutePersistenceDirectory));
        await File.WriteAllTextAsync(Path.Combine(peer.DirectoryPath, "path-probe"), "same store");
        Assert.Equal("same store", await File.ReadAllTextAsync(Path.Combine(peer.Db.AbsolutePersistenceDirectory, "path-probe")));
        Assert.NotNull(peer.Db.DiskUsage);
        var previous = DittoLogger.MinimumLogLevel;
        try
        {
            DittoLogger.MinimumLogLevel = DittoLogLevel.Error;
            Assert.Equal(DittoLogLevel.Error, DittoLogger.MinimumLogLevel);
            using var result = await peer.Db.Store.ExecuteAsync("INSERT INTO commit_samples DOCUMENTS ({'_id': 'one'})");
            ulong? commit = result.CommitID;
            Assert.NotNull(commit);
        }
        finally { DittoLogger.MinimumLogLevel = previous; }
    }
}
#endif
