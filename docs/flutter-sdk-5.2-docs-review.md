# Ditto Flutter SDK 5.2.0 — documentation review

Findings from building the `flutter-sdk` skill. Scope: the Flutter pages on
<https://docs.ditto.live>, the `ditto_live` package page and README on pub.dev, and the
dartdoc comments in the published `ditto_live` package.

**Evidence levels.** *Executed*: reproduced by a run, with the version and platform
stated inline (Flutter 3.50.0 / Dart 3.14.0 unless stated). *Source*: read from the
published `ditto_live` package or from `github.com/getditto/ditto` at the named
`sdk-release-<version>` tag; paths such as `lib/src/ditto.dart:246-259` are inside
`sdks/flutter/ditto_live/` (5.x) or `flutter/ditto_live/` (4.14.7). *Docs*: read from the
docs site on 2026-11-18; every docs item below was re-read on that date and is still
present.

Severity: **high** leads to wrong code, a failed build, a crash or apparent data loss;
**medium** misleads or omits something a Flutter developer needs; **low** is cosmetic.

## Contents

- [Summary](#summary)
- [Install guide and compatibility page](#install-guide-and-compatibility-page)
- [v4 to v5 migration guide](#v4-to-v5-migration-guide)
- [Other docs.ditto.live pages](#other-docsdittolive-pages)
- [pub.dev README and dartdoc](#pubdev-readme-and-dartdoc)
- [Checked and correct](#checked-and-correct)

## Summary

| # | Finding | Severity | Evidence |
|---|---|---|---|
| I1 | Hot-restart sample's `Random().nextInt(1 << 32)` throws on web | high | executed |
| I2 | Hot-restart sample switches production to `'ditto'`, which is not the v5 default directory | high | source |
| I3 | CDN sample passes a directory as `wasmShimUrl` and assigns `Ditto.init`'s `void` result | high | source |
| I4 | Three different Flutter minimums | medium | docs, source |
| I5 | iOS minimum: 14.0 in the migration guide, 15 on the compatibility page | medium | docs, source, executed |
| I6 | Broken anchor `#step-6-web-browser-support`; no Step 4 or Step 6 heading | low | docs |
| M1 | "No `signalNext`" in Flutter | high | executed |
| M2 | `Ditto.init()` described as mandatory and as throwing if not called | medium | source |
| M3 | `websocketSync` said to have defaulted to `true` in v4 | medium | source |
| M4 | `'/app/data/ditto'` offered as the path that preserves v4 data | medium | source |
| P1 | Cloud-authentication Flutter tab says `DittoConfig` is unsupported | high | executed |
| P2 | Observer sample's `arguments: { color: "blue" }` does not compile | high | executed |
| P3 | Transport-configuration Dart tabs are missing semicolons | medium | source |
| P4 | Flutter API reference page has no body | medium | docs |
| P5 | Testing page has no Dart samples | low | docs |
| R1 | pub.dev README lists macOS, Windows and Linux as "Planned" | medium | executed |
| R2 | `newAttachment` dartdoc example passes `execute` arguments positionally | medium | source |
| R3 | `setOfflineOnlyLicenseToken` dartdoc and log call it a no-op on web; it still verifies | medium | executed, source |

No item from the original list was dropped: each was re-read on 2026-11-18 and is still
present. P3 is restated: it was first noted as "the transports Dart tab uses the v4
mutable config", but the field paths it uses are valid on the 5.x builder (see P3).

## Install guide and compatibility page

**I1 — The hot-restart sample throws on web (high, executed).**
<https://docs.ditto.live/sdk/latest/install-guides/flutter#option-1-use-randomized-directory-in-debug-mode>
names the debug directory `'ditto_debug_${Random().nextInt(1 << 32)}'`. Under dart2js,
integers are JavaScript numbers and shifts are 32-bit, so `1 << 32` is `0`, and
`Random().nextInt(0)` throws. Executed (Dart 3.14.0, the same two lines): the Dart VM
printed `1 << 32 = 4294967296` and a random value; `dart compile js` run on Node 24.22.2
printed `1 << 32 = 0` and threw `RangeError: max must be in range 0 < max ≤ 2^32, was 0`.
A Flutter web build of the sample therefore fails at startup, on the same page that
recommends it for development. Fix: use the clock, e.g.
`'ditto-debug-${DateTime.now().microsecondsSinceEpoch}'`, or `Random().nextInt(1 << 31)`.

**I2 — The same sample's production directory is a data-loss trap (high, source).** It
sets `persistenceDirectory` to `'ditto'` in production. The v5 default is
`ditto-{databaseID}` under `Ditto.defaultRootDirectory`, and a relative path resolves
against that root, which is Application Support on 5.2.0 and Documents on 5.0.x and 5.1.x
(`lib/src/ditto.dart:55-67` @ `sdk-release-5.1.0` and `sdk-release-5.2.0`). So `'ditto'`
is `{Application Support}/ditto` on 5.2.0 and `{Documents}/ditto`, the v4 directory, on
5.0.x and 5.1.x; neither is the directory an app that shipped with the default uses, so
its users' local data seems to disappear when the snippet is pasted in. (The empty store
is an inference from the path rules; not run.) Fix: pass no `persistenceDirectory` in
production, so the SDK default applies.

**I3 — The CDN sample (high, source; not executed).**
<https://docs.ditto.live/sdk/latest/install-guides/flutter#web-assets> shows
`final ditto = await Ditto.init(wasmUrl: '…/ditto.wasm', wasmShimUrl: 'https://your-cdn.com/ditto-assets/')`
and says the directory's contents "must be reachable at the URL given by the
`wasmShimUrl` parameter". In the source `wasmShimUrl` is the URL of the `ditto.wasm.js`
module itself, passed straight to `importModule`; its default is
`/assets/packages/ditto_live/lib/assets/ditto.wasm.js`
(`lib/src/bridge/wasm/init.dart:28-55` @ `sdk-release-5.2.0`). A directory URL is not a
module. `Ditto.init` returns `Future<void>` (`lib/src/ditto.dart:88` @ `sdk-release-5.2.0`):
the assignment compiles, but any use of `ditto` fails with `use_of_void_result`
(executed with `dart analyze`, Dart 3.14.0, against a stub with the 5.2.0 signature).
Fix: `await Ditto.init(wasmUrl: '…/ditto.wasm', wasmShimUrl: '…/ditto.wasm.js');` and
describe `wasmShimUrl` as the shim's URL.

**I4 — Three Flutter minimums (medium, docs and source).**
<https://docs.ditto.live/sdk/latest/compatibility/flutter> says Flutter "3.24.0 and
later", Dart "3.5 and later", and "3.24.0 -> 3.38+" per platform.
<https://docs.ditto.live/sdk/latest/install-guides/flutter#prerequisites> says
"Flutter SDK (>3.24.5)", and its hot-reload note says "Ditto supports Flutter
3.24.5-3.32+". The published pub.dev pubspec says `flutter: ">=3.19.0"` on 4.14.7, 5.0.4,
5.1.0 and 5.2.0; the `sdk-release-5.1.0` and `-5.2.0` tags say `'>=3.24.5'`
(`pubspec.yaml`). Fix: one stated minimum, matching the published pubspec.

**I5 — iOS minimum (medium).**
<https://docs.ditto.live/sdk/latest/migration-guides/flutter-v4> says the Flutter SDK for
iOS "now targets 14.0+"; the compatibility page says iOS and iOS Simulator "15 and later".
The plugin podspec says 14.0 (`ios/ditto_live.podspec:25`, published 5.2.0). Flutter
3.50.0 raises an iOS 14.0 deployment target to 15.0 on every build (executed, macOS:
it prints its deployment-target migration and rewrites the project). Fix: state one
value and say whether 14.0 is supported.

**I6 — Broken anchor and missing step numbers (low, docs).** The install guide's Web
prerequisite links "Web Browser Support" to `#step-6-web-browser-support`. The page has
no such heading: its steps are 1, 2, 3, 5, 7, 8 and 9, and the web material is under
"Web Assets" and "Considerations for Web" inside Step 5.

## v4 to v5 migration guide

Page: <https://docs.ditto.live/sdk/latest/migration-guides/flutter-v4>.

**M1 — "No `signalNext`" (high, executed).** The AI Agent Prompt says "No `signalNext` —
backpressure handled internally by SDK", and
[Back Pressure](https://docs.ditto.live/sdk/latest/migration-guides/flutter-v4#back-pressure)
says "There is no `signalNext` function to call". `Store.registerObserverWithSignalNext`
and `StoreObserverV2.signalNext()` exist from 5.1.0 (`lib/src/store/store.dart` in the
published 5.1.0 and 5.2.0 packages; absent from 5.0.4). Executed (macOS debug, 5.1.0 and
5.2.0; Chrome debug, 5.1.0 and 5.2.0): with the first render unfinished, three inserts
delivered nothing for 2 s, then exactly one callback with all three once `signalNext()`
was called. Fix: describe both observer families per version.

**M2 — `Ditto.init()` "must be called" (medium, source).** The AI Agent Prompt,
[Ditto Instance Initialization](https://docs.ditto.live/sdk/latest/migration-guides/flutter-v4#ditto-instance-initialization),
the checklist and
[New APIs in v5](https://docs.ditto.live/sdk/latest/migration-guides/flutter-v4#new-apis-in-v5)
("required static initialization … (throws if not called)") all make it mandatory. That
holds for 5.0.x, whose `Ditto.open` does not initialize. From 5.1.0 `Ditto.open` calls
`init()` itself (`lib/src/ditto.dart:183` in the published 5.1.0 package;
`lib/src/ditto.dart:170-186` @ `sdk-release-5.2.0`, whose dartdoc says explicit calls "are
now optional for most use cases"); only `Ditto.openSync` still needs it. Fix: say
"required on 5.0.x and before `openSync`; optional for `open` from 5.1.0; memoized, so
calling it unconditionally is safe".

**M3 — `websocketSync` "was `true` in v4" (medium, source).** The AI Agent Prompt and
[WebSocket Sync Default Changed](https://docs.ditto.live/sdk/latest/migration-guides/flutter-v4#websocket-sync-default-changed)
say the default changed from `true` to `false`. 4.14.7 already defaults to `false`:
`this.websocketSync = false` (`lib/src/transport/transport_config.dart:558` @
`sdk-release-4.14.7`) and `json['websocket_sync'] as bool? ?? false`
(`lib/src/transport/transport_config.g.dart:156`, same tag). Not executed. Fix: drop
the item, or name the v4 release that defaulted to `true` if there was one.

**M4 — The path offered to preserve v4 data (medium, source).**
[Default Persistence Directory](https://docs.ditto.live/sdk/latest/migration-guides/flutter-v4#default-persistence-directory)
sets `persistenceDirectory: '/app/data/ditto'` with the comment "custom path to preserve
v4 data". The v4 default is the relative `'ditto'` under the documents directory
(`lib/src/ditto.dart:132` and `lib/src/core/native/native.dart:212` in the published
4.14.7 package), so v4 data is at `{Documents}/ditto`; `/app/data/ditto` is an unrelated
absolute path. On 5.2.0 a relative `'ditto'` no longer reaches it either (see I2). Fix:
show `'${(await getApplicationDocumentsDirectory()).path}/ditto'`, or say which v5 lines
read the v4 default directory without help.

## Other docs.ditto.live pages

**P1 — Cloud authentication says Flutter cannot use `DittoConfig` (high, executed).**
[SDK Authentication](https://docs.ditto.live/sdk/latest/auth-and-authorization/cloud-authentication#sdk-authentication)'s
Flutter tab is only a comment: "Flutter SDK does not yet support the new
DittoConfig-based initialization. Continue using the legacy DittoIdentity-based API".
Every 5.x line opens with `Ditto.open(DittoConfig(…))`, and there is no `DittoIdentity`
in 5.x. Executed: `DittoConfig` with `DittoConfigConnectServer` opens on 5.0.4, 5.1.0 and
5.2.0 (macOS debug), and `ditto.auth.login` reports a failed login in
`AuthResponse.exception`. Fix: a Dart sample with `DittoConfigConnectServer`,
`ditto.auth.setExpirationHandler` and `ditto.auth.login`.

**P2 — The observer sample does not compile (high, executed).**
[Store Observer with Query Arguments](https://docs.ditto.live/sdk/latest/crud/observing-data-changes#store-observer-with-query-arguments)
passes `arguments: { color: "blue" }`. In Dart an unquoted map key is an identifier, so
this is `undefined_identifier` (executed, `dart analyze`, Dart 3.14.0). The same text is on
the v4 page. Fix: `arguments: {'color': 'blue'}`. The sample also registers with
`onChange`; on 5.0.4 to 5.2.0 such an observer still adds every result to its unlistened
`changes` stream, which keeps them all (executed, macOS debug: 6 callbacks, then a late
`changes.listen` received exactly 6 replayed results), so the sample is also the pattern
that accumulates memory.

**P3 — Transport-configuration Dart tabs do not parse (medium, source).**
[Enabling and Disabling Transports](https://docs.ditto.live/sdk/latest/sync/customizing-transport-configurations#enabling-and-disabling-transports)
(`…bluetoothLE.isEnabled = true` and `…lan.isEnabled = true`),
[Listening for Connections](https://docs.ditto.live/sdk/latest/sync/customizing-transport-configurations#listening-for-connections)
and
[Combining Multiple Transports](https://docs.ditto.live/sdk/latest/sync/customizing-transport-configurations#combining-multiple-transports)
(`…tcp.isEnabled = true`, `…tcp.interfaceIP = '0.0.0.0'`) end statements without `;`.
The field paths themselves are valid in 5.x: `updateTransportConfig` passes a
`TransportConfigBuilder` whose `peerToPeer`, `listen.tcp` and their `isEnabled`,
`interfaceIP` and `port` fields are mutable (`lib/src/ditto.dart:238-244` and
`lib/src/transport_config.dart:154-158, 326-331` @ `sdk-release-5.2.0`). Fix: add the
semicolons, and name the callback parameter `builder` as the migration guide does.

**P4 — The Flutter API reference page is empty (medium, docs).**
<https://docs.ditto.live/sdk/latest/api-reference/flutter> has a title and nothing else.
Fix: link the pub.dev API documentation for `ditto_live`.

**P5 — No Dart on the testing page (low, docs).**
<https://docs.ditto.live/sdk/latest/deployment/testing> has no Dart or Flutter sample.

## pub.dev README and dartdoc

These ship in the package, so they need an SDK release to fix.

**R1 — README says desktop is "Planned" (medium, executed).** The README of the published
5.2.0 package (<https://pub.dev/packages/ditto_live>) lists MacOS, Windows and Linux as
"Planned". Executed on 5.2.0, debug: macOS desktop (macOS 27.2.1 arm64), Linux desktop
(ubuntu-24.04 under `xvfb-run`) and Windows desktop (windows-latest) each open Ditto,
write and read back, and run the SDK probes; the compatibility page lists all three.
Checked in the published archive; the pub.dev page itself was not fetched.

**R2 — `newAttachment` dartdoc example does not compile (medium, source).** The example in
`Store.newAttachment`'s dartdoc calls
`ditto.store.execute('INSERT INTO my_collection (my_attachment ATTACHMENT) VALUES (:doc)', {'doc': doc})`
(`lib/src/store/store.dart:245-264` @ `sdk-release-5.2.0`), but `execute` takes its
arguments as the named parameter `arguments` (`store.dart:85-89`, same tag). Fix:
`arguments: {'doc': doc}`.

**R3 — `setOfflineOnlyLicenseToken` is not a no-op on web (medium, executed and source).**
Its dartdoc says "This method is a no-op on web builds", and on web it logs
`setOfflineOnlyLicenseToken is a no-op on the web platform.`; it then still calls
`dittoFfiTryVerifyLicense(…).extract()`, which throws on an error result
(`lib/src/ditto.dart:246-259` @ `sdk-release-5.2.0`). Executed (Chrome debug, 5.0.4, 5.1.0
and 5.2.0): the warning is logged and the call returns; for the one invalid token tried,
the web core returned no error, so a throw was not observed. Fix: describe what the call
does on web, and drop "no-op" from the log text. (The dartdoc also keeps an unfinished
sentence, "Offline identities include:", and a `TODO` above the method.)

## Checked and correct

- The `ditto-{databaseID}` default directory (migration guide): executed on macOS and
  the iOS Simulator, debug: with no `persistenceDirectory`, 5.1.0 wrote its store to
  `{Documents}/ditto-<databaseID>`, and 5.2.0 then reported that directory as
  `absolutePersistenceDirectory` and read the document back.
- "TransportConfig Now Immutable" (migration guide) matches the 5.2.0 source and its
  `updateTransportConfig` / `toBuilder()` / `withAllPeerToPeerEnabled` forms.
- `wasmUrl` is the URL of `ditto.wasm` itself, as the CDN section says (`init.dart:53-55`
  @ `sdk-release-5.2.0`).
