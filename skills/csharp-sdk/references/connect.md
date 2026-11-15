# Opening, authentication and lifecycle

## CAP-03 Connecting

Source: [installation](https://docs.ditto.live/sdk/latest/install-guides/c-sharp)
and the published Ditto 5.2.0 assembly's DittoConfig/Ditto members.

Construct `new DittoConfig(databaseId, new DittoConfigConnect.SmallPeersOnly(), path)`
for offline operation, then await `Ditto.OpenAsync(config)` and call
`SetOfflineOnlyLicenseToken(license)`. Use an explicit persistent directory under the
application data directory, and include the database ID in it: data in a store that
is reopened under a different database ID is treated as new and syncs to that database.
Read `AbsolutePersistenceDirectory` to diagnose path resolution. Do not open multiple instances on the same directory.

<!-- snippet: connect-offline -->
```csharp
var config = new DittoConfig(databaseId, new DittoConfigConnect.SmallPeersOnly(),
    persistenceDirectory); // a stable per-app directory, one instance per directory
var ditto = await Ditto.OpenAsync(config);
ditto.SetOfflineOnlyLicenseToken(offlineLicense);
Console.WriteLine($"store: {ditto.AbsolutePersistenceDirectory}");
ditto.Sync.Start();
```

`new DittoConfigConnect.Server(new Uri(url))` selects server connectivity. The URL is
the SDK URL copied from the Portal. Keep database ID, credentials and URL configurable.
The starter's Settings reads its embedded appsettings.json with `<NAME>_*` environment
overrides (`DITTOTASKS_*` for the default name); this is a development convenience, not production credential provisioning.

## CAP-04 Authentication

v5 authentication types live in `DittoSDK.Auth`. With `DittoConfigConnect.Server`,
setting `Auth.ExpirationHandler` is **required**: `Sync.Start()` throws
`ExpirationHandlerMissingException` without it. Ditto calls the handler for the initial
login too (with a zero TimeSpan), then again before the token expires. The delegate
receives `Ditto` and a **TimeSpan**, not a number of seconds. `LoginAsync(token,
provider)` returns a Task<string>. `DittoAuthenticationProvider.Development` is for a
playground; production uses `DittoAuthenticationProvider.Custom(name)` for the
provider configured in the Portal (the starter's AuthProvider setting). Fetch a
per-user token at runtime; do not put a shared administrative secret in a client app.

<!-- snippet: connect-server -->
```csharp
var ditto = await Ditto.OpenAsync(new DittoConfig(databaseId,
    new DittoConfigConnect.Server(new Uri(portalSdkUrl)), persistenceDirectory));
// Required for server connections: Sync.Start throws ExpirationHandlerMissingException
// without it. Ditto also calls it for the initial login, with a zero TimeSpan.
ditto.Auth.ExpirationHandler = async (instance, timeUntilExpiry) =>
{
    try { await instance.Auth.LoginAsync(await FetchUserTokenAsync(), provider); }
    catch (Exception error) { Report(error); } // never let it escape into native code
};
var status = ditto.Auth.ObserveStatus(s => Console.WriteLine($"authenticated: {s.IsAuthenticated}"));
ditto.Sync.Start();
// ... on shutdown:
status.Dispose();
```

The starter's `TaskStore.StartAsync` takes the same idea as an optional `fetchToken`
callback: it is called for the initial login and every renewal. Without it, the starter
reuses the configured `Token`, which ships inside the app and cannot be refreshed, so
use that for development only.

This flow is compile-checked against each supported package. The starter's `fetchToken`
path was run against a real Portal server; server login is not part of the offline test
run.

Use `Auth.ObserveStatus(callback)` and retain/dispose the returned IDisposable.
`Auth.Logout` and its cleanup callback do not replace an application-specific decision
about which local data to evict. An authentication error should be surfaced; retry
transient failures with a bounded policy, not an infinite loop on rejected credentials.

Source: [cloud authentication](https://docs.ditto.live/sdk/latest/auth-and-authorization/cloud-authentication).
The starter's server flow is compile-checked; server login requires its separate
credentialed integration test and is not inferred from offline test success.

## CAP-05 Lifecycle

Start sync only after configuration, authentication/license setup and required runtime
permissions. Register subscriptions and local observers with explicit owners. Stop by
preventing new operations, awaiting in-flight application tasks, cancelling observers
and subscriptions, stopping sync, then disposing the Ditto instance.

The bundled TaskStore serializes startup/writes/shutdown with SemaphoreSlim. A failed
startup releases partially created handles so the user can fix settings and retry.
The semaphore belongs to the adapter, not the SDK. UI event handlers may be async void;
service operations return Task and are awaited. Do not block the UI during shutdown.

Mobile suspension is not process shutdown. Choose whether to pause sync according to
the app's background permissions and requirements; a page disappearing does not mean
an app-owned store should be destroyed. See the framework-specific references.
