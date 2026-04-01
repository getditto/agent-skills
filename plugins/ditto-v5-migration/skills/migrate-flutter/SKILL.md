---
name: migrate-flutter
description: Use when migrating Ditto Flutter/Dart SDK applications from v4.14 to v5.0. Covers Ditto.open(DittoConfig) factory, Ditto.openSync() new option, PresenceGraph.remotePeers type change (List→Set), isolate-unsendable restriction on Ditto and Store, AuthenticationExpirationHandler typedef, TransportConfig builder pattern, and DQL migration from legacy Query Builder.
---

# Ditto Flutter/Dart SDK: v4.14 → v5.0 Migration Reference

## Quick Summary of Changes

### Removed APIs

The following public types and members exist in v4 but are **completely removed** in v5 with no direct 1:1 replacement:

| Removed Type/Member | v4 Location | Notes |
|---|---|---|
| `Identity` (abstract class) | `src/identity.dart` | Replaced by `DittoConfig` system |
| `OnlinePlaygroundIdentity` | `src/identity.dart` | Use `DittoConfigConnectServer` instead |
| `OnlineWithAuthenticationIdentity` | `src/identity.dart` | Use `DittoConfigConnectServer` + `Authenticator` instead |
| `OfflinePlaygroundIdentity` | `src/identity.dart` | Use `DittoConfigConnectSmallPeersOnly` instead |
| `SharedKeyIdentity` | `src/identity.dart` | Use `DittoConfigConnectSmallPeersOnly(privateKey:)` instead |
| `ManualIdentity` | `src/identity.dart` | No direct replacement |
| `DocumentID` (class) | `src/shared/document_id.dart` | No longer exported; use raw values |
| `SiteID` (class) | `src/shared/site_id.dart` | No longer exported; site IDs removed from config |
| `AuthenticationHandler` (interface) | `src/auth.dart` | Replaced by `AuthenticationExpirationHandler` typedef |
| `SmallPeerInfoSyncScope` (enum) | `src/core/core.dart` | No longer exported from public API |
| `Ditto.identity` (property) | `src/ditto.dart` | Use `ditto.config` instead |
| `Ditto.startSync()` | `src/ditto.dart` | Use `ditto.sync.start()` |
| `Ditto.stopSync()` | `src/ditto.dart` | Use `ditto.sync.stop()` |
| `Ditto.isSyncActive` | `src/ditto.dart` | Use `ditto.sync.isActive` |
| `Ditto.persistenceDirectory` | `src/ditto.dart` | Use `ditto.absolutePersistenceDirectory` |
| `Authenticator.loginWithCredentials()` | `src/auth.dart` | Removed; use `login()` only |
| `Authenticator.ditto` (property) | `src/auth.dart` | No longer publicly exposed |
| `Connection.approximateDistanceInMeters` | `src/shared/presence.dart` | Removed entirely |
| `Peer.peerKeyString` | `src/shared/presence.dart` | Renamed to `Peer.peerKey` |
| `Peer.isConnectedToDittoCloud` | `src/shared/presence.dart` | Renamed to `Peer.isConnectedToDittoServer` |
| `Connection.peerKeyString1` | `src/shared/presence.dart` | Renamed to `Connection.peer1` |
| `Connection.peerKeyString2` | `src/shared/presence.dart` | Renamed to `Connection.peer2` |
| `ConnectionRequest.peerKeyString` | `src/presence/presence.dart` | Renamed to `ConnectionRequest.peerKey` |
| `DittoLogger.setLogFile()` | `src/logger.dart` | Removed |


### New APIs

The following types and members are **new in v5** with no v4 equivalent:

| New Type/Member | v5 Location | Purpose |
|---|---|---|
| `DittoConfig` | `src/ditto_config.dart` | Top-level configuration object replacing Identity |
| `DittoConfigBuilder` | `src/ditto_config.dart` | Builder for `DittoConfig` |
| `DittoConfigConnect` | `src/ditto_config.dart` | Abstract base for connectivity config |
| `DittoConfigConnectBuilder` | `src/ditto_config.dart` | Builder for `DittoConfigConnect` |
| `DittoConfigConnectServer` | `src/ditto_config.dart` | Connects to Big Peer by URL |
| `DittoConfigConnectServerBuilder` | `src/ditto_config.dart` | Builder for `DittoConfigConnectServer` |
| `DittoConfigConnectSmallPeersOnly` | `src/ditto_config.dart` | Small-peer-only connectivity |
| `DittoConfigConnectSmallPeersOnlyBuilder` | `src/ditto_config.dart` | Builder for `DittoConfigConnectSmallPeersOnly` |
| `DittoConfigExperimental` | `src/ditto_config.dart` | Experimental config (e.g. passphrase encryption) |
| `DittoConfigExperimentalBuilder` | `src/ditto_config.dart` | Builder for `DittoConfigExperimental` |
| `AuthenticationExpirationHandler` | `src/auth.dart` | Typedef: `void Function(Ditto, Duration)` |
| `Authenticator.developmentProvider` | `src/auth.dart` | Static getter for dev auth provider name |
| `Authenticator.expirationHandler` | `src/auth.dart` | Get/set expiration handler |
| `Authenticator.setExpirationHandler()` | `src/auth.dart` | Async method to set expiration handler |
| `Ditto.openSync()` | `src/ditto.dart` | Synchronous factory constructor |
| `Ditto.defaultRootDirectory` | `src/ditto.dart` | Static getter for default data directory |
| `Ditto.config` | `src/ditto.dart` | Access the `DittoConfig` used to initialize |
| `Ditto.absolutePersistenceDirectory` | `src/ditto.dart` | Resolved absolute path for persistence |
| `Sync.isActive` | `src/sync.dart` | Whether sync is currently running |
| `Sync.start()` | `src/sync.dart` | Start sync transports |
| `Sync.stop()` | `src/sync.dart` | Stop sync transports |
| `QueryResultItem.cborBytes` | `src/store/execute.dart` | Item data as CBOR bytes |
| `QueryResultItem.jsonString` | `src/store/execute.dart` | Item data as JSON string |
| `SyncSubscription.queryArgumentsCborBytes` | `src/sync.dart` | Query args as CBOR bytes |
| `SyncSubscription.queryArgumentsJsonString` | `src/sync.dart` | Query args as JSON string |
| `TransportConfigBuilder` | `src/transport_config.dart` | Builder for `TransportConfig` |
| `PeerToPeerBuilder` | `src/transport_config.dart` | Builder for `PeerToPeer` |
| `ConnectBuilder` | `src/transport_config.dart` | Builder for `Connect` |
| `ListenBuilder` | `src/transport_config.dart` | Builder for `Listen` |
| `GlobalConfigBuilder` | `src/transport_config.dart` | Builder for `GlobalConfig` |
| `LanConfigBuilder` | `src/transport_config.dart` | Builder for `LanConfig` |
| `AwdlConfigBuilder` | `src/transport_config.dart` | Builder for `AwdlConfig` |
| `BluetoothLEConfigBuilder` | `src/transport_config.dart` | Builder for `BluetoothLEConfig` |
| `WifiAwareConfigBuilder` | `src/transport_config.dart` | Builder for `WifiAwareConfig` |
| `TcpListenConfigBuilder` | `src/transport_config.dart` | Builder for `TcpListenConfig` |
| `HttpListenConfigBuilder` | `src/transport_config.dart` | Builder for `HttpListenConfig` |
| `PresenceGraphBuilder` | `src/presence/presence_graph.dart` | Builder for `PresenceGraph` |
| `PeerBuilder` | `src/presence/presence_graph.dart` | Builder for `Peer` |
| `ConnectionBuilder` | `src/presence/presence_graph.dart` | Builder for `Connection` |
| `TransportConfig.toBuilder()` | `src/transport_config.dart` | Convert to mutable builder |
| `TransportConfig.withAllPeerToPeerEnabled()` | `src/transport_config.dart` | Returns new config with P2P toggled |
| `TransportConfig.toJson()` / `fromJson()` | `src/transport_config.dart` | Serialization support |


### Renamed Properties and Methods

| v4 Name | v5 Name | Class | Notes |
|---|---|---|---|
| `Peer.peerKeyString` | `Peer.peerKey` | `Peer` | Shortened name |
| `Peer.isConnectedToDittoCloud` | `Peer.isConnectedToDittoServer` | `Peer` | "Cloud" renamed to "Server" |
| `Connection.peerKeyString1` | `Connection.peer1` | `Connection` | Shortened name |
| `Connection.peerKeyString2` | `Connection.peer2` | `Connection` | Shortened name |
| `ConnectionRequest.peerKeyString` | `ConnectionRequest.peerKey` | `ConnectionRequest` | Shortened name |
| `Ditto.persistenceDirectory` | `Ditto.absolutePersistenceDirectory` | `Ditto` | Clarifies it returns absolute path |
| `Ditto.isSyncActive` | `ditto.sync.isActive` | `Ditto` -> `Sync` | Moved to Sync class |
| `Ditto.startSync()` | `ditto.sync.start()` | `Ditto` -> `Sync` | Moved to Sync class |
| `Ditto.stopSync()` | `ditto.sync.stop()` | `Ditto` -> `Sync` | Moved to Sync class |
| `TransportConfig.setAllPeerToPeerEnabled()` | `TransportConfig.withAllPeerToPeerEnabled()` | `TransportConfig` | Returns new instance instead of mutating |



## 1. Initialization

**v4.14:**
```dart
import 'package:ditto_live/ditto_live.dart';

final identity = OnlinePlaygroundIdentity(
    appID: 'my-app-id',
    token: 'my-token',
    customAuthURL: Uri.parse('https://my-app-id.cloud.ditto.live'),
    enableDittoCloudSync: false,
);
final ditto = await Ditto.open(identity: identity);
await ditto.startSync();
```

**v5.0:**
```dart
import 'package:ditto_live/ditto_live.dart';

final config = DittoConfig(
    databaseID: 'my-app-id',
    connect: DittoConfigConnectServer(
        url: Uri.parse('https://my-app-id.cloud.ditto.live'),
    ),
);

// Async (recommended)
final ditto = await Ditto.open(config);

// OR synchronous (new in v5)
// final ditto = Ditto.openSync(config);

//authenticate 
ditto.auth?.expirationHandler = (authenticator, secondsRemaining) async {
    await authenticator.login(
        token: 'your-token',
        provider: Authenticator.developmentProvider,
    );
};

await ditto.sync.start();
```

i**v4 OnlineWithAuthenticationIdentity:**
```dart
final ditto = await Ditto.open(
  identity: OnlineWithAuthenticationIdentity(
    appID: "app-id",
    authenticationHandler: AuthenticationHandler(
      authenticationRequired: (authenticator) {
        authenticator.login(token: myToken, provider: "my-provider");
      },
      authenticationExpiringSoon: (authenticator, remaining) {
        authenticator.login(token: refreshedToken, provider: "my-provider");
      },
    ),
  ),
);
ditto.startSync();
```

**v5 equivalent:**
```dart
final ditto = await Ditto.open(DittoConfig(
  databaseID: "app-id",
  connect: DittoConfigConnectServer(url: "https://your-server-url"),
));
await ditto.auth.login(token: myToken, provider: "my-provider");
await ditto.auth.setExpirationHandler((ditto, timeUntilExpiration) {
  ditto.auth.login(token: refreshedToken, provider: "my-provider");
});
ditto.sync.start();
```

### Identity → DittoConfig Mapping

| v4.14 Identity | v5.0 DittoConfig connect |
|----------------|--------------------------|
| `OnlinePlaygroundIdentity(appID:token:customAuthURL:)` | `DittoConfigConnectServer(url:)` |
| `OnlineWithAuthenticationIdentity(appID:customAuthURL:)` | `DittoConfigConnectServer(url:)` + auth handler |
| `OfflinePlaygroundIdentity(appID:)` | `DittoConfigConnectSmallPeersOnly(privateKey: null)` |
| `SharedKeyIdentity(appID:sharedKey:)` | `DittoConfigConnectSmallPeersOnly(privateKey: key)` |
| `ManualIdentity(...)` | `DittoConfigConnectSmallPeersOnly(...)` |

**Key differences:**
- `appID` is now `databaseID`
- `SiteID` is no longer part of the configuration
- Authentication is now handled separately after initialization via `Authenticator`
- The `enableDittoCloudSync` flag is replaced by choosing `DittoConfigConnectServer` (enabled) vs `DittoConfigConnectSmallPeersOnly` (disabled)
- `customAuthUrl` is replaced by the `url` parameter on `DittoConfigConnectServer`

---

## 2. Sync API

```dart
// v4.14
await ditto.startSync();
print(ditto.isSyncActive);
ditto.stopSync();
final active = ditto.isSyncActive;

// v5.0
await ditto.sync.start();
print(ditto.sync.isActive);
ditto.sync.stop();
```

---

## 3. Authentication Handler

**v4.14 — interface:**
```dart
class MyAuthHandler implements AuthenticationHandler {
    @override
    Future<void> authenticationRequired(Authenticator authenticator) async {
        await authenticator.loginWithToken('my-token', 'my-provider');
    }

    @override
    Future<void> authenticationExpiringSoon(
        Authenticator authenticator,
        int secondsRemaining,
    ) async {
        await authenticator.loginWithToken(await fetchNewToken(), 'my-provider');
    }
}
// Set on identity: OnlineWithAuthenticationIdentity(..., authenticationHandler: MyAuthHandler())
```

**v5.0 — typedef closure:**
```dart
// Set after Ditto.open()
ditto.auth?.setExpirationHandler((authenticator, secondsRemaining) async {
    if (secondsRemaining == 0) {
        // Initial auth or expired
        final token = await fetchTokenFromServer();
        await authenticator.login(token: token, provider: 'my-provider');
    } else {
        // Token expiring soon
        final newToken = await refreshToken();
        await authenticator.login(token: newToken, provider: 'my-provider');
    }
});
```

Use development provider for playground:
```dart
await authenticator.login(
    token: token,
    provider: Authenticator.developmentProvider,
);
```

**Key auth changes:**
- `AuthenticationHandler` interface replaced by `AuthenticationExpirationHandler` typedef
- `authenticationRequired` callback removed - handle auth before calling `sync.start()`
- `authenticationExpiringSoon(authenticator, int remaining)` replaced by `AuthenticationExpirationHandler(Ditto ditto, Duration timeUntilExpiration)`
- The `remaining` parameter changed from `int` (seconds) to `Duration`
- `loginWithCredentials()` removed entirely
- New `Authenticator.developmentProvider` static getter for dev auth

--- 

## 4. Transport Configuration

v5 uses an immutable builder pattern instead of mutable copies.

**v4:**
```dart
ditto.updateTransportConfig((config) {
  config.peerToPeer.bluetoothLE.isEnabled = true;
  config.peerToPeer.lan.isEnabled = true;
  config.connect.tcpServers.add("192.168.1.1:4040");
  config.setAllPeerToPeerEnabled(true);
});

// Direct copy
final copy = ditto.transportConfig.copy();
```

**v5:**
```dart
ditto.updateTransportConfig((config) {
  config.peerToPeer.bluetoothLE.isEnabled = true;
  config.peerToPeer.lan.isEnabled = true;
  config.connect.tcpServers.add("192.168.1.1:4040");
});

// Builder pattern
final builder = ditto.transportConfig.toBuilder();
builder.peerToPeer.bluetoothLE.isEnabled = true;
final newConfig = builder.build();

// Convenience method (returns new instance)
final allP2p = ditto.transportConfig.withAllPeerToPeerEnabled(true);
```

**Key transport changes:**
- `updateTransportConfig` callback receives `TransportConfigBuilder` instead of `TransportConfig`
- `TransportConfig.copy()` replaced by `TransportConfig.toBuilder()` + `.build()`
- `setAllPeerToPeerEnabled()` (mutating) replaced by `withAllPeerToPeerEnabled()` (returns new)
- `TransportConfig.withBigPeer()` factory removed
- All config objects now have `toJson()`/`fromJson()` serialization
- All config objects now have corresponding `Builder` classes
---

## 5. Presence — `List<Peer>` → `Set<Peer>`

⚠️ **Breaking type change**: `PresenceGraph.remotePeers` changed from `List<Peer>` to `Set<Peer>`.

**v4:**
```dart
final graph = ditto.presence.graph;
final localKey = graph.localPeer.peerKeyString;
final isCloud = graph.localPeer.isConnectedToDittoCloud;

for (final peer in graph.remotePeers) {  // List<Peer>
  print(peer.peerKeyString);
  for (final conn in peer.connections) {
    print("${conn.peerKeyString1} <-> ${conn.peerKeyString2}");
    print("Distance: ${conn.approximateDistanceInMeters}");
  }
}

final request = connectionRequest;
print(request.peerKeyString);
```

**v5:**
```dart
final graph = ditto.presence.graph;
final localKey = graph.localPeer.peerKey;
final isServer = graph.localPeer.isConnectedToDittoServer;

for (final peer in graph.remotePeers) {  // Set<Peer>
  print(peer.peerKey);
  for (final conn in peer.connections) {
    print("${conn.peer1} <-> ${conn.peer2}");
    // approximateDistanceInMeters is REMOVED
  }
}

final request = connectionRequest;
print(request.peerKey);
```

Update any code that:
- Indexes into `remotePeers` by position
- Passes it to a function expecting `List<Peer>`
- Uses `remotePeers.length` (works on both) or `.isEmpty` (works on both)

---

### Back Pressure

Flutter's SDK handles back pressure **internally** — there is no `signalNext` function exposed. The `Stream<QueryResult>` observer model manages update delivery automatically. Use Dart's `StreamController` with `pause`/`resume` if you need custom flow control.

---

## 6. Isolate Restriction

⚠️ `Ditto` and `Store` are now marked `@pragma("vm:isolate-unsendable")`.

```dart
// v4.14 — this worked
await Isolate.spawn(myIsolateFunction, ditto);  // could send ditto

// v5.0 — COMPILE ERROR
await Isolate.spawn(myIsolateFunction, ditto);  // Cannot send Ditto across isolates

// v5.0 — solution: create separate Ditto instance per isolate, or use ports for data
```

Do not pass `Ditto` or `Store` instances across isolate boundaries. If you use multiple isolates, create a separate `Ditto.open()` per isolate.

---

## 7. WebSocket Sync Default — CRITICAL

⚠️ `HttpListenConfig.websocketSync` now defaults to `false` (was `true` in v4).

If your app relied on WebSocket sync being enabled by default:
```dart
// v5.0 — explicitly enable if needed
final config = ditto.transportConfig
    .toBuilder()
    ..listen.http.websocketSync = true  // must explicitly set
    ;
ditto.transportConfig = config.build();
```

---

## 8. DQL Strict Mode — CRITICAL BREAKING CHANGE

⚠️ **Silent data behavior change**: v5 defaults to `DQL_STRICT_MODE=false`. v4 default was `true`.  If you didn't set Strict Mode to false in v4, you will need to set it to true in order to maintain v4 behavior.  Contact support if you have questions about this.

```dart
final ditto = await Ditto.open(config);
// MUST set BEFORE sync.start() if maintaining v4 behavior
await ditto.store.execute('ALTER SYSTEM SET DQL_STRICT_MODE = true');
await ditto.sync.start();
```

---

## 9. DQL Migration — Legacy Query Builder → DQL

For help with migrations to DQL (Ditto Query Language) assistance for queries, subscriptions, and data operations - it's recommended to use the [DQL plugin](../ditto-dql).

### Query

```dart
// v4.14
final cars = await ditto.store.collection('cars').find("color == 'blue'").exec();
final car = await ditto.store.collection('cars').findByID('car-1').exec();

// v5.0
final result = await ditto.store.execute(
    'SELECT * FROM cars WHERE color = :color',
    arguments: {'color': 'blue'});
final result = await ditto.store.execute(
    'SELECT * FROM cars WHERE _id = :id',
    arguments: {'id': 'car-1'});
```

### Insert

```dart
// v4.14
await ditto.store.collection('cars').upsert({'_id': 'car-1', 'color': 'blue'});

// v5.0
await ditto.store.execute(
    'INSERT INTO cars DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE',
    arguments: {'doc': {'_id': 'car-1', 'color': 'blue'}});
```

### Update

```dart
// v4.14
await ditto.store.collection('cars').findByID('car-1').update((doc) {
    doc['color'].set('green');
});

// v5.0
await ditto.store.execute(
    'UPDATE cars SET color = :color WHERE _id = :id',
    arguments: {'color': 'green', 'id': 'car-1'});
```

### Delete

```dart
// v4.14
await ditto.store.collection('cars').findByID('car-1').remove();

// v5.0
await ditto.store.execute(
    'DELETE FROM cars WHERE _id = :id',
    arguments: {'id': 'car-1'});
```

### Evict

```dart
// v4.14
await ditto.store.collection('cars').findByID('car-1').evict();

// v5.0
await ditto.store.execute(
    'EVICT FROM cars WHERE _id = :id',
    arguments: {'id': 'car-1'});
```

### Observers

```dart
// v4.14
final liveQuery = ditto.store.collection('cars')
    .find("_id.locationId == '$locationId'")
    .observeLocal((docs, event) {
        updateUI(docs);
    });

// v5.0
final observer = ditto.store.registerObserver(
    'SELECT * FROM cars WHERE _id.locationId = :locationId',
    arguments: {'locationId': locationId},
    (result) {
        final cars = result.items.map((item) => Car.fromJson(item.value)).toList();
        updateUI(cars);
    });
// Cancel: observer.cancel();
```

### Sync Subscriptions

```dart
// v4.14
final sub = ditto.store.collection('cars')
    .find("color == 'red'").subscribe();

// v5.0
final sub = await ditto.sync.registerSubscription(
    'SELECT * FROM cars WHERE color = :color',
    arguments: {'color': 'red'});
sub.cancel();
```

---

## 10. Errors

**v4:**
```dart
// DittoError from src/error.dart
// DittoException, DittoClosedException from src/exception.dart
```

**v5:**
```dart
// All from src/exception.dart (merged)
// DittoError, DittoException, DittoClosedException
```

No functional change - just file consolidation.

## 11. Other API Changes

| v4.14 | v5.0 |
|-------|------|
| `Peer.peerKeyString: String` | `Peer.peerKey: String` |
| `Peer.peerKey: Uint8List` | Removed |
| `Peer.isConnectedToDittoCloud` | `Peer.isConnectedToDittoServer` |
| `Connection.peerKeyString1` / `peerKeyString2` | `Connection.peer1` / `peer2` |
| `ConnectionRequest.peerKeyString` | `ConnectionRequest.peerKey` |
| `ditto.persistenceDirectory` | `ditto.absolutePersistenceDirectory` |
| `SmallPeerInfoSyncScope` enum | `ALTER SYSTEM` DQL |
| `SmallPeerInfo.syncScope` | `ALTER SYSTEM` DQL |
| `DittoLogger.setLogFile(...)` | **Removed** — no replacement |
| `Connection.approximateDistanceInMeters` | **Removed** — no replacement |
| `HttpListenConfig.staticContentPath` | **Removed** — no replacement |


## 11. New APIs in v5

- **`DittoConfig`** / **`DittoConfigConnectServer`** / **`DittoConfigConnectSmallPeersOnly`** — new configuration hierarchy replacing all identity types
- **`Ditto.openSync(config)`** — synchronous constructor alternative to async `Ditto.open(config)`
- **`Ditto.defaultRootDirectory`** — static helper for default persistence path
- **`ditto.config`** — access the config object used to open the instance
- **`AuthenticationExpirationHandler`** typedef — replaces `AuthenticationHandler` interface
- **`Authenticator.developmentProvider`** — constant for development auth provider
- **`Authenticator.expirationHandler`** — get/set the expiration handler
- **`SyncSubscription.queryArgumentsCborBytes`** / **`queryArgumentsJsonString`** — inspect subscription query arguments
- **Builder types** for all transport config sub-types (`TransportConfigBuilder`, etc.)
- `Ditto` and `Store` marked `@pragma("vm:isolate-unsendable")` for safety

---

## 12. Complete API Rename Table

This table shows every property/method rename for search-and-replace operations:

| v4 Code Pattern | v5 Code Pattern | Scope |
|---|---|---|
| `Ditto.open(identity:` | `Ditto.open(DittoConfig(` | Initialization |
| `identity: OnlinePlaygroundIdentity(` | `DittoConfig(connect: DittoConfigConnectServer(` | Initialization |
| `identity: OfflinePlaygroundIdentity(` | `DittoConfig(connect: DittoConfigConnectSmallPeersOnly(` | Initialization |
| `identity: SharedKeyIdentity(` | `DittoConfig(connect: DittoConfigConnectSmallPeersOnly(privateKey:` | Initialization |
| `identity: OnlineWithAuthenticationIdentity(` | `DittoConfig(connect: DittoConfigConnectServer(` | Initialization |
| `ditto.identity` | `ditto.config` | Property access |
| `.appID` (on Identity) | `.databaseID` (on DittoConfig) | Config field |
| `ditto.startSync()` | `ditto.sync.start()` | Sync |
| `ditto.stopSync()` | `ditto.sync.stop()` | Sync |
| `ditto.isSyncActive` | `ditto.sync.isActive` | Sync |
| `ditto.persistenceDirectory` | `ditto.absolutePersistenceDirectory` | Property |
| `.peerKeyString` (on Peer) | `.peerKey` | Presence |
| `.peerKeyString` (on ConnectionRequest) | `.peerKey` | Presence |
| `.isConnectedToDittoCloud` | `.isConnectedToDittoServer` | Presence |
| `.peerKeyString1` | `.peer1` | Connection |
| `.peerKeyString2` | `.peer2` | Connection |
| `.approximateDistanceInMeters` | *(removed)* | Connection |
| `AuthenticationHandler(` | `AuthenticationExpirationHandler` typedef | Auth |
| `authenticationRequired:` | *(removed - handle before sync.start)* | Auth |
| `authenticationExpiringSoon:` | `setExpirationHandler()` | Auth |
| `loginWithCredentials(` | *(removed - use login() with token)* | Auth |
| `DocumentID(` | Use raw values directly | Types |
| `SiteID.fromInt(` | *(removed - not in config)* | Types |
| `TransportConfig.copy()` | `TransportConfig.toBuilder().build()` | Transport |
| `setAllPeerToPeerEnabled(` | `withAllPeerToPeerEnabled(` | Transport |
| `mutatedDocumentIDs` (property) | `mutatedDocumentIDs()` (method call) | QueryResult |
| `remotePeers` (List) | `remotePeers` (Set) | PresenceGraph |


### Quick Reference: Search-and-Replace Patterns

These regex patterns can be used for automated migration. Apply in order.

#### 1. Sync control (safe, mechanical replacement)
```
ditto.startSync()     -> ditto.sync.start()
ditto.stopSync()      -> ditto.sync.stop()
ditto.isSyncActive    -> ditto.sync.isActive
```

#### 2. Presence property renames (safe, mechanical replacement)
```
.peerKeyString1       -> .peer1
.peerKeyString2       -> .peer2
.peerKeyString        -> .peerKey
.isConnectedToDittoCloud -> .isConnectedToDittoServer
.persistenceDirectory -> .absolutePersistenceDirectory
```

#### 3. QueryResult (safe)
```
.mutatedDocumentIDs   -> .mutatedDocumentIDs()
```
Note: Be careful not to add parens if already a method call.

#### 4. Remove approximateDistanceInMeters references
Delete any code referencing `Connection.approximateDistanceInMeters` as it no longer exists.

#### 5. Identity migration (requires manual review)
Each Identity type needs to be converted to the appropriate `DittoConfig`. See the [Identity to DittoConfig](#identity-to-dittoconfig) section for the mapping.

#### 6. Auth handler migration (requires manual review)
The `AuthenticationHandler` interface is replaced by separate concerns:
- Initial auth: call `ditto.auth.login()` explicitly after `Ditto.open()`
- Expiration: use `ditto.auth.setExpirationHandler()` with `AuthenticationExpirationHandler` typedef

#### 7. Transport config builder (requires context-aware replacement)
Inside `updateTransportConfig` callbacks, the parameter is now a `TransportConfigBuilder` instead of `TransportConfig`. The builder has the same nested property structure, so interior code within the callback typically does not need to change.


## 12. Migration Checklist

### Initialization
- [ ] Replace `Ditto.open(identity:, persistenceDirectory:)` with `Ditto.open(DittoConfig(...))`
- [ ] Create `DittoConfig` with `DittoConfigConnect*` variant
- [ ] Set `DQL_STRICT_MODE=true` BEFORE `sync.start()` if maintaining v4 behavior
- [ ] Update `startSync()` → `sync.start()`

### WebSocket Sync
- [ ] Explicitly set `websocketSync = true` if your app used WebSocket sync (was default=true in v4)

### Authentication
- [ ] Remove `AuthenticationHandler` implementations
- [ ] Set `ditto.auth?.setExpirationHandler(...)` after `Ditto.open()`
- [ ] Use `Authenticator.developmentProvider` for playground tokens

### Presence
- [ ] Update all code accessing `remotePeers` — type changed from `List<Peer>` to `Set<Peer>`
- [ ] Replace index access (`remotePeers[0]`) with `.first` or `.toList()[0]`
- [ ] Update function signatures expecting `List<Peer>` to accept `Set<Peer>` or call `.toList()`

### Isolates
- [ ] Remove any code that sends `Ditto` or `Store` instances across isolate boundaries
- [ ] Create separate `Ditto.open()` per isolate if needed

### Transport Config
- [ ] Update any `updateTransportConfig` calls to use immutable builder pattern
- [ ] Remove calls to `enableAllPeerToPeer()` — configure each transport explicitly

### Data Operations
- [ ] Replace all `.collection("x").find(...)` chains with `store.execute()` DQL
- [ ] Replace `.upsert()` → `INSERT INTO ... ON ID CONFLICT DO UPDATE`
- [ ] Replace update closures → `UPDATE SET`
- [ ] Replace `.remove()` → `DELETE FROM`
- [ ] Replace `.evict()` → `EVICT FROM`
- [ ] Replace `.observeLocal()` → `store.registerObserver()`
- [ ] Replace `.subscribe()` → `sync.registerSubscription()`

### Peer Info
- [ ] Update `peerKeyString` → `peerKey`
- [ ] Update `isConnectedToDittoCloud` → `isConnectedToDittoServer`

---

## Common Pitfalls

1. **`remotePeers` type change**: `List<Peer>` → `Set<Peer>`. Code using index access or expecting `List` will break at runtime or compile time.

2. **Isolate-unsendable**: Sending `Ditto` or `Store` across isolates causes a runtime error. Create separate instances per isolate.

3. **WebSocket default flip**: Apps relying on WebSocket sync being enabled by default will silently lose sync. Explicitly set `websocketSync = true`.

4. **DQL_STRICT_MODE silent change**: Objects may merge instead of replace without setting strict mode.

5. **`AuthenticationHandler` interface removed**: Implementing the interface no longer compiles. Use the typedef closure instead.

6. **`Authenticator.loginWithCredentials()`**: Removed in v5. Use token-based auth with `login(token:provider:)`.

---

## Summary of Breaking Changes by Severity

### High Impact (requires structural code changes)
- **Identity system removed** - Must convert all Identity usage to DittoConfig
- **Sync methods moved** - `startSync()`/`stopSync()` moved from Ditto to Sync sub-object
- **Auth handler redesigned** - `AuthenticationHandler` interface replaced by typedef + explicit login

### Medium Impact (property/method renames)
- `Peer.peerKeyString` -> `Peer.peerKey`
- `Peer.isConnectedToDittoCloud` -> `Peer.isConnectedToDittoServer`
- `Connection.peerKeyString1`/`peerKeyString2` -> `Connection.peer1`/`peer2`
- `ConnectionRequest.peerKeyString` -> `ConnectionRequest.peerKey`
- `Ditto.persistenceDirectory` -> `Ditto.absolutePersistenceDirectory`
- `QueryResult.mutatedDocumentIDs` property -> `mutatedDocumentIDs()` method

### Low Impact (additions, no breakage unless referenced)
- `DocumentID` and `SiteID` classes removed from exports
- `Connection.approximateDistanceInMeters` removed
- `SmallPeerInfoSyncScope` removed from public exports
- `Authenticator.loginWithCredentials()` removed
- `DittoLogger.setLogFile()` removed
- `PresenceGraph.remotePeers` return type changed from `List<Peer>` to `Set<Peer>`
- Transport config objects are now immutable (use builders)

---

## Official Documentation

- Flutter V4→V5 Guide: https://docs.ditto.live/sdk/latest/migration-guides/flutter-v4
- Flutter DQL Migration: https://docs.ditto.live/sdk/latest/migration-guides/flutter-dql
- DQL Reference: https://docs.ditto.live/dql/dql
