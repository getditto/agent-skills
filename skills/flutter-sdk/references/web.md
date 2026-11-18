# Flutter Web

What differs when the same `ditto_live` code runs in a browser. Executed with Flutter
3.50.0 and headless Chrome 157 on macOS: `flutter drive` debug (DDC) builds on 5.0.4,
5.1.0 and 5.2.0, and release builds (dart2js, `--wasm`) on 5.1.0 and 5.2.0. Firefox,
Safari, Edge and a hosted CDN were not run.

## Contents

- [Web differences](#web-differences)
- [Asset loading](#asset-loading)
- [Build modes](#build-modes)
- [Hosting headers and CSP](#hosting-headers-and-csp)
- [In-memory store and reload](#in-memory-store-and-reload)
- [Hot restart](#hot-restart)
- [execute on the main thread](#execute-on-the-main-thread)
- [Code that compiles on web](#code-that-compiles-on-web)

## Web differences

An index: each row gives the observed result and links to where it is handled. All rows
are executed on Chrome unless marked.

| Difference | On web | Lines | Details |
|---|---|---|---|
| Peer-to-peer transports | All off after `Ditto.open`. Enabling one throws `DittoException(<validation> Expected valid TransportConfig. …: <LAN\|BluetoothLE>)` | from `sync.start()` on 5.2.0; from `updateTransportConfig` on 5.0.4, 5.1.0 | [Code that compiles on web](#code-that-compiles-on-web) |
| `setAllPeerToPeerEnabled(true)`, `withAllPeerToPeerEnabled(true)` | No-op; `sync.start()` succeeds | 5.0.4 to 5.2.0 | [transports.md](transports.md#cap-06-customizing-transports) |
| `defaultTargetPlatform` | The host OS (`macOS`), not web | all | [setup.md](setup.md#gate-platform-code-with-kisweb-then-dittocurrentplatform) |
| Sync | Server (WebSocket) only, per the docs; not executed against a server | docs | [connect.md](connect.md#cap-03-connecting) |
| Store | In memory: survives `close()` and re-open in the page | 5.0.4 to 5.2.0 | [In-memory store and reload](#in-memory-store-and-reload) |
| Store after a page load | Empty: the page load clears it | 5.1.0, 5.2.0 (release) | [In-memory store and reload](#in-memory-store-and-reload) |
| `newAttachment(path)` | Its Future fails: `DittoException(Creating attachments from files is not supported on Flutter Web.)`. `newAttachment(Uint8List)` works | 5.0.4 to 5.2.0 | [attachments.md](attachments.md#cap-12-attachments) |
| `Attachment.copyToPath` | Its Future fails: `DittoException(Retrieving a filesystem path for attachments is not supported on the Web.)`. `Attachment.data` works | 5.0.4 to 5.2.0 | [attachments.md](attachments.md#cap-12-attachments) |
| `DittoLogger.exportLogs` | Throws `UnsupportedError: Not supported on the web platform` **synchronously** at the call: `.catchError` on its Future misses it | 5.0.4 to 5.2.0 | [observability.md](observability.md#logging) |
| `setOfflineOnlyLicenseToken` | Logs `setOfflineOnlyLicenseToken is a no-op on the web platform.`, then still verifies; one invalid token did not throw | 5.0.4 to 5.2.0 | [connect.md](connect.md#cap-03-connecting) |
| `DittoSyncPermissions` | `requiredPermissions()` is `[]` | 5.1.0, 5.2.0 | [setup.md](setup.md#android-runtime-permissions) |
| `registerObserverWithSignalNext` | Works: item counts `[0]`, then `[0, 3]` after `signalNext()` | 5.1.0, 5.2.0 | [observers.md](observers.md#cap-11-observers-and-live-queries) |
| `Ditto.defaultRootDirectory` | `""`; `absolutePersistenceDirectory` is a store name, `ditto-<databaseID>` | 5.2.0 | [In-memory store and reload](#in-memory-store-and-reload) |
| Integral doubles in `systemParameters` | `1.0` is indistinguishable from `1` (dartdoc, `ditto_config.dart:89-97` @ `sdk-release-5.2.0`; not executed) | 5.2.0 | [connect.md](connect.md#cap-03-connecting) |
| `execute` | Runs on the calling isolate: large results block frames | all | [execute on the main thread](#execute-on-the-main-thread) |
| App below the site root | Default asset URL 404s | 5.1.0, 5.2.0 | [Asset loading](#asset-loading) |
| `--wasm` builds | Wrong query results | 5.1.0, 5.2.0 | [Build modes](#build-modes) |
| Content Security Policy | Needs `'wasm-unsafe-eval'` | 5.1.0, 5.2.0 | [Hosting headers and CSP](#hosting-headers-and-csp) |
| Hot restart | Re-open fails, store locked | 5.2.0 | [Hot restart](#hot-restart) |

## Asset loading

By default the WebAssembly binary and its JavaScript shim ship inside the package and are
served with the app, from `build/web/assets/packages/ditto_live/lib/assets/` after
`flutter build web`; nothing extra to host (executed). The shim is imported from the
**absolute** URL `/assets/packages/ditto_live/lib/assets/ditto.wasm.js`
(`lib/src/bridge/wasm/init.dart:36-37` @ `sdk-release-5.2.0`).

**An app served below the site root** (`flutter build web --base-href /app/`) therefore
fails in `Ditto.init()`: `Exception: Failed to initialize Ditto WebAssembly: TypeError:
Failed to fetch dynamically imported module: http://…/assets/packages/ditto_live/lib/assets/ditto.wasm.js`.
Pass a relative shim URL; `wasmUrl` is not needed, since the `.wasm` loads through
Flutter's asset bundle, which follows the base href (executed, dart2js release, 5.1.0
and 5.2.0; the bare `assets/…` form fails with `TypeError: Failed to resolve module
specifier`):

<!-- snippet: flutter-web-2 -->
<!-- Generated by scripts/sync-snippets.py from code CI runs. Edit the marked source, not this block. -->
```dart
/// Initializes Ditto for a web app served below the site root
/// (`flutter build web --base-href /app/`). Ditto loads its JavaScript
/// shim from the absolute path /assets/packages/ditto_live/lib/assets/
/// by default, which is outside /app/. A relative URL resolves against the
/// app's own script, next to its assets. Keep the `./`: a bare `assets/`
/// path is not a valid module specifier.
Future<void> initDittoForSubpath() => Ditto.init(
  wasmShimUrl: kIsWeb
      ? './assets/packages/ditto_live/lib/assets/ditto.wasm.js'
      : null,
);
```
<!-- /snippet -->

Imports: `package:ditto_live/ditto_live.dart` and `package:flutter/foundation.dart`.

**Call it first.** `Ditto.init` is memoized: the first call's URLs win, and
`Ditto.open` calls `init()` without URLs on 5.1.0+ (`ditto.dart:88-93, 186`). Await
`initDittoForSubpath()` in `main` before anything else touches Ditto.

**From a CDN:** `wasmShimUrl` is the URL of the `ditto.wasm.js` module itself and
`wasmUrl` the URL of `ditto.wasm` (source, `init.dart:36-55`). The install guide's
example passes a directory as `wasmShimUrl` and assigns `Ditto.init`'s `void` result
(<https://docs.ditto.live/sdk/latest/install-guides/flutter#web-assets>); follow the
source. Not executed. Serve the assets compressed (same guide).

## Build modes

- **Use the default `flutter build web` (dart2js).** Executed: open, insert and read
  back on 5.1.0 and 5.2.0 release; `flutter drive -d chrome` debug (DDC) builds on all three lines.
- **Never build with `--wasm`** (5.1.0, 5.2.0 release; 5.0.4 not run). Ditto initializes
  and opens, but every query result after the first is the first one again: a second
  `INSERT` reports the first `INSERT`'s mutated IDs, and `SELECT * FROM cars` returns 0
  items, with or without COOP/COEP. An SDK defect: the web bridge keys its pointer
  registry on `Object.hashAll([type, addr])`
  (`lib/src/bridge/wasm/types.dart:168` @ `sdk-release-5.2.0`), and under dart2wasm
  every JS value in the bundle hashed to 0, so every pointer of one type gets the same
  wrapper. The docs' "default build mode" means this
  (<https://docs.ditto.live/sdk/latest/install-guides/flutter#considerations-for-web>).

## Hosting headers and CSP

- **No COOP/COEP needed.** Without them, dart2js and `--wasm` bundles both opened Ditto
  (`crossOriginIsolated` false).
- **A Content Security Policy must allow `'wasm-unsafe-eval'`:** `script-src 'self'
  'wasm-unsafe-eval'` worked (release, built with `--no-web-resources-cdn` so `'self'`
  covers Flutter's renderer). Without it the app never starts: Flutter's bootstrap fails
  first (`Uncaught CompileError: WebAssembly.compileStreaming(): …` from
  `flutter_bootstrap.js`, CSP violation `script-src`, blocked URI `wasm-eval`), so
  `main()` never runs. Ditto's own WebAssembly would need the same directive, but that
  was masked rather than observed.

## In-memory store and reload

- The store lives in memory, named `ditto-<databaseID>`; `Ditto.defaultRootDirectory` is
  `""` (executed, 5.2.0). Pass no `persistenceDirectory`.
- A document written before `close()` is still there after `Ditto.open` again **in the
  same page** (5.0.4 to 5.2.0). A page load clears it: 1 document before, 0 after
  (release, 5.1.0 and 5.2.0). Treat the server as the source of truth and expect an empty
  store at every page load.

## Hot restart

`R` in `flutter run -d chrome` does not release the in-memory store, and the next
`Ditto.open` fails at once (executed, 5.2.0 debug):

```text
DittoException(File already locked, working dir = ditto-00000000-0000-0000-0000-000000000000/__ditto_lock_file, retried 0 times.
Multiple Ditto instances cannot run at the same time within the same working directory. Either use unique working directories for each instance, or consider managing your Ditto instance as a singleton instead.)
```

A retry loop for 20 s did not recover. The install guide's advice for web is to quit and
restart the dev server (<https://docs.ditto.live/sdk/latest/install-guides/flutter#considerations-for-web>);
the debug-only randomized directory also worked in Chrome. Both, and the native
behaviour: [widget-integration.md](widget-integration.md#hot-restart).

## execute on the main thread

On web there is no worker isolate: `store.execute` runs on the calling (UI) isolate
(`lib/src/bridge/wasm/store.dart:4-11` @ `sdk-release-5.2.0`). Measured (dart2js
release, Chrome 157, 5,000 small documents, one machine, read as an order of magnitude):

| Query | Time | Longest main-thread task |
|---|---|---|
| `SELECT * FROM jank`, items counted | 20 ms (5.2.0), 13 ms (5.1.0) | none over 50 ms |
| `SELECT * FROM jank`, every `item.value` read | 79 ms (5.2.0), 55 ms (5.1.0) | 5.2.0: 79 ms, longest frame gap 67 ms; 5.1.0: 55 ms, frame gap 33 ms |
| `SELECT * FROM jank LIMIT 50`, every `item.value` read | 2 ms | none over 50 ms |

So on web, bound every query a screen runs: `LIMIT` a page and fetch the next page on
demand, and decode only the items you render. Pagination syntax:
the `write-dql` skill if installed, otherwise <https://docs.ditto.live/dql/dql>.

## Code that compiles on web

- **No `dart:io` in code a web build reaches**; even importing it fails the web compile.
  Split platform code with a conditional export, as the fixture does (compiled and run
  on Chrome and macOS):
  `export 'temp_dir_web.dart' if (dart.library.io) 'temp_dir_io.dart';`
- **`package:web` and `dart:js_interop` for browser APIs, never `dart:html`** (the web
  probe app uses `dart:js_interop`).
- **Gate peer-to-peer with `kIsWeb` first, then `Ditto.currentPlatform`.** Executed on
  Chrome (every transport stays off and `sync.start()` succeeds) and on macOS
  (5.0.4 to 5.2.0: `bluetoothLE=true lan=true awdl=true wifiAware=false`); the Android,
  Linux and Windows branches were not run:

<!-- snippet: flutter-web-1 -->
<!-- Generated by scripts/sync-snippets.py from code CI runs. Edit the marked source, not this block. -->
```dart
/// Turns on the peer-to-peer transports this platform has. Web has none,
/// and enabling one there throws a DittoException (from `sync.start()` on
/// 5.2.0, from `updateTransportConfig` on 5.0.4 and 5.1.0).
/// Check `kIsWeb` first: it is a constant, so web builds drop the rest.
/// Then decide with `Ditto.currentPlatform`, never `defaultTargetPlatform`,
/// which reports the browser's host OS on web.
void enablePeerToPeer(Ditto ditto) {
  if (kIsWeb) return;
  ditto.updateTransportConfig((config) {
    config.peerToPeer.bluetoothLE.isEnabled = true;
    config.peerToPeer.lan.isEnabled = true;
    switch (Ditto.currentPlatform) {
      case SupportedPlatform.ios || SupportedPlatform.macos:
        config.peerToPeer.awdl.isEnabled = true;
      case SupportedPlatform.android:
        config.peerToPeer.wifiAware.isEnabled = true;
      case SupportedPlatform.linux ||
          SupportedPlatform.windows ||
          SupportedPlatform.web:
        break;
    }
  });
}
```
<!-- /snippet -->

Imports: `package:ditto_live/ditto_live.dart` and `package:flutter/foundation.dart`.
