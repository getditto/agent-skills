using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;
using DittoSDK;
using DittoSDK.Auth;
using DittoSDK.Store;
using DittoSDK.Sync;

namespace DittoTasks
{
    public sealed class TaskItem
    {
        [JsonPropertyName("_id")]
        public string Id { get; set; }
        [JsonPropertyName("title")]
        public string Title { get; set; }
        [JsonPropertyName("done")]
        public bool Done { get; set; }
        public override string ToString() { return (Done ? "[x] " : "[ ] ") + Title; }
    }

    // Application adapter, not an SDK-provided repository or LINQ provider.
    // C# 7.3 syntax keeps the same implementation usable from net48.
    public sealed class TaskStore
    {
        private readonly SemaphoreSlim operations = new SemaphoreSlim(1, 1);
        private Ditto ditto;
        private DittoStoreObserver observer;
        private DittoSyncSubscription subscription;
        private volatile bool stopped = true;
        public event Action<IReadOnlyList<TaskItem>> Changed;
        public event Action<string> Failed;
        public const string Query = "SELECT * FROM tasks ORDER BY title";

        public async Task StartAsync(Settings settings, string directory, Func<Task> requestPermissions = null)
        {
            settings.Validate();
            directory = Environment.GetEnvironmentVariable("DITTO_PERSISTENCE_DIRECTORY") ?? directory;
            await operations.WaitAsync().ConfigureAwait(false);
            try
            {
                if (ditto != null) return;
                DittoConfigConnect connection = string.IsNullOrWhiteSpace(settings.Url)
                    ? (DittoConfigConnect)new DittoConfigConnect.SmallPeersOnly()
                    : new DittoConfigConnect.Server(new Uri(settings.Url));
                ditto = await Ditto.OpenAsync(new DittoConfig(settings.DatabaseId, connection, directory))
                    .ConfigureAwait(false);
                // Android's SDK helper needs initialized native transports. The host
                // dispatches permission UI to its main thread; sync starts afterwards.
                if (requestPermissions != null) await requestPermissions().ConfigureAwait(false);
                if (connection is DittoConfigConnect.SmallPeersOnly)
                    ditto.SetOfflineOnlyLicenseToken(settings.OfflineLicense);
                else
                {
                    ditto.Auth.ExpirationHandler = async (db, remaining) => {
                        try { await db.Auth.LoginAsync(settings.Token, DittoAuthenticationProvider.Development).ConfigureAwait(false); }
                        catch (Exception e) { Report(e); }
                    };
                    await ditto.Auth.LoginAsync(settings.Token, DittoAuthenticationProvider.Development).ConfigureAwait(false);
                }
                stopped = false;
                if (!settings.EnablePeerToPeerRadios)
                    ditto.UpdateTransportConfig(config => {
                        config.PeerToPeer.BluetoothLE.Enabled = false;
                        config.PeerToPeer.Awdl.Enabled = false;
                        config.PeerToPeer.WifiAware.Enabled = false;
                    });
                subscription = ditto.Sync.RegisterSubscription("SELECT * FROM tasks");
                observer = ditto.Store.RegisterObserver(Query, result => {
                    // Own and dispose the native result inside the callback. Only DTOs escape.
                    using (result)
                    {
                        try
                        {
                            var rows = result.Items.Select(item => JsonSerializer.Deserialize<TaskItem>(item.JsonString())).ToList();
                            if (!stopped) Changed?.Invoke(rows);
                        }
                        catch (Exception e) { Report(e); }
                    }
                });
                ditto.Sync.Start();
            }
            catch { Close(); throw; }
            finally { operations.Release(); }
        }

        public Task SaveAsync(TaskItem item)
        {
            if (item == null || string.IsNullOrWhiteSpace(item.Id) || string.IsNullOrWhiteSpace(item.Title))
                throw new ArgumentException("A task needs an ID and title.");
            return ExecuteAsync("INSERT INTO tasks DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE",
                new Dictionary<string, object> { ["doc"] = new Dictionary<string, object> {
                    ["_id"] = item.Id, ["title"] = item.Title, ["done"] = item.Done } });
        }

        public Task SetDoneAsync(string id, bool done)
        {
            return ExecuteAsync("UPDATE tasks SET done = :done WHERE _id = :id",
                new Dictionary<string, object> { ["id"] = id, ["done"] = done });
        }

        public Task RenameAsync(string id, string title)
        {
            if (string.IsNullOrWhiteSpace(title)) throw new ArgumentException("A task needs a title.");
            return ExecuteAsync("UPDATE tasks SET title = :title WHERE _id = :id",
                new Dictionary<string, object> { ["id"] = id, ["title"] = title });
        }

        public Task DeleteAsync(string id)
        {
            return ExecuteAsync("DELETE FROM tasks WHERE _id = :id",
                new Dictionary<string, object> { ["id"] = id });
        }

        private async Task ExecuteAsync(string query, Dictionary<string, object> arguments)
        {
            await operations.WaitAsync().ConfigureAwait(false);
            try
            {
                if (stopped || ditto == null) throw new InvalidOperationException("Store is not open.");
                using (await ditto.Store.ExecuteAsync(query, arguments).ConfigureAwait(false)) { }
            }
            finally { operations.Release(); }
        }

        public async Task StopAsync()
        {
            stopped = true;
            await operations.WaitAsync().ConfigureAwait(false);
            try { Close(); }
            finally { operations.Release(); }
        }

        private void Close()
        {
            stopped = true;
            if (observer != null) { observer.Cancel(); observer.Dispose(); observer = null; }
            if (subscription != null) { subscription.Cancel(); subscription.Dispose(); subscription = null; }
            if (ditto != null) { ditto.Sync.Stop(); ditto.Dispose(); ditto = null; }
        }

        private void Report(Exception exception)
        {
            // Never let an application event-handler exception escape an FFI callback.
            try { if (!stopped) Failed?.Invoke(exception.GetType().Name + ": operation failed; check configuration and SDK logs."); }
            catch { System.Diagnostics.Trace.TraceError("Ditto application error handler failed."); }
        }
    }
}
