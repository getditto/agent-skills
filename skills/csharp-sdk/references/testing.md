# Validation

## CAP-18 Testing

Source: [Ditto testing guidance](https://docs.ditto.live/sdk/latest/deployment/testing)
and the executed example below (xUnit, Ditto 5.0.4 through 5.2.0). Public docs may
contain older API forms; compile against the selected package rather than copying
those forms without verification.

Give every test its own temporary store directory and a valid offline license, and
assert on actual observations and read-back values. A zero exit code or successful
restore does not establish correctness. Provide a database ID when the license is
bound to one; otherwise `DittoConfig.DefaultDatabaseId` works for isolated offline
stores.

<!-- snippet: testing-fixture -->
```csharp
// xUnit creates a new instance per test, so every test gets its own store directory.
public sealed class TaskQueryTests : IAsyncLifetime
{
    private readonly string directory = Path.Combine(Path.GetTempPath(), "ditto-test-" + Guid.NewGuid());
    private Ditto ditto = null!;

    public async Task InitializeAsync()
    {
        var license = Environment.GetEnvironmentVariable("DITTO_OFFLINE_LICENSE")
            ?? throw new InvalidOperationException("Set DITTO_OFFLINE_LICENSE.");
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
```

Notes for real suites:

- Two instances must never share a directory. A second open of the same path throws
  `DittoPersistenceDirectoryLockedException` while the first instance is alive, so
  derive each path from a new GUID.
- Dispose Ditto before deleting its directory. Cancel observers and subscriptions in
  `finally`, as above, so a failed assertion cannot leave callbacks running.
- Wait on a `TaskCompletionSource` with `WaitAsync(timeout)`. A fixed `Task.Delay` is
  either too slow or flaky. To prove something did *not* happen, wait a short bounded
  time and assert nothing changed.
- Native code can deadlock where managed timeouts cannot help. Run CI with a test-host
  watchdog, for example `dotnet test --blame-hang-timeout 45s`.
- For two-peer tests, connect the peers over loopback TCP (see
  [transports](transports.md)) with radios disabled. A localhost peer test proves
  replication logic, not BLE, Wi-Fi Aware or cloud durability.

Classify evidence separately: package/API inspection; compile; desktop/simulator runtime;
physical-device radios; server integration. Do not promote compile-only evidence to
runtime support.
