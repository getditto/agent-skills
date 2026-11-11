# Opening, authentication and lifecycle

## CAP-03 Connecting

Source: [installation](https://docs.ditto.live/sdk/latest/install-guides/c-sharp)
and the published Ditto 5.2.0 assembly's DittoConfig/Ditto members.

Construct `new DittoConfig(databaseId, new DittoConfigConnect.SmallPeersOnly(), path)`
for offline operation, then await `Ditto.OpenAsync(config)` and call
`SetOfflineOnlyLicenseToken(license)`. Use an explicit persistent directory under the
application data directory. Read `AbsolutePersistenceDirectory` to diagnose path
resolution. Do not open multiple instances on the same directory.

`new DittoConfigConnect.Server(new Uri(url))` selects server connectivity. The URL is
the SDK URL copied from the Portal. Keep database ID, credentials and URL configurable.
The starter's Settings reads its embedded appsettings.json with environment overrides;
this is a development convenience, not production credential provisioning.

## CAP-04 Authentication

v5 authentication types live in `DittoSDK.Auth`. Configure `Auth.ExpirationHandler`
before relying on a long-lived authenticated session. The delegate receives `Ditto`
and a **TimeSpan**, not a number of seconds. `LoginAsync(token,
DittoAuthenticationProvider.Development)` returns a Task<string>. The development
provider is for a playground; production uses the provider configured for the app.
Do not put a shared administrative secret in a client application.

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
