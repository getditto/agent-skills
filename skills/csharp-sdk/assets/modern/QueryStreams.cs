using System.Collections.Generic;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Channels;
using DittoSDK;

namespace DittoTasks;

// Application adapter for modern .NET. The SDK itself does not return IAsyncEnumerable.
public static class QueryStreams
{
    public static async IAsyncEnumerable<IReadOnlyList<string>> ObserveJsonAsync(
        Ditto ditto, string query, [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        var snapshots = Channel.CreateBounded<IReadOnlyList<string>>(new BoundedChannelOptions(1) {
            FullMode = BoundedChannelFullMode.DropOldest, SingleReader = true, SingleWriter = false
        });
        using var observer = ditto.Store.RegisterObserver(query, result => {
            using (result)
            {
                try { snapshots.Writer.TryWrite(result.Items.Select(item => item.JsonString()).ToArray()); }
                catch (System.Exception error) { snapshots.Writer.TryComplete(error); }
            }
        });
        try
        {
            await foreach (var snapshot in snapshots.Reader.ReadAllAsync(cancellationToken).ConfigureAwait(false))
                yield return snapshot;
        }
        finally
        {
            observer.Cancel();
            snapshots.Writer.TryComplete();
        }
    }
}
