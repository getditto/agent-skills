---
name: migrate-dotnet
description: Use when migrating Ditto .NET/C# SDK applications from v4.14 to v5.0. Covers ~65 API removals, Ditto.Open(DittoConfig) factory, DittoAuthenticationExpirationHandler delegate, DittoStore.TransactionAsync(), WifiAwareConfig new API, DittoSyncPermissions, namespace reorganization, and DQL migration from legacy Collection API. Includes comprehensive migration checklist.
---

# Ditto .NET/C# SDK: v4.14 → v5.0 Migration Reference

## Quick Summary of Changes

| Area | v4.14 | v5.0 |
|------|-------|------|
| Init | `new Ditto(DittoIdentity, string)` | `Ditto.Open(DittoConfig)` or `Ditto.OpenAsync(DittoConfig)` |
| Identity | `DittoIdentity` abstract class hierarchy | `DittoConfig` static factory methods |
| Sync | `Ditto.StartSync()` / `StopSync()` | `Ditto.Sync.Start()` / `Sync.Stop()` |
| Auth | `IDittoAuthenticationDelegate` interface | `DittoAuthenticationExpirationHandler` async delegate |
| Auth login | `LoginWithToken()` / `Login()` | `LoginAsync()` |
| Write tx | `DittoStore.Write()` | `DittoStore.TransactionAsync()` |
| Collection | `DittoStore.Collection(string)` | DQL via `DittoStore.ExecuteAsync()` |
| Observer | `DittoLiveQuery` | `DittoStoreObserver` |
| Subscription | `DittoSubscription` | `DittoSyncSubscription` |
| Site ID | `Ditto.SiteId` | `Ditto.DeviceId` |
| SDK version | `Ditto.SDKVersion` | `DittoDiagnostics.SdkVersion` (static) |
| Disk usage child | `DittoDiskUsageChild` | `DittoDiskUsageItem` |
| Error namespace | `DittoSDK.DittoException` | `DittoSDK.Exceptions.DittoException` |

---

## 1. Initialization

**v4.14:**
```csharp
using DittoSDK;

var identity = new DittoOnlinePlayground(
    appId: "my-app-id",
    token: "my-token",
    workingDir: "/path/to/data"
);
using var ditto = new Ditto(identity, "/path/to/data");

ditto.StartSync();
```

**v5.0:**
```csharp
using DittoSDK;

var config = DittoConfig.OnlinePlayground(
    appId: "my-app-id",
    token: "my-token",
    workingDir: "/path/to/data"
);

// Synchronous
using var ditto = Ditto.Open(config);

// OR async
using var ditto = await Ditto.OpenAsync(config);

ditto.Auth.ExpirationHandler = async (dittoAuth, secondsRemaining) =>
{
    // Initial auth
    try
    {
        await dittoAuth.Auth.LoginAsync(
            "your-token",
            DittoAuthenticationProvider.Development);
           );
    }
    catch (Exception error)
    {
        Console.WriteLine($"Ditto auth failed: {error}, seconds remaining: {secondsRemaining}");
    }
};

ditto.Sync.Start();
```

### Identity → DittoConfig Factory Method Mapping

| v4.14 DittoIdentity | v5.0 DittoConfig factory |
|---------------------|--------------------------|
| `new DittoOfflinePlayground(appId, workingDir)` | `DittoConfig.OfflinePlayground(appId, workingDir)` |
| `new DittoOnlinePlayground(appId, token, workingDir)` | `DittoConfig.OnlinePlayground(appId, token, workingDir)` |
| `new DittoOnlineWithAuthentication(appId, handler, workingDir)` | `DittoConfig.OnlineWithAuthentication(appId, handler, workingDir)` |
| `new DittoSharedKey(appId, sharedKey, siteId, workingDir)` | `DittoConfig.SharedKey(appId, sharedKey, siteId, workingDir)` |
| `new DittoManual(appId, workingDir)` | `DittoConfig.Manual(appId, workingDir)` |

---

## 2. Sync API

```csharp
// v4.14
ditto.StartSync();
ditto.StopSync();

// v5.0
ditto.Sync.Start();
ditto.Sync.Stop();
```

---

## 3. Authentication Handler

**v4.14 — interface:**
```csharp
public class MyAuthDelegate : IDittoAuthenticationDelegate
{
    public async Task AuthenticationRequired(DittoAuthenticator authenticator)
    {
        await authenticator.LoginWithToken("my-token", "my-provider");
    }

    public async Task AuthenticationExpiringSoon(
        DittoAuthenticator authenticator, long secondsRemaining)
    {
        var newToken = await FetchNewToken();
        await authenticator.LoginWithToken(newToken, "my-provider");
    }

    public void AuthenticationStatusDidChange(DittoAuthenticator authenticator) { }
}

// Set: authenticator.AuthenticationDelegate = new MyAuthDelegate();
```

**v5.0 — async delegate:**
```csharp
// In DittoConfig constructor for OnlineWithAuthentication
var config = DittoConfig.OnlineWithAuthentication(
    appId: "my-app-id",
    handler: async (authenticator, secondsRemaining) =>
    {
        if (secondsRemaining == 0)
        {
            // Initial auth or expired
            var token = await FetchTokenFromServer();
            await authenticator.LoginAsync(token, "my-provider");
        }
        else
        {
            // Token expiring soon
            var newToken = await RefreshToken();
            await authenticator.LoginAsync(newToken, "my-provider");
        }
    },
    workingDir: "/path/to/data"
);

// Or set after open:
ditto.Auth.ExpirationHandler = async (authenticator, secondsRemaining) =>
{
    await authenticator.LoginAsync(token, "my-provider");
};
```

---

## 4. Write Transactions — `Write()` → `TransactionAsync()`

```csharp
// v4.14 — synchronous write
ditto.Store.Write((tx) =>
{
    tx.Scoped("cars").Upsert(new Dictionary<string, object>
    {
        { "_id", "car-1" }, { "color", "blue" }
    });
});

// v5.0 — async DQL transaction
await ditto.Store.TransactionAsync(async (tx) =>
{
    await tx.ExecuteAsync(
        "INSERT INTO cars DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE",
        new { doc = new { _id = "car-1", color = "blue" } });
});
```

---

## 5. Store Observer — `DittoLiveQuery` → `DittoStoreObserver`

```csharp
// v4.14
DittoLiveQuery liveQuery = ditto.Store.Collection("cars")
    .Find("color == 'blue'")
    .ObserveLocal((docs, dittoCollectionEvent) =>
    {
        // handle initial + updates
        UpdateUI(docs);
    });

// v5.0
DittoStoreObserver observer = ditto.Store.RegisterObserver(
    "SELECT * FROM cars WHERE color = :color",
    new { color = "blue" },
    (DittoQueryResultsChange change) =>
    {
        var items = change.Items;
        UpdateUI(items);
    });

// Cancel: observer.Cancel();
```

---

## 6. Sync Subscriptions — `DittoSubscription` → `DittoSyncSubscription`

```csharp
// v4.14
DittoSubscription sub = ditto.Store.Collection("cars")
    .Find("color == 'red'")
    .Subscribe();

// v5.0
DittoSyncSubscription sub = ditto.Sync.RegisterSubscription(
    "SELECT * FROM cars WHERE color = :color",
    new { color = "red" });
sub.Cancel();
```

---

## 7. DQL Strict Mode — CRITICAL BREAKING CHANGE

⚠️ **Silent data behavior change**: v5 defaults to `DQL_STRICT_MODE=false`. v4 default was `true`.

```csharp
using var ditto = Ditto.Open(config);
// MUST set BEFORE Sync.Start() if maintaining v4 behavior
await ditto.Store.ExecuteAsync("ALTER SYSTEM SET DQL_STRICT_MODE = true");
ditto.Sync.Start();
```

---

## 8. DQL Migration — Legacy Collection API → DQL

For help with migrations to DQL (Ditto Query Language) assistance for queries, subscriptions, and data operations - it's recommended to use the [DQL plugin](../ditto-dql).

### Query

```csharp
// v4.14
var cars = ditto.Store.Collection("cars").Find("color == 'blue'").Exec();
var car = ditto.Store.Collection("cars").FindById(new DittoDocumentId("car-1")).Exec();

// v5.0
var result = await ditto.Store.ExecuteAsync(
    "SELECT * FROM cars WHERE color = :color",
    new { color = "blue" });
var result = await ditto.Store.ExecuteAsync(
    "SELECT * FROM cars WHERE _id = :id",
    new { id = "car-1" });
```

### Insert

```csharp
// v4.14
ditto.Store.Collection("cars").Upsert(new Dictionary<string, object>
{
    { "_id", "car-1" }, { "color", "blue" }
});

// v5.0
await ditto.Store.ExecuteAsync(
    "INSERT INTO cars DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE",
    new { doc = new { _id = "car-1", color = "blue" } });
```

### Update

```csharp
// v4.14
ditto.Store.Collection("cars").FindById(id).Update((doc) =>
{
    doc["color"].Set("green");
});

// v5.0
await ditto.Store.ExecuteAsync(
    "UPDATE cars SET color = :color WHERE _id = :id",
    new { color = "green", id = "car-1" });
```

### Delete

```csharp
// v4.14
ditto.Store.Collection("cars").FindById(id).Remove();

// v5.0
await ditto.Store.ExecuteAsync(
    "DELETE FROM cars WHERE _id = :id",
    new { id = "car-1" });
```

### Evict

```csharp
// v4.14
ditto.Store.Collection("cars").FindById(id).Evict();

// v5.0
await ditto.Store.ExecuteAsync(
    "EVICT FROM cars WHERE _id = :id",
    new { id = "car-1" });
```

### Sorting, Limits, Offsets

```csharp
// v4.14 — chain methods
var results = ditto.Store.Collection("cars")
    .FindAll()
    .Sort("color", DittoSortDirection.Ascending)  // DittoSortDirection REMOVED
    .Limit(20)
    .Offset(40)
    .Exec();

// v5.0 — DQL clauses
var result = await ditto.Store.ExecuteAsync(
    "SELECT * FROM cars ORDER BY color ASC LIMIT 20 OFFSET 40");
```

---

## 9. New APIs in v5

### `WifiAwareConfig` (new)

```csharp
// Configure Wi-Fi Aware (Android)
var transportConfig = ditto.TransportConfig;
transportConfig.PeerToPeer.WifiAware.Enabled = true;
ditto.TransportConfig = transportConfig;
```

### `DittoSyncPermissions` (MAUI only)

```csharp
// Request Bluetooth and Wi-Fi permissions on Android/iOS
await DittoSyncPermissions.RequestPermissionsAsync();
```

### Namespace reorganization

Authentication types moved to `DittoSDK.Auth` namespace:
```csharp
using DittoSDK.Auth;  // DittoAuthenticator, DittoAuthenticationExpirationHandler, etc.
```

Exceptions moved:
```csharp
using DittoSDK.Exceptions;  // DittoException
```

---

## 10. Back Pressure (RegisterObserver with signalNext)

Use the `Action<DittoQueryResult, Action>` overload of `RegisterObserver` for manual back-pressure control. The `signalNext` `Action` must be called when your handler is ready for the next update.

**Coalescing**: changes that occur while your handler executes are coalesced — you get the latest state.

```csharp
// Standard (auto-signal after handler returns)
ditto.Store.RegisterObserver(query, result => UpdateUI(result.Items));

// Async (auto-signal after Task completes)
ditto.Store.RegisterObserver(query, async result => {
    await ExpensiveOperationAsync(result.Items);
});

// Back-pressure (manual signal)
ditto.Store.RegisterObserver(
    query,
    new Dictionary<string, object> { ["color"] = "blue" },
    async (result, signalNext) => {
        await ExpensiveOperationAsync(result.Items);
        signalNext();  // Call when ready for the next update
    }
);
```

The `signalNext` parameter is a plain `Action` (no named type).

---

## 11. APIs Removed With No Replacement

| API | Notes |
|-----|-------|
| `Ditto.DisableSyncWithV3()` | v3 peer sync fully dropped |
| `DittoLiveQueryEvent.Hash()` | Document change hashing removed |
| `DittoLiveQueryEvent.HashMnemonic()` | Human-readable hash removed |
| `DittoWriteStrategy.UpdateDifferentValues` | No equivalent in DQL; use `ON ID CONFLICT DO MERGE` |
| `IDittoAuthenticationDelegate.AuthenticationStatusDidChange()` | Use `DittoAuthenticator.ObserveStatus()` for cancellable observation |
| `DittoUpdateResult` (and `Set`, `Removed`, `Incremented` subclasses) | DQL returns row counts only |
| `DittoPendingCursorOperation.ObserveLocalWithNextSignal()` | Back-pressure pattern removed |
| `DittoDocument[string].TypedAs<T>()` typed subscript | Cast from `DittoQueryResultItem.Value` manually |
| `DittoSmallPeerInfoSyncScope` enum | Use `ALTER SYSTEM SET smallPeerInfoSyncScope = '...'` |
| `DittoSortDirection` enum | Use `ASC`/`DESC` in DQL |
| `DittoStore.FetchAttachment(DittoAttachmentFetchDelegate)` | Use async `Func`/Task overload |

## 12. New APIs in v5

- **`Ditto.Sync.Start()` / `Ditto.Sync.Stop()`** — replaces `Ditto.StartSync()` / `StopSync()`
- **`Ditto.Sync.GetTransportDiagnostics()`** — moved from `Ditto` to `DittoSync`
- **`Ditto.DeviceId`** — replaces `Ditto.SiteId`
- **`DittoDiagnostics.SdkVersion`** (static) — replaces `Ditto.SDKVersion`
- **`DittoAuthenticationExpirationHandler`** — async delegate replacing `IDittoAuthenticationDelegate`
- **`DittoAuthenticator.ObserveStatus()`** — returns cancellable observer for auth status changes
- **`DittoAuthenticator.Logout()`** — explicit logout support
- **`DittoSDK.Auth` namespace** — all authentication types moved here
- **`DittoStore.TransactionAsync()`** — async DQL transaction
- **`DittoStoreObserver`** — replaces `DittoLiveQuery`
- **`DittoSyncSubscription`** — replaces `DittoSubscription`; exposes `QueryString`, `QueryArguments`, `Cancel()`
- **`DittoQueryResultItem`** — new type for single DQL result row
- **`DittoQueryResultsChange`** — event object passed to `RegisterObserver` callbacks
- **`WifiAwareConfig`** / **`WifiAwareConfigBuilder`** — new transport config for Android Wi-Fi Aware (MAUI)
- **`DittoSyncPermissions`** (MAUI) — `RequestPermissionsAsync()` for Bluetooth/Wi-Fi permissions
- **`DittoDiskUsageItem`** — replaces `DittoDiskUsageChild`; uses `System.Text.Json`
- **`DittoDiskUsage.Item`** (property) — replaces `Exec()` method
- **`DittoSDK.DiskUsage` namespace** — disk usage types moved here
- **`DittoSDK.Exceptions` namespace** — exception types moved here

---

## 13. 10-Step Migration Checklist

### Step 1: Update NuGet Package
- [ ] Update `DittoSDK` NuGet package to v5.x

### Step 2: Fix Namespace Imports
- [ ] Add `using DittoSDK.Auth;` where auth types are used
- [ ] Add `using DittoSDK.Exceptions;` where `DittoException` is caught
- [ ] Update any other namespace references per compiler errors

### Step 3: Replace Initialization
- [ ] Replace `new Ditto(identity, path)` with `Ditto.Open(DittoConfig)` or `await Ditto.OpenAsync(DittoConfig)`
- [ ] Replace `new DittoOnlinePlayground(...)` etc. with `DittoConfig.OnlinePlayground(...)` factory methods
- [ ] Remove `DittoIdentityType` enum references

### Step 4: Update Sync API
- [ ] Replace `ditto.StartSync()` → `ditto.Sync.Start()`
- [ ] Replace `ditto.StopSync()` → `ditto.Sync.Stop()`
- [ ] Move `GetTransportDiagnostics()` call to `ditto.Sync.GetTransportDiagnostics()`
- [ ] Remove `ditto.DisableSyncWithV3()` calls
- [ ] **Set `DQL_STRICT_MODE=true` BEFORE `Sync.Start()` if maintaining v4 behavior**

### Step 5: Update Authentication
- [ ] Replace `IDittoAuthenticationDelegate` implementations with `DittoAuthenticationExpirationHandler` async delegate
- [ ] Replace `LoginWithToken()` / `Login()` / `LoginWithCredentials()` → `LoginAsync()`
- [ ] Update status observation to `DittoAuthenticator.ObserveStatus()`

### Step 6: Replace Collection API with DQL
- [ ] Search for `ditto.Store.Collection(` and replace all with DQL-based `ExecuteAsync()`
- [ ] Search for `.FindAll()`, `.Find(`, `.FindById(` and convert to DQL SELECT
- [ ] Search for `.Upsert(` and convert to `INSERT INTO ... ON ID CONFLICT DO UPDATE`
- [ ] Search for `.Update(` closures and convert to `UPDATE SET`
- [ ] Search for `.Remove()` and convert to `DELETE FROM`
- [ ] Search for `.Evict()` and convert to `EVICT FROM`

### Step 7: Replace Live Queries and Subscriptions
- [ ] Replace `DittoLiveQuery` type → `DittoStoreObserver`
- [ ] Replace `.ObserveLocal()` → `ditto.Store.RegisterObserver()` with `DittoQueryResultsChange` callback
- [ ] Replace `DittoSubscription` → `DittoSyncSubscription`
- [ ] Replace `.Subscribe()` → `ditto.Sync.RegisterSubscription()`

### Step 8: Replace Write Transactions
- [ ] Replace `ditto.Store.Write(tx => { })` → `await ditto.Store.TransactionAsync(async tx => { })`
- [ ] Replace `tx.Scoped("collection").Upsert(...)` → `await tx.ExecuteAsync("INSERT ...")`

### Step 9: Update Renamed Types
- [ ] `Ditto.SiteId` → `Ditto.DeviceId`
- [ ] `Ditto.SDKVersion` → `DittoDiagnostics.SdkVersion`
- [ ] `DittoDiskUsageChild` → `DittoDiskUsageItem`
- [ ] `DittoDiskUsage.Exec()` → `DittoDiskUsage.Item` (property)
- [ ] `DittoSubscription` → `DittoSyncSubscription`

### Step 10: Verify and Test
- [ ] Build compiles with zero errors
- [ ] No deprecated API warnings
- [ ] DQL strict mode set correctly for your data model
- [ ] Auth handler fires before first sync
- [ ] Observers receive initial data
- [ ] Subscriptions sync data across peers
- [ ] Transactions are atomic

---

## Common Pitfalls

1. **`DQL_STRICT_MODE` silent change**: Default flipped. Objects merge field-by-field instead of replacing whole. Set `DQL_STRICT_MODE=true` BEFORE `Sync.Start()` if migrating existing data.

2. **Missing `await` on `ExecuteAsync`**: `ExecuteAsync` returns `Task<DittoQueryResult>`. Forgetting `await` causes silent no-op.

3. **`DittoSortDirection` removed**: `Sort("field", DittoSortDirection.Ascending)` won't compile. Use `ORDER BY field ASC` in DQL.

4. **`DittoIdentityType` enum**: Removed entirely. Code checking identity type won't compile.

5. **`LoginWithToken()` removed**: Must use `LoginAsync()`. The sync overloads are gone.

6. **`Write()` vs `TransactionAsync()`**: The callback signature changed completely — it's now async DQL, not collection-based mutations.

7. **`ObserveLocalWithNextSignal()` removed**: No back-pressure in v5 observers. Remove any NextSignal patterns.

---

## Official Documentation

- .NET V4→V5 Guide: https://docs.ditto.live/sdk/latest/migration-guides/c-sharp-v4
- .NET DQL Migration: https://docs.ditto.live/sdk/latest/migration-guides/c-sharp-dql
- DQL Reference: https://docs.ditto.live/dql/dql
