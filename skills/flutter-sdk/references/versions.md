# Versions and migration — Flutter

The single home for every fact that differs across `ditto_live` lines. Inline version
tags elsewhere in this skill agree with this file.

## Contents

- [Supported versions](#supported-versions)
  - [Toolchain floors](#toolchain-floors)
  - [Ditto.init per line](#dittoinit-per-line)
- [Capability availability matrix](#capability-availability-matrix)
  - [Behaviour that changed between lines](#behaviour-that-changed-between-lines)
- [CAP-19 v4 to v5 migration](#cap-19-v4-to-v5-migration)
  - [Package and namespace](#package-and-namespace)
  - [Initialization and identity](#initialization-and-identity)
  - [Authentication](#authentication)
  - [Sync](#sync)
  - [Query model](#query-model)
  - [Observers](#observers)
  - [On-disk store migration](#on-disk-store-migration)
  - [Removed APIs](#removed-apis)
  - [New in v5](#new-in-v5)
  - [Migration checklist](#migration-checklist)

## Supported versions

| Ditto SDK | Package version | Verified on | Status |
|---|---|---|---|
| 5.2.0 | `ditto_live: 5.2.0` | 5.2.0: macOS, Chrome, Linux, Windows, Android emulator, iOS Simulator | Latest known baseline; resolve the latest stable for new apps (`flutter pub add ditto_live`) |
| 5.1.x | `ditto_live: 5.1.0` | 5.1.0: macOS, Chrome | Earlier 5.x line |
| 5.0.x | `ditto_live: 5.0.4` | 5.0.4: macOS, Chrome (debug) | Earlier 5.x line; 5.0.4 has no `sdk-release-5.0.4` tag, so source citations use the pub.dev archive |
| 4.14.x | `ditto_live: 4.14.7` | 4.14.7: macOS (write and read back), iOS Simulator and Android release builds | LTS; the v4 API below |

All runs used Flutter 3.50.0 (Dart 3.14.0); debug builds unless the file says otherwise.

### Toolchain floors

| Line | Published `environment` (pub.dev) | Release-tag `pubspec.yaml` | Lowest Flutter for the Dart floor |
|---|---|---|---|
| 4.14.7 | `flutter: ">=3.19.0"`, `sdk: ">=3.3.0 <4.0.0"` | same | 3.19.0 |
| 5.0.4 | `flutter: ">=3.19.0"`, `sdk: '>=3.3.0 <4.0.0'` | no tag | 3.19.0 |
| 5.1.0 | `flutter: ">=3.19.0"`, `sdk: '>=3.5.4 <4.0.0'` | `flutter: '>=3.24.5'` | 3.24.4 |
| 5.2.0 | `flutter: ">=3.19.0"`, `sdk: '>=3.5.4 <4.0.0'` | `flutter: '>=3.24.5'` | 3.24.4 |

The install guide asks for Flutter 3.24.5 or later
(<https://docs.ditto.live/sdk/latest/install-guides/flutter>). Use 3.24.5+ for 5.x; only
3.50.0 was executed. Platform minimums: [setup.md](setup.md#platform-minimums).

### Ditto.init per line

| Line | `await Ditto.init()` before `Ditto.open` | Evidence |
|---|---|---|
| 4.14.x | Required ("you *must* call") | dartdoc, `flutter/ditto_live/lib/src/ditto.dart` @ `sdk-release-4.14.7` |
| 5.0.x | Required: `open` throws ``DittoError(Ditto not initialized. …)`` without it | source, `lib/src/ditto.dart:134,289`, ditto_live 5.0.4 |
| 5.1.0, 5.2.0 | Optional: `open` calls it. Still required before `Ditto.openSync`, `Ditto.defaultRootDirectory` and any `DittoLogger` member | source, `ditto.dart` @ `sdk-release-5.2.0` (`defaultRootDirectory`: `ditto.dart:65-68` @ `sdk-release-5.1.0` and `sdk-release-5.2.0`, `lib/src/ditto.dart:63-66` in 5.0.4); the logger case executed on all three 5.x lines |

`init` is memoized, so cross-line code calls it unconditionally.

## Capability availability matrix

| Capability | 4.14.x | 5.0.x | 5.1.x / 5.2.0 | Failure mode on older versions |
|---|---|---|---|---|
| `DittoConfig`, `Ditto.open(config)`, `ditto.sync.start()` | no (identity API) | yes | yes | — (different API; see migration) |
| `registerObserverV2`, `registerObserverWithSignalNext` | no | no | yes (`@experimental`) | Compile error: `The method 'registerObserverV2' isn't defined for the type 'Store'` |
| `observeTransportConditions`, `DittoSyncPermissions`, `multicastBeta`, `ConnectionType.multicast` | no | no | yes | Compile error (undefined name or member) |
| `Store.experimentalSkipExecuteIsolateOffload` | no | no | yes | Compile error |
| `Store.observers` | no | no | 5.2.0 only | Compile error on 5.1.0 |
| `DittoConfig.systemParameters` | no | no | 5.2.0 only | Compile error on 5.1.0 |
| `DittoEncryptionException`, `DittoEncryptionErrorReason` | no | no | 5.2.0 only | Compile error on 5.1.0 |
| `logout({cleanup})` | `logout()` | `logout()` | 5.2.0 only | 5.1.0: no `cleanup` parameter ([connect.md](connect.md#cap-04-authentication-and-identity)) |
| `Ditto.openSync`, `Ditto.defaultRootDirectory`, `absolutePersistenceDirectory` | no | yes | yes | Compile error on 4.14.x |
| `QueryResult.commitID`, `Differ`, `DittoLogger.exportLogs` | yes | yes | yes | — |

From grepping `lib/` at each tag (4.14.7, 5.1.0, 5.2.0) and in ditto_live 5.0.4. The
compile error text is the analyzer's (Flutter 3.50.0 against 5.0.4: `undefined_method`); the probe directories
`v51` and `v52` exist because these do not compile on older lines.

### Behaviour that changed between lines

| Behaviour | 5.0.x | 5.1.0 | 5.2.0 | Evidence |
|---|---|---|---|---|
| V1 observer without `onChange` starts | at registration | on first `listen` | on first `listen` | executed |
| V1 observer, and `SyncSubscription`, `isCancelled` after `close()` | `false` | `true` | `true` | executed |
| V1 `cancel()` after `close()` | throws `DittoClosedException` | no-op | no-op | source |
| `close()` resets `DittoLogger.customLogCallback` | no | yes | yes | executed |
| `setAllPeerToPeerEnabled(false)` | leaves AWDL / Wi-Fi Aware on | correct | correct | source |
| `execute` on native | new isolate per call | per-`Ditto` worker isolate | worker isolate | source |
| `logout()` | logs out | also stops sync | also stops sync; `cleanup` | source |
| Default persistence root | Documents | Documents | Application Support (reads an existing Documents store in place) | executed (5.1.0 → 5.2.0) |
| Web: enabling a P2P transport throws from | `updateTransportConfig` | `updateTransportConfig` | `sync.start()` | executed |
| `experimental.passphrase` | accepted | accepted | rejected with `DittoException` | executed |
| Hot restart, re-open of the same directory | `File already locked` | `Ditto.open` hangs | `File already locked` | executed (macOS) |
| Hot restart, orphaned V1 observer on a remote change | no crash | crashes | no crash | executed (macOS) |
| `ConnectionType` values | 4 | 5 (`multicast`) | 5 | executed |
| Android build with AGP 9 | builds | fails at `:ditto_live:checkDebugAarMetadata` without the compileSdk override | same | executed ([setup.md](setup.md#android-gradle)) |
| iOS Simulator x86_64 link | builds | `Framework 'DittoCore' not found` without the Podfile fix (from the podspec; 5.1.0 not built) | same (executed) | [setup.md](setup.md#ios-and-macos-cocoapods) |
| macOS podspec minimum | 10.11 | 11.0, arm64 | 11.0, arm64 | source |

## CAP-19 v4 to v5 migration

The authoritative guide is
<https://docs.ditto.live/sdk/latest/migration-guides/flutter-v4>, with the query side in
<https://docs.ditto.live/sdk/latest/migration-guides/flutter-dql>. Three of its statements
do not match the released source: that `Ditto.init()` is mandatory (optional from
5.1.0), that Flutter has no `signalNext` (it does from 5.1.0), and that
`HttpListenConfig.websocketSync` defaulted to `true` in v4 (`false` in 4.14.7).

### Package and namespace

The package and import do not change: `ditto_live`,
`import 'package:ditto_live/ditto_live.dart';`. Change the pin from `4.14.7` to the 5.x
release and fix the compile errors.

### Initialization and identity

ditto_live 4.14.x open (executed: writes and reads back one document on macOS):

<!-- snippet: flutter-v4-open -->
<!-- Generated by scripts/sync-snippets.py from code CI runs. Edit the marked source, not this block. -->
```dart
/// ditto_live 4.14.x: an identity object instead of a DittoConfig, and
/// startSync() on the instance instead of sync.start().
Future<Ditto> openV4Ditto({
  required String license,
  String persistenceDirectory = 'ditto',
  void Function(TransportConfig config)? transports,
}) async {
  await Ditto.init();
  final ditto = await Ditto.open(
    identity: OfflinePlaygroundIdentity(
      appID: 'REPLACE_ME_WITH_YOUR_APP_ID',
      siteID: SiteID.fromInt(2),
    ),
    persistenceDirectory: persistenceDirectory,
  );
  ditto.setOfflineOnlyLicenseToken(license);
  if (transports != null) ditto.updateTransportConfig(transports);
  ditto.startSync();
  return ditto;
}
```
<!-- /snippet -->

**4.14.x has no non-deprecated way to open or start sync.** Every identity class,
`SiteID` and `startSync()`/`stopSync()`/`isSyncActive` are `@Deprecated`
(`src/identity.dart`, `src/shared/site_id.dart:17`, `src/ditto.dart:200-224` under
`flutter/ditto_live/lib/` @ `sdk-release-4.14.7`). Their message names
`ditto.sync.start()`, but `Sync` has no `start`, `stop` or `isActive` at that tag
(`src/sync.dart`): that is the v5 API. So on 4.14.x, "never a deprecated API" means
"nothing deprecated beyond these". Code like the block above reports
`deprecated_member_use` infos and fails `flutter analyze --fatal-infos`; add
`// ignore_for_file: deprecated_member_use` to the file that opens Ditto, as the tested
fixture does, and keep `--fatal-infos` for everything else.

The v5 form is `DittoService.open` in [connect.md](connect.md#open-configure-close-on-failure).
The identity classes map to a `connect` mode (migration guide; 4.14.7 marks every
identity class `@Deprecated`):

<!-- dart-fragment: v4-rename-table -->
```dart
// v4.14 identity                          -> v5 DittoConfig(connect: ...)
// OfflinePlaygroundIdentity(appID, siteID) -> DittoConfigConnectSmallPeersOnly()
// SharedKeyIdentity(appID, sharedKey, …)   -> DittoConfigConnectSmallPeersOnly(privateKey: key)
// OnlinePlaygroundIdentity(appID, token)   -> DittoConfigConnectServer(url: url)
// OnlineWithAuthenticationIdentity(…)      -> DittoConfigConnectServer(url: url) + expiration handler
// ManualIdentity                           -> removed
```

`appID` becomes `DittoConfig.databaseID`; the server `url` is the portal's URL, copied as
is. `SiteID` is no longer exported.

### Authentication

| v4.14 | v5 |
|---|---|
| `AuthenticationHandler` with `authenticationRequired` and `authenticationExpiringSoon` | `await ditto.auth.setExpirationHandler((ditto, timeUntilExpiration) async { … })`, one handler |
| Handler passed through the identity | Set after `Ditto.open`, before `sync.start()` |
| `loginWithCredentials(username:, password:, provider:)` | Removed; `login(token:, provider:)` |
| `login` result | `AuthResponse`; a rejected login is `response.exception` |

Details and the executed handler: [connect.md](connect.md#cap-04-authentication-and-identity).

### Sync

| v4.14 | v5 |
|---|---|
| `ditto.startSync()`, `ditto.stopSync()`, `ditto.isSyncActive` | `ditto.sync.start()`, `ditto.sync.stop()`, `ditto.sync.isActive` |
| `smallPeerInfo.syncScope` | DQL `ALTER SYSTEM` ([sync.md](sync.md#sync-scopes)) |
| Mutable `TransportConfig` | Immutable; change it with `updateTransportConfig((builder) { … })` |
| `HttpListenConfig.websocketSync` | `false` by default on both (`transport/transport_config.dart:558`, `transport_config.g.dart:156` @ `sdk-release-4.14.7`); the migration guide's "was `true`" does not match 4.14.7 |
| `TransportConfig.withBigPeer(…)` | a server `connect` mode |

4.14.x `Ditto.open` enabled every peer-to-peer transport the platform has
(`setAllPeerToPeerEnabled(true)` in `open`, `sdk-release-4.14.7`); v5's defaults are
platform-dependent too, so set the transports you want explicitly
([transports.md](transports.md#cap-06-customizing-transports)). Subscriptions are the
same call; v5 rejects `LIMIT`/`ORDER BY` in them ([sync.md](sync.md#limit-and-order-by-are-rejected)).

### Query model

Both lines are DQL-only in Flutter (4.14.7 has no legacy collection API) and
`store.execute(query, arguments:)` keeps its shape. What changes is DQL's default: v5
runs with `DQL_STRICT_MODE=false`, so nested objects merge field by field instead of
being replaced whole (migration guide). Semantics: the `write-dql` skill if installed,
otherwise <https://docs.ditto.live/dql/strict-mode>.

### Observers

`registerObserver(query, arguments:, onChange:)` keeps its shape. In v5:
`PresenceGraph.remotePeers` is a `Set`, not a `List`; on 5.1.0+ an observer without
`onChange` starts on its first `listen`; V2 and signal-next observers exist from 5.1.0
([observers.md](observers.md#cap-11-observers-and-live-queries)).

### On-disk store migration

- **v4 → v5, the default directory.** v4's default was `{Documents}/ditto`; v5's is
  `ditto-{databaseID}`. When the app passes no `persistenceDirectory`, 5.0.4, 5.1.0 and
  5.2.0 pass `{Documents}/ditto` to the core as a legacy location, which the core opens
  in place when the v5 default has no database (`lib/src/ditto.dart`, comment and
  `legacy_persistence_directory`, in ditto_live 5.0.4 and @ `sdk-release-5.1.0`,
  `sdk-release-5.2.0`). **Not executed for 4.14 → 5.x.** The migration guide says the
  opposite ("v5 does not migrate existing databases") and shows passing the old path
  explicitly; until you have run your own upgrade on a copy of a real store, pass the
  v4 path explicitly as `persistenceDirectory`, or verify the documents after upgrading.
- **5.1 → 5.2, the default root.** 5.2.0 moved the default root from Documents to
  Application Support, and **reads an existing 5.1.0 store in place**. Executed on
  macOS and on the iOS Simulator: a 5.1.0 app wrote a document with the default
  directory; the 5.2.0 build of the same app, with no `persistenceDirectory`, reported
  `absolutePersistenceDirectory` = `{Documents}/ditto-<databaseID>`, returned the
  document, and created nothing under Application Support. With logging on it logs
  `Conflicting pre-existing default persistence directories found. Since the v5 default contains no ditto data, defaulting to legacy v4.`
  **Conditions, from source, not executed:** 5.2.0 looks for the 5.1.0 directory only
  when `databaseID` is non-null; with `databaseID: null` it checks only the v4 path. It
  builds the old name from the ID with characters outside `[A-Za-z0-9_-]` replaced but
  not lowercased, while the default directory uses the lowercase ID (`DittoConfig`
  dartdoc, `ditto_config.dart:46-49`). So a mixed-case ID on a case-sensitive file
  system (Android, Linux) would miss the old store (`resolveLegacyPersistenceDirectory`
  and `_sanitizeDatabaseId`, `lib/src/persistence_directory.dart:40-70`, called at
  `lib/src/ditto.dart:392-401`, @ `sdk-release-5.2.0`). The executed runs used the
  default all-zero ID on macOS's case-insensitive APFS. With a mixed-case or null ID,
  pass the old path as `persistenceDirectory` or test the upgrade first.
- **Not verified:** whether a store opened by 5.x can be opened again by 4.14.x
  (treat the upgrade as one-way), how long a large store takes to open the first time,
  and what an interrupted first open leaves behind. The wipe-and-resync path is to
  delete the persistence directory with Ditto closed and let subscriptions sync it
  again; on a device that is the only copy of unsynced writes, so check
  `system:data_sync_info` first ([sync.md](sync.md#cap-14-sync-status)).
- On the iOS Simulator, `flutter test` uninstalls the app after each run, deleting its
  store; upgrade tests need `--no-uninstall`.

### Removed APIs

| Removed in v5 | Replacement |
|---|---|
| `Ditto.open(identity:, persistenceDirectory:)` | `Ditto.open(DittoConfig(…))`, positional |
| `ditto.startSync()`, `stopSync()`, `isSyncActive` | `ditto.sync.start()`, `stop()`, `isActive` |
| `ditto.persistenceDirectory` | `ditto.absolutePersistenceDirectory` |
| `Peer.peerKeyString` (and `Uint8List peerKey`) | `Peer.peerKey`, a `String` |
| `Peer.isConnectedToDittoCloud` | `Peer.isConnectedToDittoServer` |
| `Connection.peerKeyString1`, `peerKeyString2` | `Connection.peer1`, `peer2` |
| `ConnectionRequest.peerKeyString` | `ConnectionRequest.peerKey` |
| `Connection.approximateDistanceInMeters` | No replacement |
| `AuthenticationHandler` | `setExpirationHandler` |
| `Authenticator.loginWithCredentials` | `login(token:, provider:)` |
| `SmallPeerInfo.syncScope`, `SmallPeerInfoSyncScope` | DQL `ALTER SYSTEM` |
| `TransportConfig.withBigPeer` | A server `connect` mode |
| `HttpListenConfig.staticContentPath` | No replacement |
| `DittoLogger.setLogFile` | No replacement; `DittoLogger.exportLogs` |
| `ManualIdentity`, `SiteID`, `DocumentID` exports | No replacement |
| `QueryResult.mutatedDocumentIDs`, a getter returning `Iterable<DocumentID>` | `mutatedDocumentIDs()`, a method returning `List<dynamic>`: the decoded `_id` values. Recomputed on each call, so call it once |

From the migration guide's tables, each checked present in 4.14.7 source and absent from
the 5.0.4 public API. The `mutatedDocumentIDs` change is not in the guide's tables: a
deprecated getter at `flutter/ditto_live/lib/src/store/execute.dart:65-70` @
`sdk-release-4.14.7`, a method at `sdks/flutter/ditto_live/lib/src/store/execute.dart:71`
@ `sdk-release-5.1.0` and `sdk-release-5.2.0` (`lib/src/store/execute.dart:71` in the
5.0.4 pub archive). v4 code such as `result.mutatedDocumentIDs.map((id) => id.value)`
does not compile on v5.

### New in v5

`DittoConfig` and the `DittoConfigConnect*` modes, `Ditto.openSync`,
`Ditto.defaultRootDirectory`, `ditto.config`, `ditto.sync.start()`/`stop()`, `Authenticator.developmentProvider`,
`setExpirationHandler`, builder types for every transport config, and
`TransportConfig.withAllPeerToPeerEnabled`. `Ditto` and `Store` are isolate-unsendable
([concurrency.md](concurrency.md#the-rules)). Later 5.x additions are in the matrix
above.

### Migration checklist

- [ ] Pin the 5.x release; run `flutter pub get`; use Flutter 3.24.5 or later.
- [ ] Replace `Ditto.open(identity:)` with `Ditto.open(DittoConfig(databaseID: …, connect: …))`; keep `await Ditto.init()` before it.
- [ ] Offline apps: `setOfflineOnlyLicenseToken` after open. Server apps: `await ditto.auth.setExpirationHandler(…)` before `sync.start()`.
- [ ] `startSync()` → `ditto.sync.start()`; set transports explicitly, one by one.
- [ ] Remove `LIMIT`/`ORDER BY` from subscriptions.
- [ ] Apply the renames above (`peerKey`, `isConnectedToDittoServer`, `absolutePersistenceDirectory`, `remotePeers` as a `Set`).
- [ ] `result.mutatedDocumentIDs` (`DocumentID`s) → `result.mutatedDocumentIDs()` (raw `_id` values; no `.value`).
- [ ] Re-check DQL that writes nested objects against strict mode off.
- [ ] Decide the persistence directory for upgraded installs; test the upgrade on a copy of a real v4 store.
- [ ] Android: `minSdk` 24 and, for 5.1.0+, the compileSdk override; iOS/macOS: the Podfile platform lines ([setup.md](setup.md#cap-01-prerequisites-and-install)).
- [ ] Run your tests on a device or desktop target ([testing.md](testing.md#cap-18-testing)).
