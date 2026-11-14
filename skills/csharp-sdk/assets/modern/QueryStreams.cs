using System.Collections.Generic;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Channels;
using DittoSDK;

#nullable enable
namespace DittoTasks;

// Application adapter for modern .NET. The SDK itself does not return IAsyncEnumerable.
public static class QueryStreams
{
    public static IAsyncEnumerable<IReadOnlyList<string>> ObserveJsonAsync(
        Ditto ditto, string query, CancellationToken cancellationToken = default)
        => ObserveJsonAsync(ditto, query, null, cancellationToken);

    // Bind values through arguments (":name" placeholders); never interpolate them into query.
    public static async IAsyncEnumerable<IReadOnlyList<string>> ObserveJsonAsync(
        Ditto ditto, string query, Dictionary<string, object>? arguments,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        System.ArgumentNullException.ThrowIfNull(ditto);
        System.ArgumentException.ThrowIfNullOrWhiteSpace(query);
        var snapshots = Channel.CreateBounded<IReadOnlyList<string>>(new BoundedChannelOptions(1) {
            FullMode = BoundedChannelFullMode.DropOldest, SingleReader = true, SingleWriter = false
        });
        System.Action<DittoSDK.Store.DittoQueryResult> handler = result => {
            using (result)
            {
                try { snapshots.Writer.TryWrite(result.Items.Select(item => item.JsonString()).ToArray()); }
                catch (System.Exception error) { snapshots.Writer.TryComplete(error); }
            }
        };
        using var observer = arguments == null
            ? ditto.Store.RegisterObserver(query, handler)
            : ditto.Store.RegisterObserver(query, arguments, handler);
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
