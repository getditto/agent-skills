---
name: migrate-flutter
description: Use when migrating Ditto Flutter/Dart SDK applications from v4.14 to v5.0. Covers Ditto.open(DittoConfig) factory, Ditto.openSync() new option, PresenceGraph.remotePeers type change (List→Set), isolate-unsendable restriction on Ditto and Store, AuthenticationExpirationHandler typedef, TransportConfig builder pattern, and DQL migration from legacy Query Builder.
---

# Ditto Flutter/Dart SDK: v4.14 → v5.0 Migration Reference

## Quick Summary of Changes

| Area | v4.14 | v5.0 |
|------|-------|------|
| Init | `Ditto.open(identity:, persistenceDirectory:)` | `Ditto.open(DittoConfig)` or `Ditto.openSync(DittoConfig)` |
| Sync | `ditto.startSync()` / `stopSync()` | `ditto.sync.start()` / `sync.stop()` |
| Auth | `AuthenticationHandler` interface | `AuthenticationExpirationHandler` typedef + `authenticator.setExpirationHandler(...)` |
| Peer key | `Peer.peerKeyString` + `Peer.peerKey: Uint8List` | `Peer.peerKey: String` |
| Peer cloud | `Peer.isConnectedToDittoCloud` | `Peer.isConnectedToDittoServer` |
| Presence | `PresenceGraph.remotePeers: List<Peer>` | `PresenceGraph.remotePeers: Set<Peer>` |
| Persistence dir | `ditto.persistenceDirectory` | `ditto.absolutePersistenceDirectory` |
| Transport config | Mutable `TransportConfig` | Immutable + `toBuilder().build()` |
| Websocket sync | `HttpListenConfig.websocketSync` defaults `true` | Defaults **`false`** — must explicitly enable |
| Isolates | No restriction | `Ditto` and `Store` are `@pragma("vm:isolate-unsendable")` |

---

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

### Identity → DittoConfig Mapping

| v4.14 Identity | v5.0 DittoConfig connect |
|----------------|--------------------------|
| `OnlinePlaygroundIdentity(appID:token:customAuthURL:)` | `DittoConfigConnectServer(url:)` |
| `OnlineWithAuthenticationIdentity(appID:customAuthURL:)` | `DittoConfigConnectServer(url:)` + auth handler |
| `OfflinePlaygroundIdentity(appID:)` | `DittoConfigConnectSmallPeersOnly(privateKey: null)` |
| `SharedKeyIdentity(appID:sharedKey:)` | `DittoConfigConnectSmallPeersOnly(privateKey: key)` |
| `ManualIdentity(...)` | `DittoConfigConnectSmallPeersOnly(...)` |

---

## 2. Sync API

```dart
// v4.14
await ditto.startSync();
ditto.stopSync();
final active = ditto.isSyncActive;

// v5.0
await ditto.sync.start();
ditto.sync.stop();
final active = ditto.sync.isActive;
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

---

## 4. Presence — `List<Peer>` → `Set<Peer>`

⚠️ **Breaking type change**: `PresenceGraph.remotePeers` changed from `List<Peer>` to `Set<Peer>`.

```dart
// v4.14
final List<Peer> peers = graph.remotePeers;
final Peer firstPeer = peers[0];  // index access works

// v5.0
final Set<Peer> peers = graph.remotePeers;
final Peer firstPeer = peers.first;  // use .first, not [0]
// or: final List<Peer> peersList = peers.toList();
```

Update any code that:
- Indexes into `remotePeers` by position
- Passes it to a function expecting `List<Peer>`
- Uses `remotePeers.length` (works on both) or `.isEmpty` (works on both)

---

### Back Pressure

Flutter's SDK handles back pressure **internally** — there is no `signalNext` function exposed. The `Stream<QueryResult>` observer model manages update delivery automatically. Use Dart's `StreamController` with `pause`/`resume` if you need custom flow control.

---

## 5. Isolate Restriction

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

## 6. Transport Config — Builder Pattern

```dart
// v4.14 — mutable config
ditto.updateTransportConfig((config) {
    config.connect.websocketUrls.add('wss://...');
    config.enableAllPeerToPeer();
});

// v5.0 — immutable + builder
final newConfig = ditto.transportConfig
    .toBuilder()
    ..connect.websocketUrls.add('wss://...')
    ..peerToPeer.bluetoothLE.enabled = true
    ..peerToPeer.lan.enabled = true
    ;
ditto.transportConfig = newConfig.build();
```

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

⚠️ **Silent data behavior change**: v5 defaults to `DQL_STRICT_MODE=false`. v4 default was `true`.

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

## 10. Other API Changes

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

## Official Documentation

- Flutter V4→V5 Guide: https://docs.ditto.live/sdk/latest/migration-guides/flutter-v4
- Flutter DQL Migration: https://docs.ditto.live/sdk/latest/migration-guides/flutter-dql
- DQL Reference: https://docs.ditto.live/dql/dql
