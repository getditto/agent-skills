# Migrating a Flutter app from v4 to v5 — agent instructions

Use this file when asked to upgrade a Flutter app from `ditto_live` 4.x to 5.x. It holds
the migration prompt Ditto publishes for AI coding assistants, copied from
<https://docs.ditto.live/sdk/latest/migration-guides/flutter-v4> ("AI Agent Prompt",
retrieved 2026-11-19). Follow it as your instructions. The per-API tables and the reasons
are in [versions.md](versions.md#cap-19-v4-to-v5-migration); the query side is
<https://docs.ditto.live/sdk/latest/migration-guides/flutter-dql>.

## Contents

- [How to run the migration](#how-to-run-the-migration)
- [Apply these over the prompt](#apply-these-over-the-prompt)
- [The migration prompt](#the-migration-prompt)

## How to run the migration

1. Read the app's `ditto_live` version in `pubspec.lock`, and find every Ditto call:
   `Ditto.open`, `startSync`, the identity classes, `AuthenticationHandler`,
   `registerSubscription`, `registerObserver`, `presence`, `updateTransportConfig`.
2. Set the `ditto_live` pin to the 5.x release the user names (the latest stable if they
   name none) and run `flutter pub get`.
3. Apply the prompt below, section by section, with the corrections in the next section.
4. Fix the platform projects: [setup.md](setup.md#cap-01-prerequisites-and-install).
5. Verify: `dart format .`, `flutter analyze`, then run the app or its
   `integration_test` on a device or desktop target
   ([testing.md](testing.md#cap-18-testing)). Report what ran and what did not.

## Apply these over the prompt

The prompt is reproduced as published. On these points the released package differs
from it, or this skill has more specific guidance; where they conflict, these win.

| The prompt says | Do this instead | Evidence |
|---|---|---|
| Observers: "No `signalNext`" | From 5.1.0, `registerObserverWithSignalNext` exists; use it for slow consumers ([observers.md](observers.md#back-pressure-registerobserverwithsignalnext-510)) | executed, 5.1.0 and 5.2.0 |
| Observers: "callback-based with `onChange`" | Register long-lived observers without `onChange` and hold one `changes` listener: with `onChange`, every result is also buffered in the unlistened stream ([observers.md](observers.md#the-onchange-buffering-defect)) | executed, 5.0.4 to 5.2.0 |
| "`HttpListenConfig.websocketSync` default changed from `true` to `false`" | Nothing to change: it was already `false` in 4.14.7 | source |
| `builder.setAllPeerToPeerEnabled(true)` | Set each transport explicitly: on 5.0.x `setAllPeerToPeerEnabled(false)` leaves AWDL and Wi-Fi Aware on ([transports.md](transports.md#cap-06-customizing-transports)) | source |
| iOS 14.0+, macOS 12.0+ | Commit `platform :ios, '15.0'` and `platform :osx, '12.0'`: Flutter 3.50 raises iOS 14 to 15 on every build ([setup.md](setup.md#platform-minimums)) | executed |
| Android `minSdk` 24 and Kotlin 2.0.0 | Also add the compileSdk override for 5.1.0 and later under AGP 9 ([setup.md](setup.md#android-gradle)) | executed |
| (not in the prompt) | `result.mutatedDocumentIDs` is a method on v5 and returns the raw `_id` values ([versions.md](versions.md#removed-apis)) | source |
| (not in the prompt) | Existing data: pass no `persistenceDirectory` and keep the v4 `appID` as `databaseID`; 5.x then opens the v4 `{Documents}/ditto` store in place. Passing the v4 path explicitly, as the guide's page shows, also works. Tell the user to test on a copy of a real store ([versions.md](versions.md#on-disk-store-migration)) | executed by hand on macOS, 5.0.4 to 5.2.0 |

`await Ditto.init()` is optional before `Ditto.open` from 5.1.0; keep it anyway, as the
prompt says: it is required on 5.0.x and memoized.

## The migration prompt

````text
I need help migrating a Ditto Flutter application from v4 to v5. Focus on these critical changes:

INITIALIZATION:
Replace `Ditto.open(identity: Identity)` with `Ditto.open(DittoConfig(...))`:
- `DittoConfig(databaseID: String, connect: DittoConfigConnect, ...)` replaces identity types
- `DittoConfigConnectServer(url: String)` replaces `OnlinePlaygroundIdentity` — URL is a plain `String`, NOT a `Uri`. Copy the URL from the Ditto Portal (Connect via SDK → **URL**) as-is — don't build it from the database ID.
- `DittoConfigConnectSmallPeersOnly(privateKey: String?)` replaces `OfflinePlaygroundIdentity` and `SharedKeyIdentity`
- `Ditto.openSync(config)` available as synchronous alternative
- `await Ditto.init()` must be called before any Ditto usage
- Remove `updateTransportConfig` WebSocket URL additions (cloud URL inferred from config)
- Remove `DQL_STRICT_MODE = false` workaround (now the v5 default)
- If your v4 app relied on `DQL_STRICT_MODE = true` (v4 default), set it BEFORE `sync.start()`.
- On SDK 5.2+, set strict mode in the config instead of running `ALTER SYSTEM` after open: `systemParameters: {'DQL_STRICT_MODE': true}` in `DittoConfig`. On 5.0 and 5.1, run `ALTER SYSTEM SET DQL_STRICT_MODE = true` after open and before starting sync.

SYNC:
- `ditto.startSync()` → `ditto.sync.start()`
- `ditto.stopSync()` → `ditto.sync.stop()`
- `ditto.isSyncActive` → `ditto.sync.isActive`
- IMPORTANT: In v5, subscription queries cannot use `LIMIT` or `ORDER BY`. Registering one fails with `<dql> Unsupported feature: Limit or Order by`. If the v4 app has `LIMIT`/`ORDER BY` in a subscription, remove those clauses: a subscription defines what to sync, not display order. Sort results at query/render time instead.

AUTHENTICATION:
Set `expirationHandler` via async method after initialization — replaces `AuthenticationHandler` interface:
- `await ditto.auth.setExpirationHandler((Ditto ditto, Duration timeUntilExpiration) { ... })`
- `ditto.auth` is non-nullable — do NOT use `ditto.auth?.`
- Handler receives `Ditto` (not `Authenticator`) and `Duration` (not `int`)
- Called when `timeUntilExpiration == Duration.zero` (initial auth or expired) or `> 0` (token expiring)
- Use `Authenticator.developmentProvider` for playground tokens
- `ditto.auth.login()` returns `Future<AuthResponse>`. Check `response.exception`; there is no `response.error` property:
```dart
await ditto.auth.setExpirationHandler((ditto, timeUntilExpiration) async {
  final response = await ditto.auth.login(
    token: 'your-token',
    provider: Authenticator.developmentProvider,
  );
  if (response.exception != null) {
    throw response.exception!;
  }
});
```
- Remove `loginWithCredentials()` — use token-based `login()` instead
- Remove `AuthenticationHandler` class/interface

TRANSPORT CONFIG:
Changed from mutable to immutable with builder pattern:
- `ditto.updateTransportConfig((builder) { builder.setAllPeerToPeerEnabled(true); })`
- Or: `ditto.transportConfig = ditto.transportConfig.withAllPeerToPeerEnabled(true);`
- `TransportConfig.withBigPeer(...)` removed — use `DittoConfig` server config

PRESENCE & PEERS:
- `PresenceGraph.remotePeers` changed from `List<Peer>` to `Set<Peer>` — use `.first` instead of `[0]`
- `Peer.peerKeyString` → `Peer.peerKey: String` (unified)
- `Peer.isConnectedToDittoCloud` → `Peer.isConnectedToDittoServer`
- `Connection.peerKeyString1/peerKeyString2` → `Connection.peer1/peer2`
- `ConnectionRequest.peerKeyString` → `ConnectionRequest.peerKey`

OBSERVERS:
- `registerObserver()` API is the same — callback-based with `onChange` parameter
- Observers also expose `Stream<QueryResult> changes` for reactive use
- No `signalNext` — backpressure handled internally by SDK

OTHER:
- `ditto.persistenceDirectory` → `ditto.absolutePersistenceDirectory`
- `HttpListenConfig.websocketSync` default changed from `true` to `false`
- `Ditto` and `Store` cannot be passed across Dart isolates
- `DittoLogger.setLogFile()` removed
- `SmallPeerInfoSyncScope` enum removed — use DQL `ALTER SYSTEM SET sync_scope`
- `SiteID` and `DocumentID` are no longer exported (internal types)
- Ditto Flutter SDK for MacOS now targets 12.0+ - if your project targets older releases you will need to raise the minimum version.
- Ditto Flutter SDK for iOS now targets 14.0+ - if your project targets older releases you will need to raise the minimum version.
- MacOS and iOS use CocoaPods for dependency management, because of this you will probably need to delete the Pod lock file and run `pod install` again.  This is a standard CocoaPods issue when upgrading dependencies.
- Ditto Flutter SDK for Android minimum SDK version is now 24 (Android 7.0 Nougat). If your project targets `minSdk = 23`, you must raise it.
- Ditto Flutter SDK for Android requires Kotlin Gradle plugin 2.0.0 or later. Kotlin 1.9 cannot read the Kotlin 2.1 metadata in the Android artifacts.

DITTO TOOLS (only if the project uses ditto_flutter_tools):
- Update `ditto_flutter_tools` to 3.0.0.
- ditto_flutter_tools 3 requires `ditto_live` 5.0.1 or a later 5.x release.
- Remove `SyncStatusHelper`, `SyncStatusView`, and `SyncStatus` usage. These APIs were removed because subscription timing did not reliably represent synchronization progress.
````
