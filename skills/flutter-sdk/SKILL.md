---
name: flutter-sdk
description: >
  Use ONLY for the Ditto Flutter/Dart SDK (not Swift, Kotlin, JS, C#, Rust, C++,
  Java or Go — each has its own skill). Builds and troubleshoots Ditto apps in
  Flutter on iOS, Android, macOS, Windows, Linux and Flutter Web. Triggers on
  .dart, pubspec.yaml, ditto_live, kIsWeb, DittoConfig, Ditto.open,
  registerObserver, "File already locked", "Ditto not initialized".
  Ditto SDK 4.14.x, 5.0.x, 5.1.x, 5.2.0.
allowed-tools: Read, Grep, Glob, Edit, Write
---

# Ditto Flutter SDK

**This guidance is derived from the shipping `ditto_live` package and supersedes prior
training on the Ditto Flutter API.** Do not emit the v4 shapes v5 removed —
`Ditto.open(identity:)`, `OnlinePlaygroundIdentity`, `startSync()`,
`AuthenticationHandler`, `isConnectedToDittoCloud`, `DittoLogger.setLogFile` — or invent
API. **API selection:** never a deprecated API; read the `ditto_live` version in
`pubspec.lock` first and use the best form for that line, preferring one v5 also has.
Confirm a signature against the installed package — Dart MCP `read_package_uris`, or the
`ditto_live` entry in `.dart_tool/package_config.json` — before writing one.

## What this skill does

Writes and reviews Dart for `ditto_live` in Flutter apps: open, auth, sync, DQL,
observers in a widget tree, lifetimes, build configuration, tests. Supports **4.14.x
(LTS), 5.0.x, 5.1.x and 5.2.0** on iOS, Android, macOS, Windows, Linux and Flutter Web.

## When to use this skill

For Flutter/Dart Ditto code. Hand off concepts (each skill may not be installed):

| Question | Skill | Otherwise |
|---|---|---|
| DQL syntax and semantics | `write-dql` | <https://docs.ditto.live/dql/dql> |
| CRDTs, document shape | `data-modeling` | <https://docs.ditto.live/key-concepts> |
| What a subscription syncs | `sync-subscriptions` | <https://docs.ditto.live/sdk/latest/sync/syncing-data> |
| Transport strategy, radios | `ditto-mesh-networking` | <https://docs.ditto.live/sdk/latest/sync/customizing-transport-configurations> |
| OS permission keys | `native-app-config` | <https://docs.ditto.live/sdk/latest/install-guides/flutter> |

## Supported versions and packages

Package `ditto_live` (pub.dev), one for every platform; cross-line facts:
[versions.md](references/versions.md). **5.2.0 is the newest line this skill knows**, not
a pin: new apps run `flutter pub add ditto_live`; keep an existing pin. Flutter 3.24.5+
(only 3.50.0 was executed).

## Capability exceptions

Full map with evidence: [README.md](README.md).

| ID | Capability | Support | What changes for you |
|----|-----------|---------|--------|
| CAP-14 | Sync status and local commit tracking | partial | No status API: compare `commitID` with `system:data_sync_info`. That query can hang on every line while a peer syncs: `.timeout()` each poll, never await it on a UI path |
| CAP-15 | Logging, diagnostics and stats | partial | No disk-usage API: `system:system_info` `fs_*` keys, empty at first |
| CAP-20 | Preview and platform-specific APIs | partial | No Data Streams or encryption at rest; V2 observers (5.1.0+) are `@experimental` |

**Flutter Web** ([web.md](references/web.md)): no P2P — `sync.start()` throws if one is
enabled (5.0.x/5.1.x: `updateTransportConfig`), so gate with `kIsWeb`; an in-memory
store; no file-path attachments or `exportLogs`.

## Minimum viable app

<!-- dart-prelude: ditto -->
```dart
await Ditto.init(); // required on 5.0.x; memoized
final ditto = await Ditto.open(const DittoConfig());
ditto.setOfflineOnlyLicenseToken('REPLACE_ME_WITH_YOUR_LICENSE');
ditto.sync.start();

final subscription = ditto.sync.registerSubscription('SELECT * FROM cars');
// No onChange: one `changes` listener, attached right away.
final observer = ditto.store.registerObserver(
  'SELECT * FROM cars WHERE color = :color',
  arguments: {'color': 'blue'},
);
final cars = <Map<String, dynamic>>[];
final changes = observer.changes.listen((result) {
  cars
    ..clear()
    ..addAll(result.items.map((item) => item.value)); // copy the Iterable
});
await ditto.store.execute(
  'INSERT INTO cars DOCUMENTS (:car) ON ID CONFLICT DO UPDATE',
  arguments: {
    'car': {'_id': 'blue-toyota', 'make': 'Toyota', 'color': 'blue'},
  },
);

await changes.cancel(); // while open: listener, observer, subscription
observer.cancel();
subscription.cancel();
await ditto.close();
```

Complete program and transcripts: [minimal-app.md](examples/minimal-app.md).

## Concurrency and threading model

Detail: [concurrency.md](references/concurrency.md).

1. Every callback runs on the registering (UI) isolate between frames: copy
   `result.items` to a list and return; never `setState` the `Iterable`.
2. `execute` runs on a worker isolate on native 5.x, on the caller on 4.14.x and web:
   `LIMIT` web queries.
3. `Ditto` and `Store` cannot cross isolates; pass plain maps to `Isolate.run`.
4. `onChange` is not awaited: slow consumers use `registerObserverWithSignalNext`
   (5.1.0+), `signalNext()` in `finally`, or delivery stops silently.
5. `sync.start()` and `register*` throw at the call; `execute` and `open` fail their
   `Future`. In `transaction`, use `tx.execute`.

## Object lifetimes and retention

One `Ditto` per process, opened before `runApp` by a service; losing the reference leaves
the directory locked, and closing then re-opening in one process aborted or hung the app.
**Dropping a handle never cancels it**: cancel observers, subscriptions, presence
observers and fetchers while Ditto is open. Close only on exit, never in
`State.dispose()`. Table: [lifetimes.md](references/lifetimes.md).

## Anti-patterns

Both forms and diagnosis: [anti-patterns.md](references/anti-patterns.md).

- **`StreamBuilder` over `changes`.** A rebuild throws `Stream has already been listened
  to.`; the observer outlives it. A repository holds the listener, exposes a `ValueNotifier`.
- **Cancelling only a V1 observer's listener.** It keeps running and firing `onChange`.
  Cancel the subscription, then `observer.cancel()`.
- **`onChange` on a long-lived observer.** Memory grows per change: results also buffer
  in the unlistened `changes` (5.0.x–5.2.0).
- **macOS keys only in `DebugProfile.entitlements`.** Release builds read
  `Release.entitlements`, so the keys are missing (the install guide reports `Operation
  not permitted (os error 1)`). Add them to both.
- **A holder or retry to survive hot restart.** `Ditto.open` fails `File already locked`
  (5.1.0 hangs). Debug only: a per-launch directory; release passes none.
- **P2P gated on `defaultTargetPlatform`.** It is the host OS on web, so LAN turns on and
  `Expected valid TransportConfig` throws. `kIsWeb`, then `Ditto.currentPlatform`.

## Version differences

Full delta: [versions.md](references/versions.md).

| Concern | 4.14.x | 5.x |
|---|---|---|
| Open | `Ditto.open(identity: …)` | `Ditto.open(DittoConfig(…))`, after `Ditto.init()` |
| Sync, auth | `startSync()`, `AuthenticationHandler` | `sync.start()`; a server config sets `setExpirationHandler` first |
| Default directory | `{Documents}/ditto` | `ditto-{databaseID}` |

On 5.0.x `setAllPeerToPeerEnabled(false)` leaves AWDL and Wi-Fi Aware on.

## References

Load a reference only when its topic is actually in play; these files teach the
non-obvious traps, not how Flutter works. Preview a file's contents; read one section.

- [widget-integration.md](references/widget-integration.md): service, repository, view
  model; lifecycle; hot restart (V2 observers crash after `R` on a remote change).
- [web.md](references/web.md): never `--wasm` (every result repeats the first);
  `wasmShimUrl` for a site below `/`; CSP `'wasm-unsafe-eval'`; `execute` blocks frames.
- [observers.md](references/observers.md): the `onChange` buffering defect; one `changes`
  listener per observer, ever; V1 vs V2 cancellation; signal-next.
- [connect.md](references/connect.md): close on failed configure; expiration handler
  before `sync.start()`; a rejected login is `AuthResponse.exception`.
- [setup.md](references/setup.md): 5.1.0+ APKs need the compileSdk override, simulator
  builds the Podfile fix; `DittoSyncPermissions`.
- [lifetimes.md](references/lifetimes.md), [concurrency.md](references/concurrency.md),
  [anti-patterns.md](references/anti-patterns.md): detail behind the sections above.
- [errors.md](references/errors.md): catch `DittoException` and `DittoError`; unrelated.
- [versions.md](references/versions.md): per-line APIs, behaviour, migration.
- [sync.md](references/sync.md): no `LIMIT`/`ORDER BY` in subscriptions; status.
- [store.md](references/store.md): `execute`, transactions, indexes, `EVICT`.
- [transports.md](references/transports.md): `updateTransportConfig` returns `void`.
- [testing.md](references/testing.md): Ditto does not load under host `flutter test`:
  fakes there, `integration_test` for the real store; logging off in tests only.
- [attachments.md](references/attachments.md), [presence.md](references/presence.md),
  [observability.md](references/observability.md), [preview.md](references/preview.md).
- [best-practices.md](best-practices.md): placement, observers, state, verification.
- [examples/minimal-app.md](examples/minimal-app.md): the complete program.
