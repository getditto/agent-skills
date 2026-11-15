using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.Json.Serialization;
using DittoSDK;
using DittoSDK.Auth;
using DittoSDK.Logging;
using DittoSDK.Store;
using DittoSDK.Sync;

namespace DittoTasks;

// Raises PropertyChanged so a list can update an existing row in place, which keeps
// UI selection stable when the observed data changes.
public sealed class TaskItem : INotifyPropertyChanged
{
    private string title = "";
    private bool done;

    public event PropertyChangedEventHandler? PropertyChanged;

    [JsonPropertyName("_id")]
    public required string Id { get; init; }

    [JsonPropertyName("title")]
    public string Title { get => title; set => Set(ref title, value ?? ""); }

    [JsonPropertyName("done")]
    public bool Done { get => done; set => Set(ref done, value); }

    [JsonIgnore]
    public string Display => ToString();

    public override string ToString() => (Done ? "[x] " : "[ ] ") + Title;

    private void Set<T>(ref T field, T value, [CallerMemberName] string property = "")
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return;
        field = value;
        PropertyChanged?.Invoke(this, new(property));
        PropertyChanged?.Invoke(this, new(nameof(Display)));
    }
}

// Application adapter, not an SDK-provided repository or LINQ provider. Modern C# for
// .NET 8 and later; the WinForms starter ships a C# 7.3 copy (common-legacy) for .NET
// Framework with the same public API.
//
// dispatch posts work to the consumer's thread (for example the UI dispatcher) and must
// throw if it cannot accept the work. Changed is raised inside the dispatched work, and
// the observer is not signalled for its next result until that work has run (manual
// back-pressure). Without a dispatcher, Changed runs on the SDK thread.
public sealed class TaskStore(Action<Action>? dispatch = null) : IDisposable, IAsyncDisposable
{
    public const string Query = "SELECT * FROM tasks ORDER BY title";

    private readonly SemaphoreSlim operations = new(1, 1);
    private readonly Action<Action> dispatch = dispatch ?? (action => action());
    private Ditto? ditto;
    private DittoStoreObserver? observer;
    private DittoSyncSubscription? subscription;
    private volatile bool stopped = true;
    private int disposed;

    // The latest snapshot applied on the consumer's thread. An observer delivers the current
    // result once and then only on change, so a view created later must read this first.
    public IReadOnlyList<TaskItem> Current { get; private set; } = [];

    public event Action<IReadOnlyList<TaskItem>>? Changed;
    public event Action<string>? Failed;

    // requestPermissions is called only when EnablePeerToPeerRadios is set, and returns
    // false when the user denies. Denial turns the radios off and is reported through
    // Failed, but does not stop the store: local data, LAN and server sync keep working.
    // fetchToken (server mode) returns a fresh per-user token for each login and renewal,
    // for example from your identity backend. Without it, the configured Token is reused,
    // which suits development only: it ships inside the app and cannot be refreshed.
    public async Task StartAsync(Settings settings, string directory, Func<Task<bool>>? requestPermissions = null,
        Func<Task<string>>? fetchToken = null)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentException.ThrowIfNullOrWhiteSpace(directory);
        ObjectDisposedException.ThrowIf(Volatile.Read(ref disposed) != 0, this);
        settings.Validate(requireToken: fetchToken is null);
        var radios = settings.EnablePeerToPeerRadios;
        var permissionsDenied = false;
        await operations.WaitAsync().ConfigureAwait(false);
        try
        {
            if (ditto is not null) return;
            DittoConfigConnect connection = string.IsNullOrWhiteSpace(settings.Url)
                ? new DittoConfigConnect.SmallPeersOnly()
                : new DittoConfigConnect.Server(new Uri(settings.Url));
            // Native INFO logging prints certificates and peer keys to stdout; keep it to warnings.
            DittoLogger.MinimumLogLevel = DittoLogLevel.Warning;
            // OpenAsync and ExecuteAsync complete synchronously in v5 (they return finished
            // tasks), so awaiting them alone would run store work on the caller's UI thread.
            var dittoConfig = new DittoConfig(settings.DatabaseId, connection, directory);
            ditto = await Task.Run(() => Ditto.OpenAsync(dittoConfig)).ConfigureAwait(false);
            // Android's SDK helper needs initialized native transports. The host
            // dispatches permission UI to its main thread; sync starts afterwards.
            if (radios && requestPermissions is not null && !await requestPermissions().ConfigureAwait(false))
            {
                permissionsDenied = true;
                radios = false;
            }
            if (connection is DittoConfigConnect.SmallPeersOnly)
            {
                ditto.SetOfflineOnlyLicenseToken(settings.OfflineLicense);
            }
            else
            {
                // Development is the playground provider. Production apps set AuthProvider
                // and obtain a per-user token at runtime instead of embedding one.
                var provider = string.IsNullOrWhiteSpace(settings.AuthProvider)
                    ? DittoAuthenticationProvider.Development
                    : DittoAuthenticationProvider.Custom(settings.AuthProvider);
                // Required for server connections (Sync.Start throws without it). Ditto also
                // calls it for the initial login, so the store does not log in separately.
                ditto.Auth.ExpirationHandler = async (db, remaining) =>
                {
                    try
                    {
                        var token = fetchToken is null ? settings.Token! : await fetchToken().ConfigureAwait(false);
                        await db.Auth.LoginAsync(token, provider).ConfigureAwait(false);
                    }
                    catch (Exception e) { Report(e); }
                };
            }
            stopped = false;
            if (permissionsDenied)
                Report(new UnauthorizedAccessException(
                    "Sync permissions were denied, so Bluetooth and Wi-Fi peer-to-peer sync are off until they are granted."));
            var tcpServers = settings.TcpServers();
            ditto.UpdateTransportConfig(config =>
            {
                if (!radios)
                {
                    config.PeerToPeer.BluetoothLE.Enabled = false;
                    config.PeerToPeer.Awdl.Enabled = false;
                    config.PeerToPeer.WifiAware.Enabled = false;
                }
                // Optional direct TCP, for example two instances on one machine or a known server.
                if (settings.TcpListenPort > 0)
                {
                    config.Listen.Tcp.Enabled = true;
                    config.Listen.Tcp.InterfaceIp = settings.TcpListenAddress ?? "127.0.0.1";
                    config.Listen.Tcp.Port = (ushort)settings.TcpListenPort;
                }
                foreach (var server in tcpServers) config.Connect.TcpServers.Add(server);
            });
            subscription = ditto.Sync.RegisterSubscription("SELECT * FROM tasks");
            observer = ditto.Store.RegisterObserver(Query, OnResult);
            ditto.Sync.Start();
        }
        catch
        {
            // Keep the original failure; a teardown error is logged, not substituted.
            if (Close() is { } closeError)
                System.Diagnostics.Trace.TraceError("DittoTasks: cleanup after failed start: " + closeError);
            throw;
        }
        finally { operations.Release(); }
    }

    private void OnResult(DittoQueryResult result, Action signalNext)
    {
        List<TaskItem> rows;
        List<string> skipped;
        try
        {
            // Own and dispose the native result inside the callback. Only DTOs escape.
            using (result) rows = Decode(result, out skipped);
        }
        catch (Exception e)
        {
            try { Report(e); } finally { signalNext(); }
            return;
        }
        try
        {
            // Signal only after the consumer has applied this snapshot, so changes
            // coalesce in Ditto instead of queueing on the consumer's thread.
            dispatch(() =>
            {
                try
                {
                    if (stopped) return;
                    Current = rows;
                    Changed?.Invoke(rows);
                    if (skipped.Count > 0)
                        Report(new InvalidDataException($"Skipped {skipped.Count} task document(s) " +
                            $"that do not match the expected shape: {string.Join(", ", skipped)}"));
                }
                catch (Exception e) { Report(e); }
                finally { signalNext(); }
            });
        }
        catch (Exception e)
        {
            // The dispatcher rejected the work, so the dispatched finally never runs.
            try { Report(e); } finally { signalNext(); }
        }
    }

    // Creates a new task. Plain INSERT fails if the ID exists, so it can never overwrite
    // or resurrect a document; edit existing tasks with the field-level methods below.
    public Task CreateAsync(TaskItem item)
    {
        ArgumentNullException.ThrowIfNull(item);
        if (string.IsNullOrWhiteSpace(item.Id) || string.IsNullOrWhiteSpace(item.Title))
            throw new ArgumentException("A task needs an ID and title.", nameof(item));
        return ExecuteAsync("INSERT INTO tasks DOCUMENTS (:doc)",
            new() { ["doc"] = new Dictionary<string, object> { ["_id"] = item.Id, ["title"] = item.Title, ["done"] = item.Done } },
            expectedId: null);
    }

    public Task SetDoneAsync(string id, bool done) =>
        ExecuteAsync("UPDATE tasks SET done = :done WHERE _id = :id",
            new() { ["id"] = RequireId(id), ["done"] = done }, id);

    public Task RenameAsync(string id, string title)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(title);
        return ExecuteAsync("UPDATE tasks SET title = :title WHERE _id = :id",
            new() { ["id"] = RequireId(id), ["title"] = title }, id);
    }

    public Task DeleteAsync(string id) =>
        ExecuteAsync("DELETE FROM tasks WHERE _id = :id", new() { ["id"] = RequireId(id) }, id);

    private static string RequireId(string id)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        return id;
    }

    // expectedId: when set, the statement must change that document. Nothing mutated means
    // it no longer exists (for example, another device deleted it), which is reported.
    private async Task ExecuteAsync(string query, Dictionary<string, object> arguments, string? expectedId)
    {
        await operations.WaitAsync().ConfigureAwait(false);
        try
        {
            if (stopped || ditto is null) throw new InvalidOperationException("Store is not open.");
            var store = ditto.Store;
            // Off the caller's thread: v5 ExecuteAsync runs the statement synchronously.
            using var result = await Task.Run(() => store.ExecuteAsync(query, arguments)).ConfigureAwait(false);
            if (expectedId is not null && result.MutatedDocumentIds.Count == 0)
                throw new InvalidOperationException($"Task {expectedId} no longer exists; it may have been deleted on another device.");
        }
        finally { operations.Release(); }
    }

    // Safe to call from a Changed or Failed handler: teardown runs on a thread-pool thread,
    // because disposing Ditto on its own callback thread would deadlock. Do not block on
    // the returned task from inside a callback.
    public async Task StopAsync()
    {
        stopped = true;
        if (Volatile.Read(ref disposed) != 0) return;
        await operations.WaitAsync().ConfigureAwait(false);
        Exception? closeError;
        try { closeError = await Task.Run(Close).ConfigureAwait(false); }
        finally { operations.Release(); }
        if (closeError is not null) throw closeError;
    }

    // Stops and releases everything. Safe to call more than once. Prefer DisposeAsync or
    // StopAsync from UI code, and never call Dispose from a Changed or Failed handler.
    public void Dispose()
    {
        if (Volatile.Read(ref disposed) != 0) return;
        StopAsync().GetAwaiter().GetResult();
        if (Interlocked.Exchange(ref disposed, 1) == 0) operations.Dispose();
    }

    public async ValueTask DisposeAsync()
    {
        if (Volatile.Read(ref disposed) != 0) return;
        await StopAsync().ConfigureAwait(false);
        if (Interlocked.Exchange(ref disposed, 1) == 0) operations.Dispose();
    }

    // Every step runs even if an earlier one fails, and each field is cleared before its
    // handle is released, so a failed shutdown can never leave a half-open store behind.
    // Returns the first failure instead of throwing. Never touch a handle after Dispose.
    private Exception? Close()
    {
        stopped = true;
        Exception? first = null;
        var (currentObserver, currentSubscription, currentDitto) = (observer, subscription, ditto);
        (observer, subscription, ditto) = (null, null, null);
        if (currentObserver is not null)
        {
            Attempt(currentObserver.Cancel, ref first);
            Attempt(currentObserver.Dispose, ref first);
        }
        if (currentSubscription is not null)
        {
            Attempt(currentSubscription.Cancel, ref first);
            Attempt(currentSubscription.Dispose, ref first);
        }
        if (currentDitto is not null)
        {
            Attempt(currentDitto.Sync.Stop, ref first);
            Attempt(currentDitto.Dispose, ref first);
        }
        return first;
    }

    private static void Attempt(Action step, ref Exception? first)
    {
        try { step(); }
        catch (Exception error) { first ??= error; }
    }

    // Decode each document separately: one malformed document from another peer or app
    // version must not hide the rest of the list. Skipped documents are reported by ID.
    private static List<TaskItem> Decode(DittoQueryResult result, out List<string> skipped)
    {
        List<TaskItem> rows = new(result.Items.Count);
        skipped = [];
        foreach (var item in result.Items)
        {
            TaskItem? row = null;
            try { row = JsonSerializer.Deserialize<TaskItem>(item.JsonString()); }
            catch (JsonException) { }
            if (row is not null && !string.IsNullOrEmpty(row.Id)) rows.Add(row);
            else skipped.Add(DocumentId(item));
        }
        return rows;
    }

    private static string DocumentId(DittoQueryResultItem item)
    {
        try
        {
            return item.Value.TryGetValue("_id", out var id) && id is not null ? id.ToString() ?? "(no _id)" : "(no _id)";
        }
        catch (Exception) { return "(unreadable)"; }
    }

    private void Report(Exception exception)
    {
        // The full exception goes to Trace, which has no output unless the host adds a
        // listener (see references/observability.md). Never log Settings: it holds secrets.
        System.Diagnostics.Trace.TraceError("DittoTasks: " + exception);
        // Never let an application event-handler exception escape an FFI callback.
        try { if (!stopped) Failed?.Invoke($"{exception.GetType().Name}: {exception.Message}"); }
        catch (Exception handlerError) { System.Diagnostics.Trace.TraceError("DittoTasks: Failed handler threw: " + handlerError); }
    }
}
